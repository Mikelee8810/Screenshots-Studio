// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Screenshots",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Screenshots", targets: ["Screenshots"])
    ],
    targets: [
        .executableTarget(
            name: "Screenshots",
            path: "Sources"
        )
    ]
)
