import Foundation
import Testing
@testable import ClipAnalysisCore
import Voice2TextCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite("PlatformDetector")
struct PlatformDetectorTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=abc123", Platform.youtube, "abc123"),
        ("https://m.youtube.com/watch?v=abc123&t=10s", .youtube, "abc123"),
        ("https://youtu.be/abc123?si=xyz", .youtube, "abc123"),
        ("https://www.youtube.com/shorts/abc123", .shorts, "abc123"),
        ("https://youtube.com/shorts/abc123?feature=share", .shorts, "abc123"),
        ("https://www.instagram.com/reel/C5abc/", .reels, "C5abc"),
        ("https://instagram.com/reels/C5abc", .reels, "C5abc"),
    ])
    func clip(_ link: String, _ platform: Platform, _ id: String) {
        guard case let .clip(p, videoID, _) = PlatformDetector.detect(link) else {
            Issue.record("ควรเป็นคลิป: \(link)")
            return
        }
        #expect(p == platform)
        #expect(videoID == id)
    }

    @Test(arguments: [
        "https://www.youtube.com/@MrBeast",
        "https://www.youtube.com/@MrBeast/shorts",
        "https://www.youtube.com/channel/UCX6OQ3DkcsbYNE6H8uQQuVA",
        "https://www.youtube.com/playlist?list=PL123",
    ])
    func collection(_ link: String) {
        guard case .collection = PlatformDetector.detect(link) else {
            Issue.record("ควรเป็นช่อง/เพลย์ลิสต์: \(link)")
            return
        }
    }

    @Test(arguments: [
        "https://www.tiktok.com/@x/video/1",
        "https://www.instagram.com/p/C5abc/",
        "not a link",
        "",
    ])
    func unsupported(_ link: String) {
        guard case .unsupported = PlatformDetector.detect(link) else {
            Issue.record("ไม่ควรรองรับ: \(link)")
            return
        }
    }

    @Test func splitsPastedLinks() {
        let text = "https://youtu.be/a\nhttps://youtu.be/b, https://youtu.be/c  \n\n"
        #expect(PlatformDetector.splitLinks(text).count == 3)
    }
}

@Suite("ClipMetrics")
struct ClipMetricsTests {
    @Test func engagementRate() {
        let m = ClipMetrics(views: 1000, likes: 40, comments: 10, followers: 500)
        #expect(m.engagementRate == 0.05)
        #expect(m.viewsPerFollower == 2)
    }

    @Test func missingValuesStayNil() {
        #expect(ClipMetrics(views: 1000).engagementRate == nil)
        #expect(ClipMetrics(likes: 5).engagementRate == nil)
        #expect(ClipMetrics(views: 0, likes: 5).engagementRate == nil)
        #expect(ClipMetrics(views: 100, followers: 0).viewsPerFollower == nil)
    }
}

@Suite("MetadataFetcher parsing")
struct MetadataParsingTests {
    @Test func shortFromShortsLink() throws {
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: fixture("youtube_short"))
        let record = try MetadataFetcher.makeRecord(
            from: info, sourceURL: URL(string: "https://www.youtube.com/shorts/aNI2jv7lBPQ")!)
        #expect(record.platform == .shorts)
        #expect(record.id == "youtube_aNI2jv7lBPQ")
        #expect(record.metrics.views != nil)
        #expect(record.channel == "MrBeast")
        #expect(record.uploadDate != nil)
    }

    @Test func verticalWatchLinkBecomesShorts() throws {
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: fixture("youtube_short"))
        let record = try MetadataFetcher.makeRecord(
            from: info, sourceURL: URL(string: "https://www.youtube.com/watch?v=aNI2jv7lBPQ")!)
        #expect(record.platform == .shorts)
        #expect(record.url.absoluteString == "https://www.youtube.com/shorts/aNI2jv7lBPQ")
    }

    @Test func nestedChannelTabsAreFlattened() throws {
        let urls = try MetadataFetcher.clipURLs(
            fromPlaylistJSON: fixture("channel_flat"),
            sourceURL: URL(string: "https://www.youtube.com/@MrBeast")!,
            limit: 10)
        #expect(urls.count == 4)
        #expect(urls.contains { $0.path.hasPrefix("/shorts/") })
    }

    @Test func collectionRespectsLimit() throws {
        let urls = try MetadataFetcher.clipURLs(
            fromPlaylistJSON: fixture("channel_flat"),
            sourceURL: URL(string: "https://www.youtube.com/@MrBeast")!,
            limit: 3)
        #expect(urls.count == 3)
    }

    @Test func uploadDate() {
        #expect(MetadataFetcher.parseUploadDate("20240115") != nil)
        #expect(MetadataFetcher.parseUploadDate("2024") == nil)
        #expect(MetadataFetcher.parseUploadDate(nil) == nil)
    }
}

@Suite("LibraryStore")
struct LibraryStoreTests {
    private func tempStore() -> LibraryStore {
        LibraryStore(baseDir: FileManager.default.temporaryDirectory
            .appendingPathComponent("v2t-test-\(UUID().uuidString)"))
    }

    @Test func upsertKeepsCreatedAtAndUpdatesMetrics() throws {
        let store = tempStore()
        let first = ClipRecord(
            platform: .shorts, videoID: "abc", url: URL(string: "https://www.youtube.com/shorts/abc")!,
            title: "A", metrics: ClipMetrics(views: 10),
            createdAt: Date(timeIntervalSince1970: 1000))
        try store.upsert(first)

        var second = first
        second.metrics.views = 99
        second.createdAt = Date()
        try store.upsert(second)

        let all = store.loadAll()
        #expect(all.count == 1)
        #expect(all[0].metrics.views == 99)
        #expect(all[0].createdAt == Date(timeIntervalSince1970: 1000))
    }

