import AppKit
import AVFoundation
import SwiftUI

/// Welcome window that asks for Screen Recording (and optionally Microphone) access before the first capture,
/// instead of failing on the first shortcut press. Shown at launch while Screen Recording is missing.
@MainActor
public final class PermissionsWindowController {
    public static let shared = PermissionsWindowController()

    private var window: NSWindow?

    private init() {}

    /// Whether launch should show this window instead of going straight to work
    public static var isNeeded: Bool { !CGPreflightScreenCaptureAccess() }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = PermissionsView { [weak self] in self?.close() }
            .environmentObject(AppConfiguration.shared)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to \(AppBranding.appName)"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 600))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    public func close() {
        window?.close()
        window = nil
    }
}

struct PermissionsView: View {
    @EnvironmentObject var config: AppConfiguration
    @ObservedObject private var permissions = PermissionManager.shared
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var askedForScreen = false
    let onDone: () -> Void

    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 36)
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                PermissionRow(
                    symbol: "rectangle.dashed.badge.record",
                    tint: .blue,
                    title: "Screen Recording",
                    badge: "Required",
                    detail: "Lets \(AppBranding.appName) capture your screen, windows and selected areas. Nothing leaves your Mac unless you upload it.",
                    isAllowed: permissions.isAuthorized,
                    actionTitle: askedForScreen ? "Open Settings" : "Allow…",
                    action: requestScreenRecording
                )
                PermissionRow(
                    symbol: "mic.fill",
                    tint: .orange,
                    title: "Microphone",
                    badge: "Optional",
                    detail: "Only needed to record your voice over screen recordings.",
                    isAllowed: microphone == .authorized,
                    actionTitle: microphone == .notDetermined ? "Allow…" : "Open Settings",
                    action: requestMicrophone
                )
            }
            .padding(.horizontal, 28)

            if askedForScreen && !permissions.isAuthorized {
                relaunchHint
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
            }

            shortcuts
                .padding(.horizontal, 28)
                .padding(.top, 18)

            Spacer(minLength: 16)

            HStack {
                Button("Later") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Get Started") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!permissions.isAuthorized)
            }
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 600)
        .background(.background)
        .onReceive(poll) { _ in refresh() }
        .onAppear { refresh() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: AppBranding.logo(size: 72))
                .resizable()
                .frame(width: 72, height: 72)
            Text("Welcome to \(AppBranding.appName)")
                .font(.system(size: 22, weight: .bold))
            Text("Give \(AppBranding.appName) access once and it works from the menu bar and your shortcuts, even with no window open.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    private var relaunchHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.blue)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("Turned it on in System Settings? macOS applies it after \(AppBranding.appName) restarts.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Relaunch \(AppBranding.appName)") { permissions.relaunchApp() }
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.08)))
    }

    private var shortcuts: some View {
        let settings = config.captureSettings
        let rows: [(String, ShortcutBinding)] = [
            ("Capture Area", settings.shortcutRegion),
            ("Capture Screen", settings.shortcutFullScreen),
            ("Capture Window", settings.shortcutWindow),
            ("Record Screen", settings.shortcutRecording),
            ("Capture Text", settings.shortcutQuickOcr)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your shortcuts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 8) {
                        Text(row.1.displayString)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12)))
                        Text(row.0)
                            .font(.callout)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        guard !permissions.isAuthorized else { return }
        Task { await permissions.verifyScreenRecordingPermission() }
    }

    private func requestScreenRecording() {
        // The system prompt appears only the first time; afterwards the switch lives in System Settings
        if !askedForScreen { _ = CGRequestScreenCaptureAccess() }
        askedForScreen = true
        permissions.openScreenRecordingSystemSettings()
    }

    private func requestMicrophone() {
        if microphone == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        } else {
            permissions.openMicrophoneSystemSettings()
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let badge: String
    let detail: String
    let isAllowed: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isAllowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                if badge == "Required" {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.12)))
    }
}
