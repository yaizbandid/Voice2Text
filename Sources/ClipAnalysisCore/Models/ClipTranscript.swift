import Foundation
import Voice2TextCore

/// ข้อความถอดเสียงของคลิป (พร้อมเวลาของแต่ละคำ) — เก็บใน ClipRecord
public struct ClipTranscript: Codable, Hashable {
    public var language: String?
    public var segments: [TranscriptSegment]
    /// โมเดล Whisper ที่ใช้ถอด
    public var model: String?
    public var transcribedAt: Date

    public init(language: String?, segments: [TranscriptSegment], model: String?, transcribedAt: Date = Date()) {
        self.language = language
        self.segments = segments
        self.model = model
        self.transcribedAt = transcribedAt
    }

    public var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }
}
