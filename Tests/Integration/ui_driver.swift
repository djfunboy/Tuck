import AppKit
import ApplicationServices
import Foundation

guard CommandLine.arguments.count >= 3, let pid = Int32(CommandLine.arguments[1]) else { exit(2) }
let action = CommandLine.arguments[2]
let app = AXUIElementCreateApplication(pid)
func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
}
func nodes(_ node: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 30 else { return [] }
    return [node] + ((attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap { nodes($0, depth: depth + 1) }
}
if action == "assert-right-edge" {
    let deadline = Date().addingTimeInterval(3)
    var evidence = "no focused window frame"
    repeat {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           let window = attribute(app, kAXFocusedWindowAttribute),
           CFGetTypeID(window) == AXUIElementGetTypeID(),
           let position = attribute(window as! AXUIElement, kAXPositionAttribute),
           CFGetTypeID(position) == AXValueGetTypeID(),
           let dimensions = attribute(window as! AXUIElement, kAXSizeAttribute),
           CFGetTypeID(dimensions) == AXValueGetTypeID(),
           let primary = NSScreen.screens.first {
            var point = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(position as! AXValue, .cgPoint, &point),
               AXValueGetValue(dimensions as! AXValue, .cgSize, &size) {
                // Accessibility uses a top-left origin; AppKit screen frames use a bottom-left origin.
                let frame = CGRect(x: point.x, y: primary.frame.maxY - point.y - size.height,
                                   width: size.width, height: size.height)
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
                    // The popup's fixed spot: 5% in from the right and 8% down from the top of the visible frame.
                    let visible = screen.visibleFrame
                    let rightDelta = abs(frame.maxX - (visible.maxX - visible.width * 0.05))
                    let topDelta = abs(frame.maxY - (visible.maxY - visible.height * 0.08))
                    evidence = "right offset=\(rightDelta), top offset=\(topDelta)"
                    if rightDelta <= 12 && topDelta <= 12 {
                        print("PASS: focused popup is at its fixed upper-right spot")
                        exit(0)
                    }
                } else {
                    evidence = "focused window is outside all AppKit screens"
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    print("FAIL: focused popup placement: \(evidence)"); exit(16)
}
if action == "assert-compact-frontmost" {
    // AX controls can appear before AppKit finishes ordering/activating the panel.
    let deadline = Date().addingTimeInterval(3)
    var evidence = "no window"
    repeat {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let active = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let window = windows.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == pid }),
           let bounds = window[kCGWindowBounds as String] as? NSDictionary,
           let frame = CGRect(dictionaryRepresentation: bounds) {
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            evidence = "frame=\(frame) layer=\(layer) active=\(String(describing: active)) target=\(pid)"
            if frame.width <= 345 && frame.height <= 300 && layer > 0 && active == pid {
                print("PASS: compact floating prompt is frontmost (\(Int(frame.width)) × \(Int(frame.height)))")
                exit(0)
            }
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    print("FAIL: prompt must be compact, floating, and frontmost: \(evidence)"); exit(12)
}
if action == "assert-hidden" {
    var windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // AppKit retains a fading snapshot briefly after orderOut; wait for dismissal.
    let deadline = Date().addingTimeInterval(3)
    while windows.contains(where: { $0[kCGWindowOwnerPID as String] as? Int32 == pid }) && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
        windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }
    guard !windows.contains(where: { $0[kCGWindowOwnerPID as String] as? Int32 == pid }) else {
        for window in windows where window[kCGWindowOwnerPID as String] as? Int32 == pid {
            print("Visible window layer=\(String(describing: window[kCGWindowLayer as String])) bounds=\(String(describing: window[kCGWindowBounds as String])) alpha=\(String(describing: window[kCGWindowAlpha as String]))")
        }
        print("FAIL: popup is still visible"); exit(13)
    }
    print("PASS: popup dismissed without another click")
    exit(0)
}
let tree = nodes(app)
if action == "assert-confirmation-cleared" || action == "assert-confirmation-typed" {
    guard let confirmation = tree.first(where: { attribute($0, kAXIdentifierAttribute) as? String == "saveConfirmation" }) else {
        print("FAIL: save confirmation is missing"); exit(17)
    }
    let labels = nodes(confirmation).flatMap { node in
        [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute(node, $0) as? String }
    }
    let valid = action == "assert-confirmation-cleared"
        ? labels.contains("Saved to Keychain · Clipboard cleared")
        : labels.contains(where: { $0.hasPrefix("Saved in Apple Keychain · all ") })
    guard valid else { print("FAIL: save confirmation text did not match: \(labels)"); exit(17) }
    print("PASS: save confirmation text matches the input path")
    exit(0)
}
if action == "assert-empty-save-inert" {
    guard let save = tree.first(where: { attribute($0, kAXIdentifierAttribute) as? String == "saveButton" }) else { exit(14) }
    // Custom SwiftUI styles can report AXEnabled even when the action is disabled.
    // Verify the behavior: an empty Save neither submits nor surfaces a write error.
    AXUIElementPerformAction(save, kAXPressAction as CFString)
    Thread.sleep(forTimeInterval: 0.25)
    let after = nodes(app)
    guard after.contains(where: { attribute($0, kAXIdentifierAttribute) as? String == "secretField" }),
          !after.contains(where: { attribute($0, kAXIdentifierAttribute) as? String == "saveError" }) else {
        print("FAIL: empty Save started a submission"); exit(14)
    }
    print("PASS: empty Save does not submit")
    exit(0)
}
// Run after the user or native GUI automation activates another ordinary app.
// A test helper that fails to activate is not evidence about window stacking.
if action == "assert-stays-above" {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let promptIndex = windows.firstIndex { $0[kCGWindowOwnerPID as String] as? Int32 == pid }
    let activeIndex = windows.firstIndex {
        $0[kCGWindowOwnerPID as String] as? Int32 == activePID && $0[kCGWindowLayer as String] as? Int == 0
    }
    guard let activePID, activePID != pid, let promptIndex, let activeIndex, promptIndex < activeIndex else {
        print("FAIL: activate another visible app, then verify Tuck stays above it")
        exit(15)
    }
    print("PASS: Tuck above another active app; window indices \(promptIndex) before \(activeIndex)")
    exit(0)
}
if ["paste-public-fixture", "paste-menu-public-fixture", "paste-context-public-fixture", "copy-public-fixture"].contains(action) {
    guard let control = tree.first(where: { attribute($0, kAXIdentifierAttribute) as? String == "secretField" }) else { exit(3) }
    AXUIElementSetAttributeValue(control, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("PUBLIC NON-CREDENTIAL PASTE FIXTURE 🌈", forType: .string)
    defer { NSPasteboard.general.clearContents() }
    func command(_ key: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)!
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(pid); up.postToPid(pid)
    }
    command(0) // Select all, including the identical-content replacement case.
    Thread.sleep(forTimeInterval: 0.1)
    if action == "copy-public-fixture" {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("PUBLIC COPY SENTINEL", forType: .string)
        command(8)
        Thread.sleep(forTimeInterval: 0.2)
        let copyProtected = NSPasteboard.general.string(forType: .string) == "PUBLIC COPY SENTINEL"
        command(7)
        Thread.sleep(forTimeInterval: 0.2)
        let cutProtected = NSPasteboard.general.string(forType: .string) == "PUBLIC COPY SENTINEL"
        NSPasteboard.general.clearContents()
        print(copyProtected && cutProtected ? "PASS: secure field prevents Copy and Cut" : "FAIL: secure field copied content")
        exit(copyProtected && cutProtected ? 0 : 6)
    } else if action == "paste-context-public-fixture" {
        var point = CGPoint.zero
        guard let position = attribute(control, kAXPositionAttribute),
              AXValueGetValue(position as! AXValue, .cgPoint, &point) else { exit(9) }
        point.x += 20; point.y += 10
        CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)?.postToPid(pid)
        CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)?.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.3)
        guard let paste = nodes(app).last(where: { attribute($0, kAXTitleAttribute) as? String == "Paste" }) else { exit(10) }
        guard AXUIElementPerformAction(paste, kAXPressAction as CFString) == .success else { exit(11) }
    } else if action == "paste-menu-public-fixture" {
        guard let paste = tree.first(where: { attribute($0, kAXTitleAttribute) as? String == "Paste" }) else { exit(7) }
        guard AXUIElementPerformAction(paste, kAXPressAction as CFString) == .success else { exit(8) }
    } else { command(9) }
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if NSPasteboard.general.string(forType: .string) == nil {
            print("PASS: native paste cleared current clipboard")
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    print("FAIL: clipboard was not cleared")
    NSPasteboard.general.clearContents()
    exit(5)
}
if action == "inspect" {
    for node in tree {
        let id = attribute(node, kAXIdentifierAttribute) as? String ?? ""
        if !id.isEmpty { print(id) }
    }
    exit(0)
}
let id = action == "fill-public-fixture" ? "secretField" : (action == "save" ? "saveButton" : "cancelButton")
guard let control = tree.first(where: { attribute($0, kAXIdentifierAttribute) as? String == id }) else { print("Control missing"); exit(3) }
let result: AXError
if action == "fill-public-fixture" {
    // This is public test data, not a real credential.
    result = AXUIElementSetAttributeValue(control, kAXValueAttribute as CFString, "PUBLIC NON-CREDENTIAL UI FIXTURE 🌈" as CFString)
} else {
    result = AXUIElementPerformAction(control, kAXPressAction as CFString)
}
print("UI action status \(result.rawValue)")
exit(result == .success ? 0 : 4)
