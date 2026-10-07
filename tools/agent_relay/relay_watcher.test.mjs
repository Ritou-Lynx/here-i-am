import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, access } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { runOnce } from './relay_watcher.mjs';

const START = 'a'.repeat(40);
const END = 'b'.repeat(40);
const NOW = Date.parse('2026-10-07T02:00:00.000Z');
const template = '# Test template\n---\nPR {{pr_number}} branch {{branch}} round {{round}}\nCONTRACT\n{{contract}}\nINSTRUCTION\n{{instruction}}\n---\n';
const contract = '<!-- relay:contract v1 -->\nOnly change tools/agent_relay/.';
const instruction = 'Run the requested tests and commit the scoped change.';
const basePr = { number: 71, headRefName: 'claude/relay-test', baseRefName: 'v3-lab', headRefOid: START, isCrossRepository: false, labels: [{ name: 'agent-relay' }] };
const baseComment = { id: 101, user: { login: 'Ritou-Lynx' }, body: `<!-- relay:to-codex round=1 -->\n${instruction}`, created_at: '2026-10-07T01:00:00Z' };

async function exists(file) {
  try { await access(file); return true; } catch (error) { if (error.code === 'ENOENT') return false; throw error; }
}

async function fixture(t, scenario = {}) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'agent-relay-test-'));
  t.after(async () => {
    assert.equal(path.dirname(path.resolve(root)), path.resolve(os.tmpdir()));
    assert.ok(path.basename(root).startsWith('agent-relay-test-'));
    await rm(root, { recursive: true, force: true });
  });
  const stateDir = path.join(root, 'state');
  const config = {
    repo: 'Ritou-Lynx/here-i-am', baseBranch: 'v3-lab', headPrefixes: ['claude/', 'codex/'],
    allowedAuthors: ['Ritou-Lynx'], repoPath: path.join(root, 'clone'), worktreeRoot: path.join(root, 'worktrees'),
    maxRounds: 4, codexTimeoutMinutes: 60, codexArgs: ['--sandbox', 'workspace-write'], summaryMaxChars: 6000,
    mention: '@Ritou-Lynx',
  };
  await mkdir(path.join(config.repoPath, '.git'), { recursive: true });
  if (scenario.wrongCommonDir) await mkdir(path.join(root, 'unrelated-repo', '.git'), { recursive: true });
  const worktree = path.join(config.worktreeRoot, 'pr-71');
  if (scenario.existing) await mkdir(worktree, { recursive: true });
  if (scenario.state || scenario.lock) {
    await mkdir(stateDir, { recursive: true });
    if (scenario.state) await writeFile(path.join(stateDir, 'state.json'), JSON.stringify(scenario.state));
    if (scenario.lock) await writeFile(path.join(stateDir, 'lock'), String(scenario.lock));
  }
  const calls = [];
  const posts = [];
  const output = [];
  let executed = false;
  let pushes = 0;
  let commentAttempts = 0;
  const run = async (cmd, args, opts = {}) => {
    const call = { cmd, args: [...args], opts };
    calls.push(call);
    const ok = (stdout = '') => ({ code: 0, stdout, stderr: '' });
    if (cmd === 'gh') {
      if (args[0] === 'pr' && args[1] === 'list') return ok(JSON.stringify(scenario.prs ?? [basePr]));
      if (args[0] === 'pr' && args[1] === 'view') return ok(JSON.stringify({ body: contract }));
      if (args[0] === 'api' && args.some(arg => /\/issues\/\d+\/comments$/.test(arg))) return ok(JSON.stringify(scenario.comments ?? [baseComment]));
      if (args[0] === 'api' && args.some(arg => arg.endsWith('/reactions'))) return ok('{}');
      if (args[0] === 'pr' && args[1] === 'edit') return ok();
      if (args[0] === 'pr' && args[1] === 'comment') {
        assert.ok(args.includes('--body-file'), 'public result must use a body file');
        call.body = await readFile(args[args.indexOf('--body-file') + 1], 'utf8');
        commentAttempts += 1;
        if (scenario.failFirstComment && commentAttempts === 1) return { code: 1, stdout: '', stderr: 'comment delivery temporarily failed' };
        posts.push(call.body);
        return ok();
      }
    }
    if (cmd === 'git') {
      if (args[0] === 'remote' && args[1] === 'get-url' && args.includes('origin')) return ok(`${scenario.wrongOrigin || (scenario.wrongPushOrigin && args.includes('--push')) ? 'https://github.com/other-owner/unrelated.git' : 'https://github.com/Ritou-Lynx/here-i-am.git'}\n`);
      if (args[0] === 'merge-base' && args.includes('--is-ancestor')) return scenario.rewrittenAncestry && executed ? { code: 1, stdout: '', stderr: '' } : ok();
      if (args[0] === 'rev-parse' && args.includes('--git-common-dir')) return ok(`${scenario.wrongCommonDir && opts.cwd === worktree ? path.join(root, 'unrelated-repo', '.git') : path.join(config.repoPath, '.git')}\n`);
      if (args[0] === 'rev-parse' && args.includes('--show-toplevel')) return ok(`${scenario.wrongRoot && opts.cwd === worktree ? config.repoPath : opts.cwd}\n`);
      if (args[0] === 'fetch') return ok();
      if (args[0] === 'show-ref') return { code: 1, stdout: '', stderr: '' };
      if (args[0] === 'worktree' && args[1] === 'add') { await mkdir(worktree, { recursive: true }); return ok(); }
      if (args[0] === 'branch' && args.includes('--show-current')) return ok(`${basePr.headRefName}\n`);
      if (args[0] === 'rev-parse') return ok(`${args.at(-1).startsWith('origin/') ? START : (executed && scenario.newCommit !== false ? END : START)}\n`);
      if (args[0] === 'status') return ok(executed ? (scenario.dirtyAfter ? ' M tools/agent_relay/example.mjs\n' : '') : (scenario.dirtyBefore ? ' M local-work.txt\n' : ''));
      if (args[0] === 'rev-list' && args.includes('--count')) return ok(`${args.some(arg => arg.includes('origin/')) ? (scenario.ahead ? 1 : 0) : (scenario.newCommit === false ? 0 : 1)}\n`);
      if (args[0] === 'diff' && args.includes('--name-only')) return ok('tools/agent_relay/example.mjs\n');
      if (args[0] === 'log') return ok(`${END} scoped relay change\n`);
      if (args[0] === 'merge') {
        if (args.includes('--abort') || args.includes('--ff-only')) return ok();
        return scenario.mergeConflict ? { code: 1, stdout: 'CONFLICT in example.mjs\n', stderr: 'merge failed' } : ok();
      }
      if (args[0] === 'push') {
        pushes += 1;
        return scenario.rejectPush && pushes === 1 ? { code: 1, stdout: '', stderr: 'rejected (fetch first)' } : ok();
      }
    }
    if (cmd === 'codex') {
      executed = true;
      const state = JSON.parse(await readFile(path.join(stateDir, 'state.json'), 'utf8'));
      assert.equal(state.comments['101'].status, 'in_progress', 'receipt must persist before Codex starts');
      if (scenario.checkCodex) await scenario.checkCodex(call, state);
      const last = args[args.indexOf('--output-last-message') + 1];
      assert.ok(args.includes('--output-last-message'));
      if (!scenario.noLastMessage) {
        await mkdir(path.dirname(last), { recursive: true });
        await writeFile(last, scenario.lastMessage ?? 'STATUS: done\nSUMMARY:\n- Updated relay.\nVERIFY:\n- tests passed\nQUESTIONS:\n- 无');
      }
      if (opts.stdoutFile) await writeFile(opts.stdoutFile, '{"type":"test-event"}\n');
      return { code: scenario.codexCode ?? 0, stdout: '', stderr: scenario.codexError ?? '', timedOut: scenario.timedOut ?? false, cleanupUnconfirmed: scenario.cleanupUnconfirmed ?? false };
    }
    throw new Error(`Unexpected subprocess: ${cmd} ${JSON.stringify(args)}`);
  };
  return {
    config, stateDir, calls, posts, output, worktree,
    once: (extra = {}) => runOnce({ config, stateDir, run, now: () => NOW, pid: 424242, isProcessAlive: () => Boolean(scenario.liveLock), log: (...args) => output.push(args), template, ...extra }),
    state: async () => JSON.parse(await readFile(path.join(stateDir, 'state.json'), 'utf8')),
  };
}
const isCodex = call => call.cmd === 'codex';
const isPush = call => call.cmd === 'git' && call.args[0] === 'push';
const isReaction = (call, name) => call.cmd === 'gh' && call.args.includes(`content=${name}`);
const index = (calls, predicate) => calls.findIndex(predicate);

