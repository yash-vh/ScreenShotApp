import AppKit
import ServiceManagement

/// Keeps YnShot reachable after a force quit or crash.
///
/// macOS can't keep a process alive once it is killed, so this registers a launchd agent
/// (`Contents/Library/LaunchAgents/com.screenshotapp.mac.relauncher.plist`) whose
/// `KeepAlive.SuccessfulExit = false` makes launchd relaunch the app whenever it exits abnormally
/// (Force Quit, `kill`, crash). Quit from the menu is a clean exit and is respected.
///
/// While the agent is on, the launchd-managed process is the one instance that runs: a copy opened
/// from Finder, the Dock or the login item hands off to it and exits.
@MainActor
public enum BackgroundRelauncher {
    static let label = "com.screenshotapp.mac.relauncher"
    static let openSettingsNotification = Notification.Name("com.screenshotapp.mac.openSettings")
    private static let pendingOpenSettingsKey = "com.screenshotapp.pendingOpenSettings"

    private static var service: SMAppService { .agent(plistName: "\(label).plist") }

    /// True when launchd started this process through the relaunch agent
    public static var isLaunchedByAgent: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label
    }

    public static var isAgentEnabled: Bool {
        service.status == .enabled
    }

    /// Registers or removes the agent. Returns an error message when macOS refuses.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                // Written before registering: launchd starts the managed instance right away and it reads this on launch
                if !isLaunchedByAgent { requestOpenSettingsInManagedInstance() }
                try service.register()
            } else {
                // Unregistering stops the agent's process; when that's us, start a plain copy first
                if isLaunchedByAgent { launchPlainInstance() }
                try service.unregister()
            }
        } catch {
            _ = consumePendingOpenSettings()
            AppLogger.shared.app.error("Relaunch agent change failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
        switch service.status {
        case .requiresApproval:
            return "Approve YnShot in System Settings › General › Login Items."
        case .enabled where !isLaunchedByAgent:
            // launchd has just started the managed instance; let it take over
            NSApp.terminate(nil)
        default:
            _ = consumePendingOpenSettings()
        }
        return nil
    }

    /// Call first thing at launch. Returns true when this copy handed off to the agent-managed instance and is exiting.
    public static func handOffIfNeeded() -> Bool {
        guard AppConfiguration.shared.relaunchAfterUnexpectedQuit, isAgentEnabled, !isLaunchedByAgent else { return false }

        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let managed = others.first {
            managed.activate()
            DistributedNotificationCenter.default().postNotificationName(openSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
        } else {
            // The managed instance was quit cleanly, so launchd won't restart it on its own
            requestOpenSettingsInManagedInstance()
            guard kickstartAgent(), waitForManagedInstance(timeout: 5) else {
                // launchd accepted the request but couldn't start YnShot (e.g. the registration points at
                // an older build whose signature no longer matches). Keep this copy running instead of leaving
                // nothing open, and remove the broken agent so launchd stops retrying.
                AppLogger.shared.app.error("Relaunch agent failed to start YnShot; turning background relaunch off.")
                _ = consumePendingOpenSettings()
                try? service.unregister()
                AppConfiguration.shared.relaunchAfterUnexpectedQuit = false
                return false
            }
        }
        AppLogger.shared.app.info("Handing off to the relaunch agent instance.")
        NSApp.terminate(nil)
        return true
    }

    /// Whether this launch should show Settings (cleared once read)
    public static func consumePendingOpenSettings() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: pendingOpenSettingsKey)
        UserDefaults.standard.removeObject(forKey: pendingOpenSettingsKey)
        return pending
    }

    // MARK: - Private

    private static func requestOpenSettingsInManagedInstance() {
        UserDefaults.standard.set(true, forKey: pendingOpenSettingsKey)
    }

    private static func kickstartAgent() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLogger.shared.app.error("launchctl kickstart failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return process.terminationStatus == 0
    }

    /// Waits for the launchd-managed copy to appear, pumping the run loop so launch can continue afterwards
    private static func waitForManagedInstance(timeout: TimeInterval) -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let me = ProcessInfo.processInfo.processIdentifier
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != me }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private static func launchPlainInstance() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }
}
