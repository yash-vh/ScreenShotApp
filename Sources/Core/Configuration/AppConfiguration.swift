import Foundation
import Combine

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
        static let activeCloudProvider = "com.screenshotapp.activeCloudProvider"
        static let s3Endpoint = "com.screenshotapp.s3Endpoint"
        static let s3Bucket = "com.screenshotapp.s3Bucket"
        static let s3Region = "com.screenshotapp.s3Region"
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

    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    @Published public var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
        }
    }

    @Published public var activeCloudProvider: CloudProviderType {
        didSet {
            defaults.set(activeCloudProvider.rawValue, forKey: Keys.activeCloudProvider)
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
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.showDockIcon = defaults.object(forKey: Keys.showDockIcon) != nil ? defaults.bool(forKey: Keys.showDockIcon) : true
        
        if let rawProvider = defaults.string(forKey: Keys.activeCloudProvider),
           let provider = CloudProviderType(rawValue: rawProvider) {
            self.activeCloudProvider = provider
        } else {
            self.activeCloudProvider = .managedCloud
        }

        self.s3Endpoint = defaults.string(forKey: Keys.s3Endpoint) ?? ""
        self.s3Bucket = defaults.string(forKey: Keys.s3Bucket) ?? ""
        self.s3Region = defaults.string(forKey: Keys.s3Region) ?? "us-east-1"
    }

    /// Resolves the local directory for saving captures
    public func resolveLocalSaveDirectory() -> URL {
        if let custom = captureSettings.customSaveDirectory, !custom.isEmpty {
            let customURL = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
            if FileManager.default.isWritableFile(atPath: customURL.path) {
                return customURL
            }
        }

        // Default to ~/Pictures/Screenshots
        let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let screenshotDir = picturesDir.appendingPathComponent("Screenshots", isDirectory: true)

        if !FileManager.default.fileExists(atPath: screenshotDir.path) {
            try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
        }

        return screenshotDir
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
