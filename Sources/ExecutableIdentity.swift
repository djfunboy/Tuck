import Foundation

/// Identity of the executable file this process was launched from.
///
/// An update (App Store or manual) replaces the app bundle on disk while agent-launched `--mcp`
/// processes keep running the old image. The Security framework then fails its code check for the
/// login Keychain on every write with `errSecCSBadObjectFormat` (-67049), which looks to the person
/// like a locked Keychain. Capture the file identity at launch and compare before each request so the
/// agent can be told to restart instead.
struct ExecutableIdentity: Equatable, Sendable {
    let inode: UInt64
    let modified: Date

    init?(url: URL?) {
        guard let url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        self.inode = inode
        self.modified = modified
    }

    /// True when the file at `url` is still the same file this identity was captured from.
    func isCurrent(at url: URL?) -> Bool { ExecutableIdentity(url: url) == self }

    /// Captured on first access; `TuckMain.main` touches it before anything else runs.
    static let launch = ExecutableIdentity(url: Bundle.main.executableURL)

    /// False once the executable this process runs from has been replaced or removed.
    /// Unknown (no bundle executable, as in unit tests) counts as current.
    static func isProcessCurrent() -> Bool {
        guard let launch else { return true }
        return launch.isCurrent(at: Bundle.main.executableURL)
    }

    /// Security framework code-signing statuses (errSecCS*) occupy -67000 ... -67999.
    static func isCodeSigningFailure(_ status: OSStatus) -> Bool { (-67_999 ... -67_000).contains(status) }
}
