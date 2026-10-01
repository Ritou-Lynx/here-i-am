// Explicit setup action for an isolated Codex login. No thread/turn/model calls.
// Tokens remain CLI-owned outside the repository; no auth file is read/copied.
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { CodexAppServerClient } from './codex_app_server_client.mjs';
import { restrictions } from './workbench_tool_behavior_probe.mjs';
import { TEXT_GATE_CLI_SHA256 } from './workbench_text_gate_runtime_pin.mjs';

function within(target, parent) {
  const relative = path.relative(parent, target);
  return !relative || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}
export function prepareDedicatedHome({ localAppData, repository, originalHomes = [] }) {
  if (!localAppData || !path.isAbsolute(localAppData)) throw new Error('Local application data directory unavailable.');
  const canonical = value => existsSync(value) ? realpathSync(value) : path.resolve(value);
  const base = realpathSync(localAppData);
  const protectedRoots = [repository, ...originalHomes].filter(Boolean).map(canonical);
  const home = path.join(base, 'HereIAm', 'Runtime', 'p6-text-only-codex');
  if (protectedRoots.some(root => within(home, root) || within(root, home))) throw new Error('Dedicated runtime overlaps a protected directory.');
  let current = base;
  for (const segment of ['HereIAm', 'Runtime', 'p6-text-only-codex', 'empty-workspace']) {
    current = path.join(current, segment);
    if (!existsSync(current)) mkdirSync(current);
    const info = lstatSync(current);
    if (!info.isDirectory() || info.isSymbolicLink() || path.relative(current, realpathSync(current)) !== '') {
      throw new Error('Dedicated runtime directory is redirected or invalid.');
    }
  }
  return { home, cwd: current };
}
function safeLoginUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || !['auth.openai.com', 'chatgpt.com'].includes(url.hostname) || url.username || url.password || url.port) throw new Error('Unexpected login origin.');
  return url.href;
}
export function loginChallenge(login, mode) {
  const expectedType = mode === 'device-login' ? 'chatgptDeviceCode' : 'chatgpt';
  if (!['login', 'device-login'].includes(mode) || login?.type !== expectedType || typeof login.loginId !== 'string' || !login.loginId) throw new Error('Unexpected login response.');
  if (mode === 'login') return { auth_url: safeLoginUrl(login.authUrl) };
  // Device codes are intentionally shown only to this user, never persisted.
  if (login.verificationUrl !== 'https://auth.openai.com/codex/device' || typeof login.userCode !== 'string' || !/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(login.userCode)) throw new Error('Unexpected device login response.');
  return { verification_url: login.verificationUrl, user_code: login.userCode };
}
export async function main(executable, { mode = 'status' } = {}) {
  if (!['status', 'login', 'device-login'].includes(mode) || !executable || !path.isAbsolute(executable)) throw new Error('Pass a pinned absolute executable and --status, --login or --device-login.');
  if (createHash('sha256').update(readFileSync(executable)).digest('hex') !== TEXT_GATE_CLI_SHA256) throw new Error('CLI fingerprint changed; setup refused.');
  const directories = {
    localAppData: process.env.LOCALAPPDATA,
    repository: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..'),
    originalHomes: [process.env.CODEX_HOME, process.env.USERPROFILE ? path.join(process.env.USERPROFILE, '.codex') : null],
  };
  const { home, cwd } = prepareDedicatedHome(directories);
  const overrides = { ...restrictions(false), model_provider: 'openai', 'agents.enabled': false, cli_auth_credentials_store: 'file' };
  const args = ['app-server', '--listen', 'stdio://'];
  for (const [key, value] of Object.entries(overrides)) args.push('-c', `${key}=${typeof value === 'object' && !Array.isArray(value) ? '{}' : JSON.stringify(value)}`);
  const env = Object.fromEntries(['SystemRoot', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT', 'PATH'].filter(key => process.env[key]).map(key => [key, process.env[key]]));
  Object.assign(env, { CODEX_HOME: home, HOME: home, USERPROFILE: home, APPDATA: home, LOCALAPPDATA: home, TEMP: home, TMP: home });
  const client = new CodexAppServerClient({ commandSpec: { command: executable, args }, cwd, env, requestTimeoutMs: 10000 });
  client.on('serverRequest', request => request.respondError({ code: -32601, message: 'Login-only host rejects runtime requests.' }));
  let loginId = null; let successful = false; let failure = null; let stage = 'startup';
  try {
    // Revalidate existing path components immediately before child creation.
    prepareDedicatedHome(directories);
    await client.start();
    stage = 'account_read';
    const current = await client.readAccount();
    if (current.requiresOpenaiAuth !== true) throw new Error('Unexpected provider authentication mode.');
    if (current.account?.type && current.account.type !== 'chatgpt') throw new Error('Dedicated directory has a different login type; left unchanged.');
    if (current.account?.type === 'chatgpt') {
      successful = true;
      console.log(JSON.stringify({ status: 'chatgpt_login_available', model_requests_sent: 0 }));
    } else if (mode === 'status') {
      console.log(JSON.stringify({ status: 'chatgpt_login_required', model_requests_sent: 0 }));
    } else {
      const afterSequence = client.notificationSequence;
      stage = 'login_start';
      const login = await client.request('account/login/start', { type: mode === 'device-login' ? 'chatgptDeviceCode' : 'chatgpt' });
      // Own cancellation before validating the user-facing challenge.
      loginId = typeof login?.loginId === 'string' && login.loginId ? login.loginId : null;
      stage = 'login_challenge';
      const challenge = loginChallenge(login, mode);
      console.log(JSON.stringify({ status: 'login_required', ...challenge, model_requests_sent: 0 }));
      stage = 'login_wait';
      const completed = await client.waitForNotification('account/login/completed', event => event.params?.loginId === loginId,
        { afterSequence, timeoutMs: 600000 });
      if (completed.params?.success !== true) throw new Error('Login did not complete successfully.');
      loginId = null;
      stage = 'login_account_verify';
      const account = await client.readAccount();
      if (account.requiresOpenaiAuth !== true || account.account?.type !== 'chatgpt') throw new Error('ChatGPT login not confirmed.');
      successful = true;
      console.log(JSON.stringify({ status: 'chatgpt_login_confirmed', model_requests_sent: 0 }));
    }
  } catch (error) {
    // Do not print upstream error payloads, account identity, or authentication.
    failure = error.code || 'login_setup_failed';
    console.log(JSON.stringify({ status: 'failed', code: failure, stage, model_requests_sent: 0 }));
  } finally {
    if (loginId) { try { await client.request('account/login/cancel', { loginId }); } catch { /* Process shutdown still follows. */ } }
    try { const stopped = await client.stop(); console.log(JSON.stringify({ process_close_observed: stopped.process_close_observed === true })); }
    catch { failure = 'stop_close_unconfirmed'; }
  }
  process.exitCode = failure ? 2 : successful || mode === 'status' ? 0 : 2;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await main(process.argv[2], { mode: process.argv.includes('--device-login') ? 'device-login' : process.argv.includes('--login') ? 'login' : 'status' });
}
