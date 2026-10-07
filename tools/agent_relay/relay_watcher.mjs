import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createWriteStream } from 'node:fs';
import { access, mkdir, open, readFile, realpath, rename, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseInstruction, isEligiblePr, renderPrompt, redact, formatReply } from './relay_core.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const REPO = 'Ritou-Lynx/here-i-am';
const defaults = { repo: REPO, baseBranch: 'v3-lab', headPrefixes: ['claude/', 'codex/'], allowedAuthors: ['Ritou-Lynx'], maxRounds: 4, codexTimeoutMinutes: 60, codexArgs: ['--sandbox', 'workspace-write'], summaryMaxChars: 6000, mention: '@Ritou-Lynx', pollSeconds: 180 };

// Every subprocess, including the Windows timeout cleanup helper, uses this boundary.
export function run(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { cwd: opts.cwd, env: { ...process.env, ...opts.env }, shell: false, windowsHide: true, detached: process.platform !== 'win32', stdio: ['pipe', 'pipe', 'pipe'] });
    const chunks = [], errors = [];
    const output = opts.stdoutFile ? createWriteStream(opts.stdoutFile, { flags: 'w', mode: 0o600 }) : null;
    let timedOut = false, timer, finishTimer, cleanup = Promise.resolve(), streamError, settled = false, cleanupUnconfirmed = false;
    output?.on('error', error => { streamError = error; });
    child.stdout.on('data', data => { if (output) output.write(data); else chunks.push(data); });
    child.stderr.on('data', data => errors.push(data));
    child.stdin.on('error', () => {});
    const finish = async code => {
      if (settled) return;
      settled = true;
      clearTimeout(timer); clearTimeout(finishTimer);
      await cleanup;
      if (output && !output.destroyed) await new Promise(done => output.end(done));
      resolve({ code: streamError ? 1 : code ?? 1, stdout: Buffer.concat(chunks).toString('utf8'), stderr: Buffer.concat(errors).toString('utf8') + (streamError ? `\n${streamError.message}` : ''), timedOut, cleanupUnconfirmed, pid: child.pid });
    };
    child.on('error', error => { clearTimeout(timer); output?.end(); reject(error); });
    child.on('close', finish);
    if (opts.timeoutMs) timer = setTimeout(() => {
      timedOut = true;
      cleanup = (async () => {
        if (opts.cleanupHelper) { cleanupUnconfirmed = true; child.kill(); return; }
        if (process.platform === 'win32') {
          try {
            const result = await run('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { timeoutMs: 10000, cleanupHelper: true });
            if (result.code !== 0 || result.timedOut) { cleanupUnconfirmed = true; errors.push(Buffer.from(`\n进程树终止未确认：${result.stderr}`)); }
          } catch (error) { cleanupUnconfirmed = true; errors.push(Buffer.from(`\n进程树终止失败：${error.message}`)); }
        } else {
          try { process.kill(-child.pid, 'SIGKILL'); } catch (error) { if (error.code !== 'ESRCH') { cleanupUnconfirmed = true; errors.push(Buffer.from(error.message)); } }
        }
      })();
      cleanup.finally(() => {
        if (settled) return;
        // A failed cleanup never leaves the polling call hanging forever. The watcher
        // latches cleanupUnconfirmed and refuses subsequent work until checked locally.
        finishTimer = setTimeout(() => {
          cleanupUnconfirmed = true;
          child.kill(); child.stdin.destroy(); child.stdout.destroy(); child.stderr.destroy();
          void finish(1);
        }, 2000);
      });
    }, opts.timeoutMs);
    child.stdin.end(opts.input ?? '');
  });
}
async function exists(file) { try { await access(file); return true; } catch (error) { if (error.code === 'ENOENT') return false; throw error; } }
function alive(pid) { try { process.kill(pid, 0); return true; } catch (error) { return error.code !== 'ESRCH'; } }
function timestamp(now) { return new Date(now()).toISOString(); }
async function readState(file) {
  try {
    const value = JSON.parse(await readFile(file, 'utf8'));
    if (!value.comments || typeof value.comments !== 'object' || Array.isArray(value.comments)) throw new Error('state.json 的 comments 无效，拒绝重放');
    return value;
  } catch (error) { if (error.code === 'ENOENT') return { comments: {} }; throw error; }
}
async function saveState(file, state) {
  const temp = `${file}.${randomUUID()}.tmp`;
  await writeFile(temp, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 });
  await rename(temp, file);
}
async function acquireLock(stateDir, pid, isProcessAlive) {
  await mkdir(stateDir, { recursive: true });
  const file = path.join(stateDir, 'lock');
  const content = JSON.stringify({ pid, token: randomUUID() });
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const handle = await open(file, 'wx', 0o600);
      try { await handle.writeFile(content); } finally { await handle.close(); }
      return async () => { try { if (await readFile(file, 'utf8') === content) await unlink(file); } catch (error) { if (error.code !== 'ENOENT') throw error; } };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      // Serialize stale-lock recovery so two reapers cannot remove a fresh lock.
      const recoveryFile = `${file}.recover`;
      let recovery;
      try { recovery = await open(recoveryFile, 'wx', 0o600); }
      catch (recoveryError) {
        if (recoveryError.code !== 'EEXIST') throw recoveryError;
        let recoveryOwner;
        try { recoveryOwner = JSON.parse(await readFile(recoveryFile, 'utf8')).pid; } catch {}
        if (Number.isInteger(recoveryOwner) && isProcessAlive(recoveryOwner)) return null;
        throw new Error('lock.recover 的恢复进程已退出或身份无法确认；请先在本机核验无 watcher/Codex 后移除该文件');
      }
      try {
        await recovery.writeFile(JSON.stringify({ pid, token: randomUUID() }));
        let previous;
        try { previous = JSON.parse(await readFile(file, 'utf8')); }
        catch (readError) { if (readError.code === 'ENOENT') continue; return null; }
        const owner = typeof previous === 'number' ? previous : previous.pid;
        if (!Number.isInteger(owner) || owner <= 0 || isProcessAlive(owner)) return null;
        await unlink(file);
      } finally {
        await recovery.close();
        await unlink(recoveryFile);
      }
    }
  }
  return null;
}
function validateConfig(input) {
  const config = { ...defaults, ...input };
  if (config.repo !== REPO || config.baseBranch !== 'v3-lab') throw new Error('只允许协议指定仓库和 v3-lab base');
  for (const field of ['allowedAuthors', 'headPrefixes', 'codexArgs']) if (!Array.isArray(config[field]) || !config[field].every(x => typeof x === 'string')) throw new Error(`${field} 必须是字符串数组`);
  if (!config.allowedAuthors.length || !config.headPrefixes.length || config.headPrefixes.some(x => !['claude/', 'codex/'].includes(x))) throw new Error('作者或分支白名单无效');
  for (const field of ['maxRounds', 'codexTimeoutMinutes', 'summaryMaxChars', 'pollSeconds']) if (!Number.isFinite(config[field]) || config[field] <= 0) throw new Error(`${field} 必须大于零`);
  if (!Number.isInteger(config.maxRounds) || config.maxRounds > 4) throw new Error('最多允许 4 轮');
  if (!config.repoPath || !config.worktreeRoot || !path.isAbsolute(config.repoPath) || !path.isAbsolute(config.worktreeRoot)) throw new Error('repoPath 与 worktreeRoot 必须是绝对路径');
  const relative = path.relative(config.repoPath, config.worktreeRoot);
  if (!relative || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))) throw new Error('worktreeRoot 必须位于主仓库外');
  // Configuration cannot replace the dedicated cwd/output/stdin boundary or bypass sandboxing.
  const forbidden = /^(?:-C|--cd|-o|--output-last-message|--json|--worktree|--add-dir|--dangerously-bypass-approvals-and-sandbox|--dangerously-bypass-hook-trust)(?:=|$)/;
  if (config.codexArgs.some(x => forbidden.test(x) || x === 'danger-full-access' || x === '-')) throw new Error('codexArgs 不得覆盖执行/输出边界或关闭沙箱');
  return config;
}

