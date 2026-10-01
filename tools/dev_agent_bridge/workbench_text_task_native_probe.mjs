// Explicit candidate no-auth/no-turn integration. It never arms a broker and
// therefore cannot send a model request or issue a production startup receipt.
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { createTextTaskBroker, TEXT_TASK_MODEL } from './workbench_text_task_broker.mjs';
import { launchWorkbenchTextNativeExecutor } from './workbench_text_task_native_executor.mjs';
import { WorkbenchTextTaskSession } from './workbench_text_task_session.mjs';

const disabled = ('shell_tool shell_snapshot unified_exec apply_patch_freeform apps plugins remote_plugin multi_agent '
  + 'js_repl js_repl_tools_only browser_use computer_use image_generation imagegen hooks memories memory_tool scheduled_tasks '
  + 'workspace_dependencies skill_mcp_dependency_install skill_env_var_dependency_prompt enable_request_compression responses_websockets '
  + 'responses_websockets_v2 code_mode_only multi_agent_v2 default_mode_request_user_input goals sleep_tool skill_search tool_suggest '
  + 'request_permissions_tool browser_use_external browser_use_full_cdp_access view_image code_mode_host respect_system_proxy').split(' ');
const empty = value => value == null || typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === 0;
const check = value => { if (!value) throw Object.assign(new Error('native_probe_config_rejected'), { code: 'native_probe_config_rejected' }); };

export function verifyNativeNoAuthConfig(result, requirements, baseUrl) {
  return verifyNativeTaskConfig(result, requirements, baseUrl, 'no_auth');
}

export function verifyNativeTaskConfig(result, requirements, baseUrl, authMode) {
  check(['no_auth', 'chatgpt'].includes(authMode));
  const config = result?.config; const provider = config?.model_providers?.p6_native_startup;
  check(config?.model === TEXT_TASK_MODEL && config.model_provider === 'p6_native_startup'
    && config.approval_policy === 'never' && config.sandbox_mode === 'read-only'
    && config.web_search === 'disabled' && config.project_doc_max_bytes === 0
    && config.agents?.enabled === false && empty(config.mcp_servers)
    && (config.notify == null || Array.isArray(config.notify) && config.notify.length === 0)
    && (empty(config.hooks) || typeof config.hooks === 'object' && !Array.isArray(config.hooks)
      && Object.values(config.hooks).every(value => Array.isArray(value) && value.length === 0))
    && disabled.every(name => config.features?.[name] === false) && config.features?.skip_host_skill_discovery === true);
  check(provider?.base_url === baseUrl && provider.wire_api === 'responses' && provider.requires_openai_auth === (authMode === 'chatgpt')
    && provider.request_max_retries === 0 && provider.stream_max_retries === 0 && provider.supports_websockets === false
    && provider.env_key == null && provider.experimental_bearer_token == null
    && empty(provider.http_headers) && empty(provider.env_http_headers) && empty(provider.query_params));
  check(Array.isArray(result.layers) && result.layers.every(layer =>
    ['system', 'sessionFlags', 'user'].includes(layer?.name?.type)
    && (layer.name.type === 'sessionFlags' || empty(layer.config)))
    && requirements && Object.hasOwn(requirements, 'requirements') && empty(requirements.requirements));
  return true;
}

export async function runNativeNoTurnProbe({ executable, sha256 }) {
  const report = { schema: 'p6_r7_native_no_turn_probe_v1', attempt_id: randomUUID(),
    supervisor_sha256: sha256, mode: 'no_auth_no_turn', started: false, config_verified: false,
    thread_verified: false, no_turn_receipt_verified: false, process_close_observed: false,
    cleanup_pending: true, host_requests: 0, broker: null, passed: false, code: null,
    production_isolation_passed: false, human_gate_passed: false };
  let owner; let client; let session; let closeReceipt;
  const broker = createTextTaskBroker({ verifyPeer: socket => owner?.verifyPeer(socket) ?? false });
  try {
    const baseUrl = await broker.listen();
    owner = launchWorkbenchTextNativeExecutor({ executable, sha256, attemptId: report.attempt_id,
      brokerPort: Number(new URL(baseUrl).port), startupTimeoutMs: 120000, closeTimeoutMs: 120000 });
    const startup = await owner.ready; report.started = true;
    client = new CodexAppServerClient({ attachedTransport: owner, experimentalApi: true, requestTimeoutMs: 15000 });
    client.on('serverRequest', request => {
      report.host_requests++;
      request.respondError({ code: -32601, message: 'Text tasks reject host requests.' });
    });
    await client.start();
    const config = await client.request('config/read', { cwd: startup.cwd, includeLayers: true });
    const requirements = await client.request('configRequirements/read', {});
    report.config_verified = verifyNativeNoAuthConfig(config, requirements, baseUrl);
    const started = await client.startThread({ cwd: startup.cwd, model: TEXT_TASK_MODEL,
      modelProvider: startup.provider, approvalPolicy: 'never', sandbox: 'read-only',
      ephemeral: true, dynamicTools: [], environments: [], runtimeWorkspaceRoots: [], selectedCapabilityRoots: [],
      baseInstructions: 'No-auth no-turn lifecycle verification. Do not execute a task.' });
    check(typeof started?.thread?.id === 'string' && started.thread.id.length > 0
      && started.model === TEXT_TASK_MODEL && started.modelProvider === startup.provider);
    report.thread_verified = true;
    session = new WorkbenchTextTaskSession({ client, broker, executionEpoch: randomUUID(),
      providerThreadId: started.thread.id, closeChild: async () => {
        closeReceipt = await owner.close(); return closeReceipt.process_close_observed === true;
      } });
    const receipt = await session.close();
    report.no_turn_receipt_verified = receipt.outcome === 'closed_without_turn' && receipt.turn_id === null
      && receipt.interrupt_dispatched === false && receipt.cancellation_confirmed === false
      && receipt.local_child_close_observed === true && receipt.proxy_drained === true;
  } catch (error) {
    report.code = /^native_[a-z_]{1,70}$/.test(error.code) ? error.code : 'native_probe_failed';
  } finally {
    broker.revoke();
    // Keep the native owner even when client initialization failed or timed out.
    if (owner && !closeReceipt) {
      try { closeReceipt = await owner.close(); } catch { report.code = 'native_probe_close_unconfirmed'; }
    }
    await broker.close(); report.broker = broker.snapshot();
    Object.assign(report, owner?.diagnostics ?? { native_failure_code: null, native_owner_exit_code: null, native_close_receipt: null });
    report.process_close_observed = closeReceipt?.process_close_observed === true;
    report.cleanup_pending = owner ? owner.cleanupPending : false;
    report.passed = report.started && report.config_verified && report.thread_verified
      && report.no_turn_receipt_verified && report.process_close_observed && !report.cleanup_pending
      && report.broker.drained && report.broker.upstream_attempts === 0 && report.host_requests === 0 && report.code === null;
  }
  return report;
}

export async function main(argv = process.argv.slice(2)) {
  if (argv.length !== 4 || argv[0] !== '--no-auth-no-turn' || !path.isAbsolute(argv[3])) {
    throw new Error('Explicit no-auth no-turn mode and a new absolute report path are required.');
  }
  const report = await runNativeNoTurnProbe({ executable: argv[1], sha256: argv[2] });
  const raw = `${JSON.stringify(report)}\n`;
  process.stdout.write(raw); // Preserve the original result even if file capture fails.
  writeFileSync(argv[3], raw, { flag: 'wx' });
  process.exitCode = report.passed ? 0 : 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main();
