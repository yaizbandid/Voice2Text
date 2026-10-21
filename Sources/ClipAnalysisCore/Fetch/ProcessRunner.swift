import Foundation

/// รันโปรแกรมภายนอกแล้วเก็บ stdout ทั้งหมด — ใช้กับ `yt-dlp -J` ที่คืน JSON ขนาดใหญ่
enum ProcessRunner {
    struct Result {
        let status: Int32
        let stdout: Data
        let stderr: Data

        var stderrLastLine: String? {
            String(data: stderr, encoding: .utf8)?
                .split(separator: "\n")
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(String.init)
        }
    }

    static func run(_ executable: String, arguments: [String]) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // อ่านทั้งสองท่อระหว่างที่โปรเซสทำงาน กันท่อเต็มแล้วค้าง
        let stdoutBuffer = LockedData()
        let stderrBuffer = LockedData()
        stdoutPipe.fileHandleForReading.readabilityHandler = { stdoutBuffer.append($0.availableData) }
        stderrPipe.fileHandleForReading.readabilityHandler = { stderrBuffer.append($0.availableData) }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        // เก็บข้อมูลที่ยังค้างอยู่ในท่อหลังโปรเซสจบ
        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        return Result(status: status, stdout: stdoutBuffer.value, stderr: stderrBuffer.value)
    }

    private final class LockedData: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()
        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }
        var value: Data {
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }
}
