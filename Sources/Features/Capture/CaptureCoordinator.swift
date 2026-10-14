import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// Coordinates capture requests, interactive overlays, post-capture processing, audio feedback, and clipboard copying.
@MainActor
public final class CaptureCoordinator: ObservableObject {
    public static let shared = CaptureCoordinator()

    @Published public var isCapturing = false

    private init() {}

    // MARK: - Public Triggers

    public func captureRegion() {
        guard PermissionManager.shared.checkScreenRecordingPermission() else {
            PermissionManager.shared.showScreenRecordingPermissionDialog()
            return
        }

        isCapturing = true
        RegionSelectionOverlayController.shared.present(
            onComplete: { [weak self] rect, screen in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    do {
                        let cgImage = try await ScreenCaptureService.shared.captureRegion(rect: rect, on: screen)
                        self.processCapturedImage(cgImage, title: "Region Capture")
                    } catch {
                        AppLogger.shared.capture.error("Region capture error: \(error.localizedDescription, privacy: .public)")
                        AppCoordinator.shared.lastErrorMessage = error.localizedDescription
                    }
                    self.isCapturing = false
                }
            },
            onCancel: { [weak self] in
                self?.isCapturing = false
            }
        )
    }

    public func captureFullScreen() {
        guard PermissionManager.shared.checkScreenRecordingPermission() else {
            PermissionManager.shared.showScreenRecordingPermissionDialog()
            return
        }

        isCapturing = true
        Task {
            do {
                let cgImage = try await ScreenCaptureService.shared.captureDisplay(displayId: CGMainDisplayID())
                self.processCapturedImage(cgImage, title: "Full Screen Capture")
            } catch {
                AppLogger.shared.capture.error("Full screen capture error: \(error.localizedDescription, privacy: .public)")
                AppCoordinator.shared.lastErrorMessage = error.localizedDescription
            }
            self.isCapturing = false
        }
    }

    public func captureWindow() {
        guard PermissionManager.shared.checkScreenRecordingPermission() else {
            PermissionManager.shared.showScreenRecordingPermissionDialog()
            return
        }

        isCapturing = true
        WindowSelectionOverlayController.shared.present(
            onSelect: { [weak self] windowId in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    do {
                        let cgImage = try await ScreenCaptureService.shared.captureWindow(windowId: windowId)
                        self.processCapturedImage(cgImage, title: "Window Capture")
                    } catch {
                        AppLogger.shared.capture.error("Window capture error: \(error.localizedDescription, privacy: .public)")
                        AppCoordinator.shared.lastErrorMessage = error.localizedDescription
                    }
                    self.isCapturing = false
                }
            },
            onCancel: { [weak self] in
                self?.isCapturing = false
            }
        )
    }

    // MARK: - Post-Capture Processing Pipeline

    public func processCapturedImage(_ cgImage: CGImage, title: String) {
        let config = AppConfiguration.shared
        let settings = config.captureSettings

        // 1. Audio Shutter Feedback
        if settings.playCaptureSound {
            playShutterSound()
        }

        // 2. Prepare file destination
        let saveDir = config.resolveLocalSaveDirectory()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileExt = settings.defaultFormat.rawValue
        let filename = "Screenshot \(timestamp).\(fileExt)"
        let fileURL = saveDir.appendingPathComponent(filename)

        // 3. Write raw capture to disk
        do {
            try ScreenCaptureService.shared.saveImage(
                cgImage,
                format: settings.defaultFormat,
                jpegQuality: settings.jpegQuality,
                to: fileURL
            )
        } catch {
            AppLogger.shared.storage.error("Failed to save capture to disk: \(error.localizedDescription, privacy: .public)")
        }

        // 4. Copy to Clipboard
        if settings.copyToClipboard {
            copyImageToPasteboard(cgImage: cgImage)
        }

        // 5. Construct domain asset
        let asset = ScreenshotAsset(
            title: title,
            originalFileURL: fileURL,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            fileSizeBytes: (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0,
            mediaType: .image
        )

        AppCoordinator.shared.recentAssets.insert(asset, at: 0)
        AppLogger.shared.capture.info("Successfully processed capture asset: \(asset.dimensionsString, privacy: .public)")

        // 6. Editor Trigger
        if settings.openInEditor {
            AppCoordinator.shared.openEditor(for: asset)
        }
    }

    private func copyImageToPasteboard(cgImage: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)

        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }
        pasteboard.writeObjects([nsImage])
    }

    private func playShutterSound() {
        if let sound = NSSound(named: "ScreenCapture") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
