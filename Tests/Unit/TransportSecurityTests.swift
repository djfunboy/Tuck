import XCTest
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
}
