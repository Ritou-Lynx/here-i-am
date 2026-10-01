// Real local HTTP + candidate adapter/TaskSession/receipt ledger. Native, broker,
// account and provider I/O are simulated; this is not an isolation or App Gate.
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createServer } from 'node:http';
import test from 'node:test';
import { ExperimentalRuntimeApi, EXPERIMENTAL_RUNTIME_PREFIX as prefix } from './experimental_runtime_api.mjs';
import { WorkbenchTextTaskRuntimeAdapter } from './workbench_text_task_runtime_adapter.mjs';
import { createBridgeRuntimeShutdown } from './bridge_runtime_shutdown.mjs';
import { TEXT_TASK_CLI_SHA256 } from './workbench_text_task_runtime_pin.mjs';
import { TEXT_TASK_MODEL } from './workbench_text_task_broker.mjs';

const disabled = ('shell_tool shell_snapshot unified_exec apply_patch_freeform apps plugins remote_plugin multi_agent '
  + 'js_repl js_repl_tools_only browser_use computer_use image_generation imagegen hooks memories memory_tool scheduled_tasks '
  + 'workspace_dependencies skill_mcp_dependency_install skill_env_var_dependency_prompt enable_request_compression responses_websockets '
  + 'responses_websockets_v2 code_mode_only multi_agent_v2 default_mode_request_user_input goals sleep_tool skill_search tool_suggest '
  + 'request_permissions_tool browser_use_external browser_use_full_cdp_access view_image code_mode_host respect_system_proxy').split(' ');
const closeFacts = { process_close_observed: true, job_empty_verified: true, stdio_eof_verified: true,
  rules_absent_verified: true, handles_closed_verified: true, helper_exits_verified: true, cleanup_pending: false };
function candidate(records) {
  let record;
  return new WorkbenchTextTaskRuntimeAdapter({ factories: {
    createBroker() {
      record = { nativeCloses: 0, brokerCloses: 0, drained: false, inputs: [], interrupts: 0 };
      records.push(record);
      return { async listen() { return 'http://127.0.0.1:32123/v1'; }, arm(text) { record.inputs.push(text); }, revoke() {},
        async close() { record.brokerCloses++; record.drained = true; }, snapshot() { return { drained: record.drained }; } };
    },
    createOwner({ attemptId }) {
      return { ready: Promise.resolve({ attempt_id: attemptId, type: 'started', seq: 1, cwd: 'D:\\synthetic\\project0',
        auth_mode: 'chatgpt', provider: 'p6_native_startup', cli_sha256: TEXT_TASK_CLI_SHA256, pid: 123,
        creation_time: '123456', network_boundary_verified: true, child_identity_verified: true, job_singleton: true }),
      cleanupPending: true, async verifyPeer() { return true; },
      async close() { record.nativeCloses++; this.cleanupPending = false; return { ...closeFacts }; } };
    },
    createClient() {
      class Client extends EventEmitter {
        isReady = false; notificationSequence = 0;
        async start() { this.isReady = true; }
        async request(method, _params, dispatch) {
          if (method === 'config/read') return { config: { model: TEXT_TASK_MODEL, model_provider: 'p6_native_startup',
            approval_policy: 'never', sandbox_mode: 'read-only', web_search: 'disabled', project_doc_max_bytes: 0,
            agents: { enabled: false }, mcp_servers: {}, notify: [], hooks: {},
            features: { ...Object.fromEntries(disabled.map(name => [name, false])), skip_host_skill_discovery: true },
            model_providers: { p6_native_startup: { base_url: 'http://127.0.0.1:32123/v1', wire_api: 'responses',
              requires_openai_auth: true, request_max_retries: 0, stream_max_retries: 0, supports_websockets: false } } },
          layers: [{ name: { type: 'sessionFlags' }, config: {} }] };
          if (method === 'configRequirements/read') return { requirements: null };
          if (method === 'account/read') return { account: { type: 'chatgpt' } };
          assert.equal(method, 'turn/start'); dispatch.onDispatched(); return { turn: { id: 'synthetic-turn' } };
        }
        async startThread(params) { return { thread: { id: 'synthetic-thread' }, cwd: params.cwd,
          model: TEXT_TASK_MODEL, modelProvider: 'p6_native_startup', approvalPolicy: 'never', sandbox: { type: 'readOnly' } }; }
        async interruptTurn(threadId, turnId, dispatch) {
          assert.equal(threadId, 'synthetic-thread'); assert.equal(turnId, 'synthetic-turn');
          dispatch.onDispatched(); record.interrupts++;
          this.notify('turn/completed', { threadId, turn: { id: turnId, status: 'interrupted' } }); return {};
        }
        notify(method, params) { this.emit('notification', { sequence: ++this.notificationSequence, message: { method, params } }); }
      }
      return record.client = new Client();
    },
  } });
}

