import Foundation
import CoreGraphics
import ScreenCaptureKit
import AppKit
import UniformTypeIdentifiers

/// Native macOS screen capture engine utilizing ScreenCaptureKit with CoreGraphics fallback.
public actor ScreenCaptureService {
    public static let shared = ScreenCaptureService()

    private init() {}

    // MARK: - Capture Methods

    /// Captures the specified display or the primary display
    public func captureDisplay(displayId: CGDirectDisplayID = CGMainDisplayID()) async throws -> CGImage {
        AppLogger.shared.capture.info("Starting display capture for Display ID: \(displayId)")

        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.current
                guard let targetDisplay = content.displays.first(where: { $0.displayID == displayId }) ?? content.displays.first else {
                    throw AppError.displayNotFound(displayId: displayId)
                }

                let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                // SCDisplay dimensions are in points; capture at native pixel resolution
                let pixelScale = CGFloat(filter.pointPixelScale)
                configuration.width = Int(CGFloat(targetDisplay.width) * pixelScale)
                configuration.height = Int(CGFloat(targetDisplay.height) * pixelScale)
                configuration.showsCursor = false
                configuration.scalesToFit = false

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                AppLogger.shared.capture.info("SCK display capture succeeded (\(image.width)x\(image.height))")
                return image
            } catch {
                AppLogger.shared.capture.notice("SCK display capture error: \(error.localizedDescription, privacy: .public). Falling back to CoreGraphics.")
            }
        }

        // CoreGraphics Fallback
        guard let cgImage = CGDisplayCreateImage(displayId) else {
            throw AppError.captureFailed(reason: "CGDisplayCreateImage returned nil for display \(displayId)")
        }
        return cgImage
    }

    /// Captures a selected window by Window ID
    public func captureWindow(windowId: CGWindowID) async throws -> CGImage {
        AppLogger.shared.capture.info("Capturing window ID: \(windowId)")

        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.current
                if let targetWindow = content.windows.first(where: { $0.windowID == windowId }) {
                    let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
                    let configuration = SCStreamConfiguration()
                    let pixelScale = CGFloat(filter.pointPixelScale)
                    configuration.width = Int(targetWindow.frame.width * pixelScale)
                    configuration.height = Int(targetWindow.frame.height * pixelScale)
                    configuration.ignoreShadowsSingleWindow = true
                    configuration.showsCursor = false

                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    AppLogger.shared.capture.info("SCK window capture succeeded (\(image.width)x\(image.height))")
                    return image
                }
            } catch {
                AppLogger.shared.capture.notice("SCK window capture error: \(error.localizedDescription, privacy: .public). Falling back to CGWindowListCreateImage.")
            }
        }

        // CoreGraphics Fallback
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowId, options) else {
            throw AppError.windowNotFound(windowId: windowId)
        }
        return cgImage
    }

    /// Captures an exact region on a screen in AppKit global coordinates
    public func captureRegion(rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        guard rect.width >= 1, rect.height >= 1 else {
            throw AppError.invalidRegion(width: rect.width, height: rect.height)
        }

        let scale = screen.backingScaleFactor
        let screenFrame = screen.frame

        // Convert AppKit coordinates (bottom-left) to display top-left coordinates
        let displayX = rect.origin.x - screenFrame.origin.x
        let displayY = screenFrame.height - (rect.origin.y - screenFrame.origin.y + rect.height)

        let pixelRect = CGRect(
            x: displayX * scale,
            y: displayY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        // Capture full display image
        let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        let fullImage = try await captureDisplay(displayId: displayId)

        // Crop to the target region, using the actual capture scale in case it differs from the backing scale
        let actualScale = CGFloat(fullImage.width) / screenFrame.width
        let scaledRect = CGRect(
            x: pixelRect.origin.x / scale * actualScale,
            y: pixelRect.origin.y / scale * actualScale,
            width: pixelRect.width / scale * actualScale,
            height: pixelRect.height / scale * actualScale
        ).integral
        guard let cropped = fullImage.cropping(to: scaledRect) else {
            throw AppError.captureFailed(reason: "Failed to crop full screen image to region: \(pixelRect)")
        }

        AppLogger.shared.capture.info("Region capture succeeded: \(cropped.width)x\(cropped.height) @ \(Int(scale))x")
        return cropped
    }

    // MARK: - Disk Export Helper

    /// Saves a CGImage to disk in PNG or JPEG format
    public nonisolated func saveImage(
        _ image: CGImage,
        format: ExportFormat,
        jpegQuality: Double = 0.85,
        to destinationURL: URL
    ) throws {
        let parentDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let uti: CFString = format == .png ? UTType.png.identifier as CFString : UTType.jpeg.identifier as CFString

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, uti, 1, nil) else {
            throw AppError.fileWriteFailed(path: destinationURL.path)
        }

        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw AppError.fileWriteFailed(path: destinationURL.path)
        }

        AppLogger.shared.storage.info("Saved capture asset to disk at: \(destinationURL.lastPathComponent, privacy: .public)")
    }
}
