import Foundation

/// Supported cloud storage provider identifiers: ImgBB and Amazon S3 / S3-compatible buckets only.
public enum CloudProviderType: String, Codable, Sendable, CaseIterable {
    case s3Compatible = "s3_compatible"
    case imgbb = "imgbb"
    /// Upload history from a provider YnShot no longer supports; links stay viewable but can't be managed
    case legacy = "legacy"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CloudProviderType(rawValue: raw) ?? .legacy
    }

    public var displayName: String {
        switch self {
        case .imgbb:        return "ImgBB"
        case .s3Compatible: return "Amazon S3 / S3-Compatible"
        case .legacy:       return "Removed provider"
        }
    }

    /// Providers with a working upload adapter
    public var isImplemented: Bool {
        self != .legacy
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
    /// Link handed to the user (shortened when a shortener is on)
    public var shareURL: URL?
    /// Provider's own link when `shareURL` is a short link
    public var originalURL: URL?
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
        capabilities: ProviderCapabilities = ProviderCapabilities(),
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
