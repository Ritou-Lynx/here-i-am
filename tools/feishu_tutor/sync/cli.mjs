import { spawn } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

export class SyncError extends Error {
  constructor(code) { super(code); this.code = code; }
}
export const fail = code => { throw new SyncError(code); };
const own = (o, k) => Object.hasOwn(o, k);
const specs = Object.freeze({
  whoami: { command: ['whoami'], keys: [] },
  record_list: { command: ['base', '+record-list'], keys: ['base', 'table', 'offset'] },
  table_get: { command: ['base', '+table-get'], keys: ['base', 'table'] },
  field_list: { command: ['base', '+field-list'], keys: ['base', 'table'] },
  record_create: { command: ['base', '+record-batch-create'], keys: ['base', 'table', 'file'] },
  record_update: { command: ['base', '+record-batch-update'], keys: ['base', 'table', 'file'] },
  doc_fetch: { command: ['docs', '+fetch'], keys: ['doc'] },
  doc_create: { command: ['docs', '+create'], keys: ['file'] },
  doc_append: { command: ['docs', '+update'], keys: ['doc', 'file'] },
});
export const COMMANDS = Object.freeze(Object.keys(specs));

// No argv passthrough: both the verb and every flag come from this closed builder.
export function buildCommand(operation, params = {}) {
  if (!own(specs, operation)) fail('command_not_allowed');
  const spec = specs[operation];
  if (Object.keys(params).some(k => !spec.keys.includes(k)) ||
      spec.keys.some(k => !own(params, k))) fail('command_not_allowed');
  for (const [key, value] of Object.entries(params)) {
    if (key === 'offset') {
      if (!Number.isSafeInteger(value) || value < 0) fail('command_not_allowed');
    } else if (typeof value !== 'string' || !value || /^[\-@]/u.test(value) || /[\r\n\0]/u.test(value)) {
      fail('command_not_allowed');
    }
    if (key === 'file' && value !== 'payload.json' && value !== 'content.md') fail('command_not_allowed');
  }
  const args = [...spec.command, '--as', 'user'];
  if (params.base) args.push('--base-token', params.base, '--table-id', params.table);
  if (operation === 'record_list') args.push('--format', 'ndjson', '--limit', '2000',
    '--offset', String(params.offset), '--output', 'records.ndjson');
  if (operation === 'table_get' || operation === 'field_list') args.push('--format', 'json');
  if (operation === 'record_create' || operation === 'record_update') args.push('--json', `@${params.file}`);
  if (params.doc) args.push('--doc', params.doc);
  if (operation.startsWith('doc_')) args.push('--doc-format', 'markdown');
  if (operation === 'doc_append') args.push('--command', 'append');
  if (operation === 'doc_create' || operation === 'doc_append') args.push('--content', `@${params.file}`);
  return args;
}

async function exists(file) { try { await access(file); return true; } catch { return false; } }

// npm's Windows .cmd cannot be spawned with shell:false. Resolve only the known
// package's native binary; never execute a command shell or arbitrary wrapper.
export async function resolveCli(config) {
  if (typeof config.cli === 'string' && /\.(mjs|cjs|js)$/iu.test(config.cli)) fail('cli_invalid');
  const requested = process.env.FEISHU_TUTOR_CLI || config.cli || 'lark-cli';
  if (typeof requested !== 'string' || !requested || /[\r\n\0]/u.test(requested)) fail('cli_invalid');
  if (/\.(mjs|cjs|js)$/iu.test(requested)) {
    if (!process.env.FEISHU_TUTOR_CLI) fail('cli_invalid');
    return { cli: process.execPath, prefix: [path.resolve(requested)] };
  }
  if (process.platform !== 'win32') return { cli: requested, prefix: [] };
  const roots = requested === 'lark-cli' ? (process.env.PATH || '').split(path.delimiter) : [path.dirname(path.resolve(requested))];
  if (/\.exe$/iu.test(requested)) return { cli: requested, prefix: [] };
  if (requested !== 'lark-cli' && path.basename(requested).toLowerCase() !== 'lark-cli.cmd') fail('cli_invalid');
  for (const root of roots.filter(Boolean)) {
    for (const candidate of [path.join(root, 'lark-cli.exe'),
      path.join(root, 'node_modules', '@larksuite', 'cli', 'bin', 'lark-cli.exe')]) {
      if (await exists(candidate)) return { cli: candidate, prefix: [] };
    }
  }
  fail('cli_not_found');
}

export async function callCli(config, operation, params = {}, payload) {
  const scratch = await mkdtemp(path.join(tmpdir(), 'feishu-tutor-'));
  try {
    const input = { ...params };
    if (payload !== undefined) {
      const file = typeof payload === 'string' ? 'content.md' : 'payload.json';
      await writeFile(path.join(scratch, file), typeof payload === 'string' ? payload : JSON.stringify(payload), { encoding: 'utf8', mode: 0o600 });
      input.file = file;
    }
    const args = buildCommand(operation, input);
    const { cli, prefix } = await resolveCli(config);
    const result = await new Promise((resolve, reject) => {
      const child = spawn(cli, [...prefix, ...args], {
        shell: false, cwd: scratch, windowsHide: true,
        env: { ...process.env, LARK_CLI_NO_PROXY: '1', LARKSUITE_CLI_NO_UPDATE_NOTIFIER: '1', LARKSUITE_CLI_NO_SKILLS_NOTIFIER: '1' },
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      let stdout = '', size = 0, overflow = false;
      child.stdout.setEncoding('utf8');
      child.stderr.resume(); // Never echo upstream output: it may contain private data.
      child.stdout.on('data', chunk => {
        size += Buffer.byteLength(chunk);
        if (size > 16 * 1024 * 1024) { overflow = true; child.kill(); }
        else stdout += chunk;
      });
      const timer = setTimeout(() => child.kill(), 120_000);
      child.once('error', () => { clearTimeout(timer); reject(new SyncError('cli_spawn_failed')); });
      child.once('close', code => {
        clearTimeout(timer);
        if (overflow || code !== 0) return reject(new SyncError('cli_failed'));
        let envelope;
        try { envelope = JSON.parse(stdout); } catch { return reject(new SyncError('cli_invalid_json')); }
        // CLI 1.0.98 shapes, confirmed on a real tenant: whoami has no ok field;
        // record-list with --output prints the manifest itself, whose rows are
        // checked against the files below. Every other command keeps the envelope.
        if (operation === 'whoami') {
          if (envelope.identity !== 'user' || envelope.available !== true) return reject(new SyncError('cli_invalid_response'));
        } else if (operation !== 'record_list' && (envelope.ok !== true || envelope.identity !== 'user')) {
          return reject(new SyncError('cli_invalid_response'));
        }
        resolve(envelope);
      });
    });
    if (operation !== 'record_list') return result.data;
    // NDJSON's physical row format is documented by CLI 1.0.98. Do not guess
    // the undocumented raw-matrix JSON layout or accept an incomplete page.
    const manifest = JSON.parse(await readFile(path.join(scratch, 'records.manifest.json'), 'utf8'));
    const text = await readFile(path.join(scratch, 'records.ndjson'), 'utf8');
    const rows = text.split(/\r?\n/u).filter(Boolean).map(line => JSON.parse(line));
    if (manifest.records_count !== rows.length || typeof manifest.has_more !== 'boolean' ||
        rows.some(row => typeof row.record_id !== 'string' || !row.record_id)) fail('cli_invalid_records');
    return { rows, manifest };
  } finally {
    // Only this invocation's temporary transport files are removed.
    await rm(scratch, { recursive: true, force: true });
  }
}
