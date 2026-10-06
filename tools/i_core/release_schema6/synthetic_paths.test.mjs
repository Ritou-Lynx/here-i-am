import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { linkSync, lstatSync, mkdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { plainPath } from './package.mjs';
import { syntheticRoot, syntheticFixedNode } from '../test_fixtures/release_schema6/synthetic_paths.mjs';

test('synthetic TEMP resolves an ancestor junction while production rejects the alias', t => {
  const root = syntheticRoot('schema6-path-fixture-');
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const parent = path.join(root, 'long canonical temporary directory');
  const alias = path.join(root, 'alias');
  mkdirSync(parent);
  symlinkSync(parent, alias, process.platform === 'win32' ? 'junction' : 'dir');
  const fixture = syntheticRoot('nested-', alias);
  assert.equal(path.dirname(fixture), realpathSync.native(parent));
  const input = path.join(fixture, 'input'); writeFileSync(input, 'synthetic');
  assert.equal(plainPath(input), input);
  assert.throws(() => plainPath(path.join(alias, path.basename(fixture), 'input')), { code: 'linked_path_rejected' });
});

test('cached hardlinked Node becomes independent bytes without accepting the cache alias', t => {
  const root = syntheticRoot('schema6-node-fixture-');
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const original = path.join(root, 'cached-node'); writeFileSync(original, 'synthetic executable bytes');
  const alias = path.join(root, 'cache-link'); linkSync(original, alias);
  assert.throws(() => plainPath(alias), { code: 'linked_path_rejected' });
  const copied = syntheticFixedNode(root, alias);
  assert.equal(lstatSync(copied).nlink, 1);
  assert.deepEqual(readFileSync(copied), readFileSync(original));
  assert.throws(() => syntheticFixedNode(root, alias), { code: 'EEXIST' });
});

test('Windows short TEMP names are canonicalized only by fixture setup', { skip: process.platform !== 'win32' }, t => {
  const root = syntheticRoot('schema6-short-path-fixture-');
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const parent = path.join(root, 'long temporary parent'); mkdirSync(parent);
  // Read-only cmd expansion; no shell deletion or moving is used.
  const short = execFileSync(process.env.ComSpec, ['/d', '/c', 'for %I in ("' + parent + '") do @echo %~sI'], { encoding: 'utf8', windowsHide: true, windowsVerbatimArguments: true }).trim();
  assert.equal(realpathSync.native(short), parent);
  const fixture = syntheticRoot('nested-', short);
  assert.equal(path.dirname(fixture), parent);
  writeFileSync(path.join(fixture, 'input'), 'synthetic');
  if (short.toLowerCase() !== parent.toLowerCase()) {
    assert.throws(() => plainPath(path.join(short, path.basename(fixture), 'input')), { code: 'input_missing_or_aliased' });
    t.diagnostic('8.3 alias exercised and rejected by unchanged production validator');
  } else {
    t.diagnostic('Volume does not assign 8.3 names; junction alias regression ran separately');
  }
});
