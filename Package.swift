// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "clipandcue",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "clipandcue",
            path: "Sources/clipandcue"
        )
    ]
)
