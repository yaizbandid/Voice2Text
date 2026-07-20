import Foundation

/// ตรรกะถอดเสียงสด: รับ sample สะสม, ถอดซ้ำเป็นรอบ ๆ,
/// แล้ว "ยืนยัน" segment ที่พ้นช่วงเสี่ยงว่าจะเปลี่ยนไปแล้ว เพื่อไม่ต้องถอดซ้ำทั้งการประชุม
/// แยกออกจากส่วนจับเสียงไมค์ เพื่อให้ทดสอบด้วยไฟล์ได้ (v2t --simulate-live)
public final class LiveSession {
    public static let sampleRate = 16000.0

    /// ยาวเกินเท่านี้ค่อยเริ่มยืนยันและตัดหน้าต่าง
    private let confirmWindowSeconds: Double
    /// ช่วงท้ายที่ยังไม่ยืนยัน เพราะข้อความอาจเปลี่ยนเมื่อได้ยินต่อ
    private let keepTailSeconds: Double

    private let service: TranscriptionService
    private let preferredLanguage: String?
    /// ภาษาที่ล็อกไว้ใช้ทั้งการอัด — ล็อกเมื่อผู้ใช้บังคับ หรือเมื่อการตรวจจับนิ่งแล้ว
    public private(set) var lockedLanguage: String?
    /// ผลตรวจภาษาของรอบก่อนหน้า ใช้เช็คว่าการตรวจจับนิ่งหรือยัง
    private var lastDetectedLanguage: String?
    /// ต้องมีเสียงอย่างน้อยเท่านี้ก่อนจะเชื่อผลตรวจภาษา (หน้าต่างสั้น ๆ เดาผิดง่ายมาก)
    private let minLanguageLockSeconds: Double = 8

    private var buffer: [Float] = []
    private let bufferLock = NSLock()
    private var offsetSeconds: Double = 0
    public private(set) var confirmedSegments: [TranscriptSegment] = []

    public init(
        service: TranscriptionService,
        language: String?,
        confirmWindowSeconds: Double = 30,
        keepTailSeconds: Double = 6
    ) {
        self.service = service
        self.preferredLanguage = language
        self.lockedLanguage = language
        self.confirmWindowSeconds = confirmWindowSeconds
        self.keepTailSeconds = keepTailSeconds
    }

    public func feed(_ samples: [Float]) {
        bufferLock.lock()
        buffer.append(contentsOf: samples)
        bufferLock.unlock()
    }

