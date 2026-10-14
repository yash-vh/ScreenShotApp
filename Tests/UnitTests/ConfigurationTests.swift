import XCTest
@testable import ScreenshotApp

final class ConfigurationTests: XCTestCase {
    func testDefaultCaptureSettings() {
        let settings = CaptureSettings.default
        XCTAssertEqual(settings.defaultFormat, .png)
        XCTAssertTrue(settings.copyToClipboard)
        XCTAssertTrue(settings.openInEditor)
        XCTAssertTrue(settings.saveToDisk)
        XCTAssertTrue(settings.runOcrAutomatically)
        XCTAssertEqual(settings.shortcutRegion.displayString, "⇧⌘4")
    }

    func testStorageModeProperties() {
        let local = StorageMode.localOnly
        XCTAssertEqual(local.title, "Local Only")
        XCTAssertEqual(local.iconName, "internaldrive")

        let cloud = StorageMode.managedCloud
        XCTAssertEqual(cloud.title, "Managed Cloud")
        XCTAssertEqual(cloud.iconName, "cloud.fill")

        let custom = StorageMode.userOwned
        XCTAssertEqual(custom.title, "My Storage")
        XCTAssertEqual(custom.iconName, "server.rack")
    }

    @MainActor
    func testAppConfigurationSaveDirectory() {
        let config = AppConfiguration.shared
        let saveDir = config.resolveLocalSaveDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveDir.path))
    }
}
