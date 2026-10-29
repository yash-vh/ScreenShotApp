import AppKit
import ScreenCaptureKit
import SwiftUI

/// Long (scrolling) screenshots: the user selects an area, then scrolls its content while YnShot keeps
/// capturing that area and stitches the frames into one tall image (`ScrollStitcher`).
@MainActor
public final class ScrollingCaptureController: ObservableObject {
    public static let shared = ScrollingCaptureController()

    @Published public private(set) var isActive = false
    @Published fileprivate var pixelHeight = 0
    @Published fileprivate var frames = 0
    @Published fileprivate var hint: String?

    private var stitcher: ScrollStitcher?
    private var captureTask: Task<Void, Never>?
    private var regionFrame: NSPanel?
    private var controlPanel: NSPanel?
    private var scaleFactor: Double = 2
    private var hintClearTask: Task<Void, Never>?

    /// Seconds between captures; short enough that a normal scroll keeps overlapping frames
    private static let interval: Duration = .milliseconds(180)

    private init() {}

    // MARK: - Lifecycle

    public func start() {
        guard !isActive else { return }
        RegionSelectionOverlayController.shared.present(
            mode: .quickSelect,
            onComplete: { [weak self] rect, screen, _, _ in
                // Give the window server a moment to remove the selection overlay before the first frame
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.begin(rect: rect, on: screen)
                }
            },
            onCancel: {}
        )
    }

    private func begin(rect: CGRect, on screen: NSScreen) {
        let rect = rect.integral
        guard rect.width >= 40, rect.height >= 40 else {
            CaptureHUD.shared.show(title: "Select a larger area", detail: "Scrolling capture needs an area at least 40 points tall.", symbol: "exclamationmark.triangle.fill")
            return
        }
        isActive = true
        frames = 0
        pixelHeight = 0
        hint = nil
        scaleFactor = Double(screen.backingScaleFactor)
        showChrome(around: rect, on: screen)

        captureTask = Task { [weak self] in
            do {
                let capturer = try await RegionCapturer(rect: rect, on: screen)
                while !Task.isCancelled {
                    let image = try await capturer.capture()
                    guard let self, !Task.isCancelled else { return }
                    self.ingest(image)
                    try await Task.sleep(for: Self.interval)
                }
            } catch is CancellationError {
                return
            } catch {
                AppLogger.shared.capture.error("Scrolling capture failed: \(error.localizedDescription, privacy: .public)")
                guard let self else { return }
                self.teardown()
                CaptureHUD.shared.show(title: "Scrolling capture failed", detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func ingest(_ image: CGImage) {
        guard var current = stitcher else {
            // Overlay scroll bars appear at the right edge while scrolling; leave them out of matching
            stitcher = ScrollStitcher(firstFrame: image, ignoredTrailingColumns: Int(20 * scaleFactor))
            frames = 1
            pixelHeight = image.height
            return
        }
        let result = current.append(image)
        stitcher = current
        frames = current.acceptedFrames
        pixelHeight = current.height
        switch result {
        case .lostTrack:
            showHint("Scroll a little slower")
        case .full:
            showHint("Maximum length reached")
            finish()
        case .appended, .unchanged:
            break
        }
    }

    private func showHint(_ text: String) {
        hint = text
        hintClearTask?.cancel()
        hintClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hint = nil
        }
    }

    /// Saves the stitched image through the normal capture pipeline (save, copy, history)
    public func finish() {
        guard isActive else { return }
        let image = stitcher?.makeImage()
        teardown()
        guard let image else { return }
        CaptureCoordinator.shared.processCapturedImage(image, title: "Scrolling Capture", scaleFactor: scaleFactor)
    }

    public func cancel() {
        teardown()
    }

    private func teardown() {
        captureTask?.cancel()
        captureTask = nil
        hintClearTask?.cancel()
        stitcher = nil
        isActive = false
        regionFrame?.orderOut(nil)
        regionFrame = nil
        if let controlPanel {
            HUDPresenter.hide(controlPanel)
        }
        controlPanel = nil
    }

    // MARK: - On-Screen Chrome

    private func showChrome(around rect: CGRect, on screen: NSScreen) {
        // Dashed frame just outside the area; clicks and scrolls pass through to the app underneath
        let inset: CGFloat = 4
        let frame = HUDPresenter.makePanel(content: ScrollRegionFrameView(), interactive: false)
        frame.hasShadow = false
        frame.sharingType = .none
        frame.setFrame(rect.insetBy(dx: -inset, dy: -inset), display: true)
        frame.orderFrontRegardless()
        regionFrame = frame

        let host = NSHostingView(rootView: ScrollCaptureControls(controller: self))
        let size = host.fittingSize
        let panel = HUDPresenter.makePanel(content: host, interactive: true)
        panel.sharingType = .none
        panel.setFrame(Self.controlFrame(size: size, below: rect, on: screen), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        controlPanel = panel
    }

    /// Below the area when there is room, else above it, else inside its bottom edge
    private static func controlFrame(size: CGSize, below rect: CGRect, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let x = min(max(rect.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        var y = rect.minY - size.height - 14
        if y < visible.minY + 8 { y = rect.maxY + 14 }
        if y + size.height > visible.maxY - 8 { y = rect.minY + 14 }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

// MARK: - Region Capturer

/// Captures one screen area repeatedly with ScreenCaptureKit, leaving out YnShot's own windows
private struct RegionCapturer {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration

    init(rect: CGRect, on screen: NSScreen) async throws {
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw AppError.displayNotFound(displayId: displayID)
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        // Display-local points, top-left origin
        let frame = screen.frame
        let source = CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let scale = CGFloat(filter.pointPixelScale)
        configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        configuration.width = Int(source.width * scale)
        configuration.height = Int(source.height * scale)
        configuration.showsCursor = false
        configuration.scalesToFit = false
    }

    func capture() async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

// MARK: - Views

private final class ScrollRegionFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 6, yRadius: 6)
        path.lineWidth = 2
        path.setLineDash([7, 5], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

/// Floating glass bar shown while scrolling: progress, Cancel and Done
private struct ScrollCaptureControls: View {
    @ObservedObject var controller: ScrollingCaptureController

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white, Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.hint ?? (controller.frames <= 1 ? "Scroll down to capture" : "Capturing as you scroll"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(controller.hint == nil ? Color.primary : Color.orange)
                Text(detail)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 190, alignment: .leading)

            Button("Cancel") { controller.cancel() }
                .controlSize(.large)

            Button {
                controller.finish()
            } label: {
                Text("Done").frame(minWidth: 44)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .hudGlass(cornerRadius: 20)
        .padding(8)
    }

    private var detail: String {
        guard controller.frames > 0 else { return "Starting…" }
        let points = Int(Double(controller.pixelHeight) / max(NSScreen.main?.backingScaleFactor ?? 2, 1))
        return "\(points.formatted()) pt tall · \(controller.frames) frame\(controller.frames == 1 ? "" : "s")"
    }
}
