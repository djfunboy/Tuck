#!/usr/bin/env python3
"""Exercise the actual signed native executable. No real credentials are used."""
import json, os, select, subprocess, sys, time

class Client:
    def __init__(self, executable):
        self.process = subprocess.Popen([executable, '--mcp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.counter = 0
    def send(self, method, params=None, notify=False):
        message = {'jsonrpc':'2.0','method':method}
        if params is not None: message['params'] = params
        if not notify:
            self.counter += 1; message['id'] = self.counter
        self.process.stdin.write(json.dumps(message).encode()+b'\n'); self.process.stdin.flush()
        return message.get('id')
    def receive(self, timeout=10):
        ready,_,_ = select.select([self.process.stdout],[],[],timeout)
        assert ready, 'Timed out waiting for MCP response'
        line = self.process.stdout.readline()
        assert line, 'MCP process ended unexpectedly'
        return json.loads(line)
    def initialize(self):
        self.send('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'Tuck public-fixture test','version':'1.0'}})
        result = self.receive()
        assert result['result']['serverInfo']['name'] == 'tuck'
        self.send('notifications/initialized', notify=True)
    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        assert self.process.returncode == 0, 'Process did not shut down cleanly'

if __name__ == '__main__':
    executable = sys.argv[1]
    client = Client(executable)
    try:
        client.initialize()
        client.send('tools/list')
        tools = client.receive()['result']['tools']
        assert [t['name'] for t in tools] == ['save_credential']
        assert tools[0]['inputSchema']['additionalProperties'] is False
        schema = tools[0]['inputSchema']
        assert set(schema['required']) == {'service', 'account'}
        assert 'provider_url' in schema['properties']
        assert schema['properties']['provider_url']['format'] == 'uri'
        assert 'restart_required' in tools[0]['description']
        client.send('tools/call',{'name':'save_credential','arguments':{'service':'fixture','account':'fixture','provider_url':'https://example.com/keys?token=PUBLIC-REJECTED-FIXTURE'}})
        invalid_url = client.receive()
        assert invalid_url['result']['isError'] is True
        assert 'PUBLIC-REJECTED-FIXTURE' not in json.dumps(invalid_url)
        client.send('tools/call',{'name':'save_credential','arguments':{'service':'fixture','account':'fixture','password':'PUBLIC REJECTED FIXTURE'}})
        rejection = client.receive()
        assert rejection['result']['isError'] is True
        assert 'PUBLIC REJECTED FIXTURE' not in json.dumps(rejection)
        client.send('tools/call',{'name':'get_credential','arguments':{'service':'fixture','account':'fixture'}})
        assert client.receive()['result']['isError'] is True
        client.send('ping')
        assert 'result' in client.receive()
        client.close()
        print('PASS: initialize, discovery, strict arguments, no read tool, ping, EOF exit')
    finally:
        if client.process.poll() is None: client.process.kill()
    codex = Client(executable)
    try:
        codex.send('initialize',{'protocolVersion':'2025-06-18','capabilities':{'elicitation':{},'experimental':{'codex/auth-change':{}}},'clientInfo':{'name':'codex-mcp-client','version':'0.0.0'}})
        reply = codex.receive()
        assert 'error' not in reply, 'Codex initialize rejected: %s' % reply.get('error')
        assert reply['result']['serverInfo']['name'] == 'tuck'
        codex.send('notifications/initialized', notify=True)
        codex.send('tools/list')
        assert [t['name'] for t in codex.receive()['result']['tools']] == ['save_credential']
        codex.close()
        print('PASS: Codex initialize with experimental capabilities, discovery')
    finally:
        if codex.process.poll() is None: codex.process.kill()
    oversized = Client(executable)
    try:
        oversized.process.stdin.write(b'x'*16385+b'\n'); oversized.process.stdin.flush()
        oversized.process.wait(timeout=10)
        assert oversized.process.returncode == 0
        print('PASS: oversized input closes session')
    finally:
        if oversized.process.poll() is None: oversized.process.kill()
