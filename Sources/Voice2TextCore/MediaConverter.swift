import Foundation
import AVFoundation

/// แปลงไฟล์สื่อให้อยู่ในรูปแบบที่ WhisperKit อ่านได้
/// - ไฟล์เสียง: ส่งต่อได้เลย
/// - ไฟล์วิดีโอ: แยกแทร็กเสียงออกมาเป็น .m4a ชั่วคราวก่อน
public enum MediaConverter {
    public static let audioExtensions: Set<String> = [
        "mp3", "wav", "m4a", "aac", "flac", "aiff", "aif", "caf",
    ]
    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mpg", "mpeg",
    ]
    public static var supportedExtensions: Set<String> {
        audioExtensions.union(videoExtensions)
    }

    public static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    public static func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let time = try await asset.load(.duration)
        return CMTimeGetSeconds(time)
    }

    public static func prepareAudio(from url: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw V2TError("ไม่พบไฟล์ \(url.lastPathComponent)")
        }
        if audioExtensions.contains(url.pathExtension.lowercased()) {
            return url
        }

        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw V2TError("ไฟล์ \(url.lastPathComponent) ไม่มีแทร็กเสียง")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw V2TError("ไม่สามารถแยกเสียงจากไฟล์ \(url.lastPathComponent) ได้")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2t-\(UUID().uuidString).m4a")
        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            throw V2TError("แยกเสียงไม่สำเร็จ: \(error.localizedDescription)")
        }
        return outputURL
    }

    /// แปลงไฟล์เสียงเป็น .m4a ข้าง ๆ ไฟล์เดิม (ใช้ตอนปิดงานอัดประชุม)
    public static func convertToM4A(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw V2TError("แปลงไฟล์เสียงไม่สำเร็จ")
        }
        let outputURL = url.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outputURL)
        try await session.export(to: outputURL, as: .m4a)
        return outputURL
    }
}