// Checklist items 1, 2 and 10 are covered by relay_core.test.mjs.
test('3: unapproved author is ignored without a reaction or Codex execution', async t => {
  const f = await fixture(t, { comments: [{ ...baseComment, user: { login: 'untrusted-author' } }] });
  assert.equal((await f.once()).status, 'idle');
  assert.equal(f.calls.some(isCodex), false);
  assert.equal(f.calls.some(call => call.args.some(arg => arg.endsWith('/reactions'))), false);
  assert.deepEqual(f.posts, []);
});

test('4: an already processed comment is never replayed', async t => {
  const f = await fixture(t, { state: { comments: { 101: { status: 'done', pr: 71, round: 1, sha: END, finishedAt: '2026-10-07T01:30:00.000Z' } } } });
  assert.equal((await f.once()).status, 'idle');
  assert.equal(f.calls.some(isCodex), false);
  assert.deepEqual(f.posts, []);
});

test('4: stale in_progress receipt becomes failed, is reported, and is not replayed', async t => {
  const f = await fixture(t, { state: { comments: { 101: { status: 'in_progress', pr: 71, round: 1, startedAt: '2026-10-06T22:00:00.000Z' } } } });
  await f.once();
  assert.equal(f.calls.some(isCodex), false);
  assert.equal((await f.state()).comments['101'].status, 'failed');
  assert.ok(f.posts.some(body => /^<!-- relay:to-claude round=1 status=failed sha=none -->/m.test(body)));
  const postCount = f.posts.length;
  await f.once();
  assert.equal(f.posts.length, postCount, 'stale failure must be reported only once');
});

