// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "clipandcue",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Sparkle drives the in-app auto-updater (verify-and-swap, no
        // browser detour). Pinned to 2.x; latest minor brings the fixes
        // we care about and stays binary-stable for users on v0.2.8+.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "clipandcue",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/clipandcue"
        )
    ]
)
