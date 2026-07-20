import Foundation
import SwiftUI
import Translation
import Voice2TextCore

/// โหมดแสดงผลข้อความเมื่อมีคำแปล
enum TranscriptDisplayMode: String, CaseIterable {
    case original
    case translated
    case bilingual

    var label: String {
        switch self {
        case .original: return "ต้นฉบับ"
        case .translated: return "คำแปล"
        case .bilingual: return "สองภาษา"
        }
    }

    var exportVariant: Exporter.Variant {
        switch self {
        case .original: return .original
        case .translated: return .translated
        case .bilingual: return .bilingual
        }
    }
}

/// ชื่อภาษาเป็นภาษาไทยจากรหัส เช่น "en" → "อังกฤษ"
func languageDisplayName(_ code: String) -> String {
    let thai = Locale(identifier: "th")
    return thai.localizedString(forIdentifier: code)
        ?? thai.localizedString(forLanguageCode: code)
        ?? code
}

struct TranscriptionJob: Identifiable {
    enum Source {
        case file(URL)
        case remote(URL)
    }

    enum Status: Equatable {
        case queued
        case preparingDownload(String)
        case downloading(Double)
        case extracting
        case transcribing(Double)
        case done
        case failed(String)
    }

    let id = UUID()
    let source: Source
    var displayName: String
    var status: Status = .queued
    var segments: [TranscriptSegment] = []
    var liveText: String = ""
    var duration: Double = 0
    /// รหัสภาษาที่ Whisper ตรวจพบ เช่น "th"
    var detectedLanguage: String?
    /// รหัสภาษาปลายทางของคำแปลที่มีอยู่ (nil = ยังไม่ได้แปล)
    var translatedLanguage: String?
    /// ความคืบหน้าการแปล 0-1 (nil = ไม่ได้กำลังแปล)
    var translationProgress: Double?

    init(file url: URL) {
        source = .file(url)
        displayName = url.lastPathComponent
    }

    init(remote url: URL) {
        source = .remote(url)
        displayName = url.absoluteString
    }

    var iconName: String {
        switch source {
        case .remote: return "link"
        case .file(let url): return MediaConverter.isVideo(url) ? "film" : "waveform"
        }
    }

    var isActive: Bool {
        switch status {
        case .preparingDownload, .downloading, .extracting, .transcribing: return true
        default: return false
        }
    }

    var hasTranslation: Bool { translatedLanguage != nil }

    /// ชื่อไฟล์เริ่มต้นตอนบันทึก .txt/.srt
    var suggestedExportBase: String {
        let cleaned = displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let withoutExtension = (cleaned as NSString).deletingPathExtension
        return withoutExtension.isEmpty ? "transcript" : withoutExtension
    }

    var statusLabel: String {
        switch status {
        case .queued: return "รอคิว"
        case .preparingDownload(let message): return message
        case .downloading(let p):
            return p >= 0 ? "กำลังดาวน์โหลด \(Int(p * 100))%" : "กำลังดาวน์โหลด…"
        case .extracting: return "กำลังแยกเสียงจากวิดีโอ…"
        case .transcribing(let p): return "กำลังถอดเสียง \(Int(p * 100))%"
        case .done:
            var parts = ["เสร็จแล้ว"]
            if let detectedLanguage {
                parts.append("ภาษา\(languageDisplayName(detectedLanguage))")
            }
            if duration > 0 {
                parts.append("ยาว \(Exporter.clock(duration))")
            }
            return parts.joined(separator: " • ")
        case .failed(let message): return "ผิดพลาด: \(message)"
        }
    }
}

/// คำขอแปลที่รอ TranslationSession จาก translationTask
struct PendingTranslation: Equatable {
    let jobID: UUID
    let targetCode: String
}

@MainActor
final class AppState: ObservableObject {
    enum ModelState: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    static let defaultModel = "openai_whisper-large-v3-v20240930_626MB"

