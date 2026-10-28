import Foundation

/// Supported cloud storage provider identifiers
public enum CloudProviderType: String, Codable, Sendable, CaseIterable {
    case managedCloud = "managed_cloud"
    case s3Compatible = "s3_compatible"
    case supabase = "supabase"
    case cloudinary = "cloudinary"
    case imgur = "imgur"
    case imgbb = "imgbb"

    public var displayName: String {
        switch self {
        case .managedCloud: return "Shot Link (free)"
        case .imgur:        return "Imgur (anonymous)"
        case .imgbb:        return "ImgBB"
        case .s3Compatible: return "Amazon S3 / S3-Compatible"
        case .supabase:     return "Supabase Storage"
        case .cloudinary:   return "Cloudinary"
        }
    }

    /// Providers with a working upload adapter
    public var isImplemented: Bool {
        switch self {
        case .managedCloud, .imgur, .imgbb, .s3Compatible: return true
        case .supabase, .cloudinary: return false
        }
    }
}

/// Provider capabilities flags
public struct ProviderCapabilities: Codable, Sendable, Equatable {
    public var supportsDelete: Bool
    public var supportsExpiringLinks: Bool
    public var supportsPasswordProtection: Bool
    public var supportsLinkRevocation: Bool
    public var supportsResumableUploads: Bool

    public init(
        supportsDelete: Bool = true,
        supportsExpiringLinks: Bool = false,
        supportsPasswordProtection: Bool = false,
        supportsLinkRevocation: Bool = false,
        supportsResumableUploads: Bool = false
    ) {
        self.supportsDelete = supportsDelete
        self.supportsExpiringLinks = supportsExpiringLinks
        self.supportsPasswordProtection = supportsPasswordProtection
        self.supportsLinkRevocation = supportsLinkRevocation
        self.supportsResumableUploads = supportsResumableUploads
    }

    public static let managedDefault = ProviderCapabilities(
        supportsDelete: true,
        supportsExpiringLinks: true,
        supportsPasswordProtection: false,
        supportsLinkRevocation: true,
        supportsResumableUploads: true
    )

    public static let s3Default = ProviderCapabilities(
        supportsDelete: true,
        supportsExpiringLinks: true,
        supportsPasswordProtection: false,
        supportsLinkRevocation: false,
        supportsResumableUploads: true
    )

    public static let imgbbDefault = ProviderCapabilities(
        supportsDelete: false,
        supportsExpiringLinks: true,
        supportsPasswordProtection: false,
        supportsLinkRevocation: false,
        supportsResumableUploads: false
    )

    public static let imgurDefault = ProviderCapabilities(
        supportsDelete: true,
        supportsExpiringLinks: false,
        supportsPasswordProtection: false,
        supportsLinkRevocation: true,
        supportsResumableUploads: false
    )
}

/// Represents the status of an asset upload
public enum UploadStatus: String, Codable, Sendable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    /// Removed from the remote provider by the user
    case deleted = "deleted"
}

/// Domain model recording an upload event to a remote cloud provider.
public struct UploadRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var providerType: CloudProviderType
    public var remoteKey: String
    public var shareURL: URL?
    public var status: UploadStatus
    public var uploadedAt: Date?
    public var expiresAt: Date?
    public var capabilities: ProviderCapabilities
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        providerType: CloudProviderType,
        remoteKey: String,
        shareURL: URL? = nil,
        status: UploadStatus = .pending,
        uploadedAt: Date? = nil,
        expiresAt: Date? = nil,
        capabilities: ProviderCapabilities = .managedDefault,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.providerType = providerType
        self.remoteKey = remoteKey
        self.shareURL = shareURL
        self.status = status
        self.uploadedAt = uploadedAt
        self.expiresAt = expiresAt
        self.capabilities = capabilities
        self.errorMessage = errorMessage
    }
}