test('4: recent in_progress receipt is not replayed or prematurely failed', async t => {
  const f = await fixture(t, { state: { comments: { 101: { status: 'in_progress', pr: 71, round: 1, startedAt: '2026-10-07T01:30:00.000Z' } } } });
  await f.once();
  assert.equal(f.calls.some(isCodex), false);
  assert.equal((await f.state()).comments['101'].status, 'in_progress');
  assert.deepEqual(f.posts, []);
});

test('5: fifth round labels the PR and reports to-human without executing Codex', async t => {
  const f = await fixture(t, { comments: [{ ...baseComment, body: '<!-- relay:to-codex round=5 -->\nPlease continue.' }] });
  await f.once();
  assert.equal(f.calls.some(isCodex), false);
  assert.ok(f.calls.some(call => call.cmd === 'gh' && call.args[0] === 'pr' && call.args[1] === 'edit' && call.args.includes('relay-needs-human')));
  assert.ok(f.posts.some(body => body.startsWith('<!-- relay:to-human -->') && body.includes('@Ritou-Lynx')));
  assert.notEqual((await f.state()).comments['101'].status, 'in_progress');
});

test('6: complete done round persists receipt, renders stdin, pushes and reports in order', async t => {
  const f = await fixture(t);
  assert.equal((await f.once()).status, 'done');
  const { calls } = f;
  const eyes = index(calls, call => isReaction(call, 'eyes'));
  const fetch = index(calls, call => call.cmd === 'git' && call.args[0] === 'fetch');
  const worktree = index(calls, call => call.cmd === 'git' && call.args[0] === 'worktree');
  const codex = index(calls, isCodex);
  const push = index(calls, isPush);
  const post = index(calls, call => call.cmd === 'gh' && call.args[1] === 'comment');
  const rocket = index(calls, call => isReaction(call, 'rocket'));
  assert.ok(eyes >= 0 && eyes < fetch && fetch < worktree && worktree < codex && codex < push && push < post && post < rocket);
  const execution = calls[codex];
  assert.equal(execution.opts.env.SKIP_PROJECT_STATE, '1');
  assert.ok(execution.opts.input.includes(contract));
  assert.ok(execution.opts.input.includes(instruction));
  assert.ok(execution.opts.input.includes('PR 71 branch claude/relay-test round 1'));
  assert.equal(execution.opts.input.includes('relay:to-codex'), false);
  assert.equal(execution.opts.input.includes('{{'), false);
  assert.equal(execution.args.at(-1), '-');
  assert.ok(execution.args.includes('--json'));
  assert.equal(execution.args[execution.args.indexOf('--cd') + 1], f.worktree);
  assert.equal(execution.opts.timeoutMs, 60 * 60 * 1000);
  assert.ok(execution.opts.stdoutFile.endsWith('.jsonl'));
  assert.ok(calls[push].args.includes('HEAD:refs/heads/claude/relay-test'));
  assert.equal(calls.some(call => call.args.some(arg => arg.includes('--force'))), false);
  assert.match(f.posts[0].split(/\r?\n/)[0], /^<!-- relay:to-claude round=1 status=done sha=b{7,40} -->$/);
  assert.ok(f.posts[0].includes('tools/agent_relay/example.mjs'));
  assert.equal((await f.state()).comments['101'].status, 'done');
  assert.equal(await exists(path.join(f.stateDir, 'lock')), false);
});

