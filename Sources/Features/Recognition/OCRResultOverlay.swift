import AppKit

/// Transparent overlay drawn above the editor canvas showing recognized text and QR/barcode bounding boxes.
/// Clicking a box copies its contents; the floating action bar offers "Copy All Text" and "Copy QR Link".
/// Clicks outside boxes and the action bar fall through to the canvas.
public final class OCRResultOverlay: NSView {
    public override var isFlipped: Bool { true }

    public var result: RecognitionResult {
        didSet {
            rebuildActionBar()
            needsDisplay = true
        }
    }

    /// Supplies the image rect (in this view's coordinates) the normalized boxes map onto
    private let imageRectProvider: () -> CGRect
    /// Reports a short status message (e.g. "Copied") to the host
    public var onMessage: ((String) -> Void)?
    public var onClose: (() -> Void)?

    private var hoveredBoxId: UUID?
    private let actionBar = NSStackView()

    public init(result: RecognitionResult, imageRectProvider: @escaping () -> CGRect) {
        self.result = result
        self.imageRectProvider = imageRectProvider
        super.init(frame: .zero)

        actionBar.orientation = .horizontal
        actionBar.spacing = 8
        actionBar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        actionBar.wantsLayer = true
        actionBar.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.92).cgColor
        actionBar.layer?.cornerRadius = 10
        actionBar.layer?.borderWidth = 1
        actionBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        addSubview(actionBar)
        rebuildActionBar()

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout & Action Bar

    public override func layout() {
        super.layout()
        let size = actionBar.fittingSize
        // Pinned to the top so it never collides with the canvas toast at the bottom
        actionBar.frame = CGRect(x: bounds.midX - size.width / 2, y: 10, width: size.width, height: size.height)
    }

    private func rebuildActionBar() {
        actionBar.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let summary = NSTextField(labelWithString: summaryText)
        summary.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        summary.textColor = NSColor.white.withAlphaComponent(0.8)
        actionBar.addArrangedSubview(summary)

        if !result.textBlocks.isEmpty {
            actionBar.addArrangedSubview(makeButton("Copy All Text", symbol: "doc.on.doc", action: #selector(copyAllText)))
        }
        if let barcode = result.barcodes.first {
            let title = barcode.url != nil ? "Copy QR Link" : "Copy Code"
            actionBar.addArrangedSubview(makeButton(title, symbol: "qrcode", action: #selector(copyFirstBarcode)))
            if barcode.url != nil {
                actionBar.addArrangedSubview(makeButton("Open Link", symbol: "safari", action: #selector(openFirstBarcode)))
            }
        }
        actionBar.addArrangedSubview(makeButton("Done", symbol: "xmark", action: #selector(close)))
        needsLayout = true
    }

    private var summaryText: String {
        if result.isEmpty { return "No text or codes found" }
        var parts: [String] = []
        if !result.textBlocks.isEmpty { parts.append("\(result.textBlocks.count) text line\(result.textBlocks.count == 1 ? "" : "s")") }
        if !result.barcodes.isEmpty { parts.append("\(result.barcodes.count) code\(result.barcodes.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ") + " — click a box to copy"
    }

    private func makeButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .recessed
        button.controlSize = .small
        button.imagePosition = .imageLeading
        button.contentTintColor = .white
        return button
    }

    // MARK: - Actions

    @objc private func copyAllText() {
        let count = result.textBlocks.count
        copyToPasteboard(result.fullText, message: "✓ Copied \(count) line\(count == 1 ? "" : "s") of text")
    }

    @objc private func copyFirstBarcode() {
        guard let barcode = result.barcodes.first else { return }
        copyToPasteboard(barcode.payload, message: barcode.url != nil ? "✓ Copied QR link" : "✓ Copied code contents")
    }

    @objc private func openFirstBarcode() {
        guard let url = result.barcodes.first?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func close() {
        onClose?()
    }

    private func copyToPasteboard(_ string: String, message: String) {
        guard !string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        onMessage?(message)
    }

    // MARK: - Hit Testing & Mouse

    private struct Box {
        let id: UUID
        let rect: CGRect
        let text: String
        let isBarcode: Bool
    }

    private var boxes: [Box] {
        let iRect = imageRectProvider()
        func map(_ r: NormalizedRect) -> CGRect {
            CGRect(x: iRect.minX + r.origin.x * iRect.width, y: iRect.minY + r.origin.y * iRect.height, width: r.width * iRect.width, height: r.height * iRect.height)
                .insetBy(dx: -3, dy: -2)
        }
        return result.textBlocks.map { Box(id: $0.id, rect: map($0.boundingBox), text: $0.text, isBarcode: false) }
            + result.barcodes.map { Box(id: $0.id, rect: map($0.boundingBox), text: $0.payload, isBarcode: true) }
    }

    private func box(at point: CGPoint) -> Box? {
        boxes.last { $0.rect.contains(point) }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if actionBar.frame.contains(local) {
            return super.hitTest(point)
        }
        return box(at: local) != nil ? self : nil
    }

    public override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard let box = box(at: loc) else { return }
        copyToPasteboard(box.text, message: box.isBarcode ? "✓ Copied code contents" : "✓ Copied “\(box.text.prefix(40))”")
    }

    public override func mouseMoved(with event: NSEvent) {
        let hovered = box(at: convert(event.locationInWindow, from: nil))?.id
        if hovered != hoveredBoxId {
            hoveredBoxId = hovered
            needsDisplay = true
        }
        if hovered != nil { NSCursor.pointingHand.set() }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for box in boxes {
            let hovered = box.id == hoveredBoxId
            let tint = box.isBarcode ? NSColor.systemGreen : NSColor.systemYellow
            let path = CGPath(roundedRect: box.rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(path)
            context.setFillColor(tint.withAlphaComponent(hovered ? 0.35 : 0.16).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(tint.withAlphaComponent(hovered ? 1.0 : 0.75).cgColor)
            context.setLineWidth(hovered ? 2 : 1)
            context.strokePath()
        }
    }
}

// MARK: - Floating Capture HUD

/// Small auto-dismissing heads-up panel used to confirm background actions such as "Text copied".
@MainActor
public final class CaptureHUD {
    public static let shared = CaptureHUD()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    public func show(title: String, detail: String? = nil, symbol: String = "checkmark.circle.fill", duration: TimeInterval = 2.4) {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        icon.contentTintColor = .white

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white

        let texts = NSStackView(views: [titleLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        if let detail = detail, !detail.isEmpty {
            let detailLabel = NSTextField(wrappingLabelWithString: detail)
            detailLabel.font = NSFont.systemFont(ofSize: 12)
            detailLabel.textColor = NSColor.white.withAlphaComponent(0.75)
            detailLabel.maximumNumberOfLines = 3
            detailLabel.preferredMaxLayoutWidth = 320
            texts.addArrangedSubview(detailLabel)
        }

        let stack = NSStackView(views: [icon, texts])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 18)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        let size = stack.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24, width: size.width, height: size.height)

        let hud = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hud.level = .statusBar
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.hasShadow = true
        hud.ignoresMouseEvents = true
        hud.collectionBehavior = [.canJoinAllSpaces, .transient]
        hud.contentView = effect
        hud.orderFrontRegardless()
        panel = hud

        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
