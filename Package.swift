// swift-tools-version: 6.0
import PackageDescription

// Target names differ from the product names on purpose: macOS disks are case-insensitive, so an app called
// `Bellhop` and a CLI called `bellhop` can't share a build folder. The bundle script renames the app binary to
// `Bellhop`.
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "Bellhop",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BellhopCore", targets: ["BellhopCore"]),
        .executable(name: "BellhopApp", targets: ["BellhopApp"]),
        .executable(name: "bellhop", targets: ["BellhopCLI"]),
        .executable(name: "bellhop-probe", targets: ["bellhop-probe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "BellhopCore",
            path: "Sources/BellhopCore",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "BellhopApp",
            dependencies: [
                "BellhopCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/BellhopApp",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "BellhopCLI",
            dependencies: [
                "BellhopCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/BellhopCLI",
            swiftSettings: swiftSettings
        ),
        // Milestone 1 spike. Delete once BellhopCore's scanner replaces it.
        .executableTarget(
            name: "bellhop-probe",
            dependencies: [
                "BellhopCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/bellhop-probe",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "BellhopCoreTests",
            dependencies: ["BellhopCore"],
            path: "Tests/BellhopCoreTests",
            swiftSettings: swiftSettings
        ),
    ]
)
