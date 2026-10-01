import AppKit

/// What to do when macOS reopens Tuck (Dock click, Finder double-click, "open -a").
///
/// LaunchServices routes an "open" of an already-running bundle to one existing process, which
/// may be an agent-launched `--mcp` process. With no pending request that process must not show
/// the credential panel (it would render header-only); the person expects the setup window. If
/// a standalone instance is already running it is brought forward, so repeated opens never
/// stack up setup windows; otherwise one is launched. With a request pending, the popup is
/// simply brought forward.
enum ReopenAction: Equatable { case showWindow, activateStandalone, launchStandalone }

enum ReopenPolicy {
    static func action(isMCP: Bool, hasPendingRequest: Bool, standaloneRunning: Bool) -> ReopenAction {
        guard isMCP, !hasPendingRequest else { return .showWindow }
        return standaloneRunning ? .activateStandalone : .launchStandalone
    }

    /// Another running instance of this app with a Dock tile: only the standalone app is
    /// `.regular`; agent processes are `.accessory`.
    @MainActor
    static func runningStandaloneInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            $0.processIdentifier != ownPID && !$0.isTerminated && $0.activationPolicy == .regular
        }
    }

    /// Same-user notification the standalone instance observes to show its window. Activation
    /// alone would not bring back a window the person closed or minimized.
    static let showWindowRequest = Notification.Name("ai.outergy.keydrop.showSetupWindow")

    @MainActor
    static func activate(_ application: NSRunningApplication) {
        NSApplication.shared.yieldActivation(to: application)
        application.activate()
        DistributedNotificationCenter.default().postNotificationName(
            showWindowRequest, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Opens a fresh instance of this app without `--mcp`, so it shows the setup screen.
    @MainActor
    static func launchStandaloneInstance() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
    }
}
