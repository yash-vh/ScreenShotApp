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
        guard let panel else { return }
        self.panel = nil
        HUDPresenter.hide(panel)
    }

    private func present(autoDismissAfter delay: TimeInterval?) {
        dismissDelay = delay
        if panel == nil {
            panel = HUDPresenter.makePanel(content: NSHostingView(rootView: UploadHUDView(model: model)), interactive: true)
        }
        guard let panel, let content = panel.contentView else { return }
        HUDPresenter.show(panel, size: content.fittingSize)
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
            .padding(14)
            .frame(width: 400, alignment: .leading)
            .hudGlass(cornerRadius: 22)
            .padding(12) // room for the panel shadow
            .onHover { model.onHover?($0) }
            .animation(.snappy(duration: 0.2), value: model.copied)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .uploading(let fraction):
            HStack(spacing: 12) {
                statusIcon("icloud.and.arrow.up.fill", tint: .accentColor)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Uploading to \(model.providerName)")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }

        case .done(let url, let expiresAt, let canDelete, let deletePageURL):
            HStack(alignment: .top, spacing: 12) {
                statusIcon(model.copied ? "checkmark" : "link", tint: .green)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.copied ? "Link copied" : model.providerName)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        closeButton
                    }
                    Text(url.absoluteString)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(expiryText(expiresAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        Button("Open") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.borderedProminent)
                        Button(model.copied ? "Copied" : "Copy") {
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
                    }
                    .controlSize(.small)
                    .buttonBorderShape(.capsule)
                    .padding(.top, 2)
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
                .frame(width: 72, height: 72)
                .padding(5)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

        case .message(let title, let detail, let symbol):
            HStack(spacing: 12) {
                statusIcon(symbol, tint: symbol.contains("exclamationmark") ? .orange : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                closeButton
            }
        }
    }

    private func statusIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(tint.gradient, in: Circle())
            .contentTransition(.symbolEffect(.replace))
    }

    private var closeButton: some View {
        Button { model.onClose?() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }

    private func expiryText(_ date: Date?) -> String {
        guard let date else { return "No expiry" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Expires \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
