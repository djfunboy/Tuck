import AppKit

/// Clears only the current pasteboard generation consumed by a successful paste.
/// Clipboard managers may already have retained an independent copy.
@MainActor
enum PasteCleanup {
    @discardableResult
    static func clear(_ pasteboard: NSPasteboard, ifUnchangedSince generation: Int, inserted: Bool) -> Bool {
        guard inserted, pasteboard.changeCount == generation else { return false }
        pasteboard.clearContents()
        return true
    }
}

@MainActor
final class TuckApplication: NSApplication {
    var didPaste: ((NSWindow?, Bool) -> Void)?

    override func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        guard ["paste:", "pasteAsPlainText:"].contains(NSStringFromSelector(action)),
              let editor = keyWindow?.firstResponder as? NSTextView,
              editor.isFieldEditor,
              editor.delegate is NSSecureTextField
        else { return super.sendAction(action, to: target, from: sender) }

        let pasteWindow = editor.window
        let generation = NSPasteboard.general.changeCount
        let observation = PasteObservation()
        let token = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification,
                                                           object: editor, queue: nil) { _ in
            MainActor.assumeIsolated { observation.inserted = true }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let handled = super.sendAction(action, to: target, from: sender)
        // The native secure editor performs insertion first. An unsuccessful paste
        // must not erase the clipboard. No pasted value is sent to the model here.
        let inserted = handled && observation.inserted
        let cleared = PasteCleanup.clear(NSPasteboard.general, ifUnchangedSince: generation,
                                         inserted: inserted)
        if inserted { didPaste?(pasteWindow, cleared) }
        return handled
    }
}

@MainActor
private final class PasteObservation {
    var inserted = false
}
