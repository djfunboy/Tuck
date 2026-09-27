#!/usr/bin/env python3
"""Real MCP + native UI tests using only explicitly public synthetic fixtures."""
import json, pathlib, subprocess, sys, time, uuid
from mcp_protocol import Client

executable, driver = sys.argv[1:3]
base = 'ai.outergy.tuck.ui-test.' + str(uuid.uuid4())
account = 'public-test-fixture'
services = [base, base+'.cancel', base+'.disconnect', base+'.sdk-cancel']

def controls(client):
    return subprocess.run([driver,str(client.process.pid),'inspect'],capture_output=True,text=True,check=True).stdout.splitlines()

def wait_control(client, name, present=True):
    until = time.monotonic()+8
    while time.monotonic()<until:
        if (name in controls(client)) == present: return
        time.sleep(.05)
    raise AssertionError('Native UI control state did not arrive: '+name)

def action(client, name):
    result = subprocess.run([driver,str(client.process.pid),name],capture_output=True)
    assert result.returncode == 0, result.stdout.decode()

def ask(client, service, provider_url=None):
    arguments = {'service':service,'account':account}
    if provider_url is not None: arguments['provider_url'] = provider_url
    request_id = client.send('tools/call',{'name':'save_credential','arguments':arguments})
    wait_control(client,'secretField')
    return request_id

def saved(client, request_id):
    response = client.receive()
    assert response['id']==request_id
    assert response['result']['structuredContent']=={'status':'saved'}
    assert response['result']['content']==[{'type':'text','text':'saved'}]

def exists(service):
    return subprocess.run(['security','find-generic-password','-s',service,'-a',account],capture_output=True).returncode==0

c=Client(executable)
try:
    c.initialize()
    request_id=ask(c,base,'https://example.com/account/keys')
    wait_control(c,'providerLink')
    action(c,'assert-compact-frontmost')
    action(c,'assert-right-edge')
    action(c,'assert-empty-save-inert')
    # Cross-application stacking is verified separately using an actual app activation.
    action(c,'paste-public-fixture')
    action(c,'paste-menu-public-fixture')
    action(c,'paste-context-public-fixture')
    action(c,'copy-public-fixture')
    action(c,'save');saved(c,request_id)
    assert exists(base)
    wait_control(c,'saveConfirmation')
    action(c,'assert-confirmation-cleared')
    print('PASS: actual native secure entry → Keychain → status-only MCP response',flush=True)
    request_id=ask(c,base)
    action(c,'assert-empty-save-inert')
    time.sleep(2.6)
    action(c,'assert-compact-frontmost')
    wait_control(c,'characterCount',False)
    action(c,'fill-public-fixture')
    wait_control(c,'characterCount')
    action(c,'save')
    wait_control(c,'saveError')
    action(c,'save');saved(c,request_id)
    wait_control(c,'saveConfirmation')
    action(c,'assert-confirmation-typed')
    time.sleep(2.6)
    action(c,'assert-hidden')
    print('PASS: duplicate requires a second explicit Replace action',flush=True)
    request_id=ask(c,base+'.cancel')
    busy_id=c.send('tools/call',{'name':'save_credential','arguments':{'service':base+'.busy','account':account}})
    busy=c.receive();assert busy['id']==busy_id and busy['result']['structuredContent']['status']=='busy'
    action(c,'cancel')
    response=c.receive();assert response['id']==request_id and response['result']['structuredContent']['status']=='cancelled'
    action(c,'assert-hidden')
    assert not exists(base+'.cancel')
    print('PASS: simultaneous request is busy; Cancel saves nothing',flush=True)
    request_id=ask(c,base+'.sdk-cancel')
    c.send('notifications/cancelled',{'requestId':request_id,'reason':'Public-fixture integration test'},notify=True)
    wait_control(c,'secretField',False)
    assert not exists(base+'.sdk-cancel')
    print('PASS: MCP client cancellation closes the native entry form',flush=True)
    c.close()
finally:
    if c.process.poll() is None:c.process.kill()
    # Remove this run's fixture even if an assertion above fails.
    if exists(base):
        subprocess.run(['security','delete-generic-password','-s',base,'-a',account],capture_output=True,check=True)

c=Client(executable)
try:
    c.initialize();ask(c,base+'.disconnect');c.close()
    assert not exists(base+'.disconnect')
    print('PASS: stdin EOF closes the app and saves nothing',flush=True)
finally:
    if c.process.poll() is None:c.process.kill()
    for service in services:
        if exists(service):
            r=subprocess.run(['security','delete-generic-password','-s',service,'-a',account],capture_output=True)
            assert r.returncode==0,'Test fixture cleanup failed'
        assert not exists(service)
    print('PASS: synthetic Keychain fixtures removed',flush=True)
