import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, access, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { main, runOnce, validateConfig } from './relay_watcher.mjs';
// Include transport tests through the existing directory entrypoint.
import './relay_notify.test.mjs';

const START = 'a'.repeat(40);
const END = 'b'.repeat(40);
const NOW = Date.parse('2026-10-07T02:00:00.000Z');
const template = '# Test template\n---\nPR {{pr_number}} branch {{branch}} round {{round}}\nCONTRACT\n{{contract}}\nINSTRUCTION\n{{instruction}}\n---\n';
const contract = '<!-- relay:contract v1 -->\nOnly change tools/agent_relay/.';
const instruction = 'Run the requested tests and leave the scoped change for the watcher to commit.';
const basePr = { number: 71, title: 'Synthetic relay PR', headRefName: 'claude/relay-test', baseRefName: 'v3-lab', headRefOid: START, isCrossRepository: false, labels: [{ name: 'agent-relay' }] };
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
  const fetchCalls = [];
  let executed = false;
  let dirtyAfter = Boolean(scenario.dirtyAfter);
  let hasNewCommit = false;
  let head = START;
  let staged = false;
  let pushes = 0;
  let commentAttempts = 0;
  const run = async (cmd, args, opts = {}) => {
    const call = { cmd, args: [...args], opts };
    calls.push(call);
    const ok = (stdout = '') => ({ code: 0, stdout, stderr: '' });
    if (cmd === 'gh') {
      if (args[0] === 'pr' && args[1] === 'list') return ok(JSON.stringify(scenario.prs ?? [basePr]));
      if (args[0] === 'pr' && args[1] === 'view') return ok(JSON.stringify({ body: contract }));
      if (args[0] === 'api' && args.some(arg => /\/issues\/\d+\/comments$/.test(arg))) {
        const number = Number(args.find(arg => /\/issues\/\d+\/comments$/.test(arg)).match(/\/issues\/(\d+)/)[1]);
        if (scenario.failCommentsFor === number) return { code: 1, stderr: 'synthetic comment read failure' };
        return ok(JSON.stringify(scenario.commentsByPr?.[number] ?? scenario.comments ?? [baseComment]));
      }
      if (args[0] === 'api' && args.some(arg => arg.endsWith('/reactions'))) return ok('{}');
      if (args[0] === 'pr' && args[1] === 'edit') return ok();
      if (args[0] === 'pr' && args[1] === 'comment') {
        assert.ok(args.includes('--body-file'), 'public result must use a body file');
        call.body = await readFile(args[args.indexOf('--body-file') + 1], 'utf8');
        commentAttempts += 1;
        if (scenario.failFirstComment && commentAttempts === 1) return { code: 1, stdout: '', stderr: 'comment delivery temporarily failed' };
        posts.push(call.body);
        return ok(`https://github.com/${config.repo}/pull/71#issuecomment-${9000 + posts.length}`);
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
      if (args[0] === 'rev-parse') return ok(`${args.at(-1).startsWith('origin/') ? START : head}\n`);
      if (args[0] === 'status') return ok(executed ? (dirtyAfter ? `${staged ? 'M ' : ' M'} tools/agent_relay/example.mjs\n` : '') : (scenario.dirtyBefore ? ' M local-work.txt\n' : ''));
      if (args[0] === 'rev-list' && args.includes('--count')) return ok(`${args.some(arg => arg.includes('origin/')) ? (scenario.ahead ? 1 : 0) : (hasNewCommit ? 1 : 0)}\n`);
      if (args[0] === 'add') {
        assert.deepEqual(args, ['add', '-A']);
        if (scenario.addFailure) return { code: 1, stdout: '', stderr: 'cannot stage changes' };
        staged = true;
        return ok();
      }
      if (args[0] === 'commit') {
        assert.equal(staged, true, 'watcher must stage changes before committing');
        if (scenario.commitFailure) return { code: 1, stdout: '', stderr: 'pre-commit hook rejected changes' };
        dirtyAfter = false;
        staged = false;
        hasNewCommit = true;
        head = END;
        return ok(`[claude/relay-test ${END.slice(0, 7)}] watcher commit\n`);
      }
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
      hasNewCommit = scenario.newCommit !== false;
      head = hasNewCommit ? END : START;
      const state = JSON.parse(await readFile(path.join(stateDir, 'state.json'), 'utf8'));
      assert.equal(state.comments['101'].status, 'in_progress', 'receipt must persist before Codex starts');
      if (scenario.checkCodex) await scenario.checkCodex(call, state);
      const last = args[args.indexOf('--output-last-message') + 1];
      assert.ok(args.includes('--output-last-message'));
      if (!scenario.noLastMessage) {
        await mkdir(path.dirname(last), { recursive: true });
        await writeFile(last, scenario.lastMessage ?? 'STATUS: done\nSUMMARY:\n- Updated relay.\nVERIFY:\n- tests passed\nQUESTIONS:\n- 无');
      }
      if (opts.stdoutFile) await writeFile(opts.stdoutFile, scenario.codexOutput ?? '{"type":"test-event"}\n');
      return { code: scenario.codexCode ?? 0, stdout: '', stderr: scenario.codexError ?? '', timedOut: scenario.timedOut ?? false, cleanupUnconfirmed: scenario.cleanupUnconfirmed ?? false };
    }
    throw new Error(`Unexpected subprocess: ${cmd} ${JSON.stringify(args)}`);
  };
  const fetchImpl = async (url, opts) => {
    fetchCalls.push({ url, opts, body: JSON.parse(opts.body) });
    if (scenario.fetchImpl) return scenario.fetchImpl(url, opts, { calls, posts });
    return { status: 200, json: async () => ({ code: 200 }) };
  };
  return {
    config, stateDir, calls, posts, output, worktree, fetchCalls,
    once: (extra = {}) => runOnce({ config, stateDir, run, now: () => NOW, pid: 424242, isProcessAlive: () => Boolean(scenario.liveLock), log: (...args) => output.push(args), template, fetchImpl, ...extra }),
    state: async () => JSON.parse(await readFile(path.join(stateDir, 'state.json'), 'utf8')),
  };
}
const isCodex = call => call.cmd === 'codex';
const isPush = call => call.cmd === 'git' && call.args[0] === 'push';
const isCommit = call => call.cmd === 'git' && call.args[0] === 'commit';
const isAdd = call => call.cmd === 'git' && call.args[0] === 'add';
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
  const f = await fixture(t, { codexCode: 1, codexError: 'execution failed', dirtyAfter: true, newCommit: false });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isPush), false);
  assert.equal(f.calls.some(isAdd), false);
  assert.equal(f.calls.some(isCommit), false);
  assert.ok(f.calls.some(call => isReaction(call, 'confused')));
  assert.equal((await f.state()).comments['101'].status, 'failed');
  assert.equal(await exists(path.join(f.stateDir, 'lock')), false);
});

