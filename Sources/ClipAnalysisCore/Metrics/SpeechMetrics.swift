import Foundation
import NaturalLanguage
import Voice2TextCore

/// ความเร็วการพูดแบ่งเป็น 4 ระดับ — เกณฑ์ปรับได้ใน Settings
public enum PaceLabel: String, Codable, CaseIterable, Hashable {
    case slow, normal, fast, veryFast

    public var displayName: String {
        switch self {
        case .slow: return "ช้า"
        case .normal: return "ปกติ"
        case .fast: return "เร็ว"
        case .veryFast: return "เร็วมาก"
        }
    }
}

/// เกณฑ์คำต่อนาที (ขอบบนของ ช้า / ปกติ / เร็ว) — เกินขอบสุดท้ายคือ "เร็วมาก"
public struct PaceThresholds: Codable, Hashable {
    public var slowBelow: Double
    public var normalBelow: Double
    public var fastBelow: Double

    public init(slowBelow: Double, normalBelow: Double, fastBelow: Double) {
        self.slowBelow = slowBelow
        self.normalBelow = normalBelow
        self.fastBelow = fastBelow
    }

    /// ไทยนับคำด้วย NLTokenizer ซึ่งตัดคำสั้นกว่าภาษาอังกฤษ ตัวเลขจึงสูงกว่า — ค่าเริ่มต้นควรปรับตามคลิปจริง
    public static let thaiDefault = PaceThresholds(slowBelow: 160, normalBelow: 230, fastBelow: 300)
    public static let englishDefault = PaceThresholds(slowBelow: 130, normalBelow: 170, fastBelow: 210)

    public func label(for wpm: Double) -> PaceLabel {
        if wpm < slowBelow { return .slow }
        if wpm < normalBelow { return .normal }
        if wpm < fastBelow { return .fast }
        return .veryFast
    }
}

/// ผลวัดการพูดของคลิป — คำนวณในเครื่องจาก transcript ไม่ใช้ AI (SPEC ข้อ 6)
public struct SpeechMetrics: Codable, Hashable {
    /// จำนวนคำ (ตัดคำด้วย NLTokenizer)
    public var wordCount: Int
    /// เวลาที่มีเสียงพูดจริง ไม่นับช่วงเงียบ (วินาที)
    public var speakingSeconds: Double
    /// คำต่อนาที คิดจากเวลาที่พูดจริง
    public var wordsPerMinute: Double
    /// คำต่อนาทีใน 5 วินาทีแรกที่เริ่มพูด — ใช้ดูจังหวะช่วง Hook ก่อนมีผลแบ่งช่วงจาก AI
    public var openingWPM: Double?
    /// วินาทีแรกที่เริ่มพูด
    public var timeToFirstWord: Double
    /// จำนวนช่วงเงียบที่ยาวกว่า `pauseThreshold`
    public var pauseCount: Int
    public var longestPause: Double
    /// สัดส่วนเวลาพูด ÷ ความยาวคลิป (0–1)
    public var speechRatio: Double?
    public var paceLabel: PaceLabel
    /// true = คำนวณจากเวลาของแต่ละคำ, false = ประมาณจากเวลาของประโยค (แม่นน้อยกว่า)
    public var usedWordTimings: Bool

    public static let pauseThreshold = 0.6
    static let openingWindow = 5.0

