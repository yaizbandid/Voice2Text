import Foundation

public struct TranscriptSegment: Identifiable, Hashable, Codable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    /// คำแปลของ segment นี้ (ถ้าผู้ใช้สั่งแปลแล้ว)
    public var translation: String?

    public init(start: Double, end: Double, text: String) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct V2TError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
