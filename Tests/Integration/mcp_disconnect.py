#!/usr/bin/env python3
"""Headless transport regressions; never launches Tuck/AppKit or accesses Keychain.

Run with --build-products pointing to an independently built Xcode Debug products
folder containing the pinned MCP/Logging .o and .swiftmodule dependencies.
--expect-vulnerable preserves the original pre-fix reproductions.
"""
import argparse
import json
import pathlib
import subprocess
import tempfile
import threading
import uuid

HARNESS = r'''
import Foundation
import MCP

@main struct TransportProbe {
    static func mark(_ value: String) {
        FileHandle.standardError.write(Data((value + "\n").utf8))
    }
    static func main() async throws {
        let permit = SavePermit()
        let transport = BoundedStdioTransport(permit: permit)
        if CommandLine.arguments.contains("output") {
            try await transport.connect()
            var input = await transport.receive().makeAsyncIterator()
            _ = try await input.next() // Parent closes stdout reader before this trigger.
            do { try await transport.send(Data("{}".utf8)); mark("SEND_SUCCEEDED") }
            catch { mark("SEND_FAILED") }
            do { try permit.perform { mark("WRITE_ALLOWED") } }
            catch { mark("WRITE_BLOCKED") }
            do { _ = try await input.next(); mark("STREAM_FINISHED") }
            catch { mark("STREAM_FINISHED") }
            await transport.disconnect()
            return
        }
        let server = Server(name: "public-transport-fixture", version: "1", capabilities: .init(tools: .init()))
        await server.withMethodHandler(CallTool.self) { _ in
            mark("HANDLER_STARTED")
            do {
                try await withTaskCancellationHandler {
                    try await Task.sleep(for: .seconds(2))
                } onCancel: { permit.close(); mark("CANCELLED") }
                try permit.perform { mark("WRITE_ALLOWED") }
            } catch { mark("WRITE_BLOCKED") }
            return .init(content: [.text(text: "public-fixture-status", annotations: nil, _meta: nil)])
        }
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
        await server.stop()
        mark("STREAM_FINISHED")
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-products', required=True, type=pathlib.Path)
    parser.add_argument('--expect-vulnerable', action='store_true')
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[2]
    products = args.build_products.resolve()
    with tempfile.TemporaryDirectory(prefix='tuck-public-transport-') as directory:
        folder = pathlib.Path(directory)
        swift = folder / 'Probe.swift'
        swift.write_text(HARNESS)
        binary = folder / 'probe'
        objects = [products / (name + '.o') for name in ['MCP', 'Logging', 'EventSource', 'SystemPackage', 'CSystem']]
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-warnings-as-errors',
                        '-parse-as-library', '-I', str(products),
                        str(root / 'Sources/BoundedStdioTransport.swift'),
                        str(root / 'Sources/SavePermit.swift'), str(swift),
                        *map(str, objects), '-o', str(binary)], check=True)

        def start(mode):
            process = subprocess.Popen([str(binary), mode], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            events = []
            started = threading.Event()
            cancelled = threading.Event()
            finished = threading.Event()
            write = threading.Event()
            def collect():
                for line in process.stderr:
                    event = line.decode().strip()
                    events.append(event)
                    if event == 'HANDLER_STARTED': started.set()
                    if event == 'CANCELLED': cancelled.set()
                    if event == 'STREAM_FINISHED': finished.set()
                    if event in ('WRITE_ALLOWED', 'WRITE_BLOCKED'): write.set()
            thread = threading.Thread(target=collect, daemon=True)
            thread.start()
            return process, events, started, cancelled, finished, write, thread

        def send(process, message):
            process.stdin.write(json.dumps(message).encode() + b'\n')
            process.stdin.flush()

        def cleanup(process, thread):
            if process.poll() is None:
                process.stdin.close()
                try: process.wait(timeout=4)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
            thread.join(timeout=1)
            for stream in (process.stdin, process.stdout, process.stderr):
                if not stream.closed: stream.close()

        fixture = 'public-' + uuid.uuid4().hex
        request = {'jsonrpc': '2.0', 'id': fixture, 'method': 'tools/call',
                   'params': {'name': 'save_credential', 'arguments': {'service': fixture, 'account': fixture}}}
        cancellation = {'jsonrpc': '2.0', 'method': 'notifications/cancelled', 'params': {'requestId': fixture}}
        for batch in (False, True):
            p, events, started, cancelled, finished, write, thread = start('sdk')
            try:
                send(p, [request] if batch else request)
                if batch and not args.expect_vulnerable:
                    assert finished.wait(3), 'Batch did not close the stream'
                    assert not started.is_set(), 'Rejected batch reached the handler'
                else:
                    assert started.wait(3), 'Handler did not start'
                    send(p, cancellation)
                    assert write.wait(4), 'Handler did not complete'
                    if batch:
                        assert 'WRITE_ALLOWED' in events and not cancelled.is_set(), events
                    else:
                        assert cancelled.is_set() and 'WRITE_ALLOWED' not in events, events
                print(('original batch cancellation defect reproduced' if args.expect_vulnerable else 'batch rejected before handler')
                      if batch else 'individual request cancellation passes')
            finally: cleanup(p, thread)

        p, events, started, cancelled, finished, write, thread = start('output')
        try:
            p.stdout.close()  # stdin intentionally remains open throughout assertions.
            send(p, {'public_fixture': fixture})
            assert write.wait(3), 'Output probe did not complete'
            assert 'SEND_FAILED' in events, events
            if args.expect_vulnerable:
                assert 'WRITE_ALLOWED' in events, events
                assert not finished.wait(0.2), 'Original receive stream unexpectedly closed'
                print('original half-open output defect reproduced')
            else:
                assert 'WRITE_BLOCKED' in events, events
                assert finished.wait(3), 'Terminal output failure left receive stream open'
                print('half-open output failure revokes permit and closes stream')
        finally: cleanup(p, thread)


if __name__ == '__main__':
    main()
