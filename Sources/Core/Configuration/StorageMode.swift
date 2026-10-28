import Foundation

/// Active storage mode configuration
public enum StorageMode: String, Codable, Sendable, CaseIterable {
    case localOnly = "local_only"
    case managedCloud = "managed_cloud"
    case userOwned = "user_owned"

    public var title: String {
        switch self {
        case .localOnly: return "Local Only"
        case .managedCloud: return "Free Share Link"
        case .userOwned: return "My Storage"
        }
    }

    public var subtitle: String {
        switch self {
        case .localOnly:
            return "Screenshots stay on your Mac. Uploading is turned off."
        case .managedCloud:
            return "Instant, unguessable share links with optional expiry. Uploads only when you press Upload (⌘U)."
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
}
