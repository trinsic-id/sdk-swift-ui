// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TrinsicUI",
    platforms: [
        .iOS(.v17)
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
    ]
)
