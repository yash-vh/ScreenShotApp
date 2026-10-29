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
                        Self.reportCaptureFailure(error)
                        AppCoordinator.shared.lastErrorMessage = error.localizedDescription
                    }
                    self.isCapturing = false
                }
            },
            onMultiScreen: { [weak self] image, global in
                // An area across displays can't be edited in place; open it fitted on the display under the pointer
                guard let self else { return }
                let screen = OverlayWindow.screenUnderMouse ?? NSScreen.screens[0]
                let frame = Self.fittedFrame(for: global, imageSize: CGSize(width: image.width, height: image.height), in: screen.visibleFrame)
                self.presentEditor(image, frame: frame, on: screen, title: "Region Capture")
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
                if let screen {
                    // Same annotate / copy / save / upload toolbar as an area capture, over the whole display
                    self.presentEditor(cgImage, frame: screen.frame, on: screen, title: "Full Screen Capture")
                    return
                }
                self.processCapturedImage(cgImage, title: "Full Screen Capture", scaleFactor: 2.0)
            } catch {
                AppLogger.shared.capture.error("Full screen capture error: \(error.localizedDescription, privacy: .public)")
                Self.reportCaptureFailure(error)
                AppCoordinator.shared.lastErrorMessage = error.localizedDescription
            }
            self.isCapturing = false
        }
    }

    /// Captures every connected display and joins them into one image, laid out as in System Settings › Displays
    public func captureAllScreens() {
        guard PermissionManager.shared.isAuthorized || PermissionManager.shared.checkScreenRecordingPermission() else {
            Task { @MainActor in
                if await PermissionManager.shared.verifyScreenRecordingPermission() {
                    self.captureAllScreens()
                } else {
                    PermissionManager.shared.showScreenRecordingPermissionDialog()
                }
            }
            return
        }
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            captureFullScreen()
            return
        }

        isCapturing = true
        Task {
            do {
                var captures: [(image: CGImage, frame: CGRect)] = []
                for screen in screens {
                    let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                    captures.append((try await ScreenCaptureService.shared.captureDisplay(displayId: displayId), screen.frame))
                }
                PermissionManager.shared.markAuthorized()
                guard let combined = Self.combineDisplays(captures) else {
                    throw AppError.captureFailed(reason: "Couldn't join the display images")
                }
                AppLogger.shared.capture.info("All-screens capture: \(captures.count) displays → \(combined.width)x\(combined.height)")

                // Annotate on the display under the pointer, scaled to fit
                let screen = OverlayWindow.screenUnderMouse ?? screens[0]
                let union = captures.map(\.frame).reduce(CGRect.null) { $0.union($1) }
                let frame = Self.fittedFrame(for: union, imageSize: CGSize(width: combined.width, height: combined.height), in: screen.visibleFrame)
                self.presentEditor(combined, frame: frame, on: screen, title: "All Screens Capture")
            } catch {
                AppLogger.shared.capture.error("All-screens capture error: \(error.localizedDescription, privacy: .public)")
                AppCoordinator.shared.lastErrorMessage = error.localizedDescription
                if !Self.reportCaptureFailure(error) {
                    CaptureHUD.shared.show(title: "Couldn't capture all screens", detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                }
                self.isCapturing = false
            }
        }
    }

    /// Places each display image at its arrangement position (AppKit global frames, points) on one canvas,
    /// at the sharpest display's pixel density. Areas no display covers stay transparent.
    nonisolated static func combineDisplays(_ captures: [(image: CGImage, frame: CGRect)]) -> CGImage? {
        guard !captures.isEmpty else { return nil }
        let union = captures.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let scale = captures.map { CGFloat($0.image.width) / max($0.frame.width, 1) }.max() ?? 1
        let width = Int((union.width * scale).rounded())
        let height = Int((union.height * scale).rounded())
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        // Both AppKit and CoreGraphics bitmaps are y-up, so frames map directly
        for capture in captures {
            let rect = CGRect(
                x: (capture.frame.minX - union.minX) * scale,
                y: (capture.frame.minY - union.minY) * scale,
                width: capture.frame.width * scale,
                height: capture.frame.height * scale
            )
            context.draw(capture.image, in: rect)
        }
        return context.makeImage()
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
                        if let placement = Self.editorPlacement(forWindow: windowId, imageSize: CGSize(width: cgImage.width, height: cgImage.height)) {
                            self.presentEditor(cgImage, frame: placement.frame, on: placement.screen, title: "Window Capture")
                            return
                        }
                        self.processCapturedImage(cgImage, title: "Window Capture", scaleFactor: Double(OverlayWindow.screenUnderMouse?.backingScaleFactor ?? 2.0))
                    } catch {
                        AppLogger.shared.capture.error("Window capture error: \(error.localizedDescription, privacy: .public)")
                        Self.reportCaptureFailure(error)
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

    /// Screen Recording access missing (e.g. revoked, or never granted after a bundle ID change): explain how to fix it
    /// instead of failing silently. Returns true when the failure was a permission problem.
    @discardableResult
    static func reportCaptureFailure(_ error: Error) -> Bool {
        guard let appError = error as? AppError,
              appError == .screenCapturePermissionDenied || appError == .screenCaptureNotAuthorized else { return false }
        PermissionManager.shared.showScreenRecordingPermissionDialog()
        return true
    }

    // MARK: - Editor for Full Screen & Window Captures

    /// Shows the annotation toolbar over an already-captured image; finishing runs the area-capture pipeline
    private func presentEditor(_ image: CGImage, frame: CGRect, on screen: NSScreen, title: String) {
        let scale = Double(image.width) / Double(max(frame.width, 1))
        RegionSelectionOverlayController.shared.presentEditor(
            image: image,
            frame: frame,
            on: screen,
            onComplete: { [weak self] _, _, action, edited in
                Task { @MainActor [weak self] in
                    self?.processCapturedRegion(edited ?? image, title: title, scaleFactor: scale, action: action)
                    self?.isCapturing = false
                }
            },
            onCancel: { [weak self] in
                self?.isCapturing = false
            }
        )
    }

    /// Where to show a captured window for editing: over the window itself when it fits on one display,
    /// otherwise scaled to fit the display that shows most of it
    static func editorPlacement(forWindow windowId: CGWindowID, imageSize: CGSize) -> (frame: CGRect, screen: NSScreen)? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowId) as? [[String: Any]])?.first,
              let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
              let primary = NSScreen.screens.first else { return nil }
        // CoreGraphics is top-left origin on the primary display; AppKit is bottom-left
        let rect = CGRect(x: cgRect.minX, y: primary.frame.height - cgRect.maxY, width: cgRect.width, height: cgRect.height)
        let screen = NSScreen.screens.max { a, b in
            a.frame.intersection(rect).width * a.frame.intersection(rect).height < b.frame.intersection(rect).width * b.frame.intersection(rect).height
        } ?? primary
        return (fittedFrame(for: rect, imageSize: imageSize, in: screen.visibleFrame), screen)
    }

    /// `rect` when it lies inside `area`, else the image aspect-fitted and centered in `area` (with a margin)
    static func fittedFrame(for rect: CGRect, imageSize: CGSize, in area: CGRect) -> CGRect {
        if area.contains(rect) { return rect }
        let bounds = area.insetBy(dx: 40, dy: 40)
        let aspect = imageSize.width / max(imageSize.height, 1)
        var size = CGSize(width: min(rect.width, bounds.width), height: min(rect.width, bounds.width) / aspect)
        if size.height > bounds.height {
            size = CGSize(width: bounds.height * aspect, height: bounds.height)
        }
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height).integral
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
            saveDir = HistoryStore.shared.capturesDirectory
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileExt = settings.defaultFormat == .jpeg ? "jpg" : "png"
        let prefix = settings.sanitizedFileNamePrefix
        var fileURL = saveDir.appendingPathComponent("\(prefix) \(timestamp).\(fileExt)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = saveDir.appendingPathComponent("\(prefix) \(timestamp) (\(suffix)).\(fileExt)")
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
        HistoryStore.shared.add(asset)

        if settings.runOcrAutomatically {
            indexText(of: image, assetId: asset.id)
        }
        return asset
    }

    /// Background on-device OCR so recent captures carry searchable text
    private func indexText(of image: CGImage, assetId: UUID) {
        Task { @MainActor in
            guard let result = try? await VisionService.shared.recognize(in: image, recognitionLevel: .fast) else { return }
            HistoryStore.shared.mutate(id: assetId) { $0.ocrText = result.fullText }
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

        if settings.copyToClipboard {
            CaptureHUD.shared.show(title: "Copied to Clipboard", symbol: "doc.on.clipboard.fill", duration: 1.4)
        } else {
            CaptureHUD.shared.show(title: "Saved Screenshot", detail: asset.originalFileURL.lastPathComponent, symbol: "square.and.arrow.down.fill", duration: 1.8)
        }
    }

    public func processCapturedRegion(_ cgImage: CGImage, title: String, scaleFactor: Double = 2.0, action: RegionCaptureAction) {
        let settings = AppConfiguration.shared.captureSettings

        // 1. Composite in-place annotations if any were drawn directly on the overlay
        let finalImage: CGImage
        let forceSave: Bool
        let overlayDocument: AnnotationDocument
        switch action {
        case .copy(let doc), .save(let doc), .upload(let doc), .defaultAction(let doc):
            overlayDocument = doc
        }
        let hasAnnotations = !overlayDocument.items.isEmpty || overlayDocument.hasStyling
        finalImage = hasAnnotations ? ExportCompositor.shared.composite(baseImage: cgImage, document: overlayDocument) : cgImage
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
            UploadService.shared.requestUpload(assetId: asset.id, image: finalImage)

        case .save:
            if settings.copyToClipboard {
                copyImageToPasteboard(cgImage: finalImage)
            }
            CaptureHUD.shared.show(title: "Saved Screenshot", detail: fileURL.lastPathComponent, symbol: "square.and.arrow.down.fill", duration: 1.8)
            AppLogger.shared.capture.info("Region captured and saved to disk: \(fileURL.lastPathComponent, privacy: .public)")

        case .defaultAction:
            if settings.copyToClipboard {
                copyImageToPasteboard(cgImage: finalImage)
            }
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
