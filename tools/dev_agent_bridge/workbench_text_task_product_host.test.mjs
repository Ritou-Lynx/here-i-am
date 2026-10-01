import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createWorkbenchTextTaskProductAdapterFactory,
  parseWorkbenchTextTaskProductHostConfig } from './workbench_text_task_product_host.mjs';

const executable = 'C:\\bounded\\TextTaskSupervisor.exe';
const sha256 = 'a'.repeat(64);
const config = Buffer.from(JSON.stringify({
  schema: 'workbench_text_task_product_host_v1', native_executable: executable, native_sha256: sha256,
}));
const configHash = createHash('sha256').update(config).digest('hex');
const env = () => ({
  DEV_AGENT_WORKBENCH_TEXT_TASK_HOST: '1',
  DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG: 'C:\\bounded\\host.json',
  DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG_SHA256: configHash,
});
const options = (overrides = {}) => ({
  ...overrides,
  env: { ...env(), ...(overrides.env || {}) },
  readFile: overrides.readFile || (() => config),
  validateNative: overrides.validateNative || (() => executable),
});

test('absent product text-host configuration keeps the profile fail-closed', () => {
  assert.equal(parseWorkbenchTextTaskProductHostConfig({ env: {} }), null);
  assert.equal(createWorkbenchTextTaskProductAdapterFactory({ env: {} }), null);
});

test('partial, malformed, and mismatched product configuration is rejected', () => {
  assert.throws(() => parseWorkbenchTextTaskProductHostConfig({
    env: { DEV_AGENT_WORKBENCH_TEXT_TASK_HOST: '1' },
  }), error => error.code === 'text_task_product_host_config_rejected');
  assert.throws(() => parseWorkbenchTextTaskProductHostConfig(options({
    env: { DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG_SHA256: 'b'.repeat(64) },
  })), error => error.code === 'text_task_product_host_config_rejected');
  assert.throws(() => parseWorkbenchTextTaskProductHostConfig(options({
    readFile: () => Buffer.from('{"schema":"workbench_text_task_product_host_v1"}'),
  })), error => error.code === 'text_task_product_host_config_rejected');
  const extra = Buffer.from(JSON.stringify({
    schema: 'workbench_text_task_product_host_v1', native_executable: executable,
    native_sha256: sha256, ordinary_adapter_fallback: true,
  }));
  assert.throws(() => parseWorkbenchTextTaskProductHostConfig(options({
    env: { DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG_SHA256:
      createHash('sha256').update(extra).digest('hex') },
    readFile: () => extra,
  })), error => error.code === 'text_task_product_host_config_rejected');
  assert.throws(() => parseWorkbenchTextTaskProductHostConfig(options({
    validateNative: () => { throw new Error('pin mismatch'); },
  })), error => error.code === 'text_task_product_host_config_rejected');
  const foreignReceipt = Buffer.from(JSON.stringify({ schema: 'workbench_text_task_product_host_v1',
    native_executable: executable, native_sha256: sha256,
    native_receipt_path: 'C:\\other\\native-close-receipts.jsonl' }));
  assert.throws(() => parseWorkbenchTextTaskProductHostConfig(options({
    env: { DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG_SHA256:
      createHash('sha256').update(foreignReceipt).digest('hex') },
    readFile: () => foreignReceipt,
  })), error => error.code === 'text_task_product_host_config_rejected');
});

test('valid opt-in validates the pinned host before supplying an adapter factory', () => {
  let validated = 0; let constructed = 0;
  const factory = createWorkbenchTextTaskProductAdapterFactory(options({
    validateNative: (file, hash) => { validated++; assert.equal(file, executable); assert.equal(hash, sha256); },
    createAdapter: nativeOptions => { constructed++; return { nativeOptions }; },
  }));
  assert.equal(validated, 1);
  assert.equal(constructed, 0);
  assert.deepEqual(factory(), { nativeOptions: { executable, sha256 } });
  assert.equal(constructed, 1);
});

test('candidate-only native receipt is persisted with fixed fields and refuses incomplete cleanup', t => {
  const root = mkdtempSync(join(tmpdir(), 'p6-native-close-receipt-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const configPath = join(root, 'host.json');
  const receiptPath = join(root, 'native-close-receipts.jsonl');
  const body = Buffer.from(JSON.stringify({ schema: 'workbench_text_task_product_host_v1',
    native_executable: executable, native_sha256: sha256, native_receipt_path: receiptPath }));
  const factory = createWorkbenchTextTaskProductAdapterFactory(options({
    env: { DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG: configPath,
      DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG_SHA256: createHash('sha256').update(body).digest('hex') },
    readFile: () => body,
    createAdapter: (_native, observer) => observer,
  }));
  const observe = factory();
  const receipt = { schema: 'workbench_text_task_native_close_v1',
    attempt_id: '8db57334-8888-4888-8888-888888888888', native_sha256: sha256,
    native_owner_pid: 321, native_owner_exit_code: 0, process_close_observed: true,
    job_empty_verified: true, stdio_eof_verified: true, rules_absent_verified: true,
    handles_closed_verified: true, helper_exits_verified: true, cleanup_pending: false };
  observe(receipt);
  assert.deepEqual(JSON.parse(readFileSync(receiptPath, 'utf8').trim()), receipt);
  assert.throws(() => observe({ ...receipt, helper_exits_verified: false }));
  assert.equal(readFileSync(receiptPath, 'utf8').trim().split('\n').length, 1);
});
