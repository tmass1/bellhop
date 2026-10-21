// swift-tools-version: 6.0
import PackageDescription

// Target names differ from the product names on purpose: macOS disks are case-insensitive, so an app called
// `Valet` and a CLI called `valet` can't share a build folder. The bundle script renames the app binary to `Valet`.
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "Valet",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ValetCore", targets: ["ValetCore"]),
        .executable(name: "ValetApp", targets: ["ValetApp"]),
        .executable(name: "valet", targets: ["ValetCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "ValetCore",
            path: "Sources/ValetCore",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "ValetApp",
            dependencies: ["ValetCore"],
            path: "Sources/ValetApp",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "ValetCLI",
            dependencies: [
                "ValetCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ValetCLI",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ValetCoreTests",
            dependencies: ["ValetCore"],
            path: "Tests/ValetCoreTests",
            swiftSettings: swiftSettings
        ),
    ]
)
