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
            targets: ["ScreenMint"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ScreenMint",
            path: "Sources",
            exclude: [
                "Resources/Info.plist",
                "Resources/ScreenMint.entitlements",
                "Resources/Assets.xcassets",
                "Resources/LaunchAgents"
            ]
        ),
        .testTarget(
            name: "ScreenMintTests",
            dependencies: ["ScreenMint"],
            path: "Tests"
        )
    ]
)
