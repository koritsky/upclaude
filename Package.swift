// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Upclaude",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "UpclaudeLib",
            path: "Sources/UpclaudeLib",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Upclaude",
            dependencies: ["UpclaudeLib"],
            path: "Sources/Upclaude",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "UpclaudeTests",
            dependencies: ["UpclaudeLib"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
