import Foundation
import SwiftData

/// SwiftData row backing one `ScreenshotAsset` in the persistent history.
/// Upload records are stored as encoded JSON so the domain model stays a plain value type.
@Model
public final class AssetRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var tags: [String]
    public var originalFilePath: String
    public var exportFilePath: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scaleFactor: Double?
    public var fileSizeBytes: Int64
    public var ocrText: String?
    public var mediaTypeRaw: String
    public var durationSeconds: Double?
    public var uploadRecordsData: Data?
    public var isAvailableLocally: Bool

    public init(asset: ScreenshotAsset) {
        self.id = asset.id
        self.title = asset.title
        self.createdAt = asset.createdAt
        self.modifiedAt = asset.modifiedAt
        self.tags = asset.tags
        self.originalFilePath = asset.originalFileURL.path
        self.exportFilePath = asset.exportFileURL?.path
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.scaleFactor = asset.scaleFactor
        self.fileSizeBytes = asset.fileSizeBytes
        self.ocrText = asset.ocrText
        self.mediaTypeRaw = asset.mediaType.rawValue
        self.durationSeconds = asset.durationSeconds
        self.uploadRecordsData = try? JSONEncoder().encode(asset.uploadRecords)
        self.isAvailableLocally = asset.isAvailableLocally
    }

    /// Copies every mutable field from the domain value
    public func apply(_ asset: ScreenshotAsset) {
        title = asset.title
        modifiedAt = asset.modifiedAt
        tags = asset.tags
        originalFilePath = asset.originalFileURL.path
        exportFilePath = asset.exportFileURL?.path
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        scaleFactor = asset.scaleFactor
        fileSizeBytes = asset.fileSizeBytes
        ocrText = asset.ocrText
        mediaTypeRaw = asset.mediaType.rawValue
        durationSeconds = asset.durationSeconds
        uploadRecordsData = try? JSONEncoder().encode(asset.uploadRecords)
        isAvailableLocally = asset.isAvailableLocally
    }

    public var asset: ScreenshotAsset {
        let uploads = uploadRecordsData.flatMap { try? JSONDecoder().decode([UploadRecord].self, from: $0) } ?? []
        return ScreenshotAsset(
            id: id,
            title: title,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            tags: tags,
            originalFileURL: URL(fileURLWithPath: originalFilePath),
            exportFileURL: exportFilePath.map { URL(fileURLWithPath: $0) },
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scaleFactor: scaleFactor,
            fileSizeBytes: fileSizeBytes,
            ocrText: ocrText,
            mediaType: MediaType(rawValue: mediaTypeRaw) ?? .image,
            durationSeconds: durationSeconds,
            uploadRecords: uploads,
            isAvailableLocally: isAvailableLocally
        )
    }
}