test('6: one pass selects the earliest unprocessed instruction and executes once globally', async t => {
  const f = await fixture(t, { prs: [basePr, { ...basePr, number: 72 }], comments: [
    { ...baseComment, id: 102, created_at: '2026-10-07T01:20:00Z', body: '<!-- relay:to-codex round=2 -->\nLater instruction.' }, baseComment,
  ] });
  assert.equal((await f.once()).status, 'done');
  assert.equal(f.calls.filter(isCodex).length, 1);
  assert.ok(f.calls.some(call => isReaction(call, 'eyes') && call.args.some(arg => arg.includes('/101/reactions'))));
  assert.equal((await f.state()).comments['102'], undefined);
});

test('7: Codex nonzero exit fails without push', async t => {
  const f = await fixture(t, { codexCode: 1, codexError: 'execution failed' });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isPush), false);
  assert.ok(f.calls.some(call => isReaction(call, 'confused')));
  assert.equal((await f.state()).comments['101'].status, 'failed');
  assert.equal(await exists(path.join(f.stateDir, 'lock')), false);
});

test('7: Codex timeout fails without push even if a final message was written', async t => {
  const f = await fixture(t, { timedOut: true, codexCode: 0 });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isPush), false);
  assert.ok(f.posts.length === 1);
});

test('7: missing final message fails without push', async t => {
  const f = await fixture(t, { noLastMessage: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isPush), false);
});

test('8: uncommitted output is dirty and never auto-committed or pushed', async t => {
  const f = await fixture(t, { dirtyAfter: true });
  assert.equal((await f.once()).status, 'dirty');
  assert.equal(f.calls.some(isPush), false);
  assert.equal(f.calls.some(call => call.cmd === 'git' && call.args[0] === 'commit'), false);
  assert.ok(f.posts[0].includes('tools/agent_relay/example.mjs'));
  assert.ok(f.calls.some(call => isReaction(call, 'confused')));
});

test('9: rejected push fetches, merges and retries without force', async t => {
  const f = await fixture(t, { rejectPush: true });
  assert.equal((await f.once()).status, 'done');
  const pushes = f.calls.map((call, i) => isPush(call) ? i : -1).filter(i => i >= 0);
  assert.equal(pushes.length, 2);
  const between = f.calls.slice(pushes[0] + 1, pushes[1]);
  assert.ok(between.some(call => call.cmd === 'git' && call.args[0] === 'fetch'));
  assert.ok(between.some(call => call.cmd === 'git' && call.args[0] === 'merge' && call.args.includes('--no-edit')));
  assert.equal(f.calls.some(call => call.args.some(arg => arg.includes('--force'))), false);
});

