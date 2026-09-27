import AppKit

/// What to do when macOS reopens Tuck (Dock click, Finder double-click, "open -a").
///
/// LaunchServices routes an "open" of an already-running bundle to the existing process. An
/// agent-launched `--mcp` process with no pending request must not show the credential panel
/// (it would render header-only); the person expects the setup window, so a separate standalone
/// instance is launched instead. With a request pending, the popup is simply brought forward.
enum ReopenAction: Equatable { case showWindow, launchStandalone }

enum ReopenPolicy {
    static func action(isMCP: Bool, hasPendingRequest: Bool) -> ReopenAction {
        isMCP && !hasPendingRequest ? .launchStandalone : .showWindow
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
