import Foundation

/// แพลตฟอร์มที่รองรับ — ดู SPEC.md ข้อ 1
public enum Platform: String, Codable, CaseIterable, Hashable {
    case youtube
    case shorts
    case reels

    public var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .shorts: return "Shorts"
        case .reels: return "Reels"
        }
    }

    /// YouTube กับ Shorts ใช้ video id ชุดเดียวกัน — ใช้เป็น prefix ของ clipID
    var idNamespace: String {
        switch self {
        case .youtube, .shorts: return "youtube"
        case .reels: return "instagram"
        }
    }
}

/// สถานะของคลิปในคลัง — เฟสถัดไปจะเพิ่ม transcribing / analyzing / pendingReview ฯลฯ
public enum ClipStatus: String, Codable, Hashable {
    case fetched
    case failed
}

/// ตัวเลขจากแพลตฟอร์ม — ค่าที่แพลตฟอร์มไม่เปิดเผยเก็บเป็น nil (ห้ามใส่ 0)
public struct ClipMetrics: Codable, Hashable {
    public var views: Int?
    public var likes: Int?
    public var comments: Int?
    public var followers: Int?

    public init(views: Int? = nil, likes: Int? = nil, comments: Int? = nil, followers: Int? = nil) {
        self.views = views
        self.likes = likes
        self.comments = comments
        self.followers = followers
    }

    /// (ไลก์ + คอมเมนต์) ÷ วิว — ไม่นับแชร์ เพราะ YouTube ไม่เปิดเผย
    public var engagementRate: Double? {
        guard let views, views > 0, likes != nil || comments != nil else { return nil }
        return Double((likes ?? 0) + (comments ?? 0)) / Double(views)
    }

    /// วิว ÷ ผู้ติดตาม — มากกว่า 1 แปลว่าคลิปไปไกลกว่าฐานแฟน
    public var viewsPerFollower: Double? {
        guard let views, let followers, followers > 0 else { return nil }
        return Double(views) / Double(followers)
    }
}

/// คลิป 1 ตัวในคลัง — บันทึกเป็น `Analysis/clips/<id>.json`
public struct ClipRecord: Codable, Identifiable, Hashable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// `<namespace>_<videoID>` เช่น `youtube_dQw4w9WgXcQ` — วางลิงก์ซ้ำจะอัปเดตตัวเดิม
    public var id: String
    public var platform: Platform
    public var videoID: String
    public var url: URL
    public var title: String
    public var channel: String?
    public var channelID: String?
    public var description: String?
    public var tags: [String]
    public var durationSeconds: Double?
    public var uploadDate: Date?
    public var thumbnailURL: URL?
    public var metrics: ClipMetrics
    public var status: ClipStatus
    public var errorMessage: String?
    /// ข้อความถอดเสียง (เฟส 2) — nil = ยังไม่ได้ถอด
    public var transcript: ClipTranscript?
    /// ผลวัดการพูด — nil = ยังไม่ได้ถอด หรือคลิปไม่มีเสียงพูด
    public var speech: SpeechMetrics?
    /// ข้อผิดพลาดล่าสุดของการถอดเสียง
    public var transcriptError: String?
    public var createdAt: Date
    public var fetchedAt: Date

    public init(
        platform: Platform,
        videoID: String,
        url: URL,
        title: String,
        channel: String? = nil,
        channelID: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        durationSeconds: Double? = nil,
        uploadDate: Date? = nil,
        thumbnailURL: URL? = nil,
        metrics: ClipMetrics = ClipMetrics(),
        status: ClipStatus = .fetched,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        fetchedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = Self.makeID(platform: platform, videoID: videoID)
        self.platform = platform
        self.videoID = videoID
        self.url = url
        self.title = title
        self.channel = channel
        self.channelID = channelID
        self.description = description
        self.tags = tags
        self.durationSeconds = durationSeconds
        self.uploadDate = uploadDate
        self.thumbnailURL = thumbnailURL
        self.metrics = metrics
        self.status = status
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.fetchedAt = fetchedAt
    }

    /// อัปเดตเฉพาะข้อมูลจากแพลตฟอร์ม (ดึงยอดใหม่) — เก็บ transcript / ผลวิเคราะห์ / createdAt เดิมไว้
    public mutating func updateMetadata(from fresh: ClipRecord) {
        platform = fresh.platform
        url = fresh.url
        title = fresh.title
        channel = fresh.channel
        channelID = fresh.channelID
        description = fresh.description
        tags = fresh.tags
        durationSeconds = fresh.durationSeconds
        uploadDate = fresh.uploadDate
        thumbnailURL = fresh.thumbnailURL
        metrics = fresh.metrics
        status = fresh.status
        errorMessage = fresh.errorMessage
        fetchedAt = fresh.fetchedAt
    }

    public static func makeID(platform: Platform, videoID: String) -> String {
        "\(platform.idNamespace)_\(videoID)"
    }

    /// อายุคลิปเป็นวัน — คลิปใหม่ยอดยังไม่นิ่ง ใช้กรองในสถิติ
    public func ageDays(now: Date = Date()) -> Int? {
        guard let uploadDate else { return nil }
        return Calendar.current.dateComponents([.day], from: uploadDate, to: now).day
    }
}
