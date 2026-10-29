import AppKit
import AVFoundation
import Combine

/// Drives screen recording: picks the target, checks microphone permission and disk space,
/// runs the session with pause / resume, and saves the result (MP4 or GIF) into the history.
@MainActor
public final class RecordingCoordinator: ObservableObject {
    public static let shared = RecordingCoordinator()

    public enum State: Equatable {
        case idle
        case selecting
        case preparing
        case recording
        case paused
        case finishing
    }

    public enum TargetKind {
        case region
        case window
        case fullScreen
    }

    @Published public private(set) var state: State = .idle
    /// Recorded time, excluding pauses
    @Published public private(set) var elapsed: TimeInterval = 0

    public var isActive: Bool { state == .recording || state == .paused }

    private var session: RecordingSession?
    private var frameWindow: RecordingFrameWindow?
    private var tickTimer: Timer?
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var finalURL: URL?
    private var settings = RecordingSettings.default
    private var lastDiskCheck = Date.distantPast

    private init() {}

    // MARK: - Entry Points

    /// Hotkey / menu: stop when recording, otherwise start a region recording
    public func toggle() {
        switch state {
        case .recording, .paused: stop()
        case .idle: start(.region)
        default: break
        }
    }

    public func start(_ kind: TargetKind) {
        guard state == .idle else { return }
        settings = AppConfiguration.shared.recordingSettings

        let outputDirectory = outputDirectory()
        if let available = DiskSpaceGuard.availableBytes(at: outputDirectory),
           !DiskSpaceGuard.canStart(available: available, minimumFreeMB: settings.minimumFreeSpaceMB) {
            CaptureHUD.shared.show(
                title: "Not enough disk space to record",
                detail: "\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) free. Free up space or lower the limit in Settings › Recording.",
                symbol: "externaldrive.badge.exclamationmark"
            )
            return
        }

        state = .selecting
        Task { @MainActor in
            guard await self.ensureMicrophoneAccess() else {
                self.state = .idle
                return
            }
            self.selectTarget(kind)
        }
    }

    public func togglePause() {
        switch state {
        case .recording:
            session?.pause()
            accumulated += segmentStart.map { Date().timeIntervalSince($0) } ?? 0
            segmentStart = nil
            state = .paused
            frameWindow?.setPaused(true)
        case .paused:
            session?.resume()
            segmentStart = Date()
            state = .recording
            frameWindow?.setPaused(false)
        default:
            break
        }
    }

    public func stop(reason: String? = nil) {
        guard isActive, let session else { return }
        state = .finishing
        tickTimer?.invalidate()
        tickTimer = nil
        frameWindow?.close()
        frameWindow = nil
        let duration = currentElapsed()

        Task { @MainActor in
            defer { self.reset() }
            do {
                let videoURL = try await session.stop()
                try await self.deliver(videoURL: videoURL, pixelSize: session.pixelSize, duration: duration, note: reason)
            } catch {
                AppLogger.shared.recording.error("Recording failed: \(error.localizedDescription, privacy: .public)")
                CaptureHUD.shared.show(title: "Recording failed", detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    public func cancel() {
        guard isActive, let session else { return }
        tickTimer?.invalidate()
        frameWindow?.close()
        Task { @MainActor in
            await session.cancel()
            self.reset()
            CaptureHUD.shared.show(title: "Recording discarded", symbol: "trash.fill", duration: 1.4)
        }
    }

    // MARK: - Setup

    private func ensureMicrophoneAccess() async -> Bool {
        guard settings.recordMicrophone else { return true }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return true }
            return askToContinueWithoutMicrophone()
        default:
            return askToContinueWithoutMicrophone()
        }
    }

    private func askToContinueWithoutMicrophone() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Microphone access is off"
        alert.informativeText = "Allow \(AppBranding.appName) in System Settings › Privacy & Security › Microphone to record voiceover. You can still record without sound."
        alert.addButton(withTitle: "Record Without Microphone")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            settings.recordMicrophone = false
            return true
        case .alertSecondButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return false
        default:
            return false
        }
    }

    private func selectTarget(_ kind: TargetKind) {
        switch kind {
        case .region:
            RegionSelectionOverlayController.shared.present(
                mode: .quickSelect,
                onComplete: { [weak self] rect, screen, _, _ in
                    guard let self else { return }
                    let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                    let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
                    self.begin(.region(displayID, rect: local), frame: rect, title: "Region Recording")
                },
                onCancel: { [weak self] in self?.state = .idle }
            )
        case .window:
            WindowSelectionOverlayController.shared.present(
                onSelect: { [weak self] windowID in
                    self?.begin(.window(windowID), frame: nil, title: "Window Recording")
                },
                onCancel: { [weak self] in self?.state = .idle }
            )
        case .fullScreen:
            let screen = OverlayWindow.screenUnderMouse ?? NSScreen.main
            let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
            begin(.display(displayID), frame: nil, title: "Screen Recording")
        }
    }

    private var title = "Screen Recording"

