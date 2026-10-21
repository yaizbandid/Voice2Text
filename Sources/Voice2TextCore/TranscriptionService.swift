import Foundation
import WhisperKit

/// จัดการโมเดล Whisper (ดาวน์โหลด/โหลด) และการถอดเสียง
public final class TranscriptionService {
    public static let shared = TranscriptionService()

    public private(set) var whisperKit: WhisperKit?
    public private(set) var loadedModel: String?

    /// แท็บถอดเสียงกับแท็บวิเคราะห์คลิปใช้โมเดลตัวเดียวกัน — ให้ถอดได้ทีละงาน
    private let gate = AsyncGate()

    private init() {}

    /// โฟลเดอร์เก็บโมเดล: ~/Library/Application Support/Voice2Text
    public static var modelsBaseDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voice2Text", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static func availableModels() async throws -> [String] {
        try await WhisperKit.fetchAvailableModels(from: "argmaxinc/whisperkit-coreml")
    }

    /// ดาวน์โหลด (ถ้ายังไม่มี) แล้วโหลดโมเดลเข้าหน่วยความจำ
    public func loadModel(
        _ variant: String,
        downloadProgress: @escaping (Double) -> Void,
        onLoadStart: @escaping () -> Void
    ) async throws {
        if loadedModel == variant, whisperKit != nil { return }
        whisperKit = nil
        loadedModel = nil

        let folder = try await WhisperKit.download(
            variant: variant,
            downloadBase: Self.modelsBaseDir,
            useBackgroundSession: false,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { progress in
                downloadProgress(progress.fractionCompleted)
            }
        )

        onLoadStart()
        let config = WhisperKitConfig(
            model: variant,
            downloadBase: Self.modelsBaseDir,
            modelFolder: folder.path,
            prewarm: true,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        loadedModel = variant
    }

    public struct TranscriptionOutput {
        public let segments: [TranscriptSegment]
        /// รหัสภาษาที่ตรวจพบ เช่น "th" (ถ้าผู้ใช้บังคับภาษาไว้ จะเป็นภาษานั้น)
        public let language: String?
    }

    /// ถอดเสียงจากไฟล์เสียง คืนค่าเป็น segment พร้อม timestamp และภาษาที่ตรวจพบ
    public func transcribe(
        audioURL: URL,
        language: String?,
        wordTimestamps: Bool = false,
        onLiveText: @escaping (String) -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> TranscriptionOutput {
        await gate.enter()
        do {
            let output = try await transcribeUnlocked(
                audioURL: audioURL, language: language, wordTimestamps: wordTimestamps,
                onLiveText: onLiveText, onProgress: onProgress)
            await gate.leave()
            return output
        } catch {
            await gate.leave()
            throw error
        }
    }

    private func transcribeUnlocked(
        audioURL: URL,
        language: String?,
        wordTimestamps: Bool,
        onLiveText: @escaping (String) -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> TranscriptionOutput {
        guard let whisperKit else {
            throw V2TError("โมเดลยังไม่พร้อมใช้งาน")
        }

        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.chunkingStrategy = .vad
        options.wordTimestamps = wordTimestamps
        if language == nil {
            options.detectLanguage = true
        }

        // อัปเดตแถบความคืบหน้าจาก Progress ของ WhisperKit เป็นระยะ
        let poller = Task {
            while !Task.isCancelled {
                onProgress(min(0.99, whisperKit.progress.fractionCompleted))
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        defer { poller.cancel() }

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options,
            callback: { progress in
                let text = Self.cleanText(progress.text)
                if !text.isEmpty { onLiveText(text) }
                return nil
            }
        )
        onProgress(1.0)
        return Self.makeOutput(from: results)
    }

    static func makeOutput(from results: [TranscriptionResult]) -> TranscriptionOutput {
        let segments = results
            .flatMap { $0.segments }
            .sorted { $0.start < $1.start }
            .map {
                TranscriptSegment(
                    start: Double($0.start),
                    end: Double($0.end),
                    text: Self.cleanText($0.text),
                    words: $0.words.map { timings in
                        timings
                            // เก็บเว้นวรรคนำหน้าไว้ — Whisper ใส่เว้นวรรคเฉพาะจุดที่เป็นการขึ้นคำใหม่
                            // ภาษาไทยจึงต่อก้อนกลับเป็นข้อความเดิมได้ด้วยการต่อกันตรง ๆ
                            .map { TranscriptWord(text: Self.stripSpecialTokens($0.word), start: Double($0.start), end: Double($0.end)) }
                            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    }
                )
            }
            .filter { !$0.text.isEmpty }
        return TranscriptionOutput(segments: segments, language: results.first?.language)
    }

    /// ตัด token พิเศษของ Whisper เช่น <|startoftranscript|> ออกจากข้อความ
    static func cleanText(_ text: String) -> String {
        stripSpecialTokens(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripSpecialTokens(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
    }
}

/// คิวแบบ async ให้เข้าใช้ได้ทีละงาน (FIFO)
actor AsyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
