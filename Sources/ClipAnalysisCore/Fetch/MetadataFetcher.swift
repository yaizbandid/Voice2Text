import Foundation
import Voice2TextCore

/// ดึง metadata ของคลิปผ่าน `yt-dlp -J --skip-download` — ไม่ดาวน์โหลดตัววิดีโอ
public final class MetadataFetcher {
    public static let shared = MetadataFetcher()
    private init() {}

    public struct Options {
        /// เบราว์เซอร์ที่ใช้คุกกี้ (chrome, safari, firefox, …) — จำเป็นสำหรับ Reels ส่วนใหญ่
        public var cookiesFromBrowser: String?
        public init(cookiesFromBrowser: String? = nil) {
            self.cookiesFromBrowser = cookiesFromBrowser
        }
    }

    /// ดึงข้อมูลคลิปเดียว
    public func fetchClip(
        _ url: URL,
        options: Options = Options(),
        onStatus: @escaping (String) -> Void = { _ in }
    ) async throws -> ClipRecord {
        let tool = try await MediaDownloader.shared.ensureYtDlp(onStatus: onStatus)
        var args = ["-J", "--skip-download", "--no-warnings", "--no-playlist"]
        args += cookieArgs(options)
        args.append(url.absoluteString)

        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.status == 0 else {
            throw Self.friendlyError(result.stderrLastLine, url: url)
        }
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: result.stdout)
        return try Self.makeRecord(from: info, sourceURL: url)
    }

    /// แตกลิงก์ช่อง/เพลย์ลิสต์เป็นรายการลิงก์คลิป (ล่าสุดก่อน) สูงสุด `limit` ตัว
    public func expandCollection(
        _ url: URL,
        limit: Int,
        options: Options = Options(),
        onStatus: @escaping (String) -> Void = { _ in }
    ) async throws -> [URL] {
        let tool = try await MediaDownloader.shared.ensureYtDlp(onStatus: onStatus)
        var args = ["--flat-playlist", "-J", "--no-warnings", "--playlist-end", String(max(1, limit))]
        args += cookieArgs(options)
        args.append(url.absoluteString)

        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.status == 0 else {
            throw Self.friendlyError(result.stderrLastLine, url: url)
        }
        return try Self.clipURLs(fromPlaylistJSON: result.stdout, sourceURL: url, limit: limit)
    }

    static func clipURLs(fromPlaylistJSON data: Data, sourceURL url: URL, limit: Int) throws -> [URL] {
        let playlist = try JSONDecoder().decode(YtDlpPlaylist.self, from: data)
        let isShortsTab = url.path.hasSuffix("/shorts")
        let urls = Self.flattenEntries(playlist.entries ?? []).compactMap { entry -> URL? in
            if isShortsTab, let id = entry.id {
                return URL(string: "https://www.youtube.com/shorts/\(id)")
            }
            if let raw = entry.url, let entryURL = URL(string: raw), entryURL.scheme != nil {
                return entryURL
            }
            return entry.id.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }
        }
        return Array(urls.prefix(limit))
    }

    private func cookieArgs(_ options: Options) -> [String] {
        guard let browser = options.cookiesFromBrowser, !browser.isEmpty else { return [] }
        return ["--cookies-from-browser", browser]
    }

    /// หน้าช่องที่ไม่ได้ระบุแท็บ yt-dlp คืนเป็นเพลย์ลิสต์ซ้อน (Videos / Shorts / Live) — แตกออกให้หมด
    private static func flattenEntries(_ entries: [YtDlpPlaylist.Entry]) -> [YtDlpPlaylist.Entry] {
        entries.flatMap { entry in
            if let nested = entry.entries { return flattenEntries(nested) }
            return [entry]
        }
    }

    // MARK: - แปลงผล yt-dlp → ClipRecord

    static func makeRecord(from info: YtDlpInfo, sourceURL: URL, now: Date = Date()) throws -> ClipRecord {
        let detected = PlatformDetector.detect(info.webpageURL ?? sourceURL.absoluteString)
        let sourceKind = PlatformDetector.detect(sourceURL.absoluteString)

        var platform: Platform
        var url: URL
        switch (sourceKind, detected) {
        case let (.clip(p, _, u), _):
            platform = p; url = u
        case let (_, .clip(p, _, u)):
            platform = p; url = u
        default:
            throw V2TError("ยังรองรับเฉพาะ YouTube, Shorts และ Reels")
        }
        if platform == .youtube,
           PlatformDetector.looksLikeShorts(width: info.width, height: info.height, duration: info.duration) {
            platform = .shorts
            url = URL(string: "https://www.youtube.com/shorts/\(info.id)")!
        }

        return ClipRecord(
            platform: platform,
            videoID: info.id,
            url: url,
            title: info.title ?? info.id,
            channel: info.channel ?? info.uploader,
            channelID: info.channelID ?? info.uploaderID,
            description: info.description,
            tags: info.tags ?? [],
            durationSeconds: info.duration,
            uploadDate: parseUploadDate(info.uploadDate) ?? info.timestamp.map { Date(timeIntervalSince1970: $0) },
            thumbnailURL: info.thumbnail.flatMap(URL.init(string:)),
            metrics: ClipMetrics(
                views: info.viewCount,
                likes: info.likeCount,
                comments: info.commentCount,
                followers: info.channelFollowerCount
            ),
            status: .fetched,
            createdAt: now,
            fetchedAt: now
        )
    }

    static func parseUploadDate(_ raw: String?) -> Date? {
        guard let raw, raw.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: raw)
    }

    static func friendlyError(_ line: String?, url: URL) -> V2TError {
        let message = line ?? "ไม่ทราบสาเหตุ"
        let lower = message.lowercased()
        if url.host()?.contains("instagram") == true,
           lower.contains("login") || lower.contains("cookie") || lower.contains("rate-limit") {
            return V2TError("Instagram ต้องล็อกอินก่อน — เปิด \"ใช้คุกกี้จากเบราว์เซอร์\" ในการตั้งค่า (เบราว์เซอร์ที่เลือกต้องล็อกอิน Instagram ไว้)")
        }
        if lower.contains("private") {
            return V2TError("คลิปนี้เป็นส่วนตัว เข้าถึงไม่ได้")
        }
        if lower.contains("unavailable") || lower.contains("not available") {
            return V2TError("คลิปนี้ถูกลบหรือไม่เปิดให้ดู")
        }
        return V2TError("ดึงข้อมูลไม่สำเร็จ: \(message)")
    }
}

// MARK: - โครงสร้าง JSON ของ yt-dlp (เฉพาะฟิลด์ที่ใช้)

struct YtDlpInfo: Decodable {
    let id: String
    let title: String?
    let description: String?
    let webpageURL: String?
    let channel: String?
    let channelID: String?
    let uploader: String?
    let uploaderID: String?
    let channelFollowerCount: Int?
    let viewCount: Int?
    let likeCount: Int?
    let commentCount: Int?
    let duration: Double?
    let uploadDate: String?
    let timestamp: Double?
    let thumbnail: String?
    let tags: [String]?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, description, channel, uploader, duration, timestamp, thumbnail, tags, width, height
        case webpageURL = "webpage_url"
        case channelID = "channel_id"
        case uploaderID = "uploader_id"
        case channelFollowerCount = "channel_follower_count"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case uploadDate = "upload_date"
    }
}

struct YtDlpPlaylist: Decodable {
    let entries: [Entry]?

    struct Entry: Decodable {
        let id: String?
        let url: String?
        let entries: [Entry]?
    }
}
