import AppKit
import SwiftUI
import Combine
import CoreGraphics

/// AppKit window controller managing the annotation editor interface.
@MainActor
public final class EditorWindowController: NSWindowController, NSWindowDelegate {
    public static var currentControllers: [UUID: EditorWindowController] = [:]

    private static let toolbarHeight: CGFloat = 44

    private let asset: ScreenshotAsset
    private let undoRedoManager: UndoRedoManager
    private let state: EditorState
    private var baseCGImage: CGImage?
    private var canvasView: AnnotationCanvasView?
    private var recognitionOverlay: OCRResultOverlay?
    private var recognitionResult: RecognitionResult?
    private var lastSavedDocument: AnnotationDocument
    private var isClosingConfirmed = false
    private var cancellables = Set<AnyCancellable>()

    public static func present(for asset: ScreenshotAsset, initialTool: EditorTool = .arrow) {
        if let existing = currentControllers[asset.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = EditorWindowController(asset: asset, initialTool: initialTool)
        currentControllers[asset.id] = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public init(asset: ScreenshotAsset, initialTool: EditorTool = .arrow) {
        self.asset = asset

        // 1. Load base image from disk
        if let imageSource = CGImageSourceCreateWithURL(asset.originalFileURL as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            self.baseCGImage = cgImage
        }

        let pixelsPerPoint = asset.scaleFactor ?? Double(NSScreen.main?.backingScaleFactor ?? 2.0)
        let doc = AnnotationDocument(assetId: asset.id, pixelsPerPoint: pixelsPerPoint)
        self.undoRedoManager = UndoRedoManager(document: doc)
        self.lastSavedDocument = doc
        self.state = EditorState(tool: initialTool)

        // 2. Size the window to show the capture at (up to) its native point size
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screen.width * 0.85
        let maxH = screen.height * 0.85 - Self.toolbarHeight
        let pointW = CGFloat(asset.pixelWidth) / CGFloat(pixelsPerPoint) + 48
        let pointH = CGFloat(asset.pixelHeight) / CGFloat(pixelsPerPoint) + 48
        let ratio = min(1.0, maxW / max(pointW, 1), maxH / max(pointH, 1))
        let winW = max(pointW * ratio, 920)
        let winH = max(pointH * ratio, 520) + Self.toolbarHeight

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot Editor — \(asset.title)"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 920, height: 420)
        window.center()

        super.init(window: window)
        window.delegate = self

        setupContentView()
        observeState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContentView() {
        guard let window = window else { return }

        let containerView = NSView(frame: window.contentView?.bounds ?? .zero)
        containerView.autoresizingMask = [.width, .height]

        let canvas = AnnotationCanvasView(frame: .zero, undoRedoManager: undoRedoManager, state: state, baseImage: baseCGImage)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.onCopyRequested = { [weak self] in self?.handleCopy() }
        canvas.onSaveRequested = { [weak self] in self?.handleExport() }
        canvas.onCloseRequested = { [weak self] in self?.handleClose() }
        self.canvasView = canvas

        let toolbarView = EditorToolbarView(
            undoRedoManager: undoRedoManager,
            state: state,
            onUndo: { [weak canvas] in canvas?.undo(nil) },
            onRedo: { [weak canvas] in canvas?.redo(nil) },
            onDelete: { [weak canvas] in canvas?.delete(nil) },
            onExport: { [weak self] in self?.handleExport() },
            onCopyToClipboard: { [weak self] in self?.handleCopy() },
            onClose: { [weak self] in self?.handleClose() }
        )
        let toolbarHost = NSHostingView(rootView: toolbarView)
        toolbarHost.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(canvas)
        containerView.addSubview(toolbarHost)

        window.contentView = containerView

        // Pin the toolbar below the (transparent) title bar so it never collides with the traffic lights
        NSLayoutConstraint.activate([
            toolbarHost.topAnchor.constraint(equalTo: (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? containerView.topAnchor),
            toolbarHost.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbarHost.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbarHost.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),

            canvas.topAnchor.constraint(equalTo: toolbarHost.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        window.initialFirstResponder = canvas
        window.makeFirstResponder(canvas)
    }

    private func observeState() {
        state.$isShowingRecognition
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] showing in
                self?.setRecognitionVisible(showing)
            }
            .store(in: &cancellables)

        undoRedoManager.$document
            .sink { [weak self] _ in
                self?.recognitionOverlay?.needsDisplay = true
                self?.recognitionOverlay?.needsLayout = true
            }
            .store(in: &cancellables)
    }

    // MARK: - Text Recognition (M4)

    private func setRecognitionVisible(_ visible: Bool) {
        guard visible else {
            recognitionOverlay?.removeFromSuperview()
            recognitionOverlay = nil
            return
        }
        if let cached = recognitionResult {
            showRecognitionOverlay(cached)
            return
        }
        guard let base = baseCGImage else { return }

        state.isRecognizing = true
        Task { @MainActor [weak self] in
            do {
                let result = try await VisionService.shared.recognize(in: base)
                guard let self = self else { return }
                self.state.isRecognizing = false
                self.recognitionResult = result
                if self.state.isShowingRecognition {
                    self.showRecognitionOverlay(result)
                }
            } catch {
                AppLogger.shared.recognition.error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
                self?.state.isRecognizing = false
                self?.state.isShowingRecognition = false
                self?.canvasView?.showToast("Text recognition failed")
            }
        }
    }

    private func showRecognitionOverlay(_ result: RecognitionResult) {
        guard let canvas = canvasView, recognitionOverlay == nil else { return }
        let overlay = OCRResultOverlay(result: result) { [weak canvas] in canvas?.imageRect ?? .zero }
        overlay.frame = canvas.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.onMessage = { [weak canvas] message in canvas?.showToast(message) }
        overlay.onClose = { [weak self] in self?.state.isShowingRecognition = false }
        canvas.addSubview(overlay)
        recognitionOverlay = overlay

        if result.isEmpty {
            canvas.showToast("No text or QR codes found")
        }
    }

    // MARK: - Export and Actions

    private func renderComposite() -> CGImage? {
        guard let base = baseCGImage else { return nil }
        return ExportCompositor.shared.composite(baseImage: base, document: undoRedoManager.document)
    }

    private func handleExport() {
        guard let compositeImage = renderComposite(), let window = window else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.directoryURL = asset.originalFileURL.deletingLastPathComponent()
        let baseName = asset.originalFileURL.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName) (edited).png"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let saveURL = panel.url, let self = self else { return }
            let ext = saveURL.pathExtension.lowercased()
            let format: ExportFormat = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
            do {
                try ScreenCaptureService.shared.saveImage(
                    compositeImage,
                    format: format,
                    jpegQuality: AppConfiguration.shared.captureSettings.jpegQuality,
                    to: saveURL
                )
                self.lastSavedDocument = self.undoRedoManager.document
                AppLogger.shared.editor.info("Exported flattened screenshot to: \(saveURL.lastPathComponent, privacy: .public)")
                self.canvasView?.showToast("✓ Saved \(saveURL.lastPathComponent)")
            } catch {
                AppLogger.shared.editor.error("Export failed: \(error.localizedDescription, privacy: .public)")
                self.canvasView?.showToast("Save failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleCopy() {
        guard let compositeImage = renderComposite() else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: compositeImage, size: NSSize(width: compositeImage.width, height: compositeImage.height))
        pasteboard.writeObjects([nsImage])
        lastSavedDocument = undoRedoManager.document
        AppLogger.shared.editor.info("Copied annotated screenshot to pasteboard.")
        canvasView?.showToast("✓ Copied to Clipboard")
    }

    private func handleClose() {
        window?.performClose(nil)
    }

    // MARK: - NSWindowDelegate

    private var hasUnexportedChanges: Bool {
        var current = undoRedoManager.document
        current.modifiedAt = lastSavedDocument.modifiedAt
        return current != lastSavedDocument
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnexportedChanges, !isClosingConfirmed else { return true }

        let alert = NSAlert()
        alert.messageText = "Keep your annotations?"
        alert.informativeText = "Your edits haven't been copied or saved. Copy the annotated screenshot to the clipboard before closing?"
        alert.addButton(withTitle: "Copy & Close")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self = self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.handleCopy()
                self.isClosingConfirmed = true
                sender.close()
            case .alertSecondButtonReturn:
                self.isClosingConfirmed = true
                sender.close()
            default:
                break
            }
        }
        return false
    }

    public func windowWillClose(_ notification: Notification) {
        Self.currentControllers.removeValue(forKey: asset.id)
    }
}
