import Foundation
import Combine
import ServiceManagement

/// Centralized observable app configuration manager.
/// Synchronizes user preferences with macOS `UserDefaults`.
@MainActor
public final class AppConfiguration: ObservableObject {
    public static let shared = AppConfiguration()

    private enum Keys {
        static let storageMode = "com.screenshotapp.storageMode"
        static let captureSettings = "com.screenshotapp.captureSettings"
        static let launchAtLogin = "com.screenshotapp.launchAtLogin"
        static let showDockIcon = "com.screenshotapp.showDockIcon"
        static let showMenuBarIcon = "com.screenshotapp.showMenuBarIcon"
        static let relaunchAfterUnexpectedQuit = "com.screenshotapp.relaunchAfterUnexpectedQuit"
        static let s3Endpoint = "com.screenshotapp.s3Endpoint"
        static let s3Bucket = "com.screenshotapp.s3Bucket"
        static let s3Region = "com.screenshotapp.s3Region"
        static let s3PublicBaseURL = "com.screenshotapp.s3PublicBaseURL"
        static let uploadExpiry = "com.screenshotapp.uploadExpiry"
        static let linkShortener = "com.screenshotapp.linkShortener"
        static let cacheQuotaMB = "com.screenshotapp.cacheQuotaMB"
        static let recordingSettings = "com.screenshotapp.recordingSettings"
    }

    private let defaults: UserDefaults

    @Published public var storageMode: StorageMode {
        didSet {
            defaults.set(storageMode.rawValue, forKey: Keys.storageMode)
            AppLogger.shared.app.info("Storage mode updated: \(self.storageMode.rawValue, privacy: .public)")
        }
    }

    @Published public var captureSettings: CaptureSettings {
        didSet {
            if let encoded = try? JSONEncoder().encode(captureSettings) {
                defaults.set(encoded, forKey: Keys.captureSettings)
            }
        }
    }

    /// Mirrors the system login-item state; change it with `setLaunchAtLogin(_:)`
    @Published public private(set) var launchAtLogin: Bool

    /// Registers or removes SyncShot as a login item. Returns an error message when macOS refuses.
    @discardableResult
    public func setLaunchAtLogin(_ enabled: Bool) -> String? {
        var problem: String?
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            problem = error.localizedDescription
            AppLogger.shared.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        if status == .requiresApproval {
            problem = "Approve SyncShot in System Settings › General › Login Items."
        }
        return problem
    }

