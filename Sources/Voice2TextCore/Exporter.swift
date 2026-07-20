import Foundation

public enum Exporter {
    /// เลือกว่าจะ export ข้อความต้นฉบับ คำแปล หรือทั้งสองภาษา
    public enum Variant {
        case original
        case translated
        case bilingual
    }

    static func lines(of segment: TranscriptSegment, variant: Variant) -> String {
        switch variant {
        case .original:
            return segment.text
        case .translated:
            return segment.translation ?? segment.text
        case .bilingual:
            if let translation = segment.translation {
                return "\(segment.text)\n\(translation)"
            }
            return segment.text
        }
    }

    public static func plainText(_ segments: [TranscriptSegment], variant: Variant = .original) -> String {
        let separator = variant == .bilingual ? "\n\n" : "\n"
        return segments.map { lines(of: $0, variant: variant) }.joined(separator: separator)
    }

    public static func srt(_ segments: [TranscriptSegment], variant: Variant = .original) -> String {
        segments.enumerated().map { index, segment in
            "\(index + 1)\n\(srtTime(segment.start)) --> \(srtTime(segment.end))\n\(lines(of: segment, variant: variant))\n"
        }.joined(separator: "\n")
    }

    /// "01:23:45" สำหรับแสดงในหน้าจอ
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// "01:23:45,678" สำหรับไฟล์ .srt
    static func srtTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let ms = min(999, Int(((seconds - Double(total)) * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", total / 3600, (total % 3600) / 60, total % 60, ms)
    }
}
