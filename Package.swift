// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Whisper",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "Whisper", targets: ["Whisper"]),
        .library(name: "WhisperShared", targets: ["WhisperShared"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "WhisperShared",
            dependencies: [
                "WhisperKit"
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
            path: "Tests"
        ),
    ]
)
