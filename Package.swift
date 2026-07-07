// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "fin-ui",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "fin-ui",
            path: "Sources/fin-ui",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
