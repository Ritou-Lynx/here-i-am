// Selectively lands the W0-accepted A3-I tree while preserving unrelated main work.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(fileURLToPath(new URL('../../', import.meta.url)));
const target = 'D:/memex';
const source = (process.env.HIA_MDA_SOURCE_ROOT ?? process.cwd());
const baseline = 'c5d7cbfe559eb517b3b1110f27e07dc8308d6442';
const candidate = 'c0bf3d49cf145cb2505750bd2d4e4d26e2e1eb9c';
const output = path.join(root, 'tmp/mda2-a3-landing-c0bf3d49');
const mode = process.argv[2];
assert.ok(['prepare', 'check', 'stage', 'commit', 'verify'].includes(mode));

const globalDocs = [
  'DEVLOG.md',
  'docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md',
  'docs/companion-first/PRODUCT_ROADMAP.md',
  'docs/development/I_PROJECT_STATE.md',
];
const support = [
  'docs/development/activity/mda2/A3_ANDROID_NATIVE_WIRING_PLAN.md',
  'docs/development/activity/mda2/android/a3_review/5f54d5b4/W0_REVIEW.md',
  'docs/development/activity/mda2/android/a3_review/c0bf3d49/ACCEPTANCE.json',
  'docs/development/activity/mda2/android/a3_review/c0bf3d49/W0_ACCEPTANCE.md',
  'tools/mda2_acceptance/a3_local_landing.mjs',
];
const reviewPath = 'docs/development/activity/mda2/android/a3_review/c0bf3d49/W0_ACCEPTANCE.md';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const env = { ...process.env, GIT_OPTIONAL_LOCKS: '0' };
delete env.SKIP_PROJECT_STATE;
assert.ok(!env.GIT_INDEX_FILE && !env.GIT_DIR && !env.GIT_WORK_TREE);
const git = (args, cwd = target) => execFileSync(
  'git', ['-c', 'core.safecrlf=false', '-C', cwd, ...args],
  { env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 32 * 1024 * 1024 },
);
const names = bytes => bytes.toString().split('\0').filter(Boolean).sort();
const head = () => git(['rev-parse', 'HEAD']).toString().trim();

function relative(name) {
  assert.match(name, /^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/);
  assert.ok(name.split('/').every(part => !['.', '..', '.git'].includes(part.toLowerCase())));
  return name;
}

function plain(filename, mustExist = false) {
  const absolute = path.resolve(filename);
  assert.match(absolute, /^[A-Za-z]:[\\/]/);
  for (let current = absolute;; current = path.dirname(current)) {
    if (fs.existsSync(current)) {
      const stat = fs.lstatSync(current);
      assert.ok(!stat.isSymbolicLink() && (!stat.isFile() || stat.nlink === 1), 'linked path rejected');
    }
    if (path.dirname(current) === current) break;
  }
  if (mustExist) assert.equal(fs.realpathSync.native(absolute).toLowerCase(), absolute.toLowerCase());
  return absolute;
}

const targetPath = name => plain(path.join(target, relative(name)));
const fingerprint = name => {
  const filename = targetPath(name);
  return fs.existsSync(filename) ? sha(fs.readFileSync(filename)) : null;
};
const put = (folder, name, bytes) => {
  const filename = path.join(output, folder, relative(name));
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, bytes, { flag: 'wx' });
};
const writeJson = (name, value) => fs.writeFileSync(
  path.join(output, name), JSON.stringify(value, null, 2) + '\n', { flag: 'wx' },
);
plain(target, true);

