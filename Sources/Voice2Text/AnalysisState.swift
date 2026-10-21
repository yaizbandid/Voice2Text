import SwiftUI
import ClipAnalysisCore
import Voice2TextCore

/// สถานะของแท็บ "วิเคราะห์คลิป" — คิวดึงข้อมูล + คลังคลิป
@MainActor
final class AnalysisState: ObservableObject {
    @Published private(set) var clips: [ClipRecord] = []
    @Published var selectedClipIDs: Set<String> = []
    /// ข้อความสถานะงานที่กำลังทำ (nil = ว่าง)
    @Published private(set) var activity: String?
    @Published private(set) var queuedCount = 0
    /// ข้อผิดพลาดของงานล่าสุด แสดงเป็นแถบใต้ช่องวางลิงก์
    @Published var messages: [String] = []

    /// ว่าง = ไม่ใช้คุกกี้; ค่าอื่นส่งให้ yt-dlp `--cookies-from-browser`
    @AppStorage("analysis.cookiesBrowser") var cookiesBrowser: String = ""
    @AppStorage("analysis.collectionLimit") var collectionLimit: Int = 20
    /// ดึงข้อมูลเสร็จแล้วถอดเสียง + วัดการพูดต่อทันที
    @AppStorage("analysis.autoTranscribe") var autoTranscribe: Bool = true
    /// ภาษาเดียวกับแท็บถอดเสียง (auto / th / en)
    @AppStorage("language") private var language: String = "auto"

    // เกณฑ์ความเร็วพูด (คำต่อนาที) แยกไทย / ภาษาอื่น
    @AppStorage("analysis.pace.th.slow") var thaiSlow: Double = PaceThresholds.thaiDefault.slowBelow
    @AppStorage("analysis.pace.th.normal") var thaiNormal: Double = PaceThresholds.thaiDefault.normalBelow
    @AppStorage("analysis.pace.th.fast") var thaiFast: Double = PaceThresholds.thaiDefault.fastBelow
    @AppStorage("analysis.pace.other.slow") var otherSlow: Double = PaceThresholds.englishDefault.slowBelow
    @AppStorage("analysis.pace.other.normal") var otherNormal: Double = PaceThresholds.englishDefault.normalBelow
    @AppStorage("analysis.pace.other.fast") var otherFast: Double = PaceThresholds.englishDefault.fastBelow

    /// สถานะการถอดเสียงรายคลิป (clipID → ข้อความ) — แสดงในตารางและแผงรายละเอียด
    @Published private(set) var clipActivity: [String: String] = [:]

    /// ใช้โหลดโมเดล Whisper ร่วมกับแท็บถอดเสียง
    weak var appState: AppState?

    private let store = LibraryStore()
    private var queue: [URL] = []
    private var working = false
    private var transcribeQueue: [String] = []
    private var transcribing = false

