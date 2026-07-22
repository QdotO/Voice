// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Whisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Whisper", targets: ["Whisper"]),
        .library(name: "WhisperShared", targets: ["WhisperShared"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    ],
    targets: [
        .target(
            name: "WhisperShared",
            dependencies: [
                "WhisperKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Shared"
        ),
        .executableTarget(
            name: "Whisper",
            dependencies: [
                "WhisperShared",
                "HotKey",
            ],
            path: "Sources/MacApp"
        ),
        .testTarget(
            name: "WhisperTests",
            dependencies: ["WhisperShared"],
            path: "Tests",
            exclude: ["CrashReporterHarness"]
        ),
    ],
    swiftLanguageVersions: [.version("6")]
)
