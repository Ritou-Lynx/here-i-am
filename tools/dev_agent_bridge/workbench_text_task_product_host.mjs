// Product Bridge opt-in for the bounded text-only task host.  This module is
// deliberately inert unless both opt-in variables are present.  It is not the
// P6 Debug candidate host and owns no process until the Runtime API asks it to
// create an adapter.
import { createHash } from 'node:crypto';
import { closeSync, fstatSync, fsyncSync, lstatSync, openSync, readFileSync, realpathSync, writeSync } from 'node:fs';
import path from 'node:path';
import { WorkbenchTextTaskRuntimeAdapter } from './workbench_text_task_runtime_adapter.mjs';
import { assertTextTaskSupervisor } from './workbench_text_task_native_executor.mjs';

const ENABLE = 'DEV_AGENT_WORKBENCH_TEXT_TASK_HOST';
const CONFIG = 'DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG';
const CONFIG_SHA256 = 'DEV_AGENT_WORKBENCH_TEXT_TASK_HOST_CONFIG_SHA256';
const HASH = /^[a-f0-9]{64}$/;
const KEYS = ['schema', 'native_executable', 'native_sha256'];
const RECEIPT_KEY = 'native_receipt_path';
const RECEIPT_NAME = 'native-close-receipts.jsonl';

function rejected(reason) {
  const error = new Error(reason);
  error.code = 'text_task_product_host_config_rejected';
  return error;
}

function exact(value, keys) {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}

export function parseWorkbenchTextTaskProductHostConfig({
  env = process.env,
  readFile = readFileSync,
  validateNative = assertTextTaskSupervisor,
} = {}) {
  const enabled = env[ENABLE] === '1';
  const configPath = typeof env[CONFIG] === 'string' ? env[CONFIG].trim() : '';
  const expectedHash = typeof env[CONFIG_SHA256] === 'string'
    ? env[CONFIG_SHA256].trim().toLowerCase() : '';
  if (!enabled && !configPath && !expectedHash) return null;
  if (!enabled || !configPath || !HASH.test(expectedHash) || !path.isAbsolute(configPath)) {
    throw rejected('text_task_product_host_config_rejected');
  }
  let bytes;
  try {
    bytes = readFile(configPath);
  } catch {
    throw rejected('text_task_product_host_config_rejected');
  }
  if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > 8192
    || createHash('sha256').update(bytes).digest('hex') !== expectedHash) {
    throw rejected('text_task_product_host_config_rejected');
  }
  let config;
  try {
    config = JSON.parse(bytes.toString('utf8'));
  } catch {
    throw rejected('text_task_product_host_config_rejected');
  }
  if (!(exact(config, KEYS) || exact(config, [...KEYS, RECEIPT_KEY]))
    || config.schema !== 'workbench_text_task_product_host_v1'
    || typeof config.native_executable !== 'string' || !path.isAbsolute(config.native_executable)
    || typeof config.native_sha256 !== 'string' || !HASH.test(config.native_sha256)
    || (Object.hasOwn(config, RECEIPT_KEY) && (typeof config.native_receipt_path !== 'string'
      || !path.isAbsolute(config.native_receipt_path)
      || path.basename(config.native_receipt_path) !== RECEIPT_NAME
      || path.dirname(config.native_receipt_path) !== path.dirname(configPath)))) {
    throw rejected('text_task_product_host_config_rejected');
  }
  try {
    // This validates canonical path and binary hash before the host can arm a
    // session. The adapter repeats the check at native spawn time.
    validateNative(config.native_executable, config.native_sha256);
  } catch {
    throw rejected('text_task_product_host_config_rejected');
  }
  return Object.freeze({
    executable: config.native_executable,
    sha256: config.native_sha256,
    ...(config.native_receipt_path ? { receiptPath: config.native_receipt_path } : {}),
  });
}

function persistNativeCloseReceipt(filename, receipt) {
  const parent = path.dirname(filename);
  const directory = lstatSync(parent);
  if (!directory.isDirectory() || directory.isSymbolicLink() || realpathSync(parent) !== parent) {
    throw rejected('text_task_product_host_receipt_rejected');
  }
  const allowed = ['schema', 'attempt_id', 'native_sha256', 'native_owner_pid',
    'native_owner_exit_code', 'process_close_observed', 'job_empty_verified',
    'stdio_eof_verified', 'rules_absent_verified', 'handles_closed_verified',
    'helper_exits_verified', 'cleanup_pending'];
  if (!exact(receipt, allowed) || receipt.schema !== 'workbench_text_task_native_close_v1'
    || !HASH.test(receipt.native_sha256) || !/^[0-9a-f-]{36}$/.test(receipt.attempt_id)
    || !Number.isInteger(receipt.native_owner_pid) || receipt.native_owner_pid <= 0
    || !Number.isInteger(receipt.native_owner_exit_code)
    || allowed.slice(5, 11).some(key => receipt[key] !== true)
    || receipt.cleanup_pending !== false) {
    throw rejected('text_task_product_host_receipt_rejected');
  }
  const fd = openSync(filename, 'a', 0o600);
  try {
    const held = fstatSync(fd), named = lstatSync(filename);
    if (!held.isFile() || held.nlink !== 1 || named.isSymbolicLink()
      || held.dev !== named.dev || held.ino !== named.ino) {
      throw rejected('text_task_product_host_receipt_rejected');
    }
    writeSync(fd, `${JSON.stringify(receipt)}\n`);
    fsyncSync(fd);
  } finally { closeSync(fd); }
}

export function createWorkbenchTextTaskProductAdapterFactory(options = {}) {
  const config = parseWorkbenchTextTaskProductHostConfig(options);
  if (config == null) return null;
  const { receiptPath, ...nativeOptions } = config;
  const createAdapter = options.createAdapter || ((value, observer) => new WorkbenchTextTaskRuntimeAdapter({
    nativeOptions: value, ...(observer ? { nativeCloseObserver: observer } : {}),
  }));
  if (typeof createAdapter !== 'function') throw rejected('text_task_product_host_config_rejected');
  return () => createAdapter(nativeOptions, receiptPath
    ? receipt => persistNativeCloseReceipt(receiptPath, receipt) : undefined);
}
