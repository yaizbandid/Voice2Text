import Foundation

/// แยกประเภทลิงก์ที่ผู้ใช้วาง: คลิปเดี่ยว / ช่องหรือเพลย์ลิสต์ / ไม่รองรับ
public enum LinkKind: Equatable {
    case clip(platform: Platform, videoID: String, url: URL)
    case collection(url: URL)
    case unsupported(String)
}

public enum PlatformDetector {
    private static let youtubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
    ]
    private static let instagramHosts: Set<String> = ["instagram.com", "www.instagram.com"]

    public static func detect(_ text: String) -> LinkKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host()?.lowercased()
        else {
            return .unsupported(trimmed)
        }
        let parts = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be", let id = parts.first {
            return .clip(platform: .youtube, videoID: id, url: watchURL(id))
        }

        if youtubeHosts.contains(host) {
            if parts.first == "watch", let id = queryValue("v", in: url) {
                return .clip(platform: .youtube, videoID: id, url: watchURL(id))
            }
            if parts.count >= 2, parts[0] == "shorts" {
                let id = parts[1]
                return .clip(platform: .shorts, videoID: id,
                             url: URL(string: "https://www.youtube.com/shorts/\(id)")!)
            }
            if parts.count >= 2, parts[0] == "live" {
                return .clip(platform: .youtube, videoID: parts[1], url: watchURL(parts[1]))
            }
            // ช่อง (@handle, /channel/, /c/, /user/) และเพลย์ลิสต์
            if let first = parts.first,
               first.hasPrefix("@") || ["channel", "c", "user", "playlist"].contains(first) {
                return .collection(url: url)
            }
            return .unsupported(trimmed)
        }

        if instagramHosts.contains(host) {
            if parts.count >= 2, ["reel", "reels"].contains(parts[0]) {
                let id = parts[1]
                return .clip(platform: .reels, videoID: id,
                             url: URL(string: "https://www.instagram.com/reel/\(id)/")!)
            }
            return .unsupported(trimmed)
        }

        return .unsupported(trimmed)
    }

    /// แยกหลายลิงก์จากข้อความที่วางมา (ขึ้นบรรทัดใหม่ / เว้นวรรค / จุลภาค)
    public static func splitLinks(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// YouTube ที่ไม่ได้มาจากลิงก์ /shorts/ แต่จริง ๆ เป็น Shorts — ดูจากสัดส่วนภาพแนวตั้งและความยาว
    static func looksLikeShorts(width: Int?, height: Int?, duration: Double?) -> Bool {
        guard let width, let height, let duration else { return false }
        return height > width && duration <= 180
    }

    private static func watchURL(_ id: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}
