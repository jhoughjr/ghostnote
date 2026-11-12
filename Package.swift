// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ghostnote",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GhostnoteEngine", targets: ["GhostnoteEngine"]),
    ],
    targets: [
        .target(
            name: "GhostnoteEngine"
        ),
        .testTarget(
            name: "GhostnoteEngineTests",
            dependencies: ["GhostnoteEngine"]
        ),
    ]
)
