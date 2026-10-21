import Foundation
import Testing
@testable import ClipAnalysisCore

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
