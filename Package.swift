// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenRecord",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScreenRecord",
            path: "Sources/ScreenRecord",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