    private func begin(_ target: RecordingTarget, frame: CGRect?, title: String) {
        state = .preparing
        self.title = title
        let finalURL = uniqueURL(in: outputDirectory(), ext: settings.outputFormat == .gif ? "gif" : "mp4")
        self.finalURL = finalURL
        // GIFs are encoded from a temporary MP4
        let videoURL = settings.outputFormat == .gif
            ? FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            : finalURL
        let settings = self.settings

        Task { @MainActor in
            do {
                let session = try await RecordingSession.make(target: target, settings: settings, outputURL: videoURL)
                session.onStreamError = { error in
                    RecordingCoordinator.shared.stop(reason: "Stopped early: \(error.localizedDescription)")
                }
                try await session.start()
                self.session = session
                if let frame {
                    let window = RecordingFrameWindow(around: frame)
                    window.orderFrontRegardless()
                    self.frameWindow = window
                }
                self.accumulated = 0
                self.segmentStart = Date()
                self.elapsed = 0
                self.state = .recording
                AppCoordinator.shared.isRecordingActive = true
                self.tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    Task { @MainActor in RecordingCoordinator.shared.tick() }
                }
                AppLogger.shared.recording.info("Recording started at \(Int(session.pixelSize.width))x\(Int(session.pixelSize.height))")
            } catch {
                AppLogger.shared.recording.error("Could not start recording: \(error.localizedDescription, privacy: .public)")
                CaptureHUD.shared.show(title: "Couldn't start recording", detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                self.reset()
            }
        }
    }

    private func tick() {
        guard isActive else { return }
        elapsed = currentElapsed()
        guard Date().timeIntervalSince(lastDiskCheck) >= 2, let url = finalURL else { return }
        lastDiskCheck = Date()
        if let available = DiskSpaceGuard.availableBytes(at: url.deletingLastPathComponent()),
           DiskSpaceGuard.mustStop(available: available, minimumFreeMB: settings.minimumFreeSpaceMB) {
            AppLogger.shared.recording.notice("Stopping recording: free disk space below limit")
            stop(reason: "Stopped automatically because the disk is almost full.")
        }
    }

    private func currentElapsed() -> TimeInterval {
        accumulated + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func reset() {
        session = nil
        tickTimer?.invalidate()
        tickTimer = nil
        frameWindow?.close()
        frameWindow = nil
        segmentStart = nil
        accumulated = 0
        elapsed = 0
        finalURL = nil
        state = .idle
        AppCoordinator.shared.isRecordingActive = false
    }

    // MARK: - Delivery

    private func deliver(videoURL: URL, pixelSize: CGSize, duration: TimeInterval, note: String?) async throws {
        guard let finalURL else { return }
        var mediaType = MediaType.video
        var size = pixelSize

        if settings.outputFormat == .gif {
            CaptureHUD.shared.show(title: "Creating GIF…", symbol: "play.square.stack", duration: 30)
            defer { try? FileManager.default.removeItem(at: videoURL) }
            let gif = try await GIFEncoder.convert(videoURL: videoURL, to: finalURL, frameRate: settings.gifFrameRate, maxPixelSize: settings.gifMaxPixelSize)
            mediaType = .gif
            size = gif.pixelSize
        }

        let asset = ScreenshotAsset(
            title: title,
            originalFileURL: finalURL,
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height),
            fileSizeBytes: HistoryStore.fileSize(at: finalURL),
            mediaType: mediaType,
            durationSeconds: duration
        )
        HistoryStore.shared.add(asset)

        if AppConfiguration.shared.captureSettings.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([finalURL as NSURL])
        }
        let detail = [finalURL.lastPathComponent, Self.format(duration), asset.formattedFileSize].joined(separator: " · ")
        CaptureHUD.shared.show(
            title: note ?? (mediaType == .gif ? "GIF saved" : "Recording saved"),
            detail: detail,
            symbol: mediaType == .gif ? "play.square.stack.fill" : "video.fill",
            duration: 3
        )
        AppLogger.shared.recording.info("Recording saved: \(finalURL.lastPathComponent, privacy: .public)")
    }

    private func outputDirectory() -> URL {
        AppConfiguration.shared.captureSettings.saveToDisk
            ? AppConfiguration.shared.resolveLocalSaveDirectory()
            : HistoryStore.shared.capturesDirectory
    }

    private func uniqueURL(in directory: URL, ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "Screen Recording \(formatter.string(from: Date()))"
        var url = directory.appendingPathComponent("\(stem).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stem) (\(suffix)).\(ext)")
            suffix += 1
        }
        return url
    }

    /// "0:42", "12:03", "1:02:03"
    nonisolated public static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}

/// Click-through outline drawn around a region being recorded.
/// Our own windows are excluded from the stream, so it never appears in the video.
final class RecordingFrameWindow: NSWindow {
    private let border = NSView()

    init(around rect: CGRect) {
        let inset: CGFloat = 3
        super.init(contentRect: rect.insetBy(dx: -inset, dy: -inset), styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .statusBar
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        border.wantsLayer = true
        border.layer?.borderWidth = 2
        border.layer?.cornerRadius = 4
        contentView = border
        setPaused(false)
    }

    func setPaused(_ paused: Bool) {
        border.layer?.borderColor = (paused ? NSColor.systemYellow : NSColor.systemRed).withAlphaComponent(0.9).cgColor
    }
}
