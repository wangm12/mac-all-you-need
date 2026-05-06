// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "Platform", targets: ["Platform"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "Core", path: "Sources/Core"),
        .target(name: "UI", dependencies: ["Core"], path: "Sources/UI"),
        .target(name: "Platform", dependencies: ["Core"], path: "Sources/Platform"),
        .testTarget(name: "CoreTests", dependencies: ["Core"], path: "Tests/CoreTests"),
        .testTarget(name: "UITests", dependencies: ["UI"], path: "Tests/UITests"),
        .testTarget(name: "PlatformTests", dependencies: ["Platform"], path: "Tests/PlatformTests"),
    ]
)