test('7: Codex timeout fails without push even if a final message was written', async t => {
  const f = await fixture(t, { timedOut: true, codexCode: 0, dirtyAfter: true, newCommit: false });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isPush), false);
  assert.equal(f.calls.some(isAdd), false);
  assert.equal(f.calls.some(isCommit), false);
  assert.ok(f.posts.length === 1);
});

test('7: missing final message fails without push', async t => {
  const f = await fixture(t, { noLastMessage: true, dirtyAfter: true, newCommit: false });
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.calls.some(isPush), false);
  assert.equal(f.calls.some(isAdd), false);
  assert.equal(f.calls.some(isCommit), false);
});

test('8: watcher stages remaining changes, uses COMMIT and commits before pushing', async t => {
  const f = await fixture(t, { dirtyAfter: true, newCommit: false, lastMessage: 'STATUS: done\nCOMMIT: 修复 relay 自动提交\nSUMMARY:\n- Updated relay.' });
  assert.equal((await f.once()).status, 'done');
  const add = index(f.calls, isAdd);
  const commit = index(f.calls, isCommit);
  const push = index(f.calls, isPush);
  assert.ok(index(f.calls, isCodex) < add && add < commit && commit < push);
  assert.deepEqual(f.calls[commit].args, ['commit', '-m', '修复 relay 自动提交', '-m', 'relay: PR #71 第 1 轮']);
  assert.equal(f.calls[add].opts.cwd, f.worktree);
  assert.equal(f.calls[commit].opts.cwd, f.worktree);
  assert.equal(f.calls[commit].opts.env.SKIP_PROJECT_STATE, '1');
  assert.equal(f.calls.filter(isCommit).length, 1);
  assert.equal(f.calls.filter(isPush).length, 1);
  assert.equal(f.calls.some(call => call.args.some(arg => arg.includes('--force'))), false);
  assert.match(f.posts[0], /^<!-- relay:to-claude round=1 status=done sha=b{7,40} -->/);
  assert.ok(f.posts[0].includes('tools/agent_relay/example.mjs'));
  assert.ok(f.calls.some(call => isReaction(call, 'rocket')));
  assert.equal((await f.state()).comments['101'].sha, END.slice(0, 12));
});

