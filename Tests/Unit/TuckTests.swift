import XCTest
import Security
import AppKit
import MCP
@testable import Tuck

@MainActor
final class PackagingTests: XCTestCase {
    func testSetupInstructionsIncludeBundledSkillAndExecutable() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "SKILL", withExtension: "md"))
        let skill = try String(contentsOf: url, encoding: .utf8)
        let instructions = try TuckView.setupRequest()
        XCTAssertTrue(instructions.contains(skill))
        XCTAssertTrue(instructions.contains("/Applications/Tuck.app/Contents/MacOS/Tuck"))
        XCTAssertTrue(skill.hasPrefix("---\nname: tuck\n"))
        XCTAssertTrue(skill.contains("provider_url"))
        XCTAssertTrue(skill.contains("Never invent"))
        XCTAssertTrue(skill.contains("restart_required"))
        XCTAssertTrue(skill.contains("https://tuckaway.dev/skill/SKILL.md"))
        XCTAssertTrue(skill.contains("MCP server named `keydrop`"))
        XCTAssertTrue(skill.contains("/Applications/Tuck.app/Contents/MacOS/Tuck --mcp"))
        XCTAssertTrue(instructions.contains("https://tuckaway.dev/skill/SKILL.md"))
        XCTAssertTrue(instructions.contains("/Applications/Keydrop.app"))
        XCTAssertTrue(instructions.contains("https://tuckaway.dev/setup/SETUP.md"))
        XCTAssertTrue(instructions.contains("user or global level"))
        XCTAssertFalse(instructions.contains("Claude"))
        XCTAssertFalse(instructions.contains("identical"))
        XCTAssertTrue(TuckView.configuration.contains("\"tuck\""))
        XCTAssertTrue(TuckView.configuration.contains("/Applications/Tuck.app/Contents/MacOS/Tuck"))
    }
    func testMissingSkillSurfacesSetupFailure() {
        XCTAssertThrowsError(try TuckView.setupRequest(bundle: Bundle(for: Self.self)))
    }
    func testAppStoreIconIncludes1024PixelRepresentation() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Tuck", withExtension: "icns"))
        let icon = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertTrue(icon.representations.contains { $0.pixelsWide == 1024 && $0.pixelsHigh == 1024 })
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, "Tuck")
    }
}

@MainActor
final class PasteCleanupTests: XCTestCase {
    func testSuccessfulPasteClearsCurrentContents() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("PUBLIC FIXTURE", forType: .string)
        XCTAssertTrue(PasteCleanup.clear(board, ifUnchangedSince: board.changeCount, inserted: true))
        XCTAssertNil(board.string(forType: .string))
    }
    func testFailedPasteAndNewCopyArePreserved() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("PUBLIC FIXTURE", forType: .string)
        let generation = board.changeCount
        XCTAssertFalse(PasteCleanup.clear(board, ifUnchangedSince: generation, inserted: false))
        board.clearContents()
        board.setString("NEW PUBLIC COPY", forType: .string)
        XCTAssertFalse(PasteCleanup.clear(board, ifUnchangedSince: generation, inserted: true))
        XCTAssertEqual(board.string(forType: .string), "NEW PUBLIC COPY")
    }
}

