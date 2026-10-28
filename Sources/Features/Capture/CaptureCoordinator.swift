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
        guard PermissionManager.shared.isAuthorized || PermissionManager.shared.checkScreenRecordingPermission() else {
            Task { @MainActor in
                if await PermissionManager.shared.verifyScreenRecordingPermission() {
                    self.captureRegion()
                } else {
                    PermissionManager.shared.showScreenRecordingPermissionDialog()
                }
            }
            return
        }

        isCapturing = true
        RegionSelectionOverlayController.shared.present(
            onComplete: { [weak self] rect, screen, action, frozenImage in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    do {
                        // Prefer the frozen frame the user annotated on, so annotations line up exactly
                        let cgImage: CGImage
                        if let frozenImage = frozenImage {
                            cgImage = frozenImage
                        } else {
                            cgImage = try await ScreenCaptureService.shared.captureRegion(rect: rect, on: screen)
                        }
                        PermissionManager.shared.markAuthorized()
                        self.processCapturedRegion(cgImage, title: "Region Capture", scaleFactor: Double(screen.backingScaleFactor), action: action)
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
        guard PermissionManager.shared.isAuthorized || PermissionManager.shared.checkScreenRecordingPermission() else {
            Task { @MainActor in
                if await PermissionManager.shared.verifyScreenRecordingPermission() {
                    self.captureFullScreen()
                } else {
                    PermissionManager.shared.showScreenRecordingPermissionDialog()
                }
            }
            return
        }

        isCapturing = true
        // Capture the display the pointer is on, not always the primary one
        let screen = OverlayWindow.screenUnderMouse
        let displayId = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        Task {
            do {
                let cgImage = try await ScreenCaptureService.shared.captureDisplay(displayId: displayId)
                PermissionManager.shared.markAuthorized()
                self.processCapturedImage(cgImage, title: "Full Screen Capture", scaleFactor: Double(screen?.backingScaleFactor ?? 2.0))
            } catch {
                AppLogger.shared.capture.error("Full screen capture error: \(error.localizedDescription, privacy: .public)")
                AppCoordinator.shared.lastErrorMessage = error.localizedDescription
            }
            self.isCapturing = false
        }
    }

    public func captureWindow() {
        guard PermissionManager.shared.isAuthorized || PermissionManager.shared.checkScreenRecordingPermission() else {
            Task { @MainActor in
                if await PermissionManager.shared.verifyScreenRecordingPermission() {
                    self.captureWindow()
                } else {
                    PermissionManager.shared.showScreenRecordingPermissionDialog()
                }
            }
            return
        }

        isCapturing = true
        WindowSelectionOverlayController.shared.present(
            onSelect: { [weak self] windowId in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    do {
                        let cgImage = try await ScreenCaptureService.shared.captureWindow(windowId: windowId)
                        PermissionManager.shared.markAuthorized()
                        self.processCapturedImage(cgImage, title: "Window Capture", scaleFactor: Double(OverlayWindow.screenUnderMouse?.backingScaleFactor ?? 2.0))
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

    /// Select a region and copy the recognized text (or QR / barcode payload) to the clipboard
    public func captureText() {
        guard PermissionManager.shared.isAuthorized || PermissionManager.shared.checkScreenRecordingPermission() else {
            Task { @MainActor in
                if await PermissionManager.shared.verifyScreenRecordingPermission() {
                    self.captureText()
                } else {
                    PermissionManager.shared.showScreenRecordingPermissionDialog()
                }
            }
            return
        }

        isCapturing = true
        RegionSelectionOverlayController.shared.present(
            mode: .quickSelect,
            onComplete: { [weak self] rect, screen, _, frozenImage in
                Task { @MainActor [weak self] in
                    defer { self?.isCapturing = false }
                    do {
                        let cgImage: CGImage
                        if let frozenImage = frozenImage {
                            cgImage = frozenImage
                        } else {
                            cgImage = try await ScreenCaptureService.shared.captureRegion(rect: rect, on: screen)
                        }
                        PermissionManager.shared.markAuthorized()
                        let result = try await VisionService.shared.recognize(in: cgImage)
                        self?.deliverRecognition(result)
                    } catch {
                        AppLogger.shared.recognition.error("OCR capture error: \(error.localizedDescription, privacy: .public)")
                        AppCoordinator.shared.lastErrorMessage = error.localizedDescription
                        CaptureHUD.shared.show(title: "Text recognition failed", detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                    }
                }
            },
            onCancel: { [weak self] in
                self?.isCapturing = false
            }
        )
    }

    private func deliverRecognition(_ result: RecognitionResult) {
        let text = result.fullText
        let pasteboard = NSPasteboard.general

        if !text.isEmpty {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            let lines = result.textBlocks.count
            CaptureHUD.shared.show(title: "Copied \(lines) line\(lines == 1 ? "" : "s") of text", detail: String(text.prefix(140)), symbol: "text.viewfinder")
        } else if let barcode = result.barcodes.first {
            pasteboard.clearContents()
            pasteboard.setString(barcode.payload, forType: .string)
            CaptureHUD.shared.show(title: barcode.url != nil ? "Copied QR link" : "Copied code contents", detail: barcode.payload, symbol: "qrcode")
        } else {
            CaptureHUD.shared.show(title: "No text found", detail: "Try selecting a larger or sharper area.", symbol: "text.magnifyingglass")
        }
        AppLogger.shared.recognition.info("OCR capture delivered \(result.textBlocks.count) lines, \(result.barcodes.count) codes")
    }

    // MARK: - Post-Capture Processing Pipeline

    /// Writes the capture to the configured folder (or a private cache when auto-save is off) and builds its asset
    private func persistCapture(_ image: CGImage, title: String, scaleFactor: Double, forceSaveToDisk: Bool = false) -> ScreenshotAsset {
        let config = AppConfiguration.shared
        let settings = config.captureSettings

        let saveDir: URL
        if settings.saveToDisk || forceSaveToDisk {
            saveDir = config.resolveLocalSaveDirectory()
        } else {
            saveDir = config.appSupportDirectory().appendingPathComponent("Captures", isDirectory: true)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileExt = settings.defaultFormat == .jpeg ? "jpg" : "png"
        var fileURL = saveDir.appendingPathComponent("Screenshot \(timestamp).\(fileExt)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = saveDir.appendingPathComponent("Screenshot \(timestamp) (\(suffix)).\(fileExt)")
            suffix += 1
        }

        do {
            try ScreenCaptureService.shared.saveImage(image, format: settings.defaultFormat, jpegQuality: settings.jpegQuality, to: fileURL)
        } catch {
            AppLogger.shared.storage.error("Failed to save capture to disk: \(error.localizedDescription, privacy: .public)")
            AppCoordinator.shared.lastErrorMessage = error.localizedDescription
        }

        let asset = ScreenshotAsset(
            title: title,
            originalFileURL: fileURL,
            pixelWidth: image.width,
            pixelHeight: image.height,
            scaleFactor: scaleFactor,
            fileSizeBytes: (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0,
            mediaType: .image
        )
        AppCoordinator.shared.recentAssets.insert(asset, at: 0)
        if AppCoordinator.shared.recentAssets.count > 50 {
            AppCoordinator.shared.recentAssets.removeLast(AppCoordinator.shared.recentAssets.count - 50)
        }

        if settings.runOcrAutomatically {
            indexText(of: image, assetId: asset.id)
        }
        return asset
    }

    /// Background on-device OCR so recent captures carry searchable text
    private func indexText(of image: CGImage, assetId: UUID) {
        Task { @MainActor in
            guard let result = try? await VisionService.shared.recognize(in: image, recognitionLevel: .fast),
                  let index = AppCoordinator.shared.recentAssets.firstIndex(where: { $0.id == assetId }) else { return }
            AppCoordinator.shared.recentAssets[index].ocrText = result.fullText
        }
    }

    public func processCapturedImage(_ cgImage: CGImage, title: String, scaleFactor: Double = 2.0) {
        let settings = AppConfiguration.shared.captureSettings

        if settings.playCaptureSound {
            playShutterSound()
        }

        let asset = persistCapture(cgImage, title: title, scaleFactor: scaleFactor)

        if settings.copyToClipboard {
            copyImageToPasteboard(cgImage: cgImage)
        }

        AppLogger.shared.capture.info("Successfully processed capture asset: \(asset.dimensionsString, privacy: .public)")

        if settings.openInEditor {
            AppCoordinator.shared.openEditor(for: asset)
        }
    }

    public func processCapturedRegion(_ cgImage: CGImage, title: String, scaleFactor: Double = 2.0, action: RegionCaptureAction) {
        let settings = AppConfiguration.shared.captureSettings

        // 1. Composite in-place annotations if any were drawn directly on the overlay
        //    ("Open in Editor" keeps the raw capture so overlay annotations stay editable in the editor)
        let finalImage: CGImage
        let forceSave: Bool
        let overlayDocument: AnnotationDocument
        switch action {
        case .copy(let doc), .save(let doc), .edit(let doc), .upload(let doc), .defaultAction(let doc):
            overlayDocument = doc
        }
        if case .edit = action {
            finalImage = cgImage
        } else {
            let hasEdits = !overlayDocument.items.isEmpty || overlayDocument.hasStyling
            finalImage = hasEdits ? ExportCompositor.shared.composite(baseImage: cgImage, document: overlayDocument) : cgImage
        }
        if case .save = action { forceSave = true } else { forceSave = false }

        if settings.playCaptureSound {
            playShutterSound()
        }

        let asset = persistCapture(finalImage, title: title, scaleFactor: scaleFactor, forceSaveToDisk: forceSave)
        let fileURL = asset.originalFileURL
        AppLogger.shared.capture.info("Successfully processed in-place region capture: \(asset.dimensionsString, privacy: .public)")

        switch action {
        case .copy:
            copyImageToPasteboard(cgImage: finalImage)
            CaptureHUD.shared.show(title: "Copied to Clipboard", symbol: "doc.on.clipboard.fill", duration: 1.4)
            AppLogger.shared.capture.info("Region captured and copied directly to clipboard.")

        case .upload:
            copyImageToPasteboard(cgImage: finalImage)
            let shareURL = handleUpload(for: asset, image: finalImage)
            AppLogger.shared.capture.info("Region captured and uploaded: \(shareURL, privacy: .public)")

        case .save:
            if settings.copyToClipboard {
                copyImageToPasteboard(cgImage: finalImage)
            }
            CaptureHUD.shared.show(title: "Saved Screenshot", detail: fileURL.lastPathComponent, symbol: "square.and.arrow.down.fill", duration: 1.8)
            AppLogger.shared.capture.info("Region captured and saved to disk: \(fileURL.lastPathComponent, privacy: .public)")

        case .edit:
            EditorWindowController.present(for: asset, document: overlayDocument)

        case .defaultAction:
            if settings.copyToClipboard {
                copyImageToPasteboard(cgImage: finalImage)
            }
            if settings.openInEditor {
                EditorWindowController.present(for: asset)
            }
        }
    }

    @discardableResult
    private func handleUpload(for asset: ScreenshotAsset, image: CGImage) -> String {
        let config = AppConfiguration.shared
        let shareId = UUID().uuidString.prefix(8).lowercased()
        let shareURLString: String

        if config.storageMode == .userOwned && !config.s3Bucket.isEmpty {
            shareURLString = "https://\(config.s3Bucket).s3.amazonaws.com/\(asset.originalFileURL.lastPathComponent)"
        } else {
            shareURLString = "https://share.screenshotapp.local/s/\(shareId)"
        }

        // Copy share URL to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.setString(shareURLString, forType: .string)

        AppLogger.shared.storage.info("Uploaded screenshot to \(config.activeCloudProvider.displayName, privacy: .public): \(shareURLString, privacy: .public)")
        return shareURLString
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
