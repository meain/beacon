// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "beacon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "beacon",
            path: "Sources/beacon",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