const snippets = new Map([
  ['DEVLOG.md', `## 2026-09-14 — MDA-2 A3-I R1通过W0并本地集成\n\n**目标**：独立验收默认关闭的Android原生活动接线并只纳入最终返修。\n**做了什么**：退回初交付的冻结store ownership泄漏；最终c0bf3d49经干净导出复跑A3 Dart 16/16、Kotlin 12/12、A1 56/56、A2 30/30、wire/Core 20/20与完整App单元任务。\n**关键决策**：只集成最终14个A3-I路径和W0材料；系统窗口与通道形状必须效果前拒绝，dispose必须释放已取得的store。\n**边界**：源码默认关闭；无APK、adb、真实UsageEvents/Core/网络/设备/BLE，A3-D另行验收。\n**证据**：[W0验收](${reviewPath})。\n\n---\n\n`],
  ['docs/development/I_PROJECT_STATE.md', `- 2026-09-14 **MDA-2 A3-I R1通过W0并选择性本地集成**：初交付\`5f54d5b4\`因冻结outbox dispose遗留owner/gate被拒；最终\`c0bf3d49\`改为释放所有已取得store，并在效果前验证UsageEvents窗口与MethodChannel精确形状。W0干净导出复跑A3 Dart 16/16、Kotlin 12/12、A1 56/56、A2 30/30、wire/Core 20/20及完整hereIAmV3Debug App单元任务；14路径、Manifest与保护区边界通过。当前只完成默认关闭的本地源码接线，未构建安装APK、未访问真实UsageEvents/Core/网络/设备/BLE；A3-D真机Gate未启动。见[A3-I验收](${reviewPath.replace('docs/development/', '')})。\n\n`],
  ['docs/companion-first/PRODUCT_ROADMAP.md', `MDA-2 A3-I Android原生接线最终\`c0bf3d49\`已通过W0并选择性本地集成：初交付因冻结store未释放ownership被拒，R1补齐无条件close、系统调用前窗口验证与MethodChannel精确形状。干净导出A3 Dart 16/16、Kotlin 12/12、A1 56/56、A2 30/30、wire/Core 20/20及完整App单元任务通过。源码保持默认关闭；真实UsageEvents、APK、手机、Doze/强停/重启、Keystore与BLE共存属于A3-D。见[A3-I验收](../development/activity/mda2/android/a3_review/c0bf3d49/W0_ACCEPTANCE.md)。\n\n`],
]);

function amend(name, bytes) {
  const text = bytes.toString('utf8');
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  if (name === 'docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md') {
    const before = '> 状态：MDA-0 已接受带红灯收口；MDA-1 已完成自动 Gate、独立终审与 Lynx 真人 Gate；MDA-2 已进入限定本地实现，R3+M3、W3与A2已选择性本地集成，真实部署/设备/真人 Gate 未开始';
    const after = '> 状态：MDA-0 已接受带红灯收口；MDA-1 已完成自动 Gate、独立终审与 Lynx 真人 Gate；MDA-2 已进入限定本地实现，R3+M3、W3、A2与默认关闭的A3-I已选择性本地集成，真实部署/设备/真人 Gate 未开始';
    assert.equal(text.split(before).length, 2);
    return Buffer.from(text.replace(before, after));
  }
  const addition = snippets.get(name).replaceAll('\n', eol);
  assert.ok(!text.includes('MDA-2 A3-I R1通过W0'));
  if (name === 'DEVLOG.md') return Buffer.concat([Buffer.from(addition), bytes]);
  const anchor = (name === 'docs/development/I_PROJECT_STATE.md'
    ? '## 最近状态' : '### MDA-1 与运行边界') + eol + eol;
  const at = text.indexOf(anchor);
  assert.ok(at >= 0);
  return Buffer.from(text.slice(0, at + anchor.length) + addition + text.slice(at + anchor.length));
}

