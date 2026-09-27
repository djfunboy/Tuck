import AppKit
import SwiftUI

@MainActor
final class PromptModel: ObservableObject {
    // MARK: State
    @Published private(set) var request: CredentialRequest?
    @Published private(set) var errorMessage: String?
    @Published private(set) var requiresReplacement = false
    @Published private(set) var lastOutcome: SaveOutcome?
    @Published private(set) var isSaving = false
    @Published private(set) var clipboardCleared = false
    private var restartRequiredOnCancel = false
    @Published private(set) var presentationID = UUID()
    private let writer: any CredentialWriting
    private let successDisplayDuration: Duration
    private let executableIsCurrent: @Sendable () -> Bool
    private var continuation: CheckedContinuation<SaveOutcome, Never>?
    private var expiryTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?
    private var pendingID: UUID?
    private var requestPermit: SavePermit?
    private var connectionPermit: SavePermit?
    var showWindow: (() -> Void)?
    var hideWindow: (() -> Void)?
    var clearField: (() -> Void)?

    init(writer: any CredentialWriting = KeychainWriter(),
         successDisplayDuration: Duration = .seconds(2),
         executableIsCurrent: @escaping @Sendable () -> Bool = ExecutableIdentity.isProcessCurrent) {
        self.writer = writer
        self.successDisplayDuration = successDisplayDuration
        self.executableIsCurrent = executableIsCurrent
    }

    static let restartMessage = String(localized: "Tuck was updated while your agent was running, so this copy can no longer write to Apple Keychain. Restart the agent (it relaunches Tuck) and try again.")

    // MARK: Request lifecycle
    func prompt(_ destination: CredentialRequest, timeout: Duration = .seconds(300)) async -> SaveOutcome {
        guard request == nil else { return .busy }
        guard !Task.isCancelled else { return .cancelled }
        // A replaced bundle cannot pass the Keychain code check; do not open a popup that cannot save.
        guard executableIsCurrent() else { return .restartRequired }
        let id = UUID()
        let permit = SavePermit()
        requestPermit = permit
        pendingID = id
        return await withTaskCancellationHandler {
            await withCheckedContinuation { result in
                continuation = result
                start(destination)
                expiryTask = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    guard let self, self.pendingID == id else { return }
                    self.finish(.timedOut)
                }
            }
        } onCancel: {
            permit.close()
            Task { @MainActor [weak self] in
                guard let self, self.pendingID == id else { return }
                self.finish(.cancelled)
            }
        }
    }

    private func start(_ destination: CredentialRequest) {
        dismissalTask?.cancel()
        dismissalTask = nil
        presentationID = UUID()
        request = destination
        requiresReplacement = false
        errorMessage = nil
        lastOutcome = nil
        clipboardCleared = false
        restartRequiredOnCancel = false
        clearField?()
        showWindow?()
    }

    func save(_ value: String, replace: Bool = false) {
        guard let request, !isSaving else { return }
        // Never retain the value in this observable model or any result object.
        isSaving = true
        defer { isSaving = false }
        var data = Data(value.utf8)
        defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
        do {
            let write = { try self.writer.save(data, for: request, replace: replace && self.requiresReplacement) }
            guard let requestPermit else { throw SavePermitError.closed }
            try requestPermit.perform {
                if let connectionPermit { try connectionPermit.perform(write) }
                else { try write() }
            }
            finish(.saved)
        } catch SavePermitError.closed {
            finish(.cancelled)
        } catch KeychainError.duplicate {
            requiresReplacement = true
            errorMessage = String(localized: "This destination already has a credential. Replace it only if you intend to change the value used by its tools.")
        } catch KeychainError.emptyValue {
            errorMessage = String(localized: "Enter a value before saving.")
        } catch KeychainError.valueTooLarge {
            errorMessage = String(localized: "This value is too long. The limit is 64 KB.")
        } catch KeychainError.unavailable(let status) {
            if ExecutableIdentity.isCodeSigningFailure(status) || !executableIsCurrent() {
                errorMessage = Self.restartMessage + " (\(status))"
                restartRequiredOnCancel = true
            } else {
                errorMessage = String(localized: "Apple Keychain couldn’t save this value. Unlock your login Keychain and try again.") + " (\(status))"
            }
        } catch {
            errorMessage = String(localized: "The value wasn’t saved. Please try again.")
        }
    }

    /// Only a successful native insertion reports here; the value never enters this model.
    func recordPasteCleanup(cleared: Bool) {
        guard request != nil else { return }
        clipboardCleared = cleared
    }

    func setConnectionPermit(_ permit: SavePermit) { connectionPermit = permit }

    func resetOutcome() { lastOutcome = nil }

    func cancel() { finish(restartRequiredOnCancel ? .restartRequired : .cancelled) }

    func finish(_ outcome: SaveOutcome) {
        guard request != nil else { return }
        requestPermit?.close()
        requestPermit = nil
        expiryTask?.cancel()
        expiryTask = nil
        pendingID = nil
        clearField?()
        request = nil
        errorMessage = nil
        requiresReplacement = false
        lastOutcome = outcome
        let result = continuation
        continuation = nil
        result?.resume(returning: outcome)
        // Completion is already returned to MCP. Only the visual feedback waits.
        if outcome == .saved, hideWindow != nil {
            let id = presentationID
            dismissalTask = Task { [weak self, successDisplayDuration] in
                do { try await Task.sleep(for: successDisplayDuration) }
                catch { return }
                guard let self, self.presentationID == id, self.request == nil else { return }
                self.hideWindow?()
            }
        } else {
            hideWindow?()
        }
    }
}
