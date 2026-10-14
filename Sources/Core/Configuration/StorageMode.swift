import Foundation

/// Active storage mode configuration
public enum StorageMode: String, Codable, Sendable, CaseIterable {
    case localOnly = "local_only"
    case managedCloud = "managed_cloud"
    case userOwned = "user_owned"

    public var title: String {
        switch self {
        case .localOnly: return "Local Only"
        case .managedCloud: return "Managed Cloud"
        case .userOwned: return "My Storage"
        }
    }

    public var subtitle: String {
        switch self {
        case .localOnly:
            return "Screenshots stay on your Mac. No cloud connection or account required."
        case .managedCloud:
            return "Instant share links hosted on our fast, secure managed cloud service."
        case .userOwned:
            return "Directly upload to your personal Amazon S3, Supabase, or Cloudinary account."
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
