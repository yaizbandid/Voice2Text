import Foundation

/// ดาวน์โหลดสื่อจากลิงก์ — YouTube และเว็บวิดีโอต่าง ๆ ผ่าน yt-dlp
/// ส่วนลิงก์ไฟล์สื่อตรง ๆ (.mp3/.mp4 ฯลฯ) ใช้ URLSession
public final class MediaDownloader {
    public static let shared = MediaDownloader()
    private init() {}

    public struct DownloadResult {
        public let fileURL: URL
        public let title: String
    }

    /// แปลงข้อความเป็นลิงก์ http/https ที่ใช้ได้ (คืน nil ถ้าไม่ใช่)
    public static func remoteURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }

    public func download(
        from url: URL,
        onStatus: @escaping (String) -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> DownloadResult {
        if MediaConverter.supportedExtensions.contains(url.pathExtension.lowercased()) {
            return try await downloadDirect(url: url, onProgress: onProgress)
        }
        return try await downloadWithYtDlp(url: url, onStatus: onStatus, onProgress: onProgress)
    }

    // MARK: - yt-dlp

    private static var bundledYtDlpURL: URL {
        TranscriptionService.modelsBaseDir.appendingPathComponent("bin/yt-dlp")
    }

    private static var ytDlpCandidates: [String] {
        [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            NSHomeDirectory() + "/.local/bin/yt-dlp",
            bundledYtDlpURL.path,
        ]
    }

    public static func installedYtDlpPath() -> String? {
        ytDlpCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static let ytDlpDownloadURL =
        URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

    /// คืน path ของ yt-dlp — ถ้าไม่มีในเครื่อง ดาวน์โหลดตัว standalone มาเก็บให้เอง (ครั้งเดียว)
    /// ตัวที่แอปติดตั้งเองจะถูกเช็คอัปเดตเป็นระยะ เพราะ YouTube ปรับระบบบ่อยจน yt-dlp เก่าใช้ไม่ได้
    public func ensureYtDlp(onStatus: @escaping (String) -> Void) async throws -> String {
        if let path = Self.installedYtDlpPath() {
            if path == Self.bundledYtDlpURL.path {
                await selfUpdateIfStale(path, onStatus: onStatus)
            }
            return path
        }

        onStatus("กำลังติดตั้งเครื่องมือดาวน์โหลดวิดีโอ (ครั้งแรกเท่านั้น ~35MB)…")
        let dest = Self.bundledYtDlpURL
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (tmp, response) = try await URLSession.shared.download(from: Self.ytDlpDownloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw V2TError("ดาวน์โหลดเครื่องมือ yt-dlp ไม่สำเร็จ — ติดตั้งเองได้ด้วยคำสั่ง: brew install yt-dlp")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        try? Data().write(to: Self.updateStampURL)
        return dest.path
    }

    // MARK: - Self-update ของ yt-dlp

    private static var updateStampURL: URL {
        bundledYtDlpURL.deletingLastPathComponent().appendingPathComponent(".last-update-check")
    }

    /// รัน `yt-dlp -U` ถ้าไม่ได้เช็คมาเกิน 3 วัน — กันตกรุ่นเวลา YouTube ปรับระบบ
    private func selfUpdateIfStale(_ toolPath: String, onStatus: @escaping (String) -> Void) async {
        let stamp = Self.updateStampURL
        if let modified = try? stamp.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) < 3 * 24 * 3600 {
            return
        }
        onStatus("กำลังเช็คอัปเดตตัวดาวน์โหลดวิดีโอ…")
        await runSelfUpdate(toolPath)
        try? Data().write(to: stamp)
    }

    /// รัน `yt-dlp -U` (ตัว standalone อัปเดตทับตัวเองได้) — ล้มเหลวก็ไม่เป็นไร ใช้ตัวเดิมต่อ
    private func runSelfUpdate(_ toolPath: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["-U", "--no-warnings"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// ดาวน์โหลดพร้อมลองซ้ำ — 403 จาก YouTube ส่วนใหญ่เป็นการปฏิเสธชั่วคราว
    /// ลำดับ: ลองปกติ 2 ครั้ง → อัปเดต yt-dlp แล้วลองครั้งสุดท้าย
    private func downloadWithYtDlp(
        url: URL,
        onStatus: @escaping (String) -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> DownloadResult {
        let toolPath = try await ensureYtDlp(onStatus: onStatus)

        var lastError: Error = V2TError("ดาวน์โหลดวิดีโอไม่สำเร็จ")
        for attempt in 1...3 {
            do {
                if attempt > 1 {
                    onStatus("ลองใหม่ครั้งที่ \(attempt)…")
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                } else {
                    onStatus("กำลังเชื่อมต่อกับเว็บไซต์…")
                }
                return try await runYtDlpOnce(
                    toolPath: toolPath, url: url, onProgress: onProgress)
            } catch {
                lastError = error
                let message = error.localizedDescription
                let retryable = message.contains("403") || message.contains("Forbidden")
                    || message.contains("timed out") || message.contains("Connection")
                guard retryable, attempt < 3 else { break }
                // ก่อนความพยายามครั้งสุดท้าย อัปเดต yt-dlp เผื่อ YouTube เพิ่งปรับระบบ
                if attempt == 2, toolPath == Self.bundledYtDlpURL.path {
                    onStatus("กำลังอัปเดตตัวดาวน์โหลดวิดีโอ…")
                    await runSelfUpdate(toolPath)
                    try? Data().write(to: Self.updateStampURL)
                }
            }
        }
        if lastError.localizedDescription.contains("403") {
            throw V2TError("YouTube ปฏิเสธการดาวน์โหลดชั่วคราว (403) — รอสักครู่แล้วส่งลิงก์ใหม่อีกครั้ง มักจะผ่าน")
        }
        throw lastError
    }

    private func runYtDlpOnce(
        toolPath: String,
        url: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> DownloadResult {

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2t-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.currentDirectoryURL = workDir
        process.arguments = [
            "--no-playlist",
            "--no-warnings",
            "--newline",
            "-f", "ba[ext=m4a]/ba/b",
            "-o", "%(title).80B.%(ext)s",
            url.absoluteString,
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let percentRegex = try! NSRegularExpression(pattern: #"\[download\]\s+(\d+(?:\.\d+)?)%"#)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            for line in chunk.split(separator: "\n") {
                let text = String(line)
                let range = NSRange(text.startIndex..., in: text)
                if let match = percentRegex.firstMatch(in: text, range: range),
                   let percentRange = Range(match.range(at: 1), in: text),
                   let percent = Double(text[percentRange]) {
                    onProgress(percent / 100)
                }
            }
        }
        let errorBuffer = ErrorBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        guard status == 0 else {
            throw V2TError("ดาวน์โหลดวิดีโอไม่สำเร็จ: \(errorBuffer.lastLine() ?? "รหัส \(status)")")
        }

        let files = (try FileManager.default.contentsOfDirectory(
            at: workDir, includingPropertiesForKeys: [.fileSizeKey]))
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension != "part" }
        guard let media = files.max(by: { fileSize($0) < fileSize($1) }) else {
            throw V2TError("ดาวน์โหลดเสร็จแต่ไม่พบไฟล์สื่อ")
        }
        return DownloadResult(fileURL: media, title: media.deletingPathExtension().lastPathComponent)
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// กันข้อความ error จาก stderr ให้อ่านทีหลังได้แบบ thread-safe
    private final class ErrorBuffer: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()
        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }
        func lastLine() -> String? {
            lock.lock(); defer { lock.unlock() }
            return String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map(String.init)
        }
    }

    // MARK: - Direct file URL

    private func downloadDirect(
        url: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> DownloadResult {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw V2TError("ดาวน์โหลดไฟล์ไม่สำเร็จ (HTTP \(code))")
        }
        let expected = response.expectedContentLength
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2t-dl-\(UUID().uuidString).\(url.pathExtension)")
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 { onProgress(Double(received) / Double(expected)) }
            }
        }
        try handle.write(contentsOf: buffer)
        onProgress(1.0)

        let title = url.deletingPathExtension().lastPathComponent.removingPercentEncoding
            ?? url.deletingPathExtension().lastPathComponent
        return DownloadResult(fileURL: dest, title: title)
    }
}