for (const [label, commitLine, expected] of [
  ['missing COMMIT', '', 'relay: 第 2 轮'],
  ['COMMIT 无', 'COMMIT: 无\n', 'relay: 第 2 轮'],
  ['padded 无', 'COMMIT:  无  \n', 'relay: 第 2 轮'],
  ['empty COMMIT', 'COMMIT:   \n', 'relay: 第 2 轮'],
  ['trimmed COMMIT', 'COMMIT:   修复空白处理  \n', '修复空白处理'],
]) {
  test(`8: watcher handles ${label} without consuming the following line`, async t => {
    const f = await fixture(t, { dirtyAfter: true, newCommit: false,
      comments: [{ ...baseComment, body: '<!-- relay:to-codex round=2 -->\nContinue the scoped change.' }],
      lastMessage: `STATUS: done\r\n${commitLine.replace(/\n/g, '\r\n')}SUMMARY:\r\n- Updated relay.`,
    });
    assert.equal((await f.once()).status, 'done');
    const commit = f.calls.find(isCommit);
    assert.deepEqual(commit.args, ['commit', '-m', expected, '-m', 'relay: PR #71 第 2 轮']);
    assert.equal(commit.opts.env.SKIP_PROJECT_STATE, '1');
    assert.equal(f.calls.filter(isPush).length, 1);
  });
}

for (const [label, failure, statusLine] of [
  ['commit hook rejection', { commitFailure: true }, 'M  tools/agent_relay/example.mjs'],
  ['staging failure', { addFailure: true }, ' M tools/agent_relay/example.mjs'],
]) {
  test(`8: ${label} fails with short status and never pushes`, async t => {
    const f = await fixture(t, { dirtyAfter: true, newCommit: false, ...failure });
    assert.equal((await f.once()).status, 'failed');
    assert.equal(f.calls.some(isPush), false);
    assert.equal(f.calls.filter(isAdd).length, 1);
    assert.equal(f.calls.filter(isCommit).length, failure.commitFailure ? 1 : 0);
    assert.ok(f.calls.some(call => call.cmd === 'git' && call.args[0] === 'status' && call.args.includes('--short')));
    assert.ok(f.posts[0].includes(statusLine));
    assert.ok(f.posts[0].includes(failure.commitFailure ? 'pre-commit hook rejected changes' : 'cannot stage changes'));
    assert.match(f.posts[0], /^<!-- relay:to-claude round=1 status=failed sha=none -->/);
    assert.ok(f.calls.some(call => isReaction(call, 'confused')));
    assert.equal((await f.state()).comments['101'].status, 'failed');
  });
}

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

