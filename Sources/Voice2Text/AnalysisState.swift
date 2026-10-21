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

    private let store = LibraryStore()
    private var queue: [URL] = []
    private var working = false

    init() {
        clips = store.loadAll()
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
                let saved = try store.upsert(fetched)
                if let index = clips.firstIndex(where: { $0.id == saved.id }) {
                    clips[index] = saved
                } else {
                    clips.insert(saved, at: 0)
                }
                if done == 1, queue.isEmpty { selectedClipIDs = [saved.id] }
            } catch {
                messages.append(error.localizedDescription)
            }
        }
        working = false
        activity = nil
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

        var lines = ["platform,title,channel,url,views,likes,comments,followers,engagement_rate,duration_sec,upload_date,fetched_at"]
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
            ].joined(separator: ","))
        }
        // BOM ให้ Excel อ่านภาษาไทยถูก
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }
}
