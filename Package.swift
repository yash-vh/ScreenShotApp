// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenMint",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ScreenMint",
            targets: ["ScreenshotApp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ScreenshotApp",
            path: "Sources",
            exclude: [
                "Resources/Info.plist",
                "Resources/ScreenshotApp.entitlements",
                "Resources/Assets.xcassets",
                "Resources/LaunchAgents"
            ]
        ),
        .testTarget(
            name: "ScreenshotAppTests",
            dependencies: ["ScreenshotApp"],
            path: "Tests"
        )
    ]
)