    @Test func delete() throws {
        let store = tempStore()
        let clip = ClipRecord(platform: .reels, videoID: "x1", url: URL(string: "https://www.instagram.com/reel/x1/")!, title: "R")
        try store.upsert(clip)
        try store.delete(id: clip.id)
        #expect(store.loadAll().isEmpty)
    }
}

@Suite("SpeechMetrics")
struct SpeechMetricsTests {
    /// คำละ 0.25 วิ ห่างกัน 0.05 วิ — ระหว่าง 3.95–6.0 วิ เงียบ 2.05 วินาที
    private func englishSegments() -> [TranscriptSegment] {
        let first = (0..<10).map { i in
            TranscriptWord(text: " word\(i)", start: 1.0 + Double(i) * 0.3, end: 1.0 + Double(i) * 0.3 + 0.25)
        }
        let second = (0..<10).map { i in
            TranscriptWord(text: " more\(i)", start: 6.0 + Double(i) * 0.3, end: 6.0 + Double(i) * 0.3 + 0.25)
        }
        return [
            TranscriptSegment(start: 1.0, end: 4.0, text: first.map(\.text).joined(), words: first),
            TranscriptSegment(start: 6.0, end: 9.0, text: second.map(\.text).joined(), words: second),
        ]
    }

    @Test func basicPaceAndPauses() throws {
        let m = try #require(SpeechMetrics.compute(segments: englishSegments(), language: "en", clipDuration: 10))
        #expect(m.wordCount == 20)
        #expect(m.timeToFirstWord == 1.0)
        #expect(m.pauseCount == 1)
        #expect(abs(m.longestPause - 2.05) < 0.01)
        // เวลาพูด = 2 ช่วง × 2.95 วิ (รอยต่อ 0.05 วิระหว่างคำนับเป็นเวลาพูด)
        #expect(abs(m.speakingSeconds - 5.9) < 0.01)
        #expect(abs(m.wordsPerMinute - 20 / (5.9 / 60)) < 0.5)
        #expect(m.usedWordTimings)
        #expect(m.paceLabel == .fast)  // ~203 คำ/นาที, เกณฑ์อังกฤษ เร็ว < 210
    }

    @Test func thaiPiecesAreNotOvercounted() throws {
        // Whisper หั่นคำไทยเป็นก้อนเล็ก ๆ ไม่มีเว้นวรรค — ต้องนับเท่ากับข้อความเต็ม
        let text = "วิธีทำซุปกิมจิแบบง่าย"
        let pieces = ["วิ", "ธี", "ทำ", "ซุ", "ป", "กิม", "จิ", "แบบ", "ง่าย"]
        let words = pieces.enumerated().map { i, p in
            TranscriptWord(text: p, start: Double(i) * 0.2, end: Double(i) * 0.2 + 0.18)
        }
        let segments = [TranscriptSegment(start: 0, end: 1.8, text: text, words: words)]
        let m = try #require(SpeechMetrics.compute(segments: segments, language: "th", clipDuration: 2))
        let expected = SpeechMetrics.countWords(text, language: "th")
        #expect(m.wordCount == expected)
        #expect(expected < pieces.count)
        let opening = try #require(m.openingWPM)
        #expect(abs(opening - m.wordsPerMinute) < 1)
    }

    @Test func fallsBackToSegmentTimes() throws {
        let segments = [TranscriptSegment(start: 0, end: 6, text: "one two three four five six seven eight nine ten")]
        let m = try #require(SpeechMetrics.compute(segments: segments, language: "en", clipDuration: 6))
        #expect(!m.usedWordTimings)
        #expect(m.wordsPerMinute == 100)
        #expect(m.paceLabel == .slow)
    }

    @Test func noSpeechReturnsNil() {
        #expect(SpeechMetrics.compute(segments: [], language: nil, clipDuration: 10) == nil)
        #expect(SpeechMetrics.compute(segments: [TranscriptSegment(start: 0, end: 2, text: "♪ ♪")],
                                      language: nil, clipDuration: 10) == nil)
    }

    @Test func thresholds() {
        let t = PaceThresholds(slowBelow: 100, normalBelow: 150, fastBelow: 200)
        #expect(t.label(for: 99) == .slow)
        #expect(t.label(for: 100) == .normal)
        #expect(t.label(for: 199) == .fast)
        #expect(t.label(for: 200) == .veryFast)
    }

    @Test func sectionWPM() throws {
        let wpm = try #require(SpeechMetrics.wordsPerMinute(segments: englishSegments(), language: "en", from: 0, to: 5))
        #expect(abs(wpm - 10 / (2.95 / 60)) < 0.5)
    }
}

@Suite("ClipRecord")
struct ClipRecordTests {
    @Test func refetchKeepsTranscript() {
        var existing = ClipRecord(platform: .shorts, videoID: "a", url: URL(string: "https://www.youtube.com/shorts/a")!,
                                  title: "old", metrics: ClipMetrics(views: 1), createdAt: Date(timeIntervalSince1970: 0))
        existing.transcript = ClipTranscript(language: "th", segments: [], model: "m")
        let fresh = ClipRecord(platform: .shorts, videoID: "a", url: existing.url, title: "new", metrics: ClipMetrics(views: 50))
        existing.updateMetadata(from: fresh)
        #expect(existing.title == "new")
        #expect(existing.metrics.views == 50)
        #expect(existing.transcript != nil)
        #expect(existing.createdAt == Date(timeIntervalSince1970: 0))
    }
}
