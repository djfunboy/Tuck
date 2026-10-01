import AppKit
import SwiftUI

@main
@MainActor
enum TuckMain {
    static func main() {
        if CommandLine.arguments.contains("--version") {
            print("Tuck 1.2.2")
            return
        }
        // Record which file we launched from before anything else; an update may replace it later.
        _ = ExecutableIdentity.launch
        let application = TuckApplication.shared
        let isMCP = CommandLine.arguments.contains("--mcp")
        // Info.plist sets LSUIElement, so every launch starts without a Dock tile and an agent's
        // --mcp process never flashes one; the standalone app promotes itself here.
        // Must precede run(): the Dock registers the tile during finishLaunching, and a policy
        // applied only afterwards left a zero-width (invisible) Dock tile.
        application.setActivationPolicy(isMCP ? .accessory : .regular)
        let delegate = AppDelegate(isMCP: isMCP)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // MARK: App lifetime
    private let isMCP: Bool
    private let model = PromptModel()
    private var window: NSWindow?
    private var serverTask: Task<Void, Never>?

    init(isMCP: Bool) { self.isMCP = isMCP }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Quit Tuck"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        // App Review (Guideline 4): a closed main window must be reopenable from the menu bar.
        // Standalone only: the agent-triggered panel is request-driven and has no menu bar.
        if !isMCP {
            addWindowMenu(to: menu)
        }
        NSApplication.shared.mainMenu = menu
        model.showWindow = { [weak self] in self?.showWindow() }
        (NSApplication.shared as? TuckApplication)?.didPaste = { [weak self] window, cleared in
            guard let self, let window, window === self.window else { return }
            self.model.recordPasteCleanup(cleared: cleared)
        }
        if isMCP {
            model.hideWindow = { [weak self] in self?.hideWindow() }
            serverTask = Task { [weak self, model] in
                do { try await MCPService(model: model).run() }
                catch { /* Transport failure closes the session; no input is logged. */ }
                model.cancel()
                self?.window?.close()
                NSApplication.shared.terminate(nil)
            }
        } else {
            showWindow()
            // An agent process that received the person's "open Tuck" asks this instance to
            // show its window instead of launching another one (see ReopenPolicy).
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(showTuckWindow(_:)), name: ReopenPolicy.showWindowRequest, object: nil)
        }
    }

    // MARK: Window
    private func showWindow() {
        if window == nil {
            let controller = NSHostingController(rootView: TuckView(model: model, isMCP: isMCP))
            let created: NSWindow
            if isMCP {
                let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.contentViewController = controller
                panel.level = .floating
                panel.hidesOnDeactivate = false
                panel.becomesKeyOnlyIfNeeded = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                created = panel
            } else {
                created = NSWindow(contentViewController: controller)
                created.styleMask = [.titled, .closable, .miniaturizable]
            }
            created.title = "Tuck"
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.backgroundColor = NSColor(srgbRed: 1, green: 0.985, blue: 0.95, alpha: 1)
            created.isReleasedWhenClosed = false
            created.isRestorable = false
            created.delegate = self
            if !isMCP { created.center() }
            window = created
        }
        if isMCP, let window {
            window.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .alertPanel
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                window.animator().alphaValue = 1
            }
            placeAtRightEdge(window)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // SwiftUI can settle the panel's size after ordering front; place it again once it has.
        if isMCP, let window { DispatchQueue.main.async { [weak self] in self?.placeAtRightEdge(window) } }
    }

    /// The agent popup always opens at one fixed spot in the upper right of the screen.
    /// Never forces a layout pass here: this runs while SwiftUI is updating for a new request,
    /// and a forced layout mid-update left the reused secure field ignoring input. Before the
    /// first layout the panel is zero-sized, so fall back to the popup's design size.
    private func placeAtRightEdge(_ window: NSWindow) {
        let size = window.frame.width > 0 ? window.frame.size : NSSize(width: 340, height: 298)
        guard let screen = NSApplication.shared.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        // One fixed, predictable spot: the upper right of the screen (5% in, 8% down).
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.maxX - size.width - (visible.width * 0.05).rounded(),
                                      y: visible.maxY - size.height - (visible.height * 0.08).rounded()))
    }

    private func hideWindow() {
        guard let window else { return }
        guard isMCP, model.lastOutcome == .saved,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.orderOut(nil)
            window.alphaValue = 1
            return
        }
        let presentationID = model.presentationID
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window else { return }
                guard self.model.presentationID == presentationID, self.model.request == nil else {
                    window.alphaValue = 1
                    return
                }
                window.orderOut(nil)
                window.alphaValue = 1
            }
        }
    }

    private func addWindowMenu(to menu: NSMenu) {
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let showItem = windowMenu.addItem(withTitle: String(localized: "Show Tuck"), action: #selector(showTuckWindow(_:)), keyEquivalent: "0")
        showItem.target = self
        windowMenu.addItem(.separator())
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApplication.shared.windowsMenu = windowMenu
    }

    @objc private func showTuckWindow(_ sender: Any?) { showWindow() }

    func windowWillClose(_ notification: Notification) { model.cancel() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let standalone = isMCP ? ReopenPolicy.runningStandaloneInstance() : nil
        switch ReopenPolicy.action(isMCP: isMCP, hasPendingRequest: model.request != nil,
                                   standaloneRunning: standalone != nil) {
        case .showWindow: showWindow()
        case .activateStandalone: if let standalone { ReopenPolicy.activate(standalone) }
        case .launchStandalone: ReopenPolicy.launchStandaloneInstance()
        }
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.cancel()
        serverTask?.cancel()
    }
}
