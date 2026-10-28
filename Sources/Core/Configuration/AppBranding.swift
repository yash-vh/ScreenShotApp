import AppKit

/// App logo and support destination shared by the menu bar, Settings and About screens.
public enum AppBranding {
    public static let appName = "SyncShot"

    /// Name of the logo image set in `Assets.xcassets` (generated from the source logo by `Scripts/generate-app-icon.sh`)
    public static let logoAssetName = "AppLogo"

    // PLACEHOLDER: replace with the real support address or help-desk URL before shipping.
    public static let supportURL = URL(string: "mailto:support@example.com?subject=SyncShot%20Support")!

    /// The app logo, or the SF Symbol mark when the logo asset isn't bundled (e.g. `swift run` builds)
    public static func logo(size: CGFloat) -> NSImage {
        let image = NSImage(named: logoAssetName)?.copy() as? NSImage
            ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: appName)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.8, weight: .regular))
            ?? NSImage()
        image.size = NSSize(width: size, height: size)
        return image
    }

    /// Opens the support destination (mail client or browser)
    @MainActor
    public static func contactSupport() {
        NSWorkspace.shared.open(supportURL)
    }
}
