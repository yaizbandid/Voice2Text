import Foundation
import AVFoundation

/// อัดเสียงจากไมโครโฟน + ถอดข้อความสดผ่าน LiveSession
/// ไฟล์เสียงเขียนลงดิสก์ตลอดเวลา (CAF/AAC ทนต่อการปิดกะทันหัน) จบแล้วแปลงเป็น .m4a
public final class LiveTranscriber {
    public struct Update {
        public let newSegments: [TranscriptSegment]
        public let liveText: String
        public let elapsed: Double
    }

    public struct Result {
        public let audioURL: URL
        public let segments: [TranscriptSegment]
        public let duration: Double
        public let detectedLanguage: String?
        /// จำนวนครั้งที่เขียน/แปลงบัฟเฟอร์เสียงพลาด — ถ้า > 0 ไฟล์เสียงอาจไม่สมบูรณ์
        public let fileWriteErrors: Int
    }

    private let engine = AVAudioEngine()
    private let session: LiveSession
    private let processingQueue = DispatchQueue(label: "v2t.live.audio")
    private var converter: AVAudioConverter?
    private var audioFile: AVAudioFile?
    private var cafURL: URL?
    private var tickTask: Task<Void, Never>?
    private var configObserver: NSObjectProtocol?
    private var onFailure: ((String) -> Void)?

    // สถานะที่ถูกแตะจากหลาย thread (audio tap / tick task / MainActor) — อ่านเขียนผ่านล็อกเสมอ
    private let stateLock = NSLock()
    private var _isRunning = false
    private var _totalSamples = 0
    private var _fileWriteErrors = 0

    public var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isRunning
    }
    public var elapsed: Double {
        stateLock.lock(); defer { stateLock.unlock() }
        return Double(_totalSamples) / LiveSession.sampleRate
    }
    private func setRunning(_ running: Bool) {
        stateLock.lock(); _isRunning = running; stateLock.unlock()
    }
    private var fileWriteErrors: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return _fileWriteErrors
    }

    public init(session: LiveSession) {
        self.session = session
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    public static func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public static var recordingsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voice2Text Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var targetFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: LiveSession.sampleRate,
            channels: 1, interleaved: false
        )
    }

    /// เริ่มอัด คืนชื่อไฟล์ที่กำลังบันทึก
    public func start(
        onUpdate: @escaping (Update) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws -> URL {
        guard !isRunning else { throw V2TError("กำลังอัดอยู่แล้ว") }
        self.onFailure = onFailure

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let baseName = "การประชุม \(formatter.string(from: Date()))"
        let cafURL = Self.recordingsDirectory.appendingPathComponent("\(baseName).caf")
        self.cafURL = cafURL

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw V2TError("ไม่พบไมโครโฟน — ตรวจสอบว่าเครื่องมีอุปกรณ์รับเสียง")
        }
        guard let targetFormat = Self.targetFormat,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw V2TError("ตั้งค่าตัวแปลงเสียงไม่สำเร็จ")
        }
        self.converter = converter

        // CAF + AAC: เขียนต่อเนื่องได้และไฟล์ไม่พังถ้าแอปถูกปิดกลางคัน
        audioFile = try AVAudioFile(
            forWriting: cafURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: LiveSession.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48000,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        stateLock.lock()
        _totalSamples = 0
        _fileWriteErrors = 0
        stateLock.unlock()

        installTap(inputFormat: inputFormat, targetFormat: targetFormat)
        engine.prepare()
        try engine.start()
        setRunning(true)

        // อุปกรณ์เสียงเปลี่ยนกลางคัน (เสียบ/ถอดหูฟัง ไมค์หลุด) — engine จะหยุดเงียบ ๆ
        // ต้องติดตั้ง tap ใหม่ตามฟอร์แมตใหม่แล้วอัดต่อ ไม่งั้นเสียการประชุมที่เหลือทั้งหมด
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        tickTask = Task { [weak self] in
            while let self, self.isRunning, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard self.isRunning, !Task.isCancelled else { break }
                if let result = try? await self.session.tick() {
                    onUpdate(Update(
                        newSegments: result.newlyConfirmed,
                        liveText: result.liveText,
                        elapsed: self.elapsed
                    ))
                }
            }
        }
        return cafURL
    }

    private func installTap(inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processingQueue.async {
                self?.process(buffer, targetFormat: targetFormat)
            }
        }
    }

    private func handleConfigurationChange() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        let newFormat = engine.inputNode.outputFormat(forBus: 0)
        guard newFormat.sampleRate > 0,
              let targetFormat = Self.targetFormat,
              let newConverter = AVAudioConverter(from: newFormat, to: targetFormat) else {
            onFailure?("อุปกรณ์เสียงเปลี่ยนและใช้งานต่อไม่ได้ — หยุดอัดเพื่อรักษาข้อความที่ถอดไว้แล้ว")
            return
        }
        // converter ถูกใช้บน processingQueue — เปลี่ยนผ่านคิวเดียวกันกันชนกัน
        processingQueue.async { [weak self] in
            self?.converter = newConverter
        }
        installTap(inputFormat: newFormat, targetFormat: targetFormat)
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                onFailure?("อุปกรณ์เสียงเปลี่ยนแล้วอัดต่อไม่สำเร็จ: \(error.localizedDescription)")
            }
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, converted.frameLength > 0,
              let channel = converted.floatChannelData else {
            stateLock.lock(); _fileWriteErrors += 1; stateLock.unlock()
            return
        }

        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(converted.frameLength)))
        session.feed(samples)
        stateLock.lock()
        _totalSamples += samples.count
        stateLock.unlock()
        do {
            try audioFile?.write(from: converted)
        } catch {
            stateLock.lock(); _fileWriteErrors += 1; stateLock.unlock()
        }
    }

    /// หยุดอัด: ถอดช่วงท้าย ปิดไฟล์ แล้วแปลงเป็น .m4a
    public func stop() async throws -> Result {
        guard isRunning else { throw V2TError("ยังไม่ได้เริ่มอัด") }
        setRunning(false)
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        tickTask?.cancel()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // รอ tick ที่อาจกำลังถอดค้างอยู่ให้จบก่อน กันถอดซ้อนกับ finish() บนโมเดลตัวเดียว
        if let tickTask {
            _ = await tickTask.value
        }
        tickTask = nil

        // รอให้คิวประมวลผลเสียงเขียนบัฟเฟอร์ค้างให้จบ
        processingQueue.sync {}
        audioFile = nil  // ปิดไฟล์

        let segments = try await session.finish()
        let duration = elapsed

        var finalURL = cafURL!
        if let m4a = try? await MediaConverter.convertToM4A(finalURL) {
            try? FileManager.default.removeItem(at: finalURL)
            finalURL = m4a
        }
        return Result(
            audioURL: finalURL,
            segments: segments,
            duration: duration,
            detectedLanguage: session.lockedLanguage,
            fileWriteErrors: fileWriteErrors
        )
    }
}
