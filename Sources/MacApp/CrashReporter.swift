import Darwin
import Foundation

// Written once before signal handlers are installed, then read only from the
// handler. `nonisolated(unsafe)` documents this process-lifetime ownership seam.
nonisolated(unsafe) private var crashLogFileDescriptor: Int32 = -1
nonisolated(unsafe) private var sigAbortRecord: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var sigSegvRecord: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var sigIllRecord: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var sigBusRecord: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var sigFpeRecord: UnsafeMutablePointer<CChar>?

private final class CrashLogURLState: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?

    func replace(with url: URL) {
        lock.lock()
        self.url = url
        lock.unlock()
    }

    func read() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return url
    }
}

final class CrashReporter {
    private static let logURLState = CrashLogURLState()

    static func setup(logDirectoryURL: URL? = nil) {
        let directoryURL = logDirectoryURL ?? defaultLogDirectoryURL()
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let logURL = directoryURL.appendingPathComponent("crash.log")
        logURLState.replace(with: logURL)
        configureSignalOutput(at: logURL)

        NSSetUncaughtExceptionHandler(crashExceptionHandler)

        signal(SIGABRT, signalHandler)
        signal(SIGSEGV, signalHandler)
        signal(SIGILL, signalHandler)
        signal(SIGBUS, signalHandler)
        signal(SIGFPE, signalHandler)
    }

    static func defaultLogDirectoryURL() -> URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library",
                isDirectory: true
            )
        return libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
    }

    private static func configureSignalOutput(at logURL: URL) {
        if crashLogFileDescriptor == -1 {
            crashLogFileDescriptor = logURL.path.withCString {
                Darwin.open($0, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
            }
        }

        if sigAbortRecord == nil {
            sigAbortRecord = strdup("[Whisper] Crash signal: SIGABRT\n")
            sigSegvRecord = strdup("[Whisper] Crash signal: SIGSEGV\n")
            sigIllRecord = strdup("[Whisper] Crash signal: SIGILL\n")
            sigBusRecord = strdup("[Whisper] Crash signal: SIGBUS\n")
            sigFpeRecord = strdup("[Whisper] Crash signal: SIGFPE\n")
        }
    }

    private static func write(_ message: String) {
        let logURL = logURLState.read()
            ?? defaultLogDirectoryURL().appendingPathComponent("crash.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)\n\n"

        if let data = fullMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? FileManager.default.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: logURL)
            }
        }
    }

    static func handleException(_ exception: NSException) {
        let message =
            "Uncaught exception: \(exception.name.rawValue) - \(exception.reason ?? "unknown")\n\(exception.callStackSymbols.joined(separator: "\n"))"
        write(message)
    }

    private static let signalHandler: @convention(c) (Int32) -> Void = { signal in
        let record: UnsafeMutablePointer<CChar>?
        let length: Int
        switch signal {
        case SIGABRT:
            record = sigAbortRecord
            length = 32
        case SIGSEGV:
            record = sigSegvRecord
            length = 32
        case SIGILL:
            record = sigIllRecord
            length = 31
        case SIGBUS:
            record = sigBusRecord
            length = 31
        case SIGFPE:
            record = sigFpeRecord
            length = 31
        default:
            record = nil
            length = 0
        }

        if crashLogFileDescriptor != -1, let record, length > 0 {
            _ = Darwin.write(crashLogFileDescriptor, record, length)
        }

        _ = Darwin.signal(signal, SIG_DFL)
        raise(signal)
    }
}

private func crashExceptionHandler(_ exception: NSException) {
    CrashReporter.handleException(exception)
}