final class DestinationTests: XCTestCase {
    func testExactDestinationAndUnicode() throws {
        let r = try CredentialRequest(service: "sentry-token", account: "chris")
        XCTAssertEqual(r.service, "sentry-token")
        XCTAssertNoThrow(try CredentialRequest(service: "虹", account: "☁️"))
    }
    func testInvalidDestinations() {
        for value in ["", " x", "x ", "a\nb", "a\0b", "a\u{202E}b", String(repeating: "x", count: 201)] {
            XCTAssertThrowsError(try CredentialRequest(service: value, account: "fixture"))
            XCTAssertThrowsError(try CredentialRequest(service: "fixture", account: value))
        }
    }
    func testOptionalProviderLinkAcceptsOnlySafePathBasedHTTPSURLs() throws {
        let rawURL = "https://platform.openai.com/api-keys"
        let arguments: [String: Value] = [
            "service": .string("fixture"),
            "account": .string("fixture"),
            "provider_url": .string(rawURL)
        ]
        let request = try MCPRequestValidator.destination(name: "save_credential", arguments: arguments)
        XCTAssertEqual(request.providerLink?.url.absoluteString, rawURL)
        XCTAssertEqual(request.providerLink?.displayHost, "platform.openai.com")

        for value in [
            "http://example.com/keys",
            "file:///tmp/fixture",
            "javascript:alert(1)",
            "https://user:password@example.com/keys",
            "https://example.com/keys?token=PUBLIC-FIXTURE",
            "https://example.com/keys#PUBLIC-FIXTURE",
            " https://example.com/keys",
            "https://example.com/keys\u{202E}",
            "https://203.0.113.5/keys",
            "https://[2001:db8::1]/keys",
            "https://[::ffff:203.0.113.5]/keys",
            "https://localhost/keys",
            "https://tuck.local/keys",
            "https://localhost./keys",
            "https://tuck.local./keys",
            "https://good.example@evil.example/keys",
            "https://example.com/keys?",
            "https://example.com/keys#",
            "",
            "https://xn--e1afmkfd.xn--p1ai/keys",
            String(repeating: "x", count: 2_049)
        ] {
            var invalid = arguments
            invalid["provider_url"] = .string(value)
            XCTAssertThrowsError(try MCPRequestValidator.destination(name: "save_credential", arguments: invalid), value)
        }
    }
    func testRejectsCredentialAndUnknownFields() throws {
        let good: [String: Value] = ["service": .string("fixture"), "account": .string("fixture")]
        XCTAssertNoThrow(try MCPRequestValidator.destination(name: "save_credential", arguments: good))
        for name in ["password", "token", "value", "extra"] {
            var args = good; args[name] = .string("PUBLIC TEST FIXTURE")
            XCTAssertThrowsError(try MCPRequestValidator.destination(name: "save_credential", arguments: args))
        }
        var wrongURLType = good
        wrongURLType["provider_url"] = .int(1)
        XCTAssertThrowsError(try MCPRequestValidator.destination(name: "save_credential", arguments: wrongURLType))
        XCTAssertThrowsError(try MCPRequestValidator.destination(name: "get_credential", arguments: good))
        XCTAssertThrowsError(try MCPRequestValidator.destination(name: "save_credential", arguments: nil))
    }
}

final class FramerTests: XCTestCase {
    func testFragmentedAndMultipleFrames() throws {
        var f = LineFramer()
        XCTAssertEqual(try f.append(Data("{\"a\":".utf8)), [])
        XCTAssertEqual(try f.append(Data("1}\n{}\n\n".utf8)), [Data("{\"a\":1}".utf8), Data("{}".utf8)])
    }
    func testExactLimitAndOverLimit() throws {
        var f = LineFramer()
        XCTAssertEqual(try f.append(Data(repeating: 65, count: LineFramer.limit)), [])
        XCTAssertEqual(try f.append(Data([10])).first?.count, LineFramer.limit)
        XCTAssertThrowsError(try f.append(Data(repeating: 65, count: LineFramer.limit + 1)))
    }
}

final class RealKeychainTests: XCTestCase {
    func testCreateDuplicateReplaceAndDelete() throws {
        let r = try CredentialRequest(service: "ai.outergy.tuck.test.\(UUID().uuidString)", account: "public-test-fixture")
        let writer = KeychainWriter()
        let first = Data("PUBLIC NON-CREDENTIAL FIXTURE 🌈".utf8)
        let second = Data("PUBLIC REPLACEMENT FIXTURE".utf8)
        defer { XCTAssertEqual(SecItemDelete(KeychainWriter.query(for: r) as CFDictionary), errSecSuccess) }
        try writer.save(first, for: r, replace: false)
        XCTAssertThrowsError(try writer.save(second, for: r, replace: false)) { XCTAssertEqual($0 as? KeychainError, .duplicate) }
        var q = KeychainWriter.query(for: r)
        q[kSecReturnData as String] = true
        var output: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(q as CFDictionary, &output), errSecSuccess)
        XCTAssertEqual(output as? Data, first)
        try writer.save(second, for: r, replace: true)
        XCTAssertEqual(SecItemCopyMatching(q as CFDictionary, &output), errSecSuccess)
        XCTAssertEqual(output as? Data, second)
    }
    /// Terminals cut long pastes short (tty canonical mode stops at 1,024 bytes). Keychain must not.
    func testLongValueRoundTripsWithoutTruncation() throws {
        let r = try CredentialRequest(service: "ai.outergy.tuck.test.\(UUID().uuidString)", account: "public-test-fixture")
        let long = Data(String(repeating: "PUBLIC-FIXTURE-", count: 667).prefix(10_000).utf8)
        XCTAssertEqual(long.count, 10_000)
        defer { XCTAssertEqual(SecItemDelete(KeychainWriter.query(for: r) as CFDictionary), errSecSuccess) }
        try KeychainWriter().save(long, for: r, replace: false)
        var q = KeychainWriter.query(for: r)
        q[kSecReturnData as String] = true
        var output: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(q as CFDictionary, &output), errSecSuccess)
        XCTAssertEqual((output as? Data)?.count, 10_000)
        XCTAssertEqual(output as? Data, long)
    }
    func testEmptyAndOversizedValuesDoNotWrite() throws {
        let r = try CredentialRequest(service: "ai.outergy.tuck.test.\(UUID().uuidString)", account: "fixture")
        XCTAssertThrowsError(try KeychainWriter().save(Data(), for: r, replace: false))
        XCTAssertThrowsError(try KeychainWriter().save(Data(repeating: 65, count: 65_537), for: r, replace: false))
        XCTAssertEqual(SecItemCopyMatching(KeychainWriter.query(for: r) as CFDictionary, nil), errSecItemNotFound)
    }
}