export async function runOnce({ config: input, stateDir = path.join(here, '.state'), run: execute = run, now = Date.now, pid = process.pid, isProcessAlive = alive, log = console.log, template, dryRun = false } = {}) {
  const config = validateConfig(input);
  let release;
  if (!dryRun) {
    release = await acquireLock(stateDir, pid, isProcessAlive);
    if (!release) return { status: 'locked' };
  }
  const stateFile = path.join(stateDir, 'state.json');
  const invoke = async (cmd, args, opts = {}) => {
    const result = await execute(cmd, args, opts);
    return { code: result.code ?? result.exitCode ?? 0, stdout: result.stdout ?? '', stderr: result.stderr ?? '', timedOut: result.timedOut ?? false, cleanupUnconfirmed: result.cleanupUnconfirmed ?? false, pid: result.pid };
  };
  const checked = async (cmd, args, opts) => {
    const result = await invoke(cmd, args, opts);
    if (result.code !== 0 || result.timedOut) throw new Error(`${cmd} ${args.join(' ')} 失败\n${result.stderr || result.stdout}`);
    return result.stdout;
  };
  const gh = args => checked('gh', args);
  const reaction = (id, content) => gh(['api', '-X', 'POST', `repos/${config.repo}/issues/comments/${id}/reactions`, '-f', `content=${content}`]);
  const post = async (pr, body) => {
    const file = path.join(stateDir, 'logs', `reply-${pr}-${randomUUID()}.md`);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, body, { mode: 0o600 });
    await gh(['pr', 'comment', String(pr), '--repo', config.repo, '--body-file', file]);
  };
  try {
    const state = await readState(stateFile);
    const promptTemplate = template ?? await readFile(path.join(here, 'CODEX_ROUND_PROMPT.md'), 'utf8');
    const deliver = async (id, entry) => {
      await post(entry.pr, entry.notification.body);
      if (entry.notification.reaction) await reaction(id, entry.notification.reaction);
      entry.notification.pending = false;
      await saveState(stateFile, state);
    };
    if (!dryRun) for (const [id, entry] of Object.entries(state.comments)) {
      if (entry.notification?.pending) await deliver(id, entry);
    }
    if (await exists(path.join(stateDir, 'cleanup-blocked.json'))) { log('上次进程树清理未确认；需本机检查后移除 cleanup-blocked.json'); return { status: 'cleanup-blocked' }; }
    // Accepted comments never replay, even after a crash. Report abandoned work separately.
    if (!dryRun) for (const [id, entry] of Object.entries(state.comments)) {
      if (entry.status === 'in_progress' && (!Number.isFinite(Date.parse(entry.startedAt)) || now() - Date.parse(entry.startedAt) > config.codexTimeoutMinutes * 120000)) {
        entry.status = 'failed'; entry.finishedAt = timestamp(now); entry.reason = '上次 in_progress 已超时；为避免重复执行不会自动重跑';
        if (Number.isSafeInteger(entry.pr) && Number.isSafeInteger(entry.round) && /^\d+$/.test(id)) {
          entry.notification = { pending: true, body: formatReply({ round: entry.round, status: 'failed', reason: entry.reason, summaryMaxChars: config.summaryMaxChars }), reaction: 'confused' };
          await saveState(stateFile, state);
          await deliver(id, entry);
        } else await saveState(stateFile, state);
        log(entry.reason);
      }
    }
    const prs = JSON.parse(await gh(['pr', 'list', '--repo', config.repo, '--state', 'open', '--label', 'agent-relay', '--json', 'number,headRefName,baseRefName,headRefOid,isCrossRepository,labels']));
    for (const pr of prs) {
      if (!Number.isSafeInteger(pr.number) || pr.number < 1 || !isEligiblePr(pr, config)) { log(`跳过 PR #${pr.number}：不满足接力条件`); continue; }
      const pages = JSON.parse(await gh(['api', `repos/${config.repo}/issues/${pr.number}/comments`, '--paginate', '--slurp']));
      const comments = pages.flat().filter(comment => Number.isSafeInteger(comment.id) && comment.id > 0 && parseInstruction(comment.body) && config.allowedAuthors.includes(comment.user?.login) && !Object.hasOwn(state.comments, String(comment.id))).sort((a, b) => Date.parse(a.created_at ?? 0) - Date.parse(b.created_at ?? 0) || Number(a.id) - Number(b.id));
      const comment = comments[0];
      if (!comment) continue;
      const { round, instruction } = parseInstruction(comment.body);
      const worktree = path.join(config.worktreeRoot, `pr-${pr.number}`);
      const codexArgs = ['exec', '--cd', worktree, ...config.codexArgs, '--json', '--output-last-message', path.join(stateDir, 'logs', `pr-${pr.number}-round-${round}.last.txt`), '-'];
      const contract = JSON.parse(await gh(['pr', 'view', String(pr.number), '--repo', config.repo, '--json', 'body'])).body ?? '';
      const prompt = renderPrompt(promptTemplate, { pr_number: pr.number, branch: pr.headRefName, round, contract, instruction });
      if (dryRun) {
        const preview = { status: 'dry-run', pr: pr.number, commentId: comment.id, round, prompt, commands: round > config.maxRounds ? [['gh', 'pr', 'edit', String(pr.number), '--add-label', 'relay-needs-human'], ['gh', 'pr', 'comment', String(pr.number)]] : [['gh', 'api', '-X', 'POST', '.../reactions', '-f', 'content=eyes'], ['git', 'fetch', 'origin', pr.headRefName], ['git', 'worktree', 'add', worktree], ['codex', ...codexArgs], ['git', 'push', 'origin', `HEAD:refs/heads/${pr.headRefName}`], ['gh', 'pr', 'comment', String(pr.number)]] };
        log(JSON.stringify(preview, null, 2));
        return preview;
      }
      if (round > config.maxRounds) {
        // Record before external effects: a partial failure cannot cause duplicate work.
        state.comments[comment.id] = { status: 'in_progress', pr: pr.number, round, startedAt: timestamp(now) };
        await saveState(stateFile, state);
        await gh(['pr', 'edit', String(pr.number), '--repo', config.repo, '--add-label', 'relay-needs-human']);
        await post(pr.number, redact(`<!-- relay:to-human -->\n${config.mention}\n第 ${round} 轮超过上限 ${config.maxRounds}，已停止。请决定缩小任务并另开 PR，或人工接手。`, config.summaryMaxChars).text);
        state.comments[comment.id] = { ...state.comments[comment.id], status: 'human', finishedAt: timestamp(now), sha: 'none' };
        await saveState(stateFile, state);
        return { status: 'human', pr: pr.number, round };
      }
      await reaction(comment.id, 'eyes');
      state.comments[comment.id] = { status: 'in_progress', pr: pr.number, round, startedAt: timestamp(now) };
      await saveState(stateFile, state);
      let status = 'failed', summary = '', reason = '', details = '', startSha = '', sha = 'none', commitCount = 0, files = [];
      const git = args => checked('git', args, { cwd: worktree });
      const remote = `origin/${pr.headRefName}`;
      const fetchArgs = ['fetch', 'origin', `refs/heads/${pr.headRefName}:refs/remotes/origin/${pr.headRefName}`];
      try {
        if (!contract.startsWith('<!-- relay:contract v1 -->')) throw new Error('PR 描述缺少 relay:contract v1 合同');
        const origin = (await checked('git', ['remote', 'get-url', 'origin'], { cwd: config.repoPath })).trim();
        if (!/^(?:https:\/\/github\.com\/|git@github\.com:|ssh:\/\/git@github\.com\/)Ritou-Lynx\/here-i-am(?:\.git)?\/?$/i.test(origin)) throw new Error('repoPath 的 origin 不是协议仓库');
        const pushOrigin = (await checked('git', ['remote', 'get-url', '--push', 'origin'], { cwd: config.repoPath })).trim();
        if (pushOrigin !== origin) throw new Error('origin 的推送目标与读取目标不一致');
        const common = (await checked('git', ['rev-parse', '--git-common-dir'], { cwd: config.repoPath })).trim();
        const repoCommon = await realpath(path.resolve(config.repoPath, common));
        await checked('git', fetchArgs, { cwd: config.repoPath });
        if (!await exists(worktree)) {
          await mkdir(config.worktreeRoot, { recursive: true });
          const local = await invoke('git', ['show-ref', '--verify', '--quiet', `refs/heads/${pr.headRefName}`], { cwd: config.repoPath });
          if (local.code > 1) throw new Error('无法核对本地分支');
          await checked('git', ['worktree', 'add', worktree, ...(local.code === 0 ? [pr.headRefName] : ['-b', pr.headRefName, remote])], { cwd: config.repoPath });
        }
        const treeCommon = (await git(['rev-parse', '--git-common-dir'])).trim();
        if (await realpath(path.resolve(worktree, treeCommon)) !== repoCommon) throw new Error('已有 worktree 不属于指定仓库');
        const top = (await git(['rev-parse', '--show-toplevel'])).trim();
        if (await realpath(top) !== await realpath(worktree)) throw new Error('worktree 路径不是独立仓库根');
        if ((await git(['branch', '--show-current'])).trim() !== pr.headRefName) throw new Error('worktree 分支与 PR 不一致');
        if ((await git(['status', '--porcelain'])).trim()) throw new Error('已有 worktree 不干净，保留原样');
        if (Number((await git(['rev-list', '--count', `${remote}..HEAD`])).trim()) !== 0) throw new Error('已有 worktree 本地领先远端，保留原样');
        await git(['merge', '--ff-only', remote]);
        startSha = (await git(['rev-parse', 'HEAD'])).trim();
        const last = codexArgs[codexArgs.indexOf('--output-last-message') + 1];
        const stdoutFile = path.join(stateDir, 'logs', `pr-${pr.number}-round-${round}.jsonl`);
        await mkdir(path.dirname(last), { recursive: true });
        // Never accept a leftover answer from an earlier interrupted run.
        try { await unlink(last); } catch (error) { if (error.code !== 'ENOENT') throw error; }
        const result = await invoke('codex', codexArgs, { cwd: worktree, input: prompt, env: { SKIP_PROJECT_STATE: '1' }, timeoutMs: config.codexTimeoutMinutes * 60000, stdoutFile });
        if (result.stdout) await writeFile(stdoutFile, result.stdout, { mode: 0o600 });
        await writeFile(path.join(stateDir, 'logs', `pr-${pr.number}-round-${round}.stderr.txt`), result.stderr, { mode: 0o600 });
        details = result.stderr;
        if (result.cleanupUnconfirmed) {
          await writeFile(path.join(stateDir, 'cleanup-blocked.json'), JSON.stringify({ pid: result.pid, pr: pr.number, round, occurredAt: timestamp(now) }) + '\n', { mode: 0o600 });
          throw new Error('Codex 超时且进程树清理未确认，后续轮询已阻止，需本机检查');
        }
        if (result.timedOut) throw new Error('Codex 超时，已请求终止进程树');
        if (result.code !== 0) throw new Error(`Codex 退出码 ${result.code}\n${result.stderr}`);
        try { summary = await readFile(last, 'utf8'); } catch (error) { if (error.code === 'ENOENT') throw new Error('Codex 未输出最后消息'); throw error; }
        if (!summary.trim()) throw new Error('Codex 最后消息为空');
        if ((await git(['branch', '--show-current'])).trim() !== pr.headRefName) throw new Error('Codex 改变了 worktree 分支，拒绝提交或推送');
        await git(['merge-base', '--is-ancestor', startSha, 'HEAD']);
        status = /^STATUS: blocked\s*$/.test(summary.split(/\r?\n/, 1)[0]) ? 'blocked' : 'done';
        const hasChanges = (await git(['status', '--porcelain'])).trim();
        if (hasChanges) {
          const proposedMessage = /^COMMIT:[ \t]*([^\r\n]*)/m.exec(summary)?.[1].trim();
          const commitMessage = proposedMessage && proposedMessage !== '无' ? proposedMessage : `relay: 第 ${round} 轮`;
          const commitOpts = { cwd: worktree, env: { SKIP_PROJECT_STATE: '1' } };
          const staged = await invoke('git', ['add', '-A'], commitOpts);
          const committed = staged.code === 0 && !staged.timedOut
            ? await invoke('git', ['commit', '-m', commitMessage, '-m', `relay: PR #${pr.number} 第 ${round} 轮`], commitOpts)
            : staged;
          if (committed.code !== 0 || committed.timedOut) {
            details = [committed.stderr, committed.stdout, await git(['status', '--short'])].filter(Boolean).join('\n');
            throw new Error(`watcher ${staged.code === 0 ? '提交' : '暂存'}失败（退出码 ${committed.code}），不推送`);
          }
          if ((await git(['status', '--porcelain'])).trim()) {
            details = await git(['status', '--short']);
            throw new Error('watcher 提交后仍有未提交改动，不推送');
          }
          if ((await git(['branch', '--show-current'])).trim() !== pr.headRefName) throw new Error('提交后 worktree 分支改变，拒绝推送');
          await git(['merge-base', '--is-ancestor', startSha, 'HEAD']);
        }
        commitCount = Number((await git(['rev-list', '--count', `${startSha}..HEAD`])).trim());
        if (!Number.isSafeInteger(commitCount) || commitCount < 0) throw new Error('提交计数无效');
        if (commitCount > 0) {
          const pushArgs = ['push', 'origin', `HEAD:refs/heads/${pr.headRefName}`];
          const firstPush = await invoke('git', pushArgs, { cwd: worktree });
          if (firstPush.code !== 0) {
            await checked('git', fetchArgs, { cwd: config.repoPath });
            const merged = await invoke('git', ['merge', '--no-edit', remote], { cwd: worktree, env: { SKIP_PROJECT_STATE: '1' } });
            if (merged.code !== 0) {
              const aborted = await invoke('git', ['merge', '--abort'], { cwd: worktree });
              throw new Error(`推送被拒且合并冲突\n${merged.stderr || merged.stdout}\n${aborted.code ? 'merge --abort 失败，请人工检查' : '已 merge --abort'}`);
            }
            await git(pushArgs);
          }
        }
        sha = (await git(['rev-parse', 'HEAD'])).trim().slice(0, 12);
        commitCount = Number((await git(['rev-list', '--count', `${startSha}..HEAD`])).trim());
        files = (await git(['diff', '--name-only', `${startSha}..HEAD`])).trim().split(/\r?\n/).filter(Boolean);
      } catch (error) {
        status = 'failed'; reason = error.message.split(/\r?\n/, 1)[0]; sha = 'none';
        if (!details) details = error.message.split(/\r?\n/).slice(1).join('\n');
      }
      await mkdir(path.join(stateDir, 'logs'), { recursive: true });
      await writeFile(path.join(stateDir, 'logs', `pr-${pr.number}-round-${round}.result.json`), JSON.stringify({ status, sha, startSha, commitCount, files, summary, reason, details }, null, 2) + '\n', { mode: 0o600 });
      const body = formatReply({ round, status, sha, startSha: startSha.slice(0, 12), commitCount, files, summary, reason, details, summaryMaxChars: config.summaryMaxChars });
      state.comments[comment.id] = { ...state.comments[comment.id], status, sha, finishedAt: timestamp(now), notification: { pending: true, body, reaction: ['done', 'blocked'].includes(status) ? 'rocket' : 'confused' } };
      await saveState(stateFile, state);
      await deliver(comment.id, state.comments[comment.id]);
      return { status, pr: pr.number, commentId: comment.id, round, sha, reason };
    }
    log('无待处理');
    return { status: 'idle' };
  } finally { await release?.(); }
}