    /// คำนวณจาก segment ของ Whisper — คืน nil ถ้าไม่มีเสียงพูด
    public static func compute(
        segments: [TranscriptSegment],
        language: String?,
        clipDuration: Double?,
        thresholds: PaceThresholds? = nil
    ) -> SpeechMetrics? {
        let fullText = segments.map(\.text).joined(separator: " ")
        let wordCount = countWords(fullText, language: language)
        guard wordCount > 0 else { return nil }

        // ช่วงเวลาที่มีเสียงพูด: ใช้เวลาของแต่ละคำถ้ามี ไม่งั้นใช้ช่วงของประโยค
        let wordSpans = segments.flatMap { $0.words ?? [] }
            .filter { $0.end > $0.start }
            .map { (start: $0.start, end: $0.end, text: $0.text) }
        let usedWordTimings = !wordSpans.isEmpty
        let spans = usedWordTimings
            ? wordSpans
            : segments.filter { $0.end > $0.start }.map { (start: $0.start, end: $0.end, text: $0.text) }
        guard !spans.isEmpty else { return nil }

        // ช่องว่างสั้นกว่าเกณฑ์ช่วงเงียบนับเป็นเวลาพูด (เวลาของคำจาก Whisper ไม่รวมรอยต่อระหว่างคำ)
        let merged = mergeIntervals(spans.map { ($0.start, $0.end) }, bridging: pauseThreshold)
        let speaking = merged.reduce(0) { $0 + ($1.1 - $1.0) }
        guard speaking > 0 else { return nil }

        var gaps: [Double] = []
        for (previous, next) in zip(merged, merged.dropFirst()) {
            gaps.append(next.0 - previous.1)
        }
        let pauses = gaps.filter { $0 > pauseThreshold }

        let wpm = Double(wordCount) / (speaking / 60)
        let first = merged[0].0

        // ช่วงเปิด: นับคำในก้อนที่เริ่มภายใน 5 วินาทีแรกนับจากเริ่มพูด
        let openingEnd = first + openingWindow
        let openingSpans = spans.filter { $0.start < openingEnd }
        let openingSpeaking = mergeIntervals(openingSpans.map { ($0.start, min($0.end, openingEnd)) }, bridging: pauseThreshold)
            .reduce(0) { $0 + max(0, $1.1 - $1.0) }
        let openingWords = countWords(joinPieces(openingSpans.map(\.text), wordLevel: usedWordTimings), language: language)
        let openingWPM = openingSpeaking >= 1 && openingWords > 0
            ? Double(openingWords) / (openingSpeaking / 60) : nil

        let resolved = thresholds ?? (isThai(language) ? .thaiDefault : .englishDefault)
        return SpeechMetrics(
            wordCount: wordCount,
            speakingSeconds: speaking,
            wordsPerMinute: wpm,
            openingWPM: openingWPM,
            timeToFirstWord: first,
            pauseCount: pauses.count,
            longestPause: pauses.max() ?? 0,
            speechRatio: clipDuration.flatMap { $0 > 0 ? min(1, speaking / $0) : nil },
            paceLabel: resolved.label(for: wpm),
            usedWordTimings: usedWordTimings
        )
    }

    /// คำต่อนาทีในช่วงเวลาที่กำหนด — ใช้กับช่วง Hook / Body / CTA ในเฟส 3
    public static func wordsPerMinute(
        segments: [TranscriptSegment], language: String?, from start: Double, to end: Double
    ) -> Double? {
        let words = segments.flatMap { $0.words ?? [] }.filter { $0.start >= start && $0.start < end }
        let spans: [(Double, Double, String)] = words.isEmpty
            ? segments.filter { $0.start >= start && $0.start < end }.map { ($0.start, min($0.end, end), $0.text) }
            : words.map { ($0.start, min($0.end, end), $0.text) }
        let speaking = mergeIntervals(spans.map { ($0.0, $0.1) }, bridging: pauseThreshold).reduce(0) { $0 + max(0, $1.1 - $1.0) }
        let count = countWords(joinPieces(spans.map(\.2), wordLevel: !words.isEmpty), language: language)
        guard speaking >= 0.5, count > 0 else { return nil }
        return Double(count) / (speaking / 60)
    }

    /// ก้อนคำจาก Whisper มีเว้นวรรคนำหน้าอยู่แล้ว (ไทยถูกหั่นกลางคำ) — ต่อตรง ๆ ไม่เติมเว้นวรรค
    static func joinPieces(_ pieces: [String], wordLevel: Bool) -> String {
        pieces.joined(separator: wordLevel ? "" : " ")
    }

    public static func isThai(_ language: String?) -> Bool {
        language?.lowercased().hasPrefix("th") == true
    }

    /// นับคำด้วย NLTokenizer — ตัดคำไทยที่ไม่มีเว้นวรรคได้ ไม่นับเครื่องหมายวรรคตอน
    static func countWords(_ text: String, language: String?) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        if let language {
            tokenizer.setLanguage(NLLanguage(rawValue: language))
        }
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if text[range].contains(where: { $0.isLetter || $0.isNumber }) { count += 1 }
            return true
        }
        return count
    }

    /// รวมช่วงเวลาที่ซ้อนกัน หรือห่างกันไม่เกิน `bridging` วินาที เป็นช่วงเดียว
    static func mergeIntervals(_ intervals: [(Double, Double)], bridging: Double = 0) -> [(Double, Double)] {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var result: [(Double, Double)] = []
        for interval in sorted {
            if let last = result.last, interval.0 <= last.1 + bridging {
                result[result.count - 1].1 = max(last.1, interval.1)
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