test('9: retry merge conflict aborts merge and fails without another push', async t => {
  const f = await fixture(t, { rejectPush: true, mergeConflict: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.filter(isPush).length, 1);
  assert.ok(f.calls.some(call => call.cmd === 'git' && call.args[0] === 'merge' && call.args.includes('--abort')));
  assert.ok(f.calls.some(call => isReaction(call, 'confused')));
});

test('11: live PID lock exits before any subprocess or mutation', async t => {
  const f = await fixture(t, { lock: 12345, liveLock: true });
  assert.equal((await f.once()).status, 'locked');
  assert.deepEqual(f.calls, []);
  assert.equal(await readFile(path.join(f.stateDir, 'lock'), 'utf8'), '12345');
});

test('12: dry-run renders a plan with no subprocess writes or persistent state', async t => {
  const f = await fixture(t);
  assert.equal((await f.once({ dryRun: true })).status, 'dry-run');
  assert.equal(f.calls.some(isCodex), false);
  assert.equal(f.calls.some(call => call.cmd === 'git'), false);
  assert.equal(f.calls.some(call => call.args.includes('POST') || call.args.includes('push') || call.args[1] === 'comment' || call.args[1] === 'edit'), false);
  assert.equal(await exists(f.stateDir), false);
  assert.equal(await exists(f.worktree), false);
  assert.ok(JSON.stringify(f.output).includes(instruction));
});

test('worktree guard: existing dirty worktree fails before merge or Codex', async t => {
  const f = await fixture(t, { existing: true, dirtyBefore: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isCodex), false);
  assert.equal(f.calls.some(call => call.cmd === 'git' && ['merge', 'reset', 'stash', 'push'].includes(call.args[0])), false);
});

test('worktree guard: locally ahead worktree fails without altering commits', async t => {
  const f = await fixture(t, { existing: true, ahead: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isCodex), false);
  assert.equal(f.calls.some(call => call.cmd === 'git' && ['merge', 'reset', 'stash', 'push'].includes(call.args[0])), false);
});

test('existing clean worktree is fast-forwarded before Codex', async t => {
  const f = await fixture(t, { existing: true });
  assert.equal((await f.once()).status, 'done');
  const ff = index(f.calls, call => call.cmd === 'git' && call.args[0] === 'merge' && call.args.includes('--ff-only'));
  assert.ok(ff >= 0 && ff < index(f.calls, isCodex));
  assert.equal(f.calls.some(call => call.cmd === 'git' && call.args[0] === 'worktree'), false);
});

test('blocked result with a new commit is pushed, reported blocked and gets rocket', async t => {
  const f = await fixture(t, { lastMessage: 'STATUS: blocked\nSUMMARY:\n- Partial change committed.\nQUESTIONS:\n- Need a product decision.' });
  assert.equal((await f.once()).status, 'blocked');
  assert.equal(f.calls.filter(isPush).length, 1);
  assert.match(f.posts[0], /^<!-- relay:to-claude round=1 status=blocked sha=b{7,40} -->/);
  assert.ok(f.calls.some(call => isReaction(call, 'rocket')));
});

test('done with no new commits does not push', async t => {
  const f = await fixture(t, { newCommit: false });
  assert.equal((await f.once()).status, 'done');
  assert.equal(f.calls.some(isPush), false);
});






test('repository guard: wrong origin fails before fetch, worktree creation or Codex', async t => {
  const f = await fixture(t, { wrongOrigin: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isCodex), false);
  assert.equal(f.calls.some(call => call.cmd === 'git' && ['fetch', 'worktree', 'merge', 'push'].includes(call.args[0])), false);
});

test('repository guard: worktree from another clone fails before Codex or push', async t => {
  const f = await fixture(t, { existing: true, wrongCommonDir: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isCodex), false);
  assert.equal(f.calls.some(isPush), false);
  assert.equal(f.calls.some(call => call.cmd === 'git' && call.args[0] === 'merge'), false);
});

test('repository guard: nested directory resolving to parent clone fails before Codex or push', async t => {
  const f = await fixture(t, { existing: true, wrongRoot: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isCodex), false);
  assert.equal(f.calls.some(isPush), false);
  assert.equal(f.calls.some(call => call.cmd === 'git' && call.args[0] === 'merge'), false);
});

test('11: concurrent stale-lock recovery executes at most one round', async t => {
  const f = await fixture(t, { lock: 12345, checkCodex: () => new Promise(resolve => setTimeout(resolve, 20)) });
  const live = owner => owner !== 12345;
  const results = await Promise.all([f.once({ pid: 424242, isProcessAlive: live }), f.once({ pid: 424243, isProcessAlive: live })]);
  assert.equal(f.calls.filter(isCodex).length, 1);
  assert.equal(f.posts.length, 1);
  assert.equal(results.filter(result => result.status === 'done').length, 1);
  assert.equal((await f.state()).comments['101'].status, 'done');
  assert.equal(await exists(path.join(f.stateDir, 'lock')), false);
});



test('repository guard: wrong pushurl fails before fetch or worktree mutation', async t => {
  const f = await fixture(t, { wrongPushOrigin: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isCodex), false);
  assert.equal(f.calls.some(call => call.cmd === 'git' && ['fetch', 'worktree', 'merge', 'push'].includes(call.args[0])), false);
});

test('history guard: rewritten start ancestry fails without push', async t => {
  const f = await fixture(t, { rewrittenAncestry: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.filter(isCodex).length, 1);
  assert.equal(f.calls.some(isPush), false);
  assert.equal((await f.state()).comments['101'].status, 'failed');
});

test('notification recovery: failed delivery retains done and retries without Codex replay', async t => {
  const f = await fixture(t, { failFirstComment: true });
  // A notification failure may reject the call or return the completed execution status.
  const [first] = await Promise.allSettled([f.once()]);
  if (first.status === 'fulfilled') assert.equal(first.value.status, 'done');
  const receipt = (await f.state()).comments['101'];
  assert.equal(receipt.status, 'done');
  assert.equal(receipt.notification.pending, true);
  assert.match(receipt.notification.body, /^<!-- relay:to-claude round=1 status=done /);
  assert.equal(receipt.notification.reaction, 'rocket');
  assert.equal(f.calls.filter(isCodex).length, 1);
  assert.equal(f.posts.length, 0);
  assert.equal(await exists(path.join(f.stateDir, 'lock')), false);
  await f.once();
  assert.equal(f.calls.filter(isCodex).length, 1, 'delivery retry cannot replay Codex');
  assert.equal(f.posts.length, 1, 'successful result posted once');
  assert.equal(f.calls.filter(call => isReaction(call, 'rocket')).length, 1);
  assert.equal((await f.state()).comments['101'].notification.pending, false);
  await f.once();
  assert.equal(f.posts.length, 1, 'completed delivery is not repeated');
});

test('timeout cleanup: unconfirmed termination latches and blocks later subprocesses', async t => {
  const f = await fixture(t, { timedOut: true, codexCode: 1, cleanupUnconfirmed: true });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isPush), false);
  assert.equal(await exists(path.join(f.stateDir, 'cleanup-blocked.json')), true);
  const callsBefore = f.calls.length;
  assert.equal((await f.once()).status, 'cleanup-blocked');
  assert.equal(f.calls.length, callsBefore, 'uncertain process cleanup must prevent every later subprocess');
});

