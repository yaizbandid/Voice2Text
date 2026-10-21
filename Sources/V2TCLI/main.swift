import Foundation
import Voice2TextCore
import ClipAnalysisCore

// เครื่องมือทดสอบผ่าน Terminal:
//   v2t <ไฟล์เสียงหรือวิดีโอ> [--model openai_whisper-tiny] [--lang th|en|auto]
//   v2t --list-models
//   v2t meta <ลิงก์คลิปหรือช่อง> [--limit 10] [--cookies chrome]

let rawArgs = Array(CommandLine.arguments.dropFirst())

func option(_ name: String, default defaultValue: String) -> String {
    if let index = rawArgs.firstIndex(of: name), index + 1 < rawArgs.count {
        return rawArgs[index + 1]
    }
    return defaultValue
}

do {
    if rawArgs.first == "meta" {
        try await runMeta()
        exit(0)
    }

    if rawArgs.contains("--list-models") {
        print("โมเดลที่มีบน argmaxinc/whisperkit-coreml:")
        for model in try await TranscriptionService.availableModels() {
            print("  \(model)")
        }
        exit(0)
    }

    guard let file = rawArgs.first(where: { !$0.hasPrefix("--") }) else {
        print("วิธีใช้: v2t <ไฟล์เสียงหรือวิดีโอ> [--model openai_whisper-tiny] [--lang th|en|auto]")
        print("        v2t --list-models")
        exit(1)
    }

    let model = option("--model", default: "openai_whisper-tiny")
    let langArg = option("--lang", default: "auto")
    let language: String? = langArg == "auto" ? nil : langArg

    print("โมเดล: \(model) | ภาษา: \(langArg)")

    var lastPercent = -1
    let service = TranscriptionService.shared
    try await service.loadModel(
        model,
        downloadProgress: { progress in
            let percent = Int(progress * 100)
            if percent != lastPercent, percent % 10 == 0 {
                lastPercent = percent
                print("  ดาวน์โหลดโมเดล \(percent)%")
            }
        },
        onLoadStart: {
            print("กำลังโหลดโมเดลเข้าหน่วยความจำ (ครั้งแรกอาจใช้เวลาสักครู่)…")
        }
    )
    // รองรับทั้งไฟล์ในเครื่องและลิงก์ (YouTube ฯลฯ)
    let inputURL: URL
    if file.hasPrefix("http://") || file.hasPrefix("https://") {
        guard let remote = MediaDownloader.remoteURL(from: file) else {
            print("❌ ลิงก์ไม่ถูกต้อง")
            exit(1)
        }
        var lastDownloadPercent = -1
        let result = try await MediaDownloader.shared.download(
            from: remote,
            onStatus: { print("  \($0)") },
            onProgress: { progress in
                let percent = Int(progress * 100)
                if percent != lastDownloadPercent, percent % 20 == 0 {
                    lastDownloadPercent = percent
                    print("  ดาวน์โหลดวิดีโอ \(percent)%")
                }
            }
        )
        print("ได้ไฟล์: \(result.title)")
        inputURL = result.fileURL
    } else {
        inputURL = URL(fileURLWithPath: file)
    }

    print("โมเดลพร้อม เริ่มถอดเสียง: \(inputURL.lastPathComponent)")
    let audioURL = try await MediaConverter.prepareAudio(from: inputURL)
    let duration = (try? await MediaConverter.duration(of: audioURL)) ?? 0

    let started = Date()
    let output = try await service.transcribe(
        audioURL: audioURL,
        language: language,
        onLiveText: { _ in },
        onProgress: { _ in }
    )
    let elapsed = -started.timeIntervalSinceNow

    print(String(repeating: "-", count: 60))
    for segment in output.segments {
        print("[\(Exporter.clock(segment.start))] \(segment.text)")
    }
    print(String(repeating: "-", count: 60))
    if let detected = output.language {
        print("ภาษาที่ตรวจพบ: \(detected)")
    }
    let speed = duration > 0 && elapsed > 0 ? String(format: " (เร็วกว่า realtime %.1f เท่า)", duration / elapsed) : ""
    print(String(format: "เสร็จใน %.1f วินาที จากเสียงยาว %.1f วินาที%@", elapsed, duration, speed))
} catch {
    print("❌ \(error.localizedDescription)")
    exit(1)
}

/// v2t meta — ดึงยอดวิว/ไลก์/คอมเมนต์ (ไม่ดาวน์โหลดวิดีโอ ไม่บันทึกลงคลัง)
func runMeta() async throws {
    guard let link = rawArgs.dropFirst().first(where: { !$0.hasPrefix("--") }) else {
        print("วิธีใช้: v2t meta <ลิงก์คลิปหรือช่อง> [--limit 10] [--cookies chrome]")
        exit(1)
    }
    let cookies = option("--cookies", default: "")
    let options = MetadataFetcher.Options(cookiesFromBrowser: cookies.isEmpty ? nil : cookies)
    let limit = Int(option("--limit", default: "10")) ?? 10

    let urls: [URL]
    switch PlatformDetector.detect(link) {
    case .clip(_, _, let url):
        urls = [url]
    case .collection(let url):
        urls = try await MetadataFetcher.shared.expandCollection(url, limit: limit, options: options)
        print("พบ \(urls.count) คลิป")
    case .unsupported:
        print("❌ ยังรองรับเฉพาะ YouTube, Shorts และ Reels")
        exit(1)
    }

    for url in urls {
        do {
            let clip = try await MetadataFetcher.shared.fetchClip(url, options: options)
            let m = clip.metrics
            func show(_ value: Int?) -> String { value.map(String.init) ?? "-" }
            let er = m.engagementRate.map { String(format: "%.2f%%", $0 * 100) } ?? "-"
            print(String(repeating: "-", count: 60))
            print("[\(clip.platform.displayName)] \(clip.title)")
            print("  ช่อง: \(clip.channel ?? "-")  ผู้ติดตาม: \(show(m.followers))")
            print("  วิว: \(show(m.views))  ไลก์: \(show(m.likes))  คอมเมนต์: \(show(m.comments))  ER: \(er)")
            print("  ยาว: \(clip.durationSeconds.map { "\(Int($0)) วิ" } ?? "-")  id: \(clip.id)")
        } catch {
            print("❌ \(url.absoluteString): \(error.localizedDescription)")
        }
    }
}
