import Foundation
import Voice2TextCore

/// ดึงเสียงของคลิป → ถอดเสียงพร้อมเวลาของแต่ละคำ → วัดการพูด
/// ต้องโหลดโมเดล Whisper ไว้ก่อน (TranscriptionService.shared.loadModel)
public enum ClipTranscriber {
    public enum Stage {
        case downloading(Double)
        case status(String)
        case extracting
        case transcribing(Double)
    }

    public static func transcribe(
        _ clip: ClipRecord,
        language: String?,
        thai: PaceThresholds = .thaiDefault,
        other: PaceThresholds = .englishDefault,
        onStage: @escaping (Stage) -> Void
    ) async throws -> ClipRecord {
        let service = TranscriptionService.shared
        guard service.whisperKit != nil else {
            throw V2TError("โมเดลถอดเสียงยังไม่พร้อม — รอให้โหลดเสร็จในแท็บถอดเสียงก่อน")
        }

        let download = try await MediaDownloader.shared.download(
            from: clip.url,
            onStatus: { onStage(.status($0)) },
            onProgress: { onStage(.downloading($0)) })
        defer { cleanUp(download.fileURL) }

        onStage(.extracting)
        let audioURL = try await MediaConverter.prepareAudio(from: download.fileURL)
        let output = try await service.transcribe(
            audioURL: audioURL,
            language: language,
            wordTimestamps: true,
            onLiveText: { _ in },
            onProgress: { onStage(.transcribing($0)) })

        var updated = clip
        let detected = language ?? output.language
        updated.transcript = ClipTranscript(
            language: detected, segments: output.segments, model: service.loadedModel)
        updated.speech = SpeechMetrics.compute(
            segments: output.segments,
            language: detected,
            clipDuration: clip.durationSeconds,
            thresholds: SpeechMetrics.isThai(detected) ? thai : other)
        updated.transcriptError = nil
        return updated
    }

    /// ลบไฟล์เสียงชั่วคราว — yt-dlp เก็บไว้ในโฟลเดอร์ v2t-dl-<uuid> ของตัวเอง (ลบทั้งโฟลเดอร์ได้)
    /// ส่วนลิงก์ไฟล์ตรงเป็นไฟล์เดี่ยวใน temp (ลบแค่ไฟล์)
    private static func cleanUp(_ fileURL: URL) {
        let folder = fileURL.deletingLastPathComponent()
        let target = folder.lastPathComponent.hasPrefix("v2t-dl-") ? folder : fileURL
        try? FileManager.default.removeItem(at: target)
    }
}
