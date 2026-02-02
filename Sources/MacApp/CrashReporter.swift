import Foundation

final class CrashReporter {
    private static var logPathCString: UnsafeMutablePointer<CChar>?

    static func setup() {
        let logPath = crashLogPath()
        if logPathCString == nil {
            logPathCString = strdup(logPath)
        }

        NSSetUncaughtExceptionHandler(crashExceptionHandler)

        signal(SIGABRT, signalHandler)
        signal(SIGSEGV, signalHandler)
        signal(SIGILL, signalHandler)
        signal(SIGBUS, signalHandler)
        signal(SIGFPE, signalHandler)
    }

    private static func crashLogPath() -> String {
        let bundleRoot = Bundle.main.bundleURL.deletingLastPathComponent()
        let logsDir = bundleRoot.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("crash.log").path
    }

    private static func write(_ message: String) {
        let logPath = crashLogPath()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)\n\n"

        if let data = fullMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    static func handleException(_ exception: NSException) {
        let message =
            "Uncaught exception: \(exception.name.rawValue) - \(exception.reason ?? "unknown")\n\(exception.callStackSymbols.joined(separator: "\n"))"
        write(message)
    }

    private static let signalHandler: @convention(c) (Int32) -> Void = { signal in
        guard let path = logPathCString else {
            _ = Darwin.signal(signal, SIG_DFL)
            raise(signal)
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let message = "[\(timestamp)] Crash signal: \(signal)\n\n"
        let fd = open(path, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        if fd != -1 {
            _ = message.withCString { ptr in
                Darwin.write(fd, ptr, strlen(ptr))
            }
            close(fd)
        }

        _ = Darwin.signal(signal, SIG_DFL)
        raise(signal)
    }
}

private func crashExceptionHandler(_ exception: NSException) {
    CrashReporter.handleException(exception)
}