    init() {
        clips = store.loadAll()
        // เกณฑ์ความเร็วพูดแก้จากหน้า Settings — วาดตารางใหม่ให้ระดับความเร็วอัปเดตทันที
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    var selectedClip: ClipRecord? {
        guard selectedClipIDs.count == 1, let id = selectedClipIDs.first else { return nil }
        return clips.first { $0.id == id }
    }

    private var fetchOptions: MetadataFetcher.Options {
        MetadataFetcher.Options(cookiesFromBrowser: cookiesBrowser.isEmpty ? nil : cookiesBrowser)
    }

    // MARK: - เพิ่มลิงก์

    /// รับข้อความที่วาง (หลายลิงก์ได้) — คืน false ถ้าไม่มีลิงก์ที่รองรับเลย
    @discardableResult
    func submit(_ text: String) -> Bool {
        messages = []
        var accepted = false
        var unsupported: [String] = []
        for link in PlatformDetector.splitLinks(text) {
            switch PlatformDetector.detect(link) {
            case .clip(_, _, let url):
                enqueue([url]); accepted = true
            case .collection(let url):
                accepted = true
                Task { await expand(url) }
            case .unsupported(let raw):
                unsupported.append(raw)
            }
        }
        if !unsupported.isEmpty {
            messages.append("ข้ามลิงก์ที่ยังไม่รองรับ (\(unsupported.count)): รองรับเฉพาะ YouTube, Shorts, Reels")
        }
        return accepted
    }

    func refresh(_ ids: Set<String>) {
        enqueue(clips.filter { ids.contains($0.id) }.map(\.url))
    }

    func delete(_ ids: Set<String>) {
        for id in ids {
            do { try store.delete(id: id) } catch { messages.append("ลบไม่สำเร็จ: \(error.localizedDescription)") }
        }
        clips.removeAll { ids.contains($0.id) }
        selectedClipIDs.subtract(ids)
    }

    private func expand(_ url: URL) async {
        activity = "กำลังอ่านรายการคลิปจาก \(url.absoluteString)…"
        do {
            let urls = try await MetadataFetcher.shared.expandCollection(
                url, limit: collectionLimit, options: fetchOptions,
                onStatus: { [weak self] status in Task { @MainActor in self?.activity = status } })
            if urls.isEmpty { messages.append("ไม่พบคลิปในลิงก์นี้: \(url.absoluteString)") }
            enqueue(urls)
        } catch {
            messages.append(error.localizedDescription)
        }
        if !working { activity = nil }
    }

    private func enqueue(_ urls: [URL]) {
        let pending = Set(queue)
        queue += urls.filter { !pending.contains($0) }
        queuedCount = queue.count
        guard !working else { return }
        working = true
        Task { await workLoop() }
    }

    // MARK: - คิว

    private func workLoop() async {
        var done = 0
        while !queue.isEmpty {
            let url = queue.removeFirst()
            queuedCount = queue.count
            done += 1
            activity = "กำลังดึงข้อมูล \(done)/\(done + queue.count): \(url.absoluteString)"
            do {
                let fetched = try await MetadataFetcher.shared.fetchClip(
                    url, options: fetchOptions,
                    onStatus: { [weak self] status in Task { @MainActor in self?.activity = status } })
                var record = fetched
                if let existing = clips.first(where: { $0.id == fetched.id }) {
                    record = existing
                    record.updateMetadata(from: fetched)
                }
                let saved = try store.upsert(record)
                replace(saved)
                if done == 1, queue.isEmpty { selectedClipIDs = [saved.id] }
                if autoTranscribe, saved.transcript == nil { transcribe([saved.id]) }
            } catch {
                messages.append(error.localizedDescription)
            }
        }
        working = false
        activity = nil
    }

    private func replace(_ record: ClipRecord) {
        if let index = clips.firstIndex(where: { $0.id == record.id }) {
            clips[index] = record
        } else {
            clips.insert(record, at: 0)
        }
    }

    // MARK: - ถอดเสียง + วัดการพูด (เฟส 2)

    func paceThresholds(for language: String?) -> PaceThresholds {
        language?.lowercased().hasPrefix("th") == true
            ? PaceThresholds(slowBelow: thaiSlow, normalBelow: thaiNormal, fastBelow: thaiFast)
            : PaceThresholds(slowBelow: otherSlow, normalBelow: otherNormal, fastBelow: otherFast)
    }

    /// ระดับความเร็วตามเกณฑ์ปัจจุบัน (เปลี่ยนเกณฑ์ใน Settings แล้วมีผลทันที ไม่ต้องถอดใหม่)
    func paceLabel(for clip: ClipRecord) -> PaceLabel? {
        guard let speech = clip.speech else { return nil }
        return paceThresholds(for: clip.transcript?.language).label(for: speech.wordsPerMinute)
    }

    func transcribe(_ ids: Set<String>) {
        let pending = Set(transcribeQueue).union(clipActivity.keys)
        let newIDs = clips.map(\.id).filter { ids.contains($0) && !pending.contains($0) }
        guard !newIDs.isEmpty else { return }
        transcribeQueue += newIDs
        for id in newIDs { clipActivity[id] = "รอถอดเสียง" }
        guard !transcribing else { return }
        transcribing = true
        Task { await transcribeLoop() }
    }

    private func transcribeLoop() async {
        while !transcribeQueue.isEmpty {
            let id = transcribeQueue.removeFirst()
            guard let clip = clips.first(where: { $0.id == id }) else {
                clipActivity[id] = nil
                continue
            }
            do {
                try await ensureModel(for: id)
                let lang: String? = language == "auto" ? nil : language
                let updated = try await ClipTranscriber.transcribe(
                    clip,
                    language: lang,
                    thai: paceThresholds(for: "th"),
                    other: paceThresholds(for: nil),
                    onStage: { [weak self] stage in
                        Task { @MainActor in self?.clipActivity[id] = Self.describe(stage) }
                    })
                // ระหว่างถอดอาจมีการดึงยอดใหม่ — ใช้ข้อมูลล่าสุดแล้วใส่เฉพาะผลถอดเสียง
                var latest = clips.first(where: { $0.id == id }) ?? updated
                latest.transcript = updated.transcript
                latest.speech = updated.speech
                latest.transcriptError = nil
                replace(try store.upsert(latest))
            } catch {
                if var failed = clips.first(where: { $0.id == id }) {
                    failed.transcriptError = error.localizedDescription
                    if let saved = try? store.upsert(failed) { replace(saved) }
                }
                messages.append("ถอดเสียงไม่สำเร็จ (\(clip.title)): \(error.localizedDescription)")
            }
            clipActivity[id] = nil
        }
        transcribing = false
    }

    /// โมเดลอาจยังโหลดไม่เสร็จตอนเปิดแอป — สั่งโหลดผ่าน AppState แล้วรอ
    private func ensureModel(for id: String) async throws {
        let service = TranscriptionService.shared
        if service.whisperKit != nil { return }
        clipActivity[id] = "กำลังโหลดโมเดลถอดเสียง…"
        if let appState {
            await appState.loadModel(variant: appState.modelVariant)
            // โหลดซ้อนกับแท็บถอดเสียงอยู่ — รอจนเสร็จ (สูงสุด ~10 นาที)
            for _ in 0..<1200 where service.whisperKit == nil {
                if case .failed(let message) = appState.modelState { throw V2TError(message) }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        guard service.whisperKit != nil else {
            throw V2TError("โมเดลถอดเสียงยังไม่พร้อม — เปิดแท็บถอดเสียงเพื่อดูสถานะโมเดล")
        }
    }

    private static func describe(_ stage: ClipTranscriber.Stage) -> String {
        switch stage {
        case .status(let message): return message
        case .downloading(let p): return p >= 0 ? "กำลังดึงเสียง \(Int(p * 100))%" : "กำลังดึงเสียง…"
        case .extracting: return "กำลังเตรียมไฟล์เสียง…"
        case .transcribing(let p): return "กำลังถอดเสียง \(Int(p * 100))%"
        }
    }

    // MARK: - Export

    /// CSV สำหรับเปิดใน Google Sheets / Excel
    func csv(for ids: Set<String>?) -> String {
        let rows = clips.filter { ids == nil || ids!.contains($0.id) }
        func field(_ value: String?) -> String {
            let text = value ?? ""
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func number(_ value: Int?) -> String { value.map(String.init) ?? "" }
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        var lines = ["platform,title,channel,url,views,likes,comments,followers,engagement_rate,duration_sec,upload_date,fetched_at,language,words_per_minute,opening_wpm,pace,time_to_first_word,pause_count"]
        for clip in rows {
            let m = clip.metrics
            lines.append([
                clip.platform.displayName,
                field(clip.title),
                field(clip.channel),
                clip.url.absoluteString,
                number(m.views), number(m.likes), number(m.comments), number(m.followers),
                m.engagementRate.map { String(format: "%.4f", $0) } ?? "",
                clip.durationSeconds.map { String(Int($0)) } ?? "",
                clip.uploadDate.map(dateFormatter.string(from:)) ?? "",
                dateFormatter.string(from: clip.fetchedAt),
                clip.transcript?.language ?? "",
                clip.speech.map { String(format: "%.0f", $0.wordsPerMinute) } ?? "",
                clip.speech?.openingWPM.map { String(format: "%.0f", $0) } ?? "",
                paceLabel(for: clip)?.rawValue ?? "",
                clip.speech.map { String(format: "%.1f", $0.timeToFirstWord) } ?? "",
                clip.speech.map { String($0.pauseCount) } ?? "",
            ].joined(separator: ","))
        }
        // BOM ให้ Excel อ่านภาษาไทยถูก
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }
}
