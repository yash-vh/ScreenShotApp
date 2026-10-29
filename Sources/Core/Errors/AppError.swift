import Foundation

/// Core error domains for ScreenMint.
/// Conforms to `LocalizedError`, `CustomNSError`, and `Sendable`.
public enum AppError: LocalizedError, CustomNSError, Sendable, Equatable {
    // Capture errors
    case screenCapturePermissionDenied
    case screenCaptureNotAuthorized
    case captureFailed(reason: String)
    case windowNotFound(windowId: UInt32)
    case displayNotFound(displayId: UInt32)
    case invalidRegion(width: Double, height: Double)

    // Storage errors
    case localDirectoryUnavailable(path: String)
    case fileNotFound(url: URL)
    case fileReadFailed(path: String)
    case fileWriteFailed(path: String)
    case diskSpaceInsufficient(requiredBytes: Int64, availableBytes: Int64)
    case assetCorrupted(id: UUID)

    // Cloud & Upload errors
    case cloudProviderNotConfigured
    case cloudUploadFailed(provider: String, reason: String)
    case cloudQuotaExceeded(usedBytes: Int64, maxBytes: Int64)
    case networkUnavailable
    case remoteObjectNotFound(objectId: String)
    case credentialsExpired

    // Recognition & Vision errors
    case ocrRecognitionFailed(reason: String)
    case qrDetectionFailed(reason: String)
    case noTextFound

    // Recording errors
    case recordingAlreadyInProgress
    case recordingNotActive
    case audioDeviceUnavailable(name: String)
    case recordingExportFailed(reason: String)
    case gifConversionFailed(reason: String)

    // Configuration & Keychain errors
    case keychainSaveFailed(status: Int32)
    case keychainReadFailed(status: Int32)
    case invalidConfiguration(key: String, reason: String)

    public static var errorDomain: String {
        return "com.screenshotapp.error"
    }

    public var errorCode: Int {
        switch self {
        case .screenCapturePermissionDenied: return 1001
        case .screenCaptureNotAuthorized:    return 1002
        case .captureFailed:                 return 1003
        case .windowNotFound:                return 1004
        case .displayNotFound:               return 1005
        case .invalidRegion:                 return 1006

        case .localDirectoryUnavailable:     return 2001
        case .fileNotFound:                  return 2002
        case .fileReadFailed:                return 2003
        case .fileWriteFailed:               return 2004
        case .diskSpaceInsufficient:         return 2005
        case .assetCorrupted:                return 2006

        case .cloudProviderNotConfigured:    return 3001
        case .cloudUploadFailed:             return 3002
        case .cloudQuotaExceeded:            return 3003
        case .networkUnavailable:            return 3004
        case .remoteObjectNotFound:          return 3005
        case .credentialsExpired:            return 3006

        case .ocrRecognitionFailed:          return 4001
        case .qrDetectionFailed:             return 4002
        case .noTextFound:                   return 4003

        case .recordingAlreadyInProgress:    return 5001
        case .recordingNotActive:            return 5002
        case .audioDeviceUnavailable:        return 5003
        case .recordingExportFailed:         return 5004
        case .gifConversionFailed:           return 5005

        case .keychainSaveFailed:            return 6001
        case .keychainReadFailed:            return 6002
        case .invalidConfiguration:          return 6003
        }
    }