    @Published public var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
        }
    }

    /// Whether the menu bar menu (status item) is shown; when hidden, reopen SyncShot from Finder or Spotlight to reach Settings
    @Published public var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
        }
    }

    /// Whether launchd should relaunch SyncShot after a force quit or crash (see `BackgroundRelauncher`)
    @Published public var relaunchAfterUnexpectedQuit: Bool {
        didSet {
            defaults.set(relaunchAfterUnexpectedQuit, forKey: Keys.relaunchAfterUnexpectedQuit)
        }
    }

    @Published public var s3Endpoint: String {
        didSet {
            defaults.set(s3Endpoint, forKey: Keys.s3Endpoint)
        }
    }

    @Published public var s3Bucket: String {
        didSet {
            defaults.set(s3Bucket, forKey: Keys.s3Bucket)
        }
    }

    @Published public var s3Region: String {
        didSet {
            defaults.set(s3Region, forKey: Keys.s3Region)
        }
    }

    /// Public base URL for objects in the user's bucket (CDN / custom domain); presigned links are used when empty
    @Published public var s3PublicBaseURL: String {
        didSet {
            defaults.set(s3PublicBaseURL, forKey: Keys.s3PublicBaseURL)
        }
    }

    @Published public var uploadExpiry: UploadExpiry {
        didSet {
            defaults.set(uploadExpiry.rawValue, forKey: Keys.uploadExpiry)
        }
    }

    /// Short-link service applied after each upload
    @Published public var linkShortener: LinkShortener {
        didSet {
            defaults.set(linkShortener.rawValue, forKey: Keys.linkShortener)
        }
    }

    /// Size limit for app-managed cached captures; the oldest are evicted beyond it (0 = unlimited)
    @Published public var cacheQuotaMB: Int {
        didSet {
            defaults.set(cacheQuotaMB, forKey: Keys.cacheQuotaMB)
        }
    }

    @Published public var recordingSettings: RecordingSettings {
        didSet {
            if let encoded = try? JSONEncoder().encode(recordingSettings) {
                defaults.set(encoded, forKey: Keys.recordingSettings)
            }
        }
    }

    /// Single user-facing choice behind the Upload button
    public var uploadDestination: UploadDestination {
        get {
            switch storageMode {
            case .localOnly: return .off
            case .managedCloud: return .imgbb
            case .userOwned: return .s3
            }
        }
        set {
            switch newValue {
            case .off: storageMode = .localOnly
            case .imgbb: storageMode = .managedCloud
            case .s3: storageMode = .userOwned
            }
        }
    }

    /// The upload provider implied by the storage mode, or nil when uploads are off
    public var uploadProvider: CloudProviderType? {
        storageMode.provider
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Storage Mode
        if let rawMode = defaults.string(forKey: Keys.storageMode),
           let mode = StorageMode(rawValue: rawMode) {
            self.storageMode = mode
        } else {
            self.storageMode = .localOnly
        }

        // Capture Settings
        if let data = defaults.data(forKey: Keys.captureSettings),
           let settings = try? JSONDecoder().decode(CaptureSettings.self, from: data) {
            self.captureSettings = settings
        } else {
            self.captureSettings = CaptureSettings.default
        }

        // App general preferences
        let loginStatus = SMAppService.mainApp.status
        self.launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        self.showDockIcon = defaults.object(forKey: Keys.showDockIcon) != nil ? defaults.bool(forKey: Keys.showDockIcon) : true
        self.showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) != nil ? defaults.bool(forKey: Keys.showMenuBarIcon) : true
        self.relaunchAfterUnexpectedQuit = defaults.bool(forKey: Keys.relaunchAfterUnexpectedQuit)

        self.s3Endpoint = defaults.string(forKey: Keys.s3Endpoint) ?? ""
        self.s3Bucket = defaults.string(forKey: Keys.s3Bucket) ?? ""
        self.s3Region = defaults.string(forKey: Keys.s3Region) ?? "us-east-1"
        self.s3PublicBaseURL = defaults.string(forKey: Keys.s3PublicBaseURL) ?? ""
        self.uploadExpiry = defaults.string(forKey: Keys.uploadExpiry).flatMap(UploadExpiry.init(rawValue:)) ?? .thirtyDays
        self.linkShortener = defaults.string(forKey: Keys.linkShortener).flatMap(LinkShortener.init(rawValue:)) ?? .off
        self.cacheQuotaMB = defaults.object(forKey: Keys.cacheQuotaMB) != nil ? defaults.integer(forKey: Keys.cacheQuotaMB) : 2048

        if let data = defaults.data(forKey: Keys.recordingSettings),
           let settings = try? JSONDecoder().decode(RecordingSettings.self, from: data) {
            self.recordingSettings = settings
        } else {
            self.recordingSettings = .default
        }

    }

    /// The folder the current settings point at, without touching the disk
    public var configuredSaveDirectory: URL {
        let settings = captureSettings
        if settings.saveLocation == .custom, let custom = settings.customSaveDirectory, !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return (settings.saveLocation.presetURL() ?? SaveLocation.desktop.presetURL())!
    }

    /// Why the configured folder can't be used right now, or nil when it's fine
    public func saveDirectoryProblem() -> String? {
        if captureSettings.saveLocation == .custom, (captureSettings.customSaveDirectory ?? "").isEmpty {
            return "No custom folder chosen. Captures go to \(SaveLocation.desktop.displayName) until you pick one."
        }
        return Self.ensureWritableDirectory(configuredSaveDirectory)
    }

    /// Resolves the local directory for saving captures, creating it when needed.
    /// Falls back to Desktop › Screenshots, then Application Support, if the chosen folder isn't writable.
    public func resolveLocalSaveDirectory() -> URL {
        let configured = configuredSaveDirectory
        guard let problem = saveDirectoryProblem() else { return configured }
        AppLogger.shared.storage.error("Save folder unavailable (\(problem, privacy: .public)); using fallback")

        if let desktop = SaveLocation.desktop.presetURL(), Self.ensureWritableDirectory(desktop) == nil {
            return desktop
        }
        let fallback = appSupportDirectory().appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Creates the folder if missing; returns an error message when it can't be written to
    static func ensureWritableDirectory(_ url: URL) -> String? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { return "\(url.lastPathComponent) is a file, not a folder." }
        } else {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                return "Couldn't create \(url.path): \(error.localizedDescription)"
            }
        }
        return fm.isWritableFile(atPath: url.path) ? nil : "SyncShot can't write to \(url.path)."
    }

    /// Directory for Application Support metadata and temporary working buffers
    public func appSupportDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.screenshotapp.mac", isDirectory: true)

        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }

        return appDir
    }
}
