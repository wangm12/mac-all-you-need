// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "Platform", targets: ["Platform"]),
        .library(name: "FeatureCore", targets: ["FeatureCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0")
    ],
    targets: [
        .target(
            name: "CArgon2",
            path: "Sources/CArgon2",
            sources: [
                "argon2-shim.c",
                "argon2/src/argon2.c",
                "argon2/src/core.c",
                "argon2/src/encoding.c",
                "argon2/src/ref.c",
                "argon2/src/thread.c",
                "argon2/src/blake2/blake2b.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("argon2/include"),
                .headerSearchPath("argon2/src"),
                .headerSearchPath("argon2/src/blake2")
            ]
        ),
        .systemLibrary(
            name: "CLibArchive",
            path: "Sources/CLibArchive"
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "CArgon2"
            ],
            path: "Sources/Core"
        ),
        .target(name: "UI", dependencies: [
            "Core",
            "Platform",
            .product(name: "Splash", package: "Splash")
        ], path: "Sources/UI"),
        .target(name: "Platform", dependencies: ["Core", "CLibArchive"], path: "Sources/Platform"),
        .testTarget(name: "CoreTests", dependencies: ["Core"], path: "Tests/CoreTests"),
        .testTarget(name: "UITests", dependencies: ["UI"], path: "Tests/UITests"),
        .testTarget(name: "PlatformTests", dependencies: ["Platform"], path: "Tests/PlatformTests"),
        .target(
            name: "FeatureCore",
            dependencies: ["Core"],
            path: "Sources/FeatureCore"
        ),
        .testTarget(
            name: "FeatureCoreTests",
            dependencies: ["FeatureCore", "Core"],
            path: "Tests/FeatureCoreTests"
        ),
    ]
)