    public var errorDescription: String? {
        switch self {
        case .screenCapturePermissionDenied:
            return "Screen Recording permission was denied. Please allow access in macOS System Settings."
        case .screenCaptureNotAuthorized:
            return "\(AppBranding.appName) is not authorized to record or capture the screen."
        case .captureFailed(let reason):
            return "Screen capture failed: \(reason)"
        case .windowNotFound(let id):
            return "Selected window (ID \(id)) could not be found or has closed."
        case .displayNotFound(let id):
            return "Display (ID \(id)) was not found or is disconnected."
        case .invalidRegion(let w, let h):
            return "Capture region dimensions (\(Int(w))x\(Int(h))) are invalid."

        case .localDirectoryUnavailable(let path):
            return "Local storage directory unavailable at: \(path)"
        case .fileNotFound(let url):
            return "Asset file not found at: \(url.lastPathComponent)"
        case .fileReadFailed(let path):
            return "Failed to read file from disk: \(path)"
        case .fileWriteFailed(let path):
            return "Failed to write file to disk: \(path)"
        case .diskSpaceInsufficient(let required, let available):
            return "Insufficient disk space. Needed: \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), Available: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))."
        case .assetCorrupted(let id):
            return "Screenshot asset data is corrupted (Asset ID: \(id.uuidString))."

        case .cloudProviderNotConfigured:
            return "No cloud storage provider is configured. Open Settings to configure storage."
        case .cloudUploadFailed(let provider, let reason):
            return "Upload to \(provider) failed: \(reason)"
        case .cloudQuotaExceeded(let used, let max):
            return "Storage quota exceeded. Used: \(ByteCountFormatter.string(fromByteCount: used, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: max, countStyle: .file))."
        case .networkUnavailable:
            return "Internet connection appears to be offline."
        case .remoteObjectNotFound(let objectId):
            return "Remote object not found: \(objectId)"
        case .credentialsExpired:
            return "Cloud provider credentials have expired. Please re-authenticate."

        case .ocrRecognitionFailed(let reason):
            return "On-device OCR failed: \(reason)"
        case .qrDetectionFailed(let reason):
            return "QR Code detection failed: \(reason)"
        case .noTextFound:
            return "No readable text detected in the selected image."

        case .recordingAlreadyInProgress:
            return "A screen recording session is already active."
        case .recordingNotActive:
            return "No active screen recording session to pause or stop."
        case .audioDeviceUnavailable(let name):
            return "Audio recording device '\(name)' is unavailable."
        case .recordingExportFailed(let reason):
            return "Failed to encode and export recording: \(reason)"
        case .gifConversionFailed(let reason):
            return "Failed to convert video to GIF: \(reason)"

        case .keychainSaveFailed(let status):
            return "Failed to save credentials to macOS Keychain (OSStatus: \(status))."
        case .keychainReadFailed(let status):
            return "Failed to read credentials from macOS Keychain (OSStatus: \(status))."
        case .invalidConfiguration(let key, let reason):
            return "Invalid configuration for '\(key)': \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .screenCapturePermissionDenied, .screenCaptureNotAuthorized:
            return "Open System Settings > Privacy & Security > Screen Recording, and enable \(AppBranding.appName)."
        case .cloudProviderNotConfigured:
            return "Visit Settings > Storage & Cloud to set up Managed Cloud or your own S3 provider."
        case .networkUnavailable:
            return "Check your Wi-Fi or network connection and retry the upload."
        case .diskSpaceInsufficient:
            return "Free up disk space on your startup drive or clean up local screenshot history."
        default:
            return nil
        }
    }

    /// Redacted description safe for logging without exposing private paths, tokens, or personal info.
    public var redactedDescription: String {
        switch self {
        case .localDirectoryUnavailable:
            return "localDirectoryUnavailable(path: [REDACTED])"
        case .fileNotFound:
            return "fileNotFound(url: [REDACTED])"
        case .fileReadFailed:
            return "fileReadFailed(path: [REDACTED])"
        case .fileWriteFailed:
            return "fileWriteFailed(path: [REDACTED])"
        case .cloudUploadFailed(let provider, _):
            return "cloudUploadFailed(provider: \(provider), reason: [REDACTED])"
        case .keychainSaveFailed(let status):
            return "keychainSaveFailed(status: \(status))"
        case .keychainReadFailed(let status):
            return "keychainReadFailed(status: \(status))"
        default:
            return errorDescription ?? "AppError.\(errorCode)"
        }
    }
}