function guard(payload, staged = false, afterCommit = false) {
  if (!afterCommit) assert.equal(head(), baseline);
  assert.equal(git(['branch', '--show-current']).toString().trim(), 'v3-lab');
  for (const marker of ['MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'index.lock']) {
    const filename = git(['rev-parse', '--path-format=absolute', '--git-path', marker]).toString().trim();
    assert.ok(!fs.existsSync(filename), `pending Git operation: ${marker}`);
  }
  assert.deepEqual(names(git(['diff', '--cached', '--name-only', '-z'])), staged ? payload.allowlist : []);
  for (const item of payload.inventory) {
    assert.equal(fingerprint(item.path), staged || afterCommit ? item.workingSha256 : item.beforeWorkingSha256, item.path);
  }
  for (const item of payload.dirty) {
    if (!globalDocs.includes(item.path)) assert.equal(fingerprint(item.path), item.sha256, item.path);
  }
  assert.deepEqual(names(git(['diff', '--name-only', '-z'])), payload.dirty.map(item => item.path));
}

if (mode === 'prepare') {
  assert.equal(head(), baseline);
  assert.equal(git(['branch', '--show-current']).toString().trim(), 'v3-lab');
  assert.equal(git(['diff', '--cached', '--name-only']).length, 0);
  assert.ok(!fs.existsSync(output));
  assert.equal(git(['rev-parse', 'HEAD'], source).toString().trim(), candidate);
  assert.equal(git(['status', '--porcelain'], source).length, 0);
  const candidatePaths = names(git(['diff', '--name-only', '-z', `${baseline}..${candidate}`], source));
  assert.equal(candidatePaths.length, 14);
  assert.ok(candidatePaths.every(name =>
    /^android\/app\/src\/(main|test)\/kotlin\/com\/memexlab\/memex\/(activity|channels)\//.test(name)
    || /^lib\/data\/services\/activity\/mda2_android\//.test(name)
    || /^test\/data\/services\/activity\/mda2_android\//.test(name)
    || /^docs\/development\/activity\/mda2\/android\/a3\//.test(name)));
  const intended = new Map(candidatePaths.map(name => [relative(name), git(['show', `${candidate}:${name}`], source)]));
  for (const name of support) intended.set(name, fs.readFileSync(path.join(root, name)));
  const acceptance = JSON.parse(intended.get('docs/development/activity/mda2/android/a3_review/c0bf3d49/ACCEPTANCE.json'));
  assert.equal(acceptance.verdict, 'accepted_for_selective_local_source_integration');
  assert.equal(acceptance.candidate_commit, candidate);
  assert.equal(acceptance.candidate_path_count, 14);
  const allowlist = [...intended.keys(), ...globalDocs].sort();
  assert.equal(new Set(allowlist).size, allowlist.length);
  const dirtyNames = names(git(['diff', '--name-only', '-z']));
  const dirty = dirtyNames.map(name => ({ path: relative(name), sha256: fingerprint(name) }));
  assert.equal(dirty.length, 56);
  const tracked = new Set(names(git(['ls-files', '-z', '--', ...allowlist])));
  for (const name of allowlist) {
    if (support.includes(name)) assert.equal(tracked.has(name), false, `support path already tracked: ${name}`);
    if (!tracked.has(name)) assert.equal(fingerprint(name), null, `new path collision: ${name}`);
  }
  fs.mkdirSync(output);
  const inventory = [];
  for (const name of allowlist) {
    const before = tracked.has(name) ? git(['show', `${baseline}:${name}`]) : null;
    const originalWorking = tracked.has(name) ? fs.readFileSync(targetPath(name)) : null;
    if (before) put('before', name, before);
    const indexed = globalDocs.includes(name) ? amend(name, before) : intended.get(name);
    const working = globalDocs.includes(name) ? amend(name, originalWorking) : indexed;
    put('index', name, indexed);
    put('working', name, working);
    inventory.push({
      path: name,
      indexSha256: sha(indexed),
      workingSha256: sha(working),
      beforeWorkingSha256: originalWorking ? sha(originalWorking) : null,
    });
  }
  const diff = spawnSync('git', ['-c', 'core.autocrlf=false', 'diff', '--no-index', '--binary', '--', 'before', 'index'], {
    cwd: output, env, windowsHide: true, maxBuffer: 32 * 1024 * 1024,
  });
  assert.equal(diff.status, 1);
  const beforePrefix = ['a', 'before', ''].join('/');
  const indexPrefix = ['b', 'index', ''].join('/');
  const patch = diff.stdout.toString().replaceAll(beforePrefix, 'a/').replaceAll(indexPrefix, 'b/');
  fs.writeFileSync(path.join(output, 'INDEX.patch'), patch);
  const payload = {
    baseline, candidate, candidatePaths, allowlist, inventory, dirty,
    patchSha256: sha(Buffer.from(patch)),
  };
  writeJson('PAYLOAD.json', payload);
  guard(payload);
  git(['apply', '--cached', '--check', path.join(output, 'INDEX.patch')]);
    console.log(JSON.stringify({ prepared: true, paths: allowlist.length, candidatePaths: 14, protectedDirty: dirty.length, output }));
} else {
  const payload = JSON.parse(fs.readFileSync(path.join(output, 'PAYLOAD.json')));
  assert.equal(payload.baseline, baseline);
  assert.equal(payload.candidate, candidate);
  const patchFile = path.join(output, 'INDEX.patch');
  assert.equal(sha(fs.readFileSync(patchFile)), payload.patchSha256);
  for (const item of payload.inventory) {
    assert.equal(sha(fs.readFileSync(path.join(output, 'index', item.path))), item.indexSha256);
    assert.equal(sha(fs.readFileSync(path.join(output, 'working', item.path))), item.workingSha256);
  }
  if (mode === 'check') {
    guard(payload);
    git(['apply', '--cached', '--check', patchFile]);
    console.log('CHECK_PASSED');
  }
  if (mode === 'stage') {
    guard(payload);
    git(['apply', '--cached', '--check', patchFile]);
    for (const item of payload.inventory) {
      const filename = targetPath(item.path);
      assert.equal(fingerprint(item.path), item.beforeWorkingSha256);
      fs.mkdirSync(path.dirname(filename), { recursive: true });
      fs.writeFileSync(filename, fs.readFileSync(path.join(output, 'working', item.path)), { flag: item.beforeWorkingSha256 === null ? 'wx' : 'w' });
    }
    git(['apply', '--cached', patchFile]);
    guard(payload, true);
    for (const item of payload.inventory) assert.equal(sha(git(['show', `:${item.path}`])), item.indexSha256, item.path);
    writeJson('STAGED.json', { paths: payload.allowlist, protectedDirty: payload.dirty.length });
    console.log('STAGED_AND_VERIFIED');
  }
  if (mode === 'commit') {
    guard(payload, true);
    for (const item of payload.inventory) assert.equal(sha(git(['show', `:${item.path}`])), item.indexSha256);
    assert.equal(git(['config', '--get', 'core.hooksPath']).toString().trim(), '.githooks');
    const result = git(['commit', '-m', 'Integrate verified MDA-2 A3 Android native wiring']);
    writeJson('COMMITTED.json', {
      commit: head(), parent: git(['rev-parse', 'HEAD^']).toString().trim(), hookOutput: result.toString(),
    });
    console.log(result.toString());
  }
  if (mode === 'verify') {
    const receipt = JSON.parse(fs.readFileSync(path.join(output, 'COMMITTED.json')));
    assert.equal(head(), receipt.commit);
    assert.equal(receipt.parent, baseline);
    guard(payload, false, true);
    assert.equal(git(['diff', '--cached', '--name-only']).length, 0);
    assert.deepEqual(names(git(['diff-tree', '--no-commit-id', '--name-only', '-r', '-z', receipt.commit])), payload.allowlist);
    for (const item of payload.inventory) {
      assert.equal(sha(git(['show', `${receipt.commit}:${item.path}`])), item.indexSha256, item.path);
      assert.equal(fingerprint(item.path), item.workingSha256, item.path);
    }
    writeJson('VERIFIED.json', {
      commit: receipt.commit,
      parent: baseline,
      sourceCandidate: candidate,
      paths: payload.allowlist.length,
      candidatePaths: 14,
      protectedDirty: payload.dirty.length,
      indexEmpty: true,
      pushed: false,
      deployed: false,
    });
    console.log(JSON.stringify(receipt));
  }
}
