import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Interactive glass panel showing upload progress and, on success, the link with a QR code and Open / Copy / Delete.
@MainActor
public final class UploadHUD {
    public static let shared = UploadHUD()

    final class Model: ObservableObject {
        enum Phase {
            case uploading(Double)
            case done(url: URL, expiresAt: Date?, canDelete: Bool, deletePageURL: URL?)
            case message(title: String, detail: String, symbol: String)
        }
        @Published var phase: Phase = .uploading(0)
        @Published var providerName = ""
        @Published var copied = false
        @Published var qrCode: NSImage?
        var onDelete: (() -> Void)?
        var onClose: (() -> Void)?
        var onHover: ((Bool) -> Void)?
    }

    private let model = Model()
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var dismissDelay: TimeInterval?

    private init() {
        model.onClose = { [weak self] in self?.dismiss() }
        model.onHover = { [weak self] hovering in
            if hovering { self?.dismissWorkItem?.cancel() } else { self?.scheduleDismiss() }
        }
    }

    public func showProgress(providerName: String) {
        model.providerName = providerName
        model.copied = false
        model.phase = .uploading(0)
        present(autoDismissAfter: nil)
    }

    public func updateProgress(_ fraction: Double) {
        if case .uploading = model.phase { model.phase = .uploading(min(max(fraction, 0), 1)) }
    }

    public func showSuccess(url: URL, expiresAt: Date?, canDelete: Bool, deletePageURL: URL? = nil, onDelete: @escaping () -> Void) {
        model.copied = true
        model.onDelete = { [weak self] in
            self?.dismiss()
            onDelete()
        }
        model.phase = .done(url: url, expiresAt: expiresAt, canDelete: canDelete, deletePageURL: deletePageURL)
        loadQRCode(for: url)
        present(autoDismissAfter: 12)
    }

    public func showQueuedCompletion(url: URL, count: Int) {
        model.copied = false
        model.onDelete = nil
        model.providerName = count == 1 ? "Queued upload finished" : "\(count) queued uploads finished"
        model.phase = .done(url: url, expiresAt: nil, canDelete: false, deletePageURL: nil)
        loadQRCode(for: url)
        present(autoDismissAfter: 12)
    }

    public func showMessage(title: String, detail: String, symbol: String) {
        model.phase = .message(title: title, detail: detail, symbol: symbol)
        present(autoDismissAfter: 6)
    }

    public func dismiss() {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(autoDismissAfter delay: TimeInterval?) {
        dismissDelay = delay
        if panel == nil {
            let host = NSHostingView(rootView: UploadHUDView(model: model))
            let hud = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            hud.level = .statusBar
            hud.isOpaque = false
            hud.backgroundColor = .clear
            hud.hasShadow = true
            hud.collectionBehavior = [.canJoinAllSpaces, .transient]
            hud.contentView = host
            panel = hud
        }
        guard let panel, let content = panel.contentView else { return }
        let size = content.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissWorkItem?.cancel()
        guard let delay = dismissDelay else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Renders the QR code once, off the main thread, instead of on every SwiftUI body pass
    private func loadQRCode(for url: URL) {
        model.qrCode = nil
        let string = url.absoluteString
        Task { [model] in
            let image = await Task.detached(priority: .userInitiated) { UploadHUD.qrImage(for: string) }.value
            if case .done(let current, _, _, _) = model.phase, current == url { model.qrCode = image }
        }
    }

    private nonisolated static let ciContext = CIContext()

    nonisolated static func qrImage(for string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

private struct UploadHUDView: View {
    @ObservedObject var model: UploadHUD.Model

    var body: some View {
        content
            .padding(16)
            .frame(width: 420, alignment: .leading)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .onHover { model.onHover?($0) }
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .uploading(let fraction):
            VStack(alignment: .leading, spacing: 10) {
                Label("Uploading to \(model.providerName)…", systemImage: "icloud.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            }

        case .done(let url, let expiresAt, let canDelete, let deletePageURL):
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.copied ? "Link copied" : model.providerName, systemImage: "checkmark.icloud.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.2, green: 0.83, blue: 0.6))
                    Text(url.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(expiryText(expiresAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Open") { NSWorkspace.shared.open(url) }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            model.copied = true
                        }
                        if canDelete, let onDelete = model.onDelete {
                            Button("Delete", role: .destructive) { onDelete() }
                        } else if let deletePageURL {
                            Button("Delete…") { NSWorkspace.shared.open(deletePageURL) }
                                .help("Open the delete page in your browser")
                        }
                        Spacer()
                        Button { model.onClose?() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Dismiss")
                    }
                    .controlSize(.small)
                }
                // Fixed slot so the panel doesn't resize when the QR code arrives
                Group {
                    if let qr = model.qrCode {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .accessibilityLabel("QR code for the share link")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 84, height: 84)
                .padding(4)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

        case .message(let title, let detail, let symbol):
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                Button { model.onClose?() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func expiryText(_ date: Date?) -> String {
        guard let date else { return "No expiry" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Expires \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
