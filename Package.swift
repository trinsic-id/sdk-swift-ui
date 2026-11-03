// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TrinsicUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TrinsicUI",
            targets: ["TrinsicUI"]),
    ],
    targets: [
        .target(
            name: "TrinsicUI",
            dependencies: []),
        .testTarget(
            name: "TrinsicUITests",
            dependencies: ["TrinsicUI"]),
    ]
)
