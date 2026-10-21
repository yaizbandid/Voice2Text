import Foundation
import Voice2TextCore

/// คลังคลิป — เก็บ ClipRecord ละไฟล์ JSON ที่
/// `~/Library/Application Support/Voice2Text/Analysis/clips/`
public final class LibraryStore {
    public let clipsDir: URL

    public init(baseDir: URL = TranscriptionService.modelsBaseDir.appendingPathComponent("Analysis", isDirectory: true)) {
        clipsDir = baseDir.appendingPathComponent("clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// โหลดทุกคลิป ใหม่สุดก่อน — ไฟล์ที่อ่านไม่ได้จะถูกข้าม (ไม่ลบทิ้ง)
    public func loadAll() -> [ClipRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(ClipRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func load(id: String) -> ClipRecord? {
        try? Self.decoder.decode(ClipRecord.self, from: Data(contentsOf: fileURL(id)))
    }

    /// บันทึก — ถ้ามีคลิปนี้อยู่แล้ว เก็บ createdAt เดิมไว้
    @discardableResult
    public func upsert(_ record: ClipRecord) throws -> ClipRecord {
        var record = record
        if let existing = load(id: record.id) {
            record.createdAt = existing.createdAt
        }
        let data = try Self.encoder.encode(record)
        try data.write(to: fileURL(record.id), options: .atomic)
        return record
    }

    public func delete(id: String) throws {
        let url = fileURL(id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(_ id: String) -> URL {
        // id มาจาก platform + video id — กันอักขระที่ใช้เป็นชื่อไฟล์ไม่ได้
        let safe = id.replacingOccurrences(of: #"[^A-Za-z0-9_\-]"#, with: "_", options: .regularExpression)
        return clipsDir.appendingPathComponent("\(safe).json")
    }
}