    private func snapshotBuffer() -> [Float] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return buffer
    }

    private func dropBufferPrefix(_ count: Int) {
        bufferLock.lock()
        buffer.removeFirst(min(count, buffer.count))
        bufferLock.unlock()
    }

    private func clearBuffer() {
        bufferLock.lock()
        buffer.removeAll()
        bufferLock.unlock()
    }

    public struct TickResult {
        /// segment ที่เพิ่งยืนยันเพิ่มในรอบนี้ (เวลาเป็นวินาทีสัมบูรณ์จากจุดเริ่มอัด)
        public let newlyConfirmed: [TranscriptSegment]
        /// ข้อความช่วงท้ายที่ยังไม่ยืนยัน ไว้แสดงสด ๆ
        public let liveText: String
    }

    /// ข้ามหน้าต่างที่เงียบ — Whisper ชอบสร้างข้อความหลอนจากความเงียบ/เสียงรบกวน
    /// เกณฑ์ตั้งต่ำมาก (ตัดเฉพาะความเงียบจริง ๆ) เพื่อไม่ตัดเสียงพูดเบา/ไมค์เกนต่ำ —
    /// เสียงกำกวมปล่อยให้ noSpeechThreshold ของ Whisper กรองอีกชั้น
    static func isMostlySilent(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return true }
        var sumOfSquares: Float = 0
        var peak: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
            peak = max(peak, abs(sample))
        }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        return rms < 0.0005 && peak < 0.004
    }

    /// ล็อกภาษาต่อเมื่อ (1) ผู้ใช้ไม่ได้บังคับภาษา (2) มีเสียงยาวพอ และ
    /// (3) ผลตรวจตรงกับรอบก่อนหน้า — กันเคสหน้าต่างแรกสั้น ๆ เดาภาษาผิด (เช่นเดาเป็นไอซ์แลนด์)
    /// แล้วค้างไปทั้งการอัด
    private func updateLanguageLock(detected: String?, windowSeconds: Double) {
        guard lockedLanguage == nil, let detected else { return }
        if windowSeconds >= minLanguageLockSeconds, detected == lastDetectedLanguage {
            lockedLanguage = detected
        } else {
            lastDetectedLanguage = detected
        }
    }

    /// เรียกเป็นระยะ (~ทุก 2-3 วินาที) เพื่อถอดหน้าต่างเสียงปัจจุบัน
    public func tick() async throws -> TickResult {
        let window = snapshotBuffer()
        let windowSeconds = Double(window.count) / Self.sampleRate
        guard windowSeconds >= 1.0 else {
            return TickResult(newlyConfirmed: [], liveText: "")
        }
        if Self.isMostlySilent(window) {
            // เงียบยาว ๆ (เช่นพักประชุม): ตัดบัฟเฟอร์ทิ้งโดยเก็บช่วงท้ายไว้
            // ไม่งั้นหน่วยความจำและเวลาถอดต่อรอบจะโตไปเรื่อย ๆ
            if windowSeconds > confirmWindowSeconds {
                let keep = Int(keepTailSeconds * Self.sampleRate)
                let drop = window.count - keep
                if drop > 0 {
                    dropBufferPrefix(drop)
                    offsetSeconds += Double(drop) / Self.sampleRate
                }
            }
            return TickResult(newlyConfirmed: [], liveText: "")
        }

        let output = try await service.transcribeSamples(window, language: lockedLanguage)
        updateLanguageLock(detected: output.language, windowSeconds: windowSeconds)
        let segments = output.segments

        var newlyConfirmed: [TranscriptSegment] = []
        var confirmedCut: Double = 0

        // ยังไม่ยืนยันข้อความจนกว่าภาษาจะนิ่ง กันข้อความภาษาผิดถูกล็อกถาวร
        // ปกติรอให้มี segment อย่างน้อย 2 ช่วง แต่ถ้าพูดต่อเนื่องจน segment เดียวลากยาวมาก
        // ให้ยืนยันได้เลย กันหน้าต่างโตไม่จำกัด
        let enoughSegments = segments.count >= 2 || windowSeconds > confirmWindowSeconds + 15
        if windowSeconds > confirmWindowSeconds, enoughSegments, lockedLanguage != nil {
            let cutoff = windowSeconds - keepTailSeconds
            let toConfirm = segments.filter { $0.end <= cutoff }
            if let lastEnd = toConfirm.last?.end, lastEnd > 1.0 {
                newlyConfirmed = toConfirm.map {
                    TranscriptSegment(
                        start: $0.start + offsetSeconds,
                        end: $0.end + offsetSeconds,
                        text: $0.text
                    )
                }
                confirmedSegments.append(contentsOf: newlyConfirmed)
                confirmedCut = lastEnd
                dropBufferPrefix(Int(lastEnd * Self.sampleRate))
                offsetSeconds += lastEnd
            }
        }

        let liveText = segments
            .filter { $0.end > confirmedCut }
            .map(\.text)
            .joined(separator: " ")
        return TickResult(newlyConfirmed: newlyConfirmed, liveText: liveText)
    }

    /// ปิดงาน: ถอดส่วนที่ค้างในหน้าต่างแล้วยืนยันทั้งหมด คืน segment ครบทุกช่วง
    /// (ไม่ใช้ silence gate ที่นี่ — รอบสุดท้ายควรพยายามถอดเสมอ ให้ Whisper กรองเองพอ)
    public func finish() async throws -> [TranscriptSegment] {
        let window = snapshotBuffer()
        if Double(window.count) / Self.sampleRate >= 0.5 {
            let output = try await service.transcribeSamples(window, language: lockedLanguage)
            if lockedLanguage == nil {
                // อัดสั้นจนไม่ทันล็อกภาษา — ใช้ผลตรวจจากเสียงทั้งก้อนซึ่งแม่นกว่าหน้าต่างสั้น
                lockedLanguage = output.language
            }
            let remaining = output.segments.map {
                TranscriptSegment(
                    start: $0.start + offsetSeconds,
                    end: $0.end + offsetSeconds,
                    text: $0.text
                )
            }
            confirmedSegments.append(contentsOf: remaining)
        }
        clearBuffer()
        return confirmedSegments
    }
}
