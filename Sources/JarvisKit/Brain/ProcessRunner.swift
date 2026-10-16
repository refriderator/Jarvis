import Foundation

/// Runs a command-line program off the main thread and collects its output.
enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
    }

    static func run(_ executable: URL, arguments: [String], environment: [String: String],
                    directory: URL, input: String, timeout: TimeInterval) async throws -> Output {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = directory
            let stdin = Pipe(), stdout = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            try process.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            return Output(status: process.terminationStatus, stdout: data)
        }.value
    }
}