    @Published var modelState: ModelState = .idle
    @Published var jobs: [TranscriptionJob] = []
    @Published var selectedJobID: UUID?
    @Published var pendingTranslation: PendingTranslation?
    @Published var translationError: String?

    @AppStorage("modelVariant") var modelVariant: String = AppState.defaultModel
    @AppStorage("language") var language: String = "auto"
    @AppStorage("transcriptDisplayMode") var displayModeRaw: String = TranscriptDisplayMode.original.rawValue

    var displayMode: TranscriptDisplayMode {
        get { TranscriptDisplayMode(rawValue: displayModeRaw) ?? .original }
        set { displayModeRaw = newValue.rawValue }
    }

    private let service = TranscriptionService.shared
    private var working = false

    init() {
        // ผู้ใช้ต้องการให้ถอดตามภาษาต้นทาง — ย้ายค่าเดิม "th" เป็น "auto" ครั้งเดียว
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didMigrateLanguageToAuto") {
            defaults.set("auto", forKey: "language")
            defaults.set(true, forKey: "didMigrateLanguageToAuto")
        }
    }

    var selectedJob: TranscriptionJob? {
        guard let selectedJobID else { return nil }
        return jobs.first { $0.id == selectedJobID }
    }

    // MARK: - Model

    func loadModelIfNeeded() {
        Task { await loadModel(variant: modelVariant) }
    }

    func loadModel(variant: String) async {
        if case .downloading = modelState { return }
        if modelState == .loading { return }
        if modelState == .ready, service.loadedModel == variant { return }

        modelState = .downloading(0)
        Self.diagnose("start loadModel variant=\(variant)")
        do {
            try await service.loadModel(
                variant,
                downloadProgress: { progress in
                    Task { @MainActor in
                        if case .downloading = self.modelState {
                            self.modelState = .downloading(progress)
                        }
                    }
                },
                onLoadStart: {
                    Task { @MainActor in
                        Self.diagnose("download done, loading into memory")
                        self.modelState = .loading
                    }
                }
            )
            modelState = .ready
            Self.diagnose("model ready")
            processQueueIfNeeded()
        } catch {
            Self.diagnose("FAILED: \(error)")
            modelState = .failed(error.localizedDescription)
        }
    }

    /// เขียนสถานะสำคัญลงไฟล์ ไว้วินิจฉัยปัญหาโดยไม่ต้องเปิด Console
    nonisolated static func diagnose(_ message: String) {
        let url = TranscriptionService.modelsBaseDir.appendingPathComponent("app-state.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Jobs

    func add(urls: [URL]) {
        let valid = urls.filter {
            MediaConverter.supportedExtensions.contains($0.pathExtension.lowercased())
        }
        guard !valid.isEmpty else { return }
        for url in valid {
            jobs.append(TranscriptionJob(file: url))
        }
        if selectedJobID == nil {
            selectedJobID = jobs.first?.id
        }
        processQueueIfNeeded()
    }

    /// เพิ่มงานจากลิงก์ คืน false ถ้าข้อความไม่ใช่ลิงก์ที่ใช้ได้
    @discardableResult
    func addRemote(_ text: String) -> Bool {
        guard let url = MediaDownloader.remoteURL(from: text) else { return false }
        jobs.append(TranscriptionJob(remote: url))
        selectedJobID = jobs.last?.id
        processQueueIfNeeded()
        return true
    }

    func remove(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isActive else { return }
        jobs.remove(at: index)
        if selectedJobID == id {
            selectedJobID = jobs.last?.id
        }
    }

    func processQueueIfNeeded() {
        guard !working, modelState == .ready else { return }
        guard jobs.contains(where: { $0.status == .queued }) else { return }
        working = true
        Task { await workLoop() }
    }

    private func workLoop() async {
        defer { working = false }
        while modelState == .ready,
              let next = jobs.first(where: { $0.status == .queued }) {
            await run(jobID: next.id)
        }
    }

    private func run(jobID: UUID) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        selectedJobID = jobID
        do {
            // 1) หาไฟล์ในเครื่อง — งานจากลิงก์ต้องดาวน์โหลดก่อน
            let localURL: URL
            switch job.source {
            case .file(let url):
                localURL = url
            case .remote(let url):
                update(jobID) { $0.status = .downloading(-1) }
                let result = try await MediaDownloader.shared.download(
                    from: url,
                    onStatus: { message in
                        Task { @MainActor in
                            self.update(jobID) { $0.status = .preparingDownload(message) }
                        }
                    },
                    onProgress: { progress in
                        Task { @MainActor in
                            self.update(jobID) { $0.status = .downloading(progress) }
                        }
                    }
                )
                localURL = result.fileURL
                update(jobID) { $0.displayName = result.title }
            }

            // 2) แยกเสียง (ถ้าเป็นวิดีโอ)
            update(jobID) { $0.status = .extracting }
            let audioURL = try await MediaConverter.prepareAudio(from: localURL)
            let duration = (try? await MediaConverter.duration(of: audioURL)) ?? 0
            update(jobID) {
                $0.duration = duration
                $0.status = .transcribing(0)
            }

            // 3) ถอดเสียง — "auto" คือให้ Whisper ตรวจภาษาเอง
            let lang: String? = language == "auto" ? nil : language
            let output = try await service.transcribe(
                audioURL: audioURL,
                language: lang,
                onLiveText: { text in
                    Task { @MainActor in
                        self.update(jobID) { $0.liveText = text }
                    }
                },
                onProgress: { progress in
                    Task { @MainActor in
                        self.update(jobID) {
                            if case .transcribing = $0.status {
                                $0.status = .transcribing(progress)
                            }
                        }
                    }
                }
            )
            update(jobID) {
                $0.segments = output.segments
                $0.detectedLanguage = lang ?? output.language
                $0.liveText = ""
                $0.status = .done
            }
        } catch {
            Self.diagnose("job failed: \(error)")
            update(jobID) {
                $0.liveText = ""
                $0.status = .failed(error.localizedDescription)
            }
        }
    }

    private func update(_ id: UUID, _ mutate: (inout TranscriptionJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    // MARK: - Translation

    /// ทำงานภายใน translationTask ของ SwiftUI — แปลทีละ segment พร้อมรายงานความคืบหน้า
    func performTranslation(session: TranslationSession) async {
        guard let pending = pendingTranslation else { return }
        pendingTranslation = nil
        guard let jobIndex = jobs.firstIndex(where: { $0.id == pending.jobID }) else { return }
        let segments = jobs[jobIndex].segments
        guard !segments.isEmpty else { return }

        translationError = nil
        update(pending.jobID) { $0.translationProgress = 0 }
        do {
            // ดาวน์โหลดแพ็กภาษา (ระบบจะถามยืนยันครั้งแรกของแต่ละคู่ภาษา)
            try await session.prepareTranslation()

            let requests = segments.enumerated().map { index, segment in
                TranslationSession.Request(sourceText: segment.text, clientIdentifier: "\(index)")
            }
            var finished = 0
            for try await response in session.translate(batch: requests) {
                guard let identifier = response.clientIdentifier,
                      let segmentIndex = Int(identifier) else { continue }
                finished += 1
                update(pending.jobID) { job in
                    if job.segments.indices.contains(segmentIndex) {
                        job.segments[segmentIndex].translation = response.targetText
                    }
                    job.translationProgress = Double(finished) / Double(requests.count)
                }
            }
            update(pending.jobID) {
                $0.translatedLanguage = pending.targetCode
                $0.translationProgress = nil
            }
            // แปลเสร็จแล้วสลับไปโหมดสองภาษาให้เห็นผลทันที (ถ้ายังดูต้นฉบับอยู่)
            if displayMode == .original {
                displayMode = .bilingual
            }
            Self.diagnose("translated job to \(pending.targetCode)")
        } catch {
            Self.diagnose("translation failed: \(error)")
            translationError = error.localizedDescription
            update(pending.jobID) { $0.translationProgress = nil }
        }
    }
}
