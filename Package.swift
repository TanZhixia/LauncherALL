// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCLauncher",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MCLauncher", targets: ["MCLauncher"]),
        .library(name: "LauncherUI", targets: ["LauncherUI"]),
    ],
    targets: [
        .target(
            name: "LauncherUI",
            path: "Sources/LauncherUI",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MCLauncher",
            dependencies: ["LauncherUI"],
            path: "Sources/MCLauncher",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LauncherUITests",
            dependencies: ["LauncherUI"],
            path: "Tests/LauncherUITests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
