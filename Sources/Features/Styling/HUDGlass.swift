import AppKit
import SwiftUI

extension View {
    /// Floating-panel surface: Liquid Glass on macOS 26 and later, HUD vibrancy before that
    @ViewBuilder
    func hudGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(HUDVibrancy().clipShape(shape))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }
}

private struct HUDVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Positions a floating panel at the top center of the screen under the pointer and fades it in or out
@MainActor
enum HUDPresenter {
    static func frame(for size: CGSize) -> CGRect {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 16, width: size.width, height: size.height)
    }

    static func show(_ panel: NSPanel, size: CGSize) {
        let target = frame(for: size)
        let alreadyVisible = panel.isVisible && panel.alphaValue > 0.9
        if !alreadyVisible {
            panel.setFrame(target.offsetBy(dx: 0, dy: 10), display: false)
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    static func hide(_ panel: NSPanel, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            completion?()
        })
    }

    static func makePanel(content: NSView, interactive: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = !interactive
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = content
        return panel
    }
}