test('blocked result with Codex own commit is accepted, pushed and gets rocket', async t => {
  const f = await fixture(t, { lastMessage: 'STATUS: blocked\nSUMMARY:\n- Partial change committed.\nQUESTIONS:\n- Need a product decision.' });
  assert.equal((await f.once()).status, 'blocked');
  assert.equal(f.calls.filter(isPush).length, 1);
  assert.equal(f.calls.some(isAdd), false);
  assert.equal(f.calls.some(isCommit), false);
  assert.match(f.posts[0], /^<!-- relay:to-claude round=1 status=blocked sha=b{7,40} -->/);
  assert.ok(f.calls.some(call => isReaction(call, 'rocket')));
});

test('done with no changes does not stage, commit or push', async t => {
  const f = await fixture(t, { newCommit: false });
  assert.equal((await f.once()).status, 'done');
  assert.equal(f.calls.some(isPush), false);
  assert.equal(f.calls.some(isAdd), false);
  assert.equal(f.calls.some(isCommit), false);
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

test('blocked result with remaining changes is committed and pushed before reporting blocked', async t => {
  const f = await fixture(t, { dirtyAfter: true, newCommit: false, lastMessage: 'STATUS: blocked\nCOMMIT: 保存本轮部分实现\nSUMMARY:\n- Partial implementation.\nQUESTIONS:\n- Need a product decision.' });
  assert.equal((await f.once()).status, 'blocked');
  assert.deepEqual(f.calls.find(isCommit).args, ['commit', '-m', '保存本轮部分实现', '-m', 'relay: PR #71 第 1 轮']);
  assert.ok(index(f.calls, isAdd) < index(f.calls, isCommit));
  assert.ok(index(f.calls, isCommit) < index(f.calls, isPush));
  assert.equal(f.calls.filter(isPush).length, 1);
  assert.match(f.posts[0], /^<!-- relay:to-claude round=1 status=blocked sha=b{7,40} -->/);
  assert.ok(f.calls.some(call => isReaction(call, 'rocket')));
  assert.equal((await f.state()).comments['101'].status, 'blocked');
});

test('CLI maps failed and cleanup-blocked to exit 1 and other terminal states to exit 0', async t => {
  const f = await fixture(t);
  const configFile = path.join(f.config.repoPath, 'cli-config.json');
  await writeFile(configFile, JSON.stringify(f.config));
  const previousExitCode = process.exitCode;
  for (const [status, expected] of [
    ['failed', 1], ['cleanup-blocked', 1], ['idle', 0], ['done', 0],
    ['blocked', 0], ['locked', 0], ['dry-run', 0], ['human', 0],
  ]) {
    let executions = 0;
    const messages = [];
    const code = await main(['--config', configFile, status === 'dry-run' ? '--dry-run' : '--once'], {
      executeOnce: async ({ config, stateDir, dryRun }) => {
        executions += 1;
        assert.equal(config.repo, f.config.repo);
        assert.equal(config.repoPath, f.config.repoPath);
        assert.equal(stateDir, path.dirname(configFile));
        assert.equal(dryRun, status === 'dry-run');
        return { status, pr: 71 };
      },
      log: message => messages.push(message),
    });
    assert.equal(code, expected, `exit code for ${status}`);
    assert.equal(executions, 1, `single execution for ${status}`);
    assert.equal(process.exitCode, previousExitCode, 'imported CLI wrapper must not mutate global exitCode');
  }
  assert.deepEqual(f.calls, [], 'CLI tests must not invoke any subprocess');
});

const notificationConfig = { pushplusToken: 'synthetic-push-token', barkKey: 'synthetic-bark-key', barkServer: 'https://api.day.app' };
const enabledState = { comments: {}, notified: {}, notifyEnabledAt: '2026-10-07T00:00:00.000Z' };
const humanComment = (id, marker = 'done', extra = {}) => ({ ...baseComment, id, body: `<!-- relay:${marker} -->\nPlease review.\n---\nSynthetic signature`, ...extra });

test('notify config is optional and validates types/https without exposing input credentials', async t => {
  const f = await fixture(t);
  assert.deepEqual(validateConfig(f.config).notify, { pushplusToken: '', barkKey: '', barkServer: 'https://api.day.app' });
  assert.deepEqual(validateConfig({ ...f.config, notify: notificationConfig }).notify, notificationConfig);
  for (const notify of [null, [], false, 'bad', { pushplusToken: 123 }, { barkKey: true }, { barkServer: 123 }, { barkServer: 'http://synthetic-push-token.test' }, { barkServer: 'https://synthetic-push-token@api.day.app' }, { barkServer: 'https://api.day.app?key=synthetic-push-token' }]) {
    assert.throws(() => validateConfig({ ...f.config, notify }), error => !error.message.includes(notificationConfig.pushplusToken) && /notify/.test(error.message));
  }
});

test('all labelled PRs notify before execution, even paused/human, and comment reads are reused', async t => {
  const f = await fixture(t, { state: enabledState,
    prs: [basePr, { ...basePr, number: 72, labels: ['agent-relay', 'relay-needs-human'] }, { ...basePr, number: 73, labels: ['agent-relay', 'relay-paused'] }],
    commentsByPr: { 71: [baseComment], 72: [humanComment(202, 'to-human')], 73: [humanComment(203)] },
    checkCodex: () => assert.equal(f.fetchCalls.length, 4, 'notifications for later PRs must happen before the first round'),
  });
  f.config.notify = notificationConfig;
  assert.equal((await f.once()).status, 'done');
  assert.deepEqual(f.fetchCalls.filter(x => x.url.includes('pushplus')).map(x => x.body.title), ['接力 PR #72：需要你决定', '接力 PR #73：完成，等你验收']);
  assert.equal(f.calls.filter(x => x.args.some(arg => /\/issues\/\d+\/comments$/.test(arg))).length, 3);
  assert.ok(f.calls.find(x => x.args[1] === 'list').args.some(arg => arg.includes('title')));
  assert.equal((await f.state()).notified['202'].status, 'sent');
  await f.once();
  assert.equal(f.fetchCalls.length, 4, 'same comments must not be notified twice');
  assert.equal(f.calls.filter(isCodex).length, 1);
});

test('done/to-human notify, AI handoffs and non-whitelisted authors do not', async t => {
  const f = await fixture(t, { state: enabledState, comments: [humanComment(201), humanComment(202, 'to-human'), humanComment(203, 'done', { user: { login: 'outsider' } }), { ...baseComment, user: { login: 'outsider' } }, { ...baseComment, id: 204, body: '<!-- relay:to-claude round=1 status=done sha=abc -->\nDone' }, { ...baseComment, id: 205, body: '<!-- relay:to-claude round=1 status=blocked sha=abc -->\nBlocked' }, { ...baseComment, id: 206, body: '<!-- relay:to-claude round=1 status=failed sha=none -->\nForeign failure' }] });
  f.config.notify = notificationConfig;
  assert.equal((await f.once()).status, 'idle');
  assert.equal(f.fetchCalls.length, 4);
  const bark = f.fetchCalls.find(x => x.url.includes('day.app'));
  assert.equal(bark.body.url, 'https://github.com/Ritou-Lynx/here-i-am/pull/71');
  assert.match(bark.body.body, /^Synthetic relay PR\nhttps:\/\/github.com\/Ritou-Lynx\/here-i-am\/pull\/71\nPlease review\./);
  assert.doesNotMatch(bark.body.body, /relay:|Synthetic signature/);
  assert.deepEqual(Object.keys((await f.state()).notified), ['201', '202']);
});

test('first enable ignores history and persists the baseline, then notifies new comments', async t => {
  const comments = [humanComment(201), humanComment(202, 'to-human')];
  const f = await fixture(t, { comments });
  f.config.notify = notificationConfig;
  await f.once();
  assert.equal(f.fetchCalls.length, 0);
  const state = await f.state();
  assert.equal(state.notifyEnabledAt, new Date(NOW).toISOString());
  assert.deepEqual(state.notified['201'], { status: 'sent', attempts: 0, at: state.notifyEnabledAt });
  await f.once();
  assert.equal(f.fetchCalls.length, 0);
  comments.push(humanComment(203, 'done', { created_at: '2026-10-07T02:01:00Z' }));
  await f.once();
  assert.equal(f.fetchCalls.length, 2);
  assert.equal((await f.state()).notified['203'].status, 'sent');
});

test('no channels causes one log and no fetch, and does not initialize notification history', async t => {
  const f = await fixture(t, { comments: [humanComment(201)] });
  await f.once();
  assert.equal(f.fetchCalls.length, 0);
  assert.equal(f.output.filter(x => x[0] === '未配置通知通道').length, 1);
  assert.equal(await exists(path.join(f.stateDir, 'state.json')), false);
});

test('all failures retry at most three times; a pending payload survives removed/closed PRs', async t => {
  const prs = [basePr];
  const f = await fixture(t, { state: enabledState, prs, comments: [humanComment(201)], fetchImpl: async () => { throw new Error('synthetic-push-token synthetic-bark-key'); } });
  f.config.notify = notificationConfig;
  await f.once();
  assert.equal((await f.state()).notified['201'].status, 'pending');
  prs.length = 0;
  for (let i = 0; i < 4; i++) await f.once();
  assert.equal(f.fetchCalls.length, 6);
  assert.equal((await f.state()).notified['201'].status, 'gave_up');
  assert.equal((await f.state()).notified['201'].attempts, 3);
  assert.equal((await f.state()).notified['201'].notification, undefined);
  assert.ok(JSON.stringify(f.output).includes('放弃重试'));
  for (const secret of Object.values(notificationConfig).slice(0, 2)) assert.equal(JSON.stringify(f.output).includes(secret), false);
});

test('one channel success marks sent and avoids duplicate delivery on the successful channel', async t => {
  const f = await fixture(t, { state: enabledState, comments: [humanComment(201)], fetchImpl: async url => ({ status: 200, json: async () => ({ code: url.includes('pushplus') ? 500 : 200 }) }) });
  f.config.notify = notificationConfig;
  await f.once();
  await f.once();
  assert.equal(f.fetchCalls.length, 2);
  assert.equal((await f.state()).notified['201'].status, 'sent');
  assert.equal((await f.state()).notified['201'].attempts, 1);
});

test('failed mobile notification cannot stop execution, push or reply', async t => {
  const f = await fixture(t, { state: enabledState, comments: [humanComment(201), baseComment], fetchImpl: async () => { throw new Error('synthetic outage'); } });
  f.config.notify = notificationConfig;
  assert.equal((await f.once()).status, 'done');
  assert.equal(f.calls.filter(isPush).length, 1);
  assert.equal(f.posts.length, 1);
  assert.equal((await f.state()).notified['201'].status, 'pending');
});

test('watcher failed reply sends immediately after delivery and retries without reposting or replaying', async t => {
  let failures = true;
  const f = await fixture(t, { state: enabledState, codexCode: 1, fetchImpl: async (url, opts, { posts }) => {
    assert.equal(posts.length, 1, 'failure notification must follow a successful GitHub reply');
    assert.match(posts[0], /^<!-- relay:to-claude round=1 status=failed/);
    return { status: 200, json: async () => ({ code: failures ? 500 : 200 }) };
  } });
  f.config.notify = notificationConfig;
  assert.equal((await f.once()).status, 'failed');
  assert.equal(f.fetchCalls[0].body.title, '接力 PR #71：第 1 轮失败');
  assert.match(f.fetchCalls[0].body.content, /^Synthetic relay PR\n/);
  assert.equal((await f.state()).notified['9001'].status, 'pending');
  failures = false;
  await f.once();
  await f.once();
  assert.equal(f.fetchCalls.length, 4);
  assert.equal(f.posts.length, 1);
  assert.equal(f.calls.filter(isCodex).length, 1);
  assert.equal((await f.state()).notified['9001'].status, 'sent');
});

test('a failed GitHub reply sends no mobile notification until the reply succeeds', async t => {
  const f = await fixture(t, { state: enabledState, codexCode: 1, failFirstComment: true });
  f.config.notify = notificationConfig;
  await assert.rejects(f.once(), /comment delivery temporarily failed/);
  assert.equal(f.fetchCalls.length, 0);
  await f.once();
  assert.equal(f.fetchCalls.length, 2);
  assert.equal(f.posts.length, 1);
  assert.equal(f.calls.filter(isCodex).length, 1);
});

test('dry-run previews notification titles without network or changes to existing state', async t => {
  const f = await fixture(t, { state: enabledState, comments: [humanComment(201)] });
  f.config.notify = notificationConfig;
  const before = await readFile(path.join(f.stateDir, 'state.json'), 'utf8');
  await f.once({ dryRun: true });
  assert.equal(f.fetchCalls.length, 0);
  assert.equal(await readFile(path.join(f.stateDir, 'state.json'), 'utf8'), before);
  assert.equal(await exists(path.join(f.stateDir, 'lock')), false);
  assert.ok(JSON.stringify(f.output).includes('将要发送通知：接力 PR #71：完成，等你验收'));
  assert.deepEqual(f.posts, []);
});

test('a notification scan read failure on one PR does not prevent executing another PR', async t => {
  const f = await fixture(t, { state: enabledState, prs: [{ ...basePr, number: 72, labels: ['agent-relay', 'relay-needs-human'] }, basePr], failCommentsFor: 72 });
  f.config.notify = notificationConfig;
  assert.equal((await f.once()).status, 'done');
  assert.equal(f.calls.filter(isCodex).length, 1);
});

test('test-notify reads only config, reports each channel, and never calls the watcher or touches state', async t => {
  const f = await fixture(t);
  const configFile = path.join(f.stateDir, 'config.json');
  await mkdir(f.stateDir, { recursive: true });
  await writeFile(configFile, JSON.stringify({ ...f.config, notify: notificationConfig }));
  await writeFile(path.join(f.stateDir, 'state.json'), 'deliberately invalid state');
  const logs = [], requests = [];
  const options = { executeOnce: async () => { assert.fail('must not access GitHub/watcher'); }, log: msg => logs.push(msg), fetchImpl: async (url, opts) => { requests.push(JSON.parse(opts.body)); return { status: 200, json: async () => ({ code: 200 }) }; } };
  assert.equal(await main(['--config', configFile, '--test-notify', '--loop'], options), 0);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].title, '接力测试通知');
  assert.ok(logs.includes('pushplus=ok bark=ok'));
  assert.equal(await readFile(path.join(f.stateDir, 'state.json'), 'utf8'), 'deliberately invalid state');
  assert.equal(await exists(path.join(f.stateDir, 'lock')), false);
  assert.deepEqual(f.calls, []);
  assert.equal(await main(['--config', configFile, '--test-notify', '--dry-run'], options), 0);
  assert.equal(requests.length, 2);
  for (const secret of [notificationConfig.pushplusToken, notificationConfig.barkKey]) assert.equal(JSON.stringify(logs).includes(secret), false);
});

