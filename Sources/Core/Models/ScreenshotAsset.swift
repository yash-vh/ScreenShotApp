import Foundation

/// Core domain model representing a captured image, recording, or animated GIF.
public struct ScreenshotAsset: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var tags: [String]
    
    /// Path to original raw capture file on disk
    public var originalFileURL: URL
    
    /// Path to flattened/rendered export file (if exported)
    public var exportFileURL: URL?
    
    /// Native pixel dimensions
    public var pixelWidth: Int
    public var pixelHeight: Int

    /// Pixels per screen point at capture time (2.0 on Retina displays); nil when unknown
    public var scaleFactor: Double?
    public var fileSizeBytes: Int64
    
    /// Recognized on-device OCR text
    public var ocrText: String?
    
    /// Media classification
    public var mediaType: MediaType
    
    /// Associated cloud upload history records
    public var uploadRecords: [UploadRecord]
    
    /// Whether file is present on the local filesystem
    public var isAvailableLocally: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        tags: [String] = [],
        originalFileURL: URL,
        exportFileURL: URL? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        scaleFactor: Double? = nil,
        fileSizeBytes: Int64,
        ocrText: String? = nil,
        mediaType: MediaType = .image,
        uploadRecords: [UploadRecord] = [],
        isAvailableLocally: Bool = true
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.tags = tags
        self.originalFileURL = originalFileURL
        self.exportFileURL = exportFileURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scaleFactor = scaleFactor
        self.fileSizeBytes = fileSizeBytes
        self.ocrText = ocrText
        self.mediaType = mediaType
        self.uploadRecords = uploadRecords
        self.isAvailableLocally = isAvailableLocally
    }

    /// Formatted dimensions string (e.g. "1920 × 1080")
    public var dimensionsString: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    /// Human readable file size (e.g. "2.4 MB")
    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Latest successful share URL if available
    public var primaryShareURL: URL? {
        uploadRecords.last(where: { $0.shareURL != nil })?.shareURL
    }
}