private struct RejectingWriter: CredentialWriting {
    let error: KeychainError
    func save(_ value: Data, for request: CredentialRequest, replace: Bool) throws { throw error }
}

private struct SuccessfulFixtureWriter: CredentialWriting {
    func save(_ value: Data, for request: CredentialRequest, replace: Bool) throws {}
}

private struct ExpectedFixtureWriter: CredentialWriting {
    let expected: Data
    func save(_ value: Data, for request: CredentialRequest, replace: Bool) throws {
        XCTAssertEqual(value, expected)
    }
}

@MainActor
final class PromptTests: XCTestCase {
    private func destination() throws -> CredentialRequest { try .init(service: "fixture", account: "fixture") }
    func testTypedOnlySaveKeepsCharacterCountPathAndValue() async throws {
        let value = "PUBLIC TEST FIXTURE"
        let model = PromptModel(writer: ExpectedFixtureWriter(expected: Data(value.utf8)))
        let request = try destination()
        let task = Task { await model.prompt(request) }
        while model.request == nil { await Task.yield() }
        XCTAssertFalse(model.clipboardCleared)
        model.save(value)
        let outcome = await task.value
        XCTAssertEqual(outcome, .saved)
        XCTAssertFalse(model.clipboardCleared, "typed-only confirmation keeps the all N characters path")
    }
    func testLatestInsertionCleanupControlsSavedConfirmation() async throws {
        let model = PromptModel(writer: SuccessfulFixtureWriter())
        let request = try destination()
        let task = Task { await model.prompt(request) }
        while model.request == nil { await Task.yield() }
        model.recordPasteCleanup(cleared: true)
        XCTAssertTrue(model.clipboardCleared)
        model.recordPasteCleanup(cleared: false)
        XCTAssertFalse(model.clipboardCleared, "the latest insertion wins")
        model.recordPasteCleanup(cleared: true)
        model.save("PUBLIC TEST FIXTURE")
        let outcome = await task.value
        XCTAssertEqual(outcome, .saved)
        XCTAssertTrue(model.clipboardCleared, "confirmed cleanup survives through save")
    }
    func testNewRequestResetsClipboardCleanupAndInactiveReportsAreIgnored() async throws {
        let model = PromptModel(writer: SuccessfulFixtureWriter())
        model.recordPasteCleanup(cleared: true)
        XCTAssertFalse(model.clipboardCleared)
        let request = try destination()
        let first = Task { await model.prompt(request) }
        while model.request == nil { await Task.yield() }
        model.recordPasteCleanup(cleared: true)
        model.save("PUBLIC TEST FIXTURE")
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .saved)
        model.recordPasteCleanup(cleared: false)
        XCTAssertTrue(model.clipboardCleared, "inactive reports cannot change the saved confirmation")
        let second = Task { await model.prompt(request) }
        while model.request == nil { await Task.yield() }
        XCTAssertFalse(model.clipboardCleared)
        model.cancel()
        let secondOutcome = await second.value
        XCTAssertEqual(secondOutcome, .cancelled)
    }
    func testSavedReturnsBeforeWindowAutomaticallyHides() async throws {
        let model = PromptModel(writer: SuccessfulFixtureWriter(), successDisplayDuration: .milliseconds(100))
        let hidden = expectation(description: "Success feedback dismisses without another click")
        var didHide = false
        var didClear = false
        model.hideWindow = { didHide = true; hidden.fulfill() }
        let destination = try destination()
        let task = Task { await model.prompt(destination) }
        while model.request == nil { await Task.yield() }
        model.clearField = { didClear = true }
        model.save("PUBLIC TEST FIXTURE")
        let result = await task.value
        XCTAssertEqual(result, .saved)
        XCTAssertTrue(didClear)
        XCTAssertFalse(didHide)
        XCTAssertNil(model.request)
        await fulfillment(of: [hidden], timeout: 2)
    }
    func testNewRequestCannotBeHiddenByPreviousSuccess() async throws {
        let model = PromptModel(writer: SuccessfulFixtureWriter(), successDisplayDuration: .milliseconds(50))
        var hides = 0
        model.hideWindow = { hides += 1 }
        let destination = try destination()
        let first = Task { await model.prompt(destination) }
        while model.request == nil { await Task.yield() }
        let firstID = model.presentationID
        model.save("PUBLIC TEST FIXTURE")
        _ = await first.value
        let second = Task { await model.prompt(destination) }
        while model.request == nil { await Task.yield() }
        XCTAssertNotEqual(firstID, model.presentationID)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(hides, 0)
        XCTAssertEqual(model.request, destination)
        model.cancel()
        _ = await second.value
        XCTAssertEqual(hides, 1)
    }
    func testTimeoutHidesWithoutConfirmation() async throws {
        let model = PromptModel()
        var hides = 0
        model.hideWindow = { hides += 1 }
        let result = await model.prompt(try destination(), timeout: .milliseconds(10))
        XCTAssertEqual(result, .timedOut)
        XCTAssertEqual(hides, 1)
    }
    func testCancelAndBusy() async throws {
        let m = PromptModel()
        let d = try destination()
        let task = Task { await m.prompt(d) }
        while m.request == nil { await Task.yield() }
        let busy = await m.prompt(d)
        XCTAssertEqual(busy, .busy)
        m.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertNil(m.request)
    }
    func testTimeoutClearsField() async throws {
        let m = PromptModel()
        var cleared = 0
        m.clearField = { cleared += 1 }
        let outcome = await m.prompt(try destination(), timeout: .milliseconds(10))
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertNil(m.request)
        XCTAssertGreaterThan(cleared, 0)
    }
    func testTaskCancellationClosesPrompt() async throws {
        let m = PromptModel(); let d = try destination()
        let task = Task { await m.prompt(d) }
        while m.request == nil { await Task.yield() }
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertNil(m.request)
    }
    func testReplacedExecutableReturnsRestartRequiredWithoutPopup() async throws {
        let m = PromptModel(writer: SuccessfulFixtureWriter(), executableIsCurrent: { false })
        var shown = 0
        m.showWindow = { shown += 1 }
        let outcome = await m.prompt(try destination())
        XCTAssertEqual(outcome, .restartRequired)
        XCTAssertEqual(outcome.rawValue, "restart_required")
        XCTAssertEqual(shown, 0)
        XCTAssertNil(m.request)
    }
    func testCodeSigningFailureOnSaveExplainsRestart() async throws {
        // -67049 errSecCSBadObjectFormat: the on-disk executable no longer matches the running process.
        let m = PromptModel(writer: RejectingWriter(error: .unavailable(-67049)))
        let d = try destination(); let task = Task { await m.prompt(d) }
        while m.request == nil { await Task.yield() }
        m.save("PUBLIC TEST FIXTURE")
        XCTAssertEqual(m.errorMessage, PromptModel.restartMessage + " (-67049)")
        XCTAssertTrue(m.errorMessage?.contains("Restart the agent") == true)
        XCTAssertFalse(m.errorMessage?.contains("Unlock") == true)
        // The person sees the message; cancelling then tells the agent the same thing.
        m.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .restartRequired)
    }
    func testOrdinaryKeychainFailureStillCancels() async throws {
        let m = PromptModel(writer: RejectingWriter(error: .unavailable(errSecAuthFailed)))
        let d = try destination(); let task = Task { await m.prompt(d) }
        while m.request == nil { await Task.yield() }
        m.save("PUBLIC TEST FIXTURE")
        XCTAssertTrue(m.errorMessage?.contains("Unlock") == true)
        m.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }
    func testErrorRemainsVisibleWithoutCompleting() async throws {
        let m = PromptModel(writer: RejectingWriter(error: .unavailable(errSecAuthFailed)))
        let d = try destination(); let task = Task { await m.prompt(d) }
        while m.request == nil { await Task.yield() }
        m.save("PUBLIC TEST FIXTURE")
        XCTAssertNotNil(m.errorMessage)
        XCTAssertNotNil(m.request)
        m.cancel()
        _ = await task.value
    }
}

