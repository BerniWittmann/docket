import Foundation

public protocol ProcessRunning: Sendable {
    /// Runs a command and returns stdout. Throws `SourceError` with stderr on a non-zero exit.
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> Data
}

public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.searchPath.joined(separator: ":")
        process.environment = environment
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            let output = OutputBuffer()
            stdout.fileHandleForReading.readabilityHandler = { output.append($0.availableData) }
            process.terminationHandler = { process in
                stdout.fileHandleForReading.readabilityHandler = nil
                output.append(stdout.fileHandleForReading.readDataToEndOfFile())
                let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: SourceError.message("\(Self.name(executable)) timed out"))
                } else if process.terminationStatus != 0 {
                    let message = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: SourceError.message(message.isEmpty ? "\(Self.name(executable)) exited with \(process.terminationStatus)" : message))
                } else {
                    continuation.resume(returning: output.data)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: SourceError.message("Cannot run \(executable): \(error.localizedDescription)"))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }

    private static func name(_ executable: String) -> String { URL(fileURLWithPath: executable).lastPathComponent }

    /// GUI apps start with a minimal PATH, so look where Homebrew and friends install tools.
    static let searchPath: [String] = {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let common = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                      NSHomeDirectory() + "/.local/bin"]
        return common + inherited.filter { !common.contains($0) }
    }()

    /// The full path of a command, or nil when it is not installed.
    public static func locate(_ command: String) -> String? {
        if command.contains("/") { return FileManager.default.isExecutableFile(atPath: command) ? command : nil }
        return searchPath.map { "\($0)/\(command)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    func append(_ data: Data) { lock.withLock { buffer.append(data) } }
    var data: Data { lock.withLock { buffer } }
}
