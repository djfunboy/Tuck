import XCTest
import MCP
@testable import Tuck

final class TransportSecurityTests: XCTestCase {
    func testRejectsBatchesIncludingWhitespaceAndFragmentedInput() throws {
        for batch in ["[]\n", " \t\r[{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":1}]\n"] {
            var framer = LineFramer()
            let data = Data(batch.utf8)
            XCTAssertEqual(try framer.append(Data(data.dropLast())), [])
            XCTAssertThrowsError(try framer.append(Data(data.suffix(1)))) { error in
                guard case PipeError.unsupportedBatch = error else {
                    return XCTFail("Expected unsupportedBatch, received \(error)")
                }
            }
        }
    }

    func testIndividualMessagesMayContainArrays() throws {
        let message = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"public_fixture\":[1,2]}}"
        var framer = LineFramer()
        XCTAssertEqual(try framer.append(Data((message + "\n").utf8)), [Data(message.utf8)])
    }

    // MARK: Initialize compatibility
    func testCodexInitializeLosesOnlyExperimentalCapabilities() throws {
        let codex = #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"elicitation":{},"experimental":{"codex/auth-change":{}}},"clientInfo":{"name":"codex-mcp-client","version":"0.0.0"}}}"#
        let adapted = InitializeCompatibility.stripExperimentalCapabilities(Data(codex.utf8))
        let message = try XCTUnwrap(JSONSerialization.jsonObject(with: adapted) as? [String: Any])
        let params = try XCTUnwrap(message["params"] as? [String: Any])
        let capabilities = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertNil(capabilities["experimental"])
        XCTAssertNotNil(capabilities["elicitation"])
        XCTAssertEqual(message["id"] as? Int, 0)
        XCTAssertEqual(params["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((params["clientInfo"] as? [String: Any])?["name"] as? String, "codex-mcp-client")
        XCTAssertNoThrow(try JSONDecoder().decode(Request<Initialize>.self, from: adapted))
    }

    func testOtherFramesPassThroughByteForByte() {
        let frames = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"fixture","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"save_credential","arguments":{"service":"experimental","account":"fixture"}}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"initialize","params":{"capabilities":{"experimental":"#
        ]
        for frame in frames {
            XCTAssertEqual(InitializeCompatibility.stripExperimentalCapabilities(Data(frame.utf8)), Data(frame.utf8))
        }
    }
}