@MainActor
final class DisconnectTests: XCTestCase {
    func testObservedDisconnectPreventsWrite() async throws {
        let model = PromptModel()
        let permit = SavePermit()
        model.setConnectionPermit(permit)
        let r = try CredentialRequest(service: "ai.outergy.tuck.test.\(UUID().uuidString)", account: "fixture")
        let task = Task { await model.prompt(r) }
        while model.request == nil { await Task.yield() }
        permit.close()
        model.save("PUBLIC TEST FIXTURE")
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(SecItemCopyMatching(KeychainWriter.query(for: r) as CFDictionary, nil), errSecItemNotFound)
    }
    func testClosedPermitDoesNotRunOperation() {
        let permit = SavePermit()
        permit.close()
        var ran = false
        XCTAssertThrowsError(try permit.perform { ran = true })
        XCTAssertFalse(ran)
    }
}


final class ExecutableIdentityTests: XCTestCase {
    private func temporaryFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tuck-exe-\(UUID().uuidString)")
        try Data(contents.utf8).write(to: url)
        return url
    }
    func testUntouchedFileIsCurrent() throws {
        let url = try temporaryFile("build 5")
        defer { try? FileManager.default.removeItem(at: url) }
        let identity = try XCTUnwrap(ExecutableIdentity(url: url))
        XCTAssertTrue(identity.isCurrent(at: url))
    }
    func testOverwrittenInPlaceIsNotCurrent() throws {
        let url = try temporaryFile("build 5")
        defer { try? FileManager.default.removeItem(at: url) }
        let identity = try XCTUnwrap(ExecutableIdentity(url: url))
        // Same inode, new contents: only the modification date can tell.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: url.path)
        XCTAssertFalse(identity.isCurrent(at: url))
    }
    func testReplacedFileIsNotCurrent() throws {
        let url = try temporaryFile("build 5")
        defer { try? FileManager.default.removeItem(at: url) }
        let identity = try XCTUnwrap(ExecutableIdentity(url: url))
        // An update removes the bundle and writes a new one: a new inode at the same path.
        try FileManager.default.removeItem(at: url)
        try Data("build 6".utf8).write(to: url)
        XCTAssertFalse(identity.isCurrent(at: url))
    }
    func testDeletedFileIsNotCurrent() throws {
        let url = try temporaryFile("build 5")
        let identity = try XCTUnwrap(ExecutableIdentity(url: url))
        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(identity.isCurrent(at: url))
        XCTAssertNil(ExecutableIdentity(url: url))
        XCTAssertNil(ExecutableIdentity(url: nil))
    }
    func testCodeSigningStatusRange() {
        XCTAssertTrue(ExecutableIdentity.isCodeSigningFailure(-67049))
        XCTAssertTrue(ExecutableIdentity.isCodeSigningFailure(-67061))
        XCTAssertFalse(ExecutableIdentity.isCodeSigningFailure(errSecAuthFailed))
        XCTAssertFalse(ExecutableIdentity.isCodeSigningFailure(errSecInteractionNotAllowed))
        XCTAssertFalse(ExecutableIdentity.isCodeSigningFailure(errSecSuccess))
    }
}


final class ReopenPolicyTests: XCTestCase {
    func testStandaloneAlwaysShowsItsWindow() {
        XCTAssertEqual(ReopenPolicy.action(isMCP: false, hasPendingRequest: false), .showWindow)
        XCTAssertEqual(ReopenPolicy.action(isMCP: false, hasPendingRequest: true), .showWindow)
    }
    func testAgentProcessWithoutRequestLaunchesStandaloneInstead() {
        // The 2026-09-18 bug: reopen reached an agent's --mcp process and showed an empty credential panel.
        XCTAssertEqual(ReopenPolicy.action(isMCP: true, hasPendingRequest: false), .launchStandalone)
    }
    func testAgentProcessWithRequestBringsPopupForward() {
        XCTAssertEqual(ReopenPolicy.action(isMCP: true, hasPendingRequest: true), .showWindow)
    }
}
