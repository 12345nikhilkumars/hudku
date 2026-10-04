import Foundation

/// Runs a command-line tool out of process and hands back what it wrote.
enum ToolRunner {
    struct Result: Sendable {
        /// Standard output, verbatim.
        let output: String
        /// Standard error, verbatim; empty when the tool wrote none.
        let error: String

        var succeeded: Bool { exitCode == 0 }
        let exitCode: Int32

        /// The last few lines of whichever stream spoke, for one-line failure messages.
        var tail: String {
            let streams = [output, error].joined(separator: "\n")
            let lines = streams.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
            return lines.suffix(3).joined(separator: "\n")
        }
    }

    struct Failure: Error {
        let errorDescription: String
    }

    /// The tool exits on its own, or the timeout kills it; a launch failure throws.
    static func run(
        _ executable: URL, _ arguments: [String], timeout: TimeInterval?
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let exited = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in
                continuation.yield()
                continuation.finish()
            }
        }
        do {
            try process.run()
        } catch {
            throw Failure(errorDescription: error.localizedDescription)
        }

        if let timeout {
            let killer = Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard process.isRunning else { return }
                process.terminate()
            }
            defer { killer.cancel() }
            for await _ in exited { break }
        } else {
            for await _ in exited { break }
        }

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        return Result(
            output: String(bytes: output, encoding: .utf8) ?? "",
            error: String(bytes: error, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus)
    }
}
