import XCTest
@testable import ScreenshotApp

final class ConfigurationTests: XCTestCase {
    func testDefaultCaptureSettings() {
        let settings = CaptureSettings.default
        XCTAssertEqual(settings.defaultFormat, .png)
        XCTAssertTrue(settings.copyToClipboard)
        XCTAssertTrue(settings.saveToDisk)
        XCTAssertTrue(settings.runOcrAutomatically)
        XCTAssertEqual(settings.shortcutRegion.displayString, "⌥⌘4")
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
        XCTAssertEqual(cloud.title, "ImgBB")
        XCTAssertEqual(cloud.provider, .imgbb)
        XCTAssertEqual(cloud.iconName, "cloud.fill")

        let custom = StorageMode.userOwned
        XCTAssertEqual(custom.title, "Amazon S3")
        XCTAssertEqual(custom.provider, .s3Compatible)
        XCTAssertNil(local.provider)
        XCTAssertEqual(custom.iconName, "server.rack")
    }

    @MainActor
    func testMenuBarMenuIsShownByDefault() {
        let suite = "MenuVisibility-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AppConfiguration(defaults: defaults).showMenuBarIcon)
    }

    @MainActor
    func testMenuBarMenuVisibilityPersistsAcrossLaunches() {
        let suite = "MenuVisibility-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        AppConfiguration(defaults: defaults).showMenuBarIcon = false
        XCTAssertFalse(AppConfiguration(defaults: defaults).showMenuBarIcon)

        AppConfiguration(defaults: defaults).showMenuBarIcon = true
        XCTAssertTrue(AppConfiguration(defaults: defaults).showMenuBarIcon)
    }

    @MainActor
    func testRelaunchAfterUnexpectedQuitIsOffByDefaultAndPersists() {
        let suite = "Relaunch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(AppConfiguration(defaults: defaults).relaunchAfterUnexpectedQuit)
        AppConfiguration(defaults: defaults).relaunchAfterUnexpectedQuit = true
        XCTAssertTrue(AppConfiguration(defaults: defaults).relaunchAfterUnexpectedQuit)
    }

    func testDefaultsAvoidMacOSScreenshotShortcuts() {
        let settings = CaptureSettings.default
        for binding in [settings.shortcutRegion, settings.shortcutFullScreen, settings.shortcutWindow, settings.shortcutRecording, settings.shortcutQuickOcr] {
            XCTAssertFalse(binding.isMacOSScreenshotShortcut, binding.displayString)
            XCTAssertTrue(binding.isValidGlobalHotKey, binding.displayString)
        }
        XCTAssertTrue(ShortcutBinding(key: "4", modifiers: ["⇧", "⌘"]).isMacOSScreenshotShortcut)
        XCTAssertTrue(ShortcutBinding(key: "3", modifiers: ["⌃", "⇧", "⌘"]).isMacOSScreenshotShortcut)
        XCTAssertFalse(ShortcutBinding(key: "4", modifiers: ["⌥", "⌘"]).isMacOSScreenshotShortcut)
    }

    func testStoredSystemShortcutsMigrateButCustomOnesStay() throws {
        var legacy = CaptureSettings.default
        legacy.shortcutRegion = ShortcutBinding(key: "4", modifiers: ["⇧", "⌘"])
        legacy.shortcutQuickOcr = ShortcutBinding(key: "7", modifiers: ["⇧", "⌘"])
        legacy.shortcutWindow = ShortcutBinding(key: "W", modifiers: ["⌃", "⌥"])
        let decoded = try JSONDecoder().decode(CaptureSettings.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.shortcutRegion, .defaultRegion)
        XCTAssertEqual(decoded.shortcutQuickOcr, .defaultQuickOcr)
        XCTAssertEqual(decoded.shortcutWindow.displayString, "⌃⌥W")
    }

    func testUnusableStoredShortcutFallsBackToDefault() throws {
        var legacy = CaptureSettings.default
        legacy.shortcutRegion = ShortcutBinding(key: ")", modifiers: ["⇧", "⌘"])
        let decoded = try JSONDecoder().decode(CaptureSettings.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.shortcutRegion, .defaultRegion)
    }

    @MainActor
    func testMigratedShortcutsArePersisted() throws {
        let suite = "ShortcutMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = CaptureSettings.default
        legacy.shortcutFullScreen = ShortcutBinding(key: "3", modifiers: ["⇧", "⌘"])
        defaults.set(try JSONEncoder().encode(legacy), forKey: "com.screenshotapp.captureSettings")

        _ = AppConfiguration(defaults: defaults)

        let stored = try JSONDecoder().decode(CaptureSettings.self, from: XCTUnwrap(defaults.data(forKey: "com.screenshotapp.captureSettings")))
        XCTAssertEqual(stored.shortcutFullScreen, .defaultFullScreen)
    }

    func testCaptureSettingsDecodeIgnoresRemovedEditorFlag() throws {
        let json = #"{"openInEditor":true,"copyToClipboard":false}"#
        let settings = try JSONDecoder().decode(CaptureSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.copyToClipboard)
    }

    @MainActor
    func testAppConfigurationSaveDirectory() {
        let config = AppConfiguration.shared
        let saveDir = config.resolveLocalSaveDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveDir.path))
    }

    func testDefaultSaveLocationIsDesktopScreenshots() {
        XCTAssertEqual(CaptureSettings.default.saveLocation, .desktop)
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        XCTAssertEqual(SaveLocation.desktop.presetURL(home: home)?.path, "/Users/test/Desktop/Screenshots")
        XCTAssertEqual(SaveLocation.pictures.presetURL(home: home)?.path, "/Users/test/Pictures/Screenshots")
        XCTAssertNil(SaveLocation.custom.presetURL(home: home))
    }

    func testLegacyCustomFolderDecodesAsCustomLocation() throws {
        let legacy = try JSONDecoder().decode(CaptureSettings.self, from: Data(#"{"customSaveDirectory":"~/Shots"}"#.utf8))
        XCTAssertEqual(legacy.saveLocation, .custom)
        let fresh = try JSONDecoder().decode(CaptureSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(fresh.saveLocation, .desktop)
        XCTAssertEqual(fresh.fileNamePrefix, "Screenshot")
    }

    func testFileNamePrefixIsSanitized() {
        var settings = CaptureSettings.default
        settings.fileNamePrefix = "  Bug/Report:1 "
        XCTAssertEqual(settings.sanitizedFileNamePrefix, "Bug-Report-1")
        settings.fileNamePrefix = "   "
        XCTAssertEqual(settings.sanitizedFileNamePrefix, "Screenshot")
    }

    @MainActor
    func testCustomFolderIsCreatedAndUnwritableFallsBack() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SaveLocationTests-\(UUID().uuidString)"))
        let config = AppConfiguration(defaults: defaults)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SaveLocationTests-\(UUID().uuidString)/Nested", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        config.captureSettings.saveLocation = .custom
        config.captureSettings.customSaveDirectory = folder.path
        XCTAssertNil(config.saveDirectoryProblem())
        XCTAssertEqual(config.resolveLocalSaveDirectory().standardizedFileURL.path, folder.standardizedFileURL.path)

        config.captureSettings.customSaveDirectory = "/System/NotWritable"
        XCTAssertNotNil(config.saveDirectoryProblem())
        XCTAssertNotEqual(config.resolveLocalSaveDirectory().path, "/System/NotWritable")

        config.captureSettings.customSaveDirectory = nil
        XCTAssertNotNil(config.saveDirectoryProblem(), "custom with no folder chosen is reported")
    }
}