test('test-notify reports failure/off without logging rejected fetch diagnostics or writing state', async t => {
  const f = await fixture(t);
  const configFile = path.join(f.config.repoPath, 'cli-config.json');
  const logs = [];
  await writeFile(configFile, JSON.stringify({ ...f.config, notify: { pushplusToken: notificationConfig.pushplusToken } }));
  assert.equal(await main(['--config', configFile, '--test-notify'], { log: msg => logs.push(msg), fetchImpl: async () => { throw new Error(notificationConfig.pushplusToken); } }), 1);
  assert.ok(logs.includes('pushplus=failed bark=off'));
  assert.equal(JSON.stringify(logs).includes(notificationConfig.pushplusToken), false);
  assert.equal(await exists(f.stateDir), false);
});

test('tokens echoed in PR text are excluded from notification content, watcher logs and replies', async t => {
  const echoed = `${notificationConfig.pushplusToken} ${notificationConfig.barkKey}`;
  const f = await fixture(t, { state: enabledState, comments: [humanComment(201, 'done', { body: `<!-- relay:done -->\n${echoed}` }), baseComment], lastMessage: `STATUS: done\nSUMMARY:\n${echoed}`, codexOutput: JSON.stringify({ diagnostic: echoed }), codexError: echoed });
  f.config.notify = notificationConfig;
  assert.equal((await f.once()).status, 'done');
  for (const secret of [notificationConfig.pushplusToken, notificationConfig.barkKey]) {
    assert.equal(f.fetchCalls[0].body.content.includes(secret), false);
    assert.equal(JSON.stringify(f.output).includes(secret), false);
    assert.equal(f.posts.join('\n').includes(secret), false);
    for (const file of await readdir(path.join(f.stateDir, 'logs'))) {
      assert.equal((await readFile(path.join(f.stateDir, 'logs', file), 'utf8')).includes(secret), false, `credential leaked in ${file}`);
    }
  }
});

