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
        XCTAssertEqual(settings.shortcutCopy.displayString, "⌘C")
        XCTAssertEqual(settings.shortcutUpload.displayString, "⌘U")
        XCTAssertEqual(settings.shortcutCancel.displayString, "Esc")
    }

    func testCustomShortcutsSerialization() throws {
        var settings = CaptureSettings.default
        let custom = CustomShortcutItem(name: "Upload Cloud", action: "Upload & Share Link", binding: ShortcutBinding(key: "U", modifiers: ["⌘"]))
        settings.customShortcuts.append(custom)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CaptureSettings.self, from: data)

        XCTAssertEqual(decoded.customShortcuts.count, 1)
        XCTAssertEqual(decoded.customShortcuts.first?.name, "Upload Cloud")
        XCTAssertEqual(decoded.customShortcuts.first?.binding.displayString, "⌘U")
        XCTAssertEqual(decoded.shortcutCopy.displayString, "⌘C")
        XCTAssertEqual(decoded.shortcutUpload.displayString, "⌘U")
        XCTAssertEqual(decoded.shortcutCancel.displayString, "Esc")
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
