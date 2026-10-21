import Foundation

public struct TranscriptSegment: Identifiable, Hashable, Codable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    /// คำแปลของ segment นี้ (ถ้าผู้ใช้สั่งแปลแล้ว)
    public var translation: String?
    /// เวลาของแต่ละคำ — มีเฉพาะเมื่อถอดแบบ wordTimestamps (ใช้ในแท็บวิเคราะห์คลิป)
    public var words: [TranscriptWord]?

    public init(start: Double, end: Double, text: String, words: [TranscriptWord]? = nil) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }
}

/// คำ 1 คำพร้อมเวลา — ภาษาไทยไม่มีเว้นวรรค Whisper อาจรวมหลายคำเป็นก้อนเดียว
public struct TranscriptWord: Hashable, Codable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct V2TError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
