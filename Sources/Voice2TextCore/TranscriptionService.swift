import Foundation
import WhisperKit

/// จัดการโมเดล Whisper / OpenThai (ดาวน์โหลด/โหลด) และการถอดเสียง
public final class TranscriptionService {
    public static let shared = TranscriptionService()
    public static let openThaiModelVariant = "openthai-2.0-asr-streaming"

    public private(set) var whisperKit: WhisperKit?
    public private(set) var loadedModel: String?

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
        if variant == Self.openThaiModelVariant {
            _ = try Self.resolveOpenThaiPaths()
            whisperKit = nil
            onLoadStart()
            loadedModel = variant
            return
        }

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
        onLiveText: @escaping (String) -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> TranscriptionOutput {
        if loadedModel == Self.openThaiModelVariant {
            return try await transcribeWithOpenThai(
                audioURL: audioURL,
                language: language,
                onLiveText: onLiveText,
                onProgress: onProgress
            )
        }

        guard let whisperKit else {
            throw V2TError("โมเดลยังไม่พร้อมใช้งาน")
        }

        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.chunkingStrategy = .vad
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
                    text: Self.cleanText($0.text)
                )
            }
            .filter { !$0.text.isEmpty }
        return TranscriptionOutput(segments: segments, language: results.first?.language)
    }

    /// ตัด token พิเศษของ Whisper เช่น <|startoftranscript|> ออกจากข้อความ
    static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenThai 2.0 ASR Streaming

    private struct OpenThaiPaths {
        let pythonURL: URL
        let scriptURL: URL
    }

    private struct OpenThaiResponse: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
        }
        let language: String?
        let text: String
        let segments: [Segment]
    }

    private static func resolveOpenThaiPaths() throws -> OpenThaiPaths {
        let fm = FileManager.default
        let envDir = ProcessInfo.processInfo.environment["OPENTHAI_ASR_DIR"]
        let baseDir = envDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("work/openthai-asr", isDirectory: true)

        let pythonURL = baseDir.appendingPathComponent(".venv/bin/python")
        let scriptURL = baseDir.appendingPathComponent("transcribe.py")
        let modelURL = baseDir.appendingPathComponent("openthai2.0-asr-streaming_raw.nemo")

        guard fm.isExecutableFile(atPath: pythonURL.path),
              fm.fileExists(atPath: scriptURL.path),
              fm.fileExists(atPath: modelURL.path) else {
            throw V2TError("ไม่พบชุดโมเดล OpenThai 2.0 ASR ใน \(baseDir.path)")
        }
        return OpenThaiPaths(pythonURL: pythonURL, scriptURL: scriptURL)
    }

    private func transcribeWithOpenThai(
        audioURL: URL,
        language: String?,
        onLiveText: @escaping (String) -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> TranscriptionOutput {
        let paths = try Self.resolveOpenThaiPaths()
        let promptLang = (language == "th") ? "th-TH" : "th-mix"

        onLiveText("กำลังประมวลผลด้วย OpenThai 2.0 ASR…")
        let progressTask = Task {
            var p = 0.08
            while !Task.isCancelled {
                onProgress(p)
                p = min(0.92, p + 0.04)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        defer { progressTask.cancel() }

        let outputData: Data = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = paths.pythonURL
                process.arguments = [paths.scriptURL.path, audioURL.path, "--json", "--lang", promptLang]
                process.currentDirectoryURL = paths.scriptURL.deletingLastPathComponent()

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(process.terminationStatus)"
                        continuation.resume(throwing: V2TError("OpenThai 2.0 ASR ผิดพลาด: \(errMsg)"))
                        return
                    }
                    continuation.resume(returning: outData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let decoded: OpenThaiResponse
        do {
            decoded = try JSONDecoder().decode(OpenThaiResponse.self, from: outputData)
        } catch {
            let raw = String(data: outputData, encoding: .utf8) ?? ""
            throw V2TError("อ่านผลลัพธ์จาก OpenThai 2.0 ASR ไม่สำเร็จ: \(raw.prefix(200))")
        }

        let segments: [TranscriptSegment]
        if decoded.segments.isEmpty {
            let cleaned = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            segments = cleaned.isEmpty ? [] : [TranscriptSegment(start: 0, end: 0, text: cleaned)]
        } else {
            segments = decoded.segments.map {
                TranscriptSegment(start: $0.start, end: $0.end, text: $0.text)
            }
        }

        onProgress(1.0)
        return TranscriptionOutput(segments: segments, language: decoded.language ?? "th")
    }
}
