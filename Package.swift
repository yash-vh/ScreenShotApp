// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ScreenshotApp",
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
                "Resources/Assets.xcassets"
            ]
        ),
        .testTarget(
            name: "ScreenshotAppTests",
            dependencies: ["ScreenshotApp"],
            path: "Tests"
        )
    ]
)
