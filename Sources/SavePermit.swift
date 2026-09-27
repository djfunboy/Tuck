import Foundation

/// Serializes observed disconnect/cancellation with the beginning of a write.
/// A write already in progress may complete; Keychain has no rollback API.
final class SavePermit: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true

    func close() {
        lock.lock()
        defer { lock.unlock() }
        open = false
    }

    func perform<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard open else { throw SavePermitError.closed }
        return try operation()
    }
}

enum SavePermitError: Error { case closed }
