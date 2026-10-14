import AppKit
import SwiftUI
import CoreGraphics

/// AppKit window controller managing the annotation editor interface.
@MainActor
public final class EditorWindowController: NSWindowController {
    public static var currentControllers: [UUID: EditorWindowController] = [:]

    private let asset: ScreenshotAsset
    private let undoRedoManager: UndoRedoManager
    private var baseCGImage: CGImage?
    private var canvasView: AnnotationCanvasView?

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

        // Load or create initial annotation document
        let doc = AnnotationDocument(assetId: asset.id)
        self.undoRedoManager = UndoRedoManager(document: doc)

        // Calculate initial window dimensions
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screen.width * 0.8
        let maxH = screen.height * 0.8

        var winW = CGFloat(asset.pixelWidth) / 2.0
        var winH = CGFloat(asset.pixelHeight) / 2.0

        if winW > maxW || winH > maxH {
            let ratio = min(maxW / winW, maxH / winH)
            winW *= ratio
            winH *= ratio
        }

        winW = max(winW, 600)
        winH = max(winH, 450) + 80 // Include toolbar height

        let window = NSWindow(
            contentRect: NSRect(x: (screen.width - winW) / 2, y: (screen.height - winH) / 2, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot Editor — \(asset.title)"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupContentView(width: winW, height: winH - 80, initialTool: initialTool)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContentView(width: CGFloat, height: CGFloat, initialTool: EditorTool = .arrow) {
        guard let window = window else { return }

        // 1. Load base image from disk
        if let imageSource = CGImageSourceCreateWithURL(asset.originalFileURL as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            self.baseCGImage = cgImage
        }

        let containerView = NSView(frame: window.contentView?.bounds ?? .zero)
        containerView.autoresizingMask = [.width, .height]

        // 2. Setup Canvas
        let canvas = AnnotationCanvasView(
            frame: .zero,
            undoRedoManager: undoRedoManager,
            baseImage: baseCGImage
        )
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.currentTool = initialTool
        self.canvasView = canvas

        // 3. Setup Toolbar State Bindings
        let toolbarView = EditorToolbarContainer(
            undoRedoManager: undoRedoManager,
            canvasView: canvas,
            initialTool: initialTool,
            onExport: { [weak self] in self?.handleExport() },
            onCopy: { [weak self] in self?.handleCopy() },
            onClose: { [weak self] in self?.handleClose() }
        )

        let toolbarHost = NSHostingView(rootView: toolbarView)
        toolbarHost.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(toolbarHost)
        containerView.addSubview(canvas)

        NSLayoutConstraint.activate([
            toolbarHost.topAnchor.constraint(equalTo: containerView.topAnchor),
            toolbarHost.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbarHost.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbarHost.heightAnchor.constraint(equalToConstant: 80),

            canvas.topAnchor.constraint(equalTo: toolbarHost.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        window.contentView = containerView
        window.makeFirstResponder(canvas)
    }

    // MARK: - Export and Actions

    private func handleExport() {
        guard let base = baseCGImage else { return }
        let compositeImage = ExportCompositor.shared.composite(baseImage: base, document: undoRedoManager.document)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = asset.originalFileURL.lastPathComponent

        if panel.runModal() == .OK, let saveURL = panel.url {
            let format: ExportFormat = saveURL.pathExtension.lowercased() == "jpg" || saveURL.pathExtension.lowercased() == "jpeg" ? .jpeg : .png
            try? ScreenCaptureService.shared.saveImage(compositeImage, format: format, to: saveURL)
            AppLogger.shared.editor.info("Exported flattened screenshot to: \(saveURL.lastPathComponent, privacy: .public)")
        }
    }

    private func handleCopy() {
        guard let base = baseCGImage else { return }
        let compositeImage = ExportCompositor.shared.composite(baseImage: base, document: undoRedoManager.document)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: compositeImage, size: NSSize(width: compositeImage.width, height: compositeImage.height))
        pasteboard.writeObjects([nsImage])
        AppLogger.shared.editor.info("Copied annotated screenshot to pasteboard.")
    }

    private func handleClose() {
        window?.close()
        Self.currentControllers.removeValue(forKey: asset.id)
    }
}

// MARK: - SwiftUI Toolbar Host Wrapper

struct EditorToolbarContainer: View {
    @ObservedObject var undoRedoManager: UndoRedoManager
    let canvasView: AnnotationCanvasView
    let onExport: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void

    @State private var selectedTool: EditorTool
    @State private var selectedColor: AnnotationColor = .red
    @State private var strokeWidth: Double = 3.0
    @State private var textContent: String = "Text"
    @State private var fontSize: Double = 22.0
    @State private var blurRadius: Double = 20.0

    init(
        undoRedoManager: UndoRedoManager,
        canvasView: AnnotationCanvasView,
        initialTool: EditorTool = .arrow,
        onExport: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.undoRedoManager = undoRedoManager
        self.canvasView = canvasView
        self._selectedTool = State(initialValue: initialTool)
        self.onExport = onExport
        self.onCopy = onCopy
        self.onClose = onClose
    }

    var body: some View {
        EditorToolbarView(
            undoRedoManager: undoRedoManager,
            selectedTool: $selectedTool,
            selectedColor: $selectedColor,
            strokeWidth: $strokeWidth,
            textContent: $textContent,
            fontSize: $fontSize,
            blurRadius: $blurRadius,
            onExport: onExport,
            onCopyToClipboard: onCopy,
            onClose: onClose
        )
        .onChange(of: selectedTool) { _, newTool in
            canvasView.currentTool = newTool
        }
        .onChange(of: selectedColor) { _, newColor in
            canvasView.currentStrokeColor = newColor
        }
        .onChange(of: strokeWidth) { _, newWidth in
            canvasView.currentStrokeWidth = newWidth
        }
        .onChange(of: textContent) { _, newText in
            canvasView.currentTextContent = newText
        }
        .onChange(of: fontSize) { _, newSize in
            canvasView.currentFontSize = newSize
        }
        .onChange(of: blurRadius) { _, newRad in
            canvasView.currentBlurRadius = newRad
        }
    }
}
