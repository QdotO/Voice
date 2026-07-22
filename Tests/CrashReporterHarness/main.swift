import Darwin
import Foundation

if CommandLine.arguments.contains("--print-default-directory") {
    print(CrashReporter.defaultLogDirectoryURL().path)
    exit(EXIT_SUCCESS)
}

guard let directoryPath = ProcessInfo.processInfo.environment["WHISPER_CRASH_HARNESS_DIRECTORY"] else {
    fatalError("WHISPER_CRASH_HARNESS_DIRECTORY is required")
}

CrashReporter.setup(
    logDirectoryURL: URL(fileURLWithPath: directoryPath, isDirectory: true)
)
raise(SIGABRT)
