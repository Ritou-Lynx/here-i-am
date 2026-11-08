// M1 (daily life digest) rollout, round 1: prepare. Changes only one new private folder, nothing in production.
//   --mode prepare
//     0  live task is the G2 MCP (server e418eade); data sources the generator will read exist (Core DB, sharing policy,
//        heart-rate minutes, Feishu notes mirror)
//     1  Codex CLI: found, version, login status, configured model name, and one tiny `codex exec` (JSON reply)
//     2  %USERPROFILE%\life-digest\config with a protected DACL copied from the MCP state folder, and an RSA-3072 key
//        pair in it; prints the PUBLIC key so the next round can carry the AMap key and ntfy topic encrypted
//     3  the M1 candidate builds from this checkout (server hash pinned) and its life_digest tool loads
// Output: one JSON row per step; no tokens, logins, paths, SIDs or message text.
// Usage: m1-prepare.ps1 (Windows PowerShell 5.1, -File) runs this with --git <git.exe>.
import { createHash, createPublicKey, generateKeyPairSync, randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ACTIVE = 'HereIAm-iCoreSchema6-g2-tools-20261106';
const LIVE_SERVER = 'e418eade';
// LF build of this branch: only server.mjs differs from the live G2 candidate.
const MCP_EXPECTED = { 'i_remote_mcp/server.mjs': 'bde3ff9f', 'i_remote_mcp/oauth.mjs': 'e2c88aca', 'i_remote_mcp/diagnostics.mjs': '67b0fbec',
  'i_remote_mcp/mcp.mjs': '838810b2', 'i_remote_mcp/writeback.mjs': 'a7a6f95d', 'i_memory/i_memory_read.mjs': 'cee18518' };
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

class Stop extends Error { constructor(step, detail) { super(detail); this.step = step; this.detail = detail; } }
const sha = b => createHash('sha256').update(b).digest('hex');
const short = h => String(h).slice(0, 8).toLowerCase();
const emit = (step, ok, detail) => console.log(JSON.stringify({ step, ok, detail }));
const need = (cond, step, detail) => { if (!cond) throw new Stop(step, detail); };
const plain = p => typeof p === 'string' && path.win32.isAbsolute(p) && path.win32.normalize(p) === p && p.indexOf(':', 2) < 0 && !p.endsWith('\\') && !p.startsWith('\\\\');
function readJson(p, expected, step) { const b = readFileSync(p); if (expected) need(sha(b) === String(expected).toLowerCase(), step, 'hash_mismatch:' + path.basename(p)); return JSON.parse(b.toString('utf8').replace(/^﻿/, '')); }
const childEnv = () => { const e = {}; for (const [k, v] of Object.entries(process.env)) if (!/^(NODE_|I_CORE_|I_REMOTE_MCP_|GIT_)/i.test(k)) e[k] = v; e.PSModulePath = path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'Modules'); return e; };
function run(file, args, { cwd, input, step, timeoutMin = 10 } = {}) {
  const r = spawnSync(file, args, { cwd, input, env: childEnv(), encoding: 'utf8', windowsHide: true, maxBuffer: 64 * 1024 * 1024, timeout: timeoutMin * 60 * 1000 });
  if (r.error) return { code: 'spawn_failed:' + r.error.code, stdout: '', stderr: '' };
  return { code: r.status, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}
// First line of tool output reduced to a safe label (no paths, no secrets).
const label = t => (String(t).trim().split(/\r?\n/).find(Boolean) ?? '').replace(/[A-Za-z]:\\[^\s]*/g, '<path>').replace(/[^\w .:@()\/<>=+-]/g, '').slice(0, 120);
const rows = t => t.split(/\r?\n/).filter(Boolean).map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
const lastErr = r => (r.stderr.trim().split(/\r?\n/).filter(Boolean).pop() ?? '').slice(0, 240);
const PS = () => path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
const HEAD51 = "$ErrorActionPreference='Stop'\nif($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'host_not_51'}\n$q=[Console]::In.ReadToEnd()|ConvertFrom-Json\n";
function value(script, input, step) {
  const r = run(PS(), ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', Buffer.from(HEAD51 + script, 'utf16le').toString('base64')], { input: JSON.stringify(input ?? {}), step, timeoutMin: 5 });
  need(r.code === 0, step, 'powershell_exit_' + r.code + ':' + lastErr(r));
  return JSON.parse(r.stdout.trim().split(/\r?\n/).filter(Boolean).pop());
}
const asList = v => Array.isArray(v) ? v : [v];
const TASKS_PS = "ConvertTo-Json -InputObject @(Get-ScheduledTask|Where-Object{$_.TaskName -like 'HereIAm-*'}|ForEach-Object{[pscustomobject]@{name=$_.TaskName;state=[string]$_.State;arguments=[string]$_.Actions[0].Arguments}}) -Compress -Depth 3";
function loginOf(task, step) {
  const tok = [...task.arguments.matchAll(/"([^"]*)"|(\S+)/g)].map(m => m[1] ?? m[2]);
  const arg = re => { const i = tok.map((t, j) => re.test(t) ? j : -1).filter(j => j >= 0); need(i.length === 1 && i[0] + 1 < tok.length, step, 'login_argument_ambiguous'); return tok[i[0] + 1]; };
  const p = arg(/^-(Login)?ConfigurationPath$/i), h = arg(/^-(Login)?ConfigurationSha256$/i).toLowerCase();
  const login = readJson(p, h, step); need(login.format === 'schema6-login-v1', step, 'login_format'); return login;
}
// Copy the DACL (only) of a source directory onto a target, protected.
const ACL_PS = "$a=(Get-Item -LiteralPath $q.from).GetAccessControl('Access');$a.SetAccessRuleProtection($true,$true);(Get-Item -LiteralPath $q.to).SetAccessControl($a);$v=(Get-Item -LiteralPath $q.to).GetAccessControl('Access');ConvertTo-Json -InputObject ([pscustomobject]@{protected=$v.AreAccessRulesProtected;rules=@($v.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])).Count}) -Compress";
const files = root => { const out = []; const go = d => { for (const e of readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) go(p); else out.push(p); } }; go(root); return out; };

// Codex CLI: an npm shim (codex.cmd → node …/@openai/codex/bin/codex.js) or a native codex.exe.
function findCodex(step) {
  const r = run('where.exe', ['codex'], { step });
  const hits = r.code === 0 ? r.stdout.split(/\r?\n/).map(s => s.trim()).filter(s => s && existsSync(s)) : [];
  const exe = hits.find(h => /\.exe$/i.test(h));
  if (exe) return { kind: 'exe', argv: [exe] };
  for (const hit of hits) {
    const js = path.join(path.dirname(hit), 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
    if (existsSync(js)) return { kind: 'npm', argv: [process.execPath, js] };
  }
  const fallback = path.join(process.env.APPDATA ?? '', 'npm', 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
  if (existsSync(fallback)) return { kind: 'npm', argv: [process.execPath, fallback] };
  return null;
}

async function main() {
  const a = process.argv.slice(2);
  need(a.length === 4 && a[0] === '--mode' && a[1] === 'prepare' && a[2] === '--git', 'args', 'usage: --mode prepare --git <git.exe>');
  need(process.platform === 'win32' && /^v24\./.test(process.version) && plain(process.execPath), 'args', 'windows_node24_required');
  const G = a[3]; need(plain(G) && existsSync(G) && statSync(G).isFile(), 'args', 'git_path_required');
  const home = process.env.USERPROFILE; need(plain(home), 'args', 'userprofile_missing');

  // 0. Live task and data sources (read-only).
  const all = asList(value(TASKS_PS, {}, 'step0'));
  const active = all.find(t => t.name === ACTIVE); need(active?.state === 'Running', 'step0', 'active_task_not_running:' + (active?.state ?? 'missing'));
  need(all.filter(t => /^HereIAm-iCoreSchema6-/.test(t.name)).every(t => t.name === ACTIVE || t.state === 'Disabled'), 'step0', 'other_task_enabled');
  const login = loginOf(active, 'step0');
  const mcp = readJson(login.mcp_configuration_path, login.mcp_configuration_sha256, 'step0');
  need(short(mcp.source_files.find(f => f.path === 'i_remote_mcp/server.mjs')?.sha256) === LIVE_SERVER, 'step0', 'live_server_not_g2');
  const stateMcp = mcp.environment?.I_REMOTE_MCP_STATE_DIR, coreDb = mcp.database_path, policy = mcp.environment?.I_MEMORY_POLICY;
  need(plain(stateMcp) && existsSync(stateMcp), 'step0', 'mcp_state_dir');
  const notesIndex = path.join(home, 'feishu-notes', 'index.json');
  const sources = { core_db: plain(coreDb) && existsSync(coreDb), policy: plain(policy) && existsSync(policy),
    heart_rate_dir: existsSync(path.join(stateMcp, 'heart_rate')), notes_index: existsSync(notesIndex),
    life_digest_json: existsSync(path.join(stateMcp, 'life_digest.json')), release_node: plain(path.join(login.release_directory, 'runtime', 'node.exe')) };
  need(sources.core_db && sources.policy, 'step0', 'chat_sources_missing');
  emit('step0', true, { active: 'Running', live_server: LIVE_SERVER, ...sources, node: process.version });

  // 1. Codex CLI.
  const codex = findCodex('step1');
  if (!codex) emit('step1', false, { codex: 'not_found' });
  else {
    const version = run(codex.argv[0], [...codex.argv.slice(1), '--version'], { step: 'step1', timeoutMin: 2 });
    const status = run(codex.argv[0], [...codex.argv.slice(1), 'login', 'status'], { step: 'step1', timeoutMin: 2 });
    let model = null;
    try { model = (/^\s*model\s*=\s*"([^"]{1,80})"/m.exec(readFileSync(path.join(home, '.codex', 'config.toml'), 'utf8'))?.[1] ?? null)?.replace(/[^\w.:-]/g, '') ?? null; } catch { model = 'config_unreadable'; }
    const work = path.join(home, 'life-digest', 'work-probe-' + randomBytes(3).toString('hex'));
    mkdirSync(work, { recursive: true });
    const out = path.join(work, 'reply.txt');
    const probe = extra => {
      const t0 = Date.now();
      const r = run(codex.argv[0], [...codex.argv.slice(1), 'exec', '--sandbox', 'read-only', '--skip-git-repo-check', '--color', 'never', ...extra, '--output-last-message', out, '-'],
        { cwd: work, input: '只输出下面这个 JSON，不要任何别的文字：{"ok":true}', step: 'step1', timeoutMin: 5 });
      let reply = '';
      try { reply = readFileSync(out, 'utf8'); rmSync(out, { force: true }); } catch { /* none */ }
      return { exit: r.code, seconds: Math.round((Date.now() - t0) / 1000), json_ok: /\{\s*"ok"\s*:\s*true\s*\}/.test(reply), err: r.code === 0 ? '' : label(r.stderr) };
    };
    const withoutMcp = probe(['-c', 'mcp_servers={}']);
    const plainRun = withoutMcp.exit === 0 ? null : probe([]);
    rmSync(work, { recursive: true, force: true });
    emit('step1', withoutMcp.json_ok || Boolean(plainRun?.json_ok), { codex: codex.kind, version: label(version.stdout || version.stderr), login: label(status.stdout || status.stderr),
      config_model: model, exec_no_mcp: withoutMcp, ...(plainRun ? { exec_plain: plainRun } : {}) });
  }

  // 2. Private config folder and the deploy key pair (reused if already there).
  const base = path.join(home, 'life-digest'), cfg = path.join(base, 'config');
  mkdirSync(cfg, { recursive: true });
  const acl = value(ACL_PS, { from: stateMcp, to: cfg }, 'step2');
  need(acl.protected === true && acl.rules > 0, 'step2', 'config_acl');
  const keyFile = path.join(cfg, 'deploy-key.pem');
  let publicDer, created = false;
  if (existsSync(keyFile)) publicDer = createPublicKey(readFileSync(keyFile, 'utf8')).export({ type: 'spki', format: 'der' });
  else {
    const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 3072 });
    writeFileSync(keyFile, privateKey.export({ type: 'pkcs8', format: 'pem' }), { flag: 'wx', mode: 0o600 });
    publicDer = publicKey.export({ type: 'spki', format: 'der' }); created = true;
  }
  emit('step2', true, { config_dir: 'protected', rules: acl.rules, key: created ? 'created' : 'reused', fingerprint: short(sha(publicDer)) });
  emit('step2.public_key', true, publicDer.toString('base64'));

  // 3. Candidate built in this worktree only; life_digest loads from a throwaway state folder.
  const buildRel = 'build/m1-candidate-' + randomBytes(4).toString('hex'), build = path.join(REPO, ...buildRel.split('/'));
  const r = run(process.execPath, [path.join(REPO, 'tools', 'i_remote_mcp', 'chatgpt_candidate.mjs'), '--out', buildRel], { cwd: REPO, step: 'step3' });
  need(r.code === 0, 'step3', 'candidate_build_failed:' + lastErr(r));
  const cm = readJson(path.join(build, 'manifest.json'), null, 'step3');
  const hashes = Object.fromEntries(cm.files.map(f => [f.path, short(f.result_sha256)]));
  need(JSON.stringify(hashes) === JSON.stringify(Object.fromEntries(Object.keys(hashes).map(k => [k, MCP_EXPECTED[k]]))), 'step3', 'candidate_hash:' + JSON.stringify(hashes));
  const code = "import {pathToFileURL} from 'node:url';import {mkdirSync,writeFileSync} from 'node:fs';import path from 'node:path';let t='';process.stdin.on('data',d=>t+=d).on('end',async()=>{const q=JSON.parse(t);" +
    "mkdirSync(path.join(q.state,'digest','days'),{recursive:true});writeFileSync(path.join(q.state,'life_digest.json'),JSON.stringify({format:'life-digest-v1',digest_dir:path.join(q.state,'digest')}));" +
    "const m=await import(pathToFileURL(q.server).href);const l=m.createLifeDigest({stateDir:q.state});const d=await l.handlers.life_digest({});" +
    "console.log(JSON.stringify({tools:l.tools.map(x=>x.name).join(','),available:d.available,snapshot:l.snapshot().length>0}));});";
  const pr = run(process.execPath, ['--disable-warning=ExperimentalWarning', '--input-type=module', '-e', code], { step: 'step3', input: JSON.stringify({ server: path.join(build, 'runtime', 'i_remote_mcp', 'server.mjs'), state: path.join(build, 'probe-state') }) });
  const probe = rows(pr.stdout).pop();
  need(pr.code === 0 && probe?.tools === 'life_digest,life_todo' && probe.available === false && probe.snapshot === true, 'step3', 'life_digest_probe:' + (lastErr(pr) || pr.code));
  emit('step3', true, { candidate: 'built_in_worktree', server: MCP_EXPECTED['i_remote_mcp/server.mjs'], files: files(path.join(build, 'runtime')).length, probe });
  emit('done', true, { mode: 'prepare', next: 'deploy round carries the encrypted settings' });
}

main().catch(e => { emit(e.step ?? 'unexpected', false, e.detail ?? String(e.message).slice(0, 300)); process.exitCode = 1; });