test('HTTP candidate contract binds completed and interrupted receipts, then graceful host shutdown', async t => {
  const records = [];
  const api = new ExperimentalRuntimeApi({ enabled: true,
    adapterFactory: () => { throw new Error('Ordinary adapter must not be constructed.'); },
    textAdapterFactory: () => candidate(records) });
  const server = createServer((req, res) => { void api.handle(req, res, new URL(req.url, 'http://localhost')); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await api.stop({ permanent: true }).catch(() => {}); server.closeAllConnections(); if (server.listening) server.close(); });
  const base = `http://127.0.0.1:${server.address().port}${prefix}`;
  const http = async (method, path, body) => {
    const response = await fetch(base + path, { method, ...(body ? { body: JSON.stringify(body), headers: { 'content-type': 'application/json' } } : {}) });
    const result = await response.json(); assert.equal(response.status, 200, JSON.stringify(result)); return result;
  };
  for (const scenario of ['completed', 'interrupted']) {
    const epoch = 'synthetic-' + scenario;
    const created = await http('POST', '/sessions', { config: { runtime_profile: 'workbench_text_only_v1' },
      context_manifest: { execution_epoch: epoch, task_id: 'synthetic-task', execution_mode: 'isolated_text_only' } });
    const id = created.session_id; const route = '/sessions/' + id;
    assert.deepEqual(created.execution_profile_receipt, { profile: 'workbench_text_only_v1', version: 2,
      local_session_id: id, execution_epoch: epoch, provider_thread_id: 'synthetic-thread', isolation_verified: true, tools_disabled: true });
    const turn = await http('POST', route + '/turns', { input: 'Synthetic contract input' });
    const r = records.at(-1);
    if (scenario === 'completed') {
      r.client.notify('item/agentMessage/delta', { threadId: 'synthetic-thread', turnId: 'synthetic-turn', delta: 'Synthetic answer' });
      r.client.notify('turn/completed', { threadId: 'synthetic-thread', turn: { id: 'synthetic-turn', status: 'completed' } });
    } else await http('POST', route + '/turns/' + turn.local_turn_id + '/interrupt', {});
    const events = await http('GET', route + '/events');
    assert.equal(events.events.at(-1).status, scenario);
    assert.equal(events.events.at(-1).turn_id, turn.local_turn_id);
    assert.equal(Object.hasOwn(events.events.at(-1).data, 'status'), false);
    const result = await http('DELETE', route);
    const receipt = result.stop_receipt;
    assert.equal(receipt.version, 2); assert.equal(receipt.profile, 'workbench_text_only_v1');
    assert.equal(receipt.local_session_id, id); assert.equal(receipt.execution_epoch, epoch);
    assert.equal(receipt.provider_thread_id, turn.provider_thread_id);
    assert.equal(receipt.local_turn_id, turn.local_turn_id); assert.equal(receipt.turn_id, turn.provider_turn_id);
    assert.equal(receipt.provider_terminal_status, scenario); assert.equal(receipt.provider_terminal_confirmed, true);
    assert.equal(receipt.cancellation_confirmed, scenario === 'interrupted');
    assert.equal(receipt.local_child_close_observed, true); assert.equal(receipt.proxy_drained, true);
    assert.deepEqual(await http('DELETE', route), result);
    assert.equal(r.nativeCloses, 1); assert.equal(r.drained, true);
    assert.deepEqual(r.inputs, ['Synthetic contract input']);
  }
  const shutdown = createBridgeRuntimeShutdown({ runtimeApi: api, server });
  assert.deepEqual(await shutdown.shutdown(), { status: 'closed', runtime_closed: true, http_server_closed: true });
  assert.equal(server.listening, false);
  for (const r of records) assert.equal(r.nativeCloses, 1);
});
