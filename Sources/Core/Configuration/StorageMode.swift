import Foundation

/// Where the Upload button sends captures; maps onto `StorageMode`.
/// ScreenMint supports exactly two upload backends: ImgBB and Amazon S3 (or an S3-compatible bucket).
public enum UploadDestination: String, CaseIterable, Identifiable, Sendable {
    case off
    case imgbb
    case s3

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off (keep screenshots on this Mac)"
        case .imgbb: return "ImgBB"
        case .s3: return "Amazon S3 / S3-compatible bucket"
        }
    }
}

/// Active storage mode configuration
public enum StorageMode: String, Codable, Sendable, CaseIterable {
    case localOnly = "local_only"
    /// ImgBB uploads (raw value kept for stored preferences)
    case managedCloud = "managed_cloud"
    /// The user's own Amazon S3 / S3-compatible bucket
    case userOwned = "user_owned"

    public var title: String {
        switch self {
        case .localOnly: return "Local Only"
        case .managedCloud: return "ImgBB"
        case .userOwned: return "Amazon S3"
        }
    }

    public var subtitle: String {
        switch self {
        case .localOnly:
            return "Screenshots stay on your Mac. Uploading is turned off."
        case .managedCloud:
            return "Share links hosted on ImgBB with optional expiry. Uploads only when you press Upload (⌘U)."
        case .userOwned:
            return "Upload to your own Amazon S3 or S3-compatible bucket (R2, B2, MinIO). Keys are kept in the Keychain."
        }
    }

    public var iconName: String {
        switch self {
        case .localOnly: return "internaldrive"
        case .managedCloud: return "cloud.fill"
        case .userOwned: return "server.rack"
        }
    }

    /// The upload provider this mode sends captures to, or nil when uploads are off
    public var provider: CloudProviderType? {
        switch self {
        case .localOnly: return nil
        case .managedCloud: return .imgbb
        case .userOwned: return .s3Compatible
        }
    }
}
