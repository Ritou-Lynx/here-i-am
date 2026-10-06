import test from 'node:test';import assert from 'node:assert/strict';
import {listenForFetch} from './fetch_test_listener.mjs';
test('test listeners rebind blocked OS ports before issuing any request and keep real startup failures',async()=>{
  let closes=0,starts=0;const ports=[6000,10080,49152];
  const server={close(callback){closes++;callback();}};
  const address=await listenForFetch(server,async()=>({port:ports[starts++]}));
  assert.equal(address.port,49152);assert.equal(closes,2);assert.equal(starts,3);
  const failure=new Error('real bind error');await assert.rejects(()=>listenForFetch(server,async()=>{throw failure;}),error=>error===failure);
});
test('repeated unusable ports stop with a bounded error rather than hiding a failing fixture',async()=>{
  let closes=0;await assert.rejects(()=>listenForFetch({close(callback){closes++;callback();}},async()=>({port:6667})),/fetch_safe_ephemeral_port_unavailable/);
  assert.equal(closes,16);
});
