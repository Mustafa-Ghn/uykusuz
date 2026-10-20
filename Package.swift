// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Uykusuz",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        .executableTarget(
            name: "Uykusuz",
            path: "Sources/Uykusuz",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Test-only C target. Its constructor points UYKUSUZ_HOME at a temp
        // directory when the test bundle loads, before any test can log.
        .target(
            name: "UykusuzTestHome",
            path: "Tests/UykusuzTestHome"
        ),
        .testTarget(
            name: "UykusuzTests",
            dependencies: ["Uykusuz", "UykusuzTestHome"],
            path: "Tests/UykusuzTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
