import Foundation
import Darwin
import Logging
import MCP

struct LineFramer: Sendable {
    static let limit = 16_384
    private var pending = Data()

    mutating func append(_ chunk: Data) throws -> [Data] {
        var frames: [Data] = []
        for byte in chunk {
            if byte == 10 {
                // MCP removed JSON-RPC batches in 2025-06-18. The pinned SDK
                // still accepts them and blocks cancellation while awaiting a batch.
                if pending.first(where: { ![UInt8(32), 9, 13].contains($0) }) == 91 {
                    throw PipeError.unsupportedBatch
                }
                if !pending.isEmpty { frames.append(pending) }
                pending = Data()
            } else {
                guard pending.count < Self.limit else { throw PipeError.oversized }
                pending.append(byte)
            }
        }
        return frames
    }
}

enum InitializeCompatibility {
    /// The pinned SDK types `capabilities.experimental` as `[String: String]`, while MCP defines
    /// its values as objects; Codex sends `{"codex/auth-change": {}}` and the SDK rejects the
    /// whole `initialize`. Tuck uses no experimental client capability, so the field is removed.
    static func stripExperimentalCapabilities(_ frame: Data) -> Data {
        guard frame.range(of: Data("experimental".utf8)) != nil,
              var message = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              capabilities.removeValue(forKey: "experimental") != nil else { return frame }
        params["capabilities"] = capabilities
        message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? frame
    }
}

enum PipeError: Error { case oversized, overloaded, unsupportedBatch, disconnected, io }

actor BoundedStdioTransport: Transport {
    // MARK: Connection state
    nonisolated let logger = Logger(label: "tuck.mcp", factory: { _ in SwiftLogNoOpLogHandler() })
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var connected = false
    private var reader: Task<Void, Never>?
    private var framer = LineFramer()
    private let permit: SavePermit
    private let outputQueue = DispatchQueue(label: "ai.outergy.tuck.stdout")

    init(permit: SavePermit = SavePermit()) {
        self.permit = permit
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
        stream = pair.stream
        continuation = pair.continuation
    }

    // MARK: MCP transport
    func connect() async throws {
        guard !connected else { return }
        signal(SIGPIPE, SIG_IGN)
        let flags = fcntl(STDIN_FILENO, F_GETFL)
        guard flags >= 0, fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) >= 0 else { throw PipeError.io }
        connected = true
        reader = Task { await readLoop() }
    }

    func disconnect() async {
        permit.close()
        connected = false
        reader?.cancel()
        reader = nil
        continuation.finish()
    }

    func receive() -> AsyncThrowingStream<Data, Error> { stream }

    func send(_ data: Data) async throws {
        guard connected else { throw PipeError.disconnected }
        var frame = data
        frame.append(10)
        let bytes = frame
        do {
            try await withCheckedThrowingContinuation { (result: CheckedContinuation<Void, Error>) in
                outputQueue.async {
                    var offset = 0
                    while offset < bytes.count {
                        var descriptor = pollfd(fd: STDOUT_FILENO, events: Int16(POLLOUT), revents: 0)
                        guard poll(&descriptor, 1, 1_000) > 0 else { result.resume(throwing: PipeError.io); return }
                        let count = bytes.withUnsafeBytes { buffer in
                            Darwin.write(STDOUT_FILENO, buffer.baseAddress?.advanced(by: offset), bytes.count - offset)
                        }
                        guard count > 0 else { result.resume(throwing: PipeError.io); return }
                        offset += count
                    }
                    result.resume()
                }
            }
        } catch {
            // A half-open pipe is unusable even when stdin has not reached EOF.
            // Revoke future saves and wake the SDK receive loop before returning.
            await disconnect()
            throw error
        }
    }

    // MARK: Bounded input
    private func readLoop() async {
        defer { permit.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while connected && !Task.isCancelled {
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR {
                    do { try await Task.sleep(for: .milliseconds(20)) }
                    catch { break }
                    continue
                }
                continuation.finish(throwing: PipeError.io)
                connected = false
                return
            }
            do {
                for frame in try framer.append(Data(buffer.prefix(count))) {
                    let compatible = InitializeCompatibility.stripExperimentalCapabilities(frame)
                    if case .dropped = continuation.yield(compatible) { throw PipeError.overloaded }
                }
            } catch {
                continuation.finish(throwing: error)
                connected = false
                return
            }
        }
        permit.close()
        connected = false
        continuation.finish()
    }
}