test('failed execution diagnostics are sanitized in every local log before the failure reply', async t => {
  const echoed = `${notificationConfig.pushplusToken} ${notificationConfig.barkKey}`;
  const f = await fixture(t, { state: enabledState, codexCode: 1, codexOutput: echoed, codexError: echoed, lastMessage: echoed });
  f.config.notify = notificationConfig;
  assert.equal((await f.once()).status, 'failed');
  for (const file of await readdir(path.join(f.stateDir, 'logs'))) {
    const contents = await readFile(path.join(f.stateDir, 'logs', file), 'utf8');
    for (const secret of [notificationConfig.pushplusToken, notificationConfig.barkKey]) assert.equal(contents.includes(secret), false, file);
  }
  assert.doesNotMatch(f.fetchCalls[0].body.content, /synthetic-push-token|synthetic-bark-key/);
});

test('configured notification credentials cannot enter the Codex prompt or dry-run preview', async t => {
  const echoed = `${notificationConfig.pushplusToken} ${notificationConfig.barkKey}`;
  const f = await fixture(t, { comments: [{ ...baseComment, body: `<!-- relay:to-codex round=1 -->\n${echoed}` }],
    checkCodex: call => assert.doesNotMatch(call.opts.input, /synthetic-push-token|synthetic-bark-key/),
  });
  f.config.notify = notificationConfig;
  const preview = await f.once({ dryRun: true });
  assert.doesNotMatch(preview.prompt, /synthetic-push-token|synthetic-bark-key/);
  assert.equal((await f.once()).status, 'done');
});

test('history discovered after first enable is recorded, while newer messages still notify', async t => {
  const f = await fixture(t, { state: enabledState, comments: [humanComment(201, 'done', { created_at: '2026-10-06T23:00:00Z' })] });
  f.config.notify = notificationConfig;
  await f.once();
  assert.equal(f.fetchCalls.length, 0);
  assert.equal((await f.state()).notified['201'].attempts, 0);
});

test('first-enable comment read failures do not reset the activation time or suppress later messages', async t => {
  const scenario = { failCommentsFor: 71, comments: [humanComment(201)] };
  const f = await fixture(t, scenario);
  f.config.notify = notificationConfig;
  await f.once();
  assert.equal((await f.state()).notifyEnabledAt, new Date(NOW).toISOString());
  scenario.failCommentsFor = undefined;
  scenario.comments.push(humanComment(202, 'to-human', { created_at: '2026-10-07T02:01:00Z' }));
  await f.once();
  assert.equal(f.fetchCalls.length, 2);
  assert.equal((await f.state()).notified['201'].attempts, 0);
  assert.equal((await f.state()).notified['202'].status, 'sent');
});