test('11: empty recovery guard reports an explicit lock.recover error without subprocesses', async t => {
  const f = await fixture(t, { lock: 12345 });
  await writeFile(path.join(f.stateDir, 'lock.recover'), '');
  await assert.rejects(f.once(), /lock\.recover/);
  assert.deepEqual(f.calls, []);
});

test('timeout cleanup: latched run still retries pending failure notification without execution', async t => {
  const f = await fixture(t, { timedOut: true, codexCode: 1, cleanupUnconfirmed: true, failFirstComment: true });
  const [first] = await Promise.allSettled([f.once()]);
  if (first.status === 'fulfilled') assert.equal(first.value.status, 'failed');
  assert.equal(await exists(path.join(f.stateDir, 'cleanup-blocked.json')), true);
  const receipt = (await f.state()).comments['101'];
  assert.equal(receipt.status, 'failed');
  assert.equal(receipt.notification.pending, true);
  const callsBeforeRetry = f.calls.length;
  assert.equal((await f.once()).status, 'cleanup-blocked');
  assert.equal(f.calls.filter(isCodex).length, 1);
  assert.equal(f.calls.slice(callsBeforeRetry).some(call => call.cmd === 'git' || call.cmd === 'codex'), false);
  assert.equal(f.posts.length, 1);
  assert.match(f.posts[0], /^<!-- relay:to-claude round=1 status=failed sha=none -->/);
  assert.equal(f.calls.filter(call => isReaction(call, 'confused')).length, 1);
  assert.equal((await f.state()).comments['101'].notification.pending, false);
});