export async function main(argv = process.argv.slice(2), { executeOnce = runOnce, log = console.log } = {}) {
  let loop = false, dryRun = false, configFile = path.join(here, '.state', 'config.json');
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--loop') loop = true;
    else if (argv[i] === '--once') loop = false;
    else if (argv[i] === '--dry-run') dryRun = true;
    else if (argv[i] === '--config' && argv[i + 1]) configFile = path.resolve(argv[++i]);
    else throw new Error(`未知参数：${argv[i]}`);
  }
  let input;
  try { input = JSON.parse(await readFile(configFile, 'utf8')); }
  catch (error) {
    if (!dryRun || error.code !== 'ENOENT') throw error;
    // Preview discovery works before installation, without creating local configuration.
    input = { ...defaults, repoPath: path.resolve(here, '../..'), worktreeRoot: path.join(os.homedir(), 'relay-worktrees') };
  }
  const config = validateConfig(input);
  do {
    const result = await executeOnce({ config, stateDir: path.dirname(configFile), dryRun, log });
    if (!['idle', 'locked', 'dry-run'].includes(result.status)) log(redact(`PR #${result.pr ?? '-'}: ${result.status}${result.reason ? ` - ${result.reason}` : ''}`).text);
    if (!loop || dryRun) return ['failed', 'cleanup-blocked'].includes(result.status) ? 1 : 0;
    if (loop && !dryRun) await new Promise(resolve => setTimeout(resolve, config.pollSeconds * 1000));
  } while (loop && !dryRun);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().then(code => { process.exitCode = code; }).catch(error => { console.error(redact(error.message).text); process.exitCode = 1; });
}
