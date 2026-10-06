import assert from 'node:assert/strict';
import { constants, copyFileSync, lstatSync, mkdtempSync, readFileSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { plainPath, sha256 } from '../../release_schema6/package.mjs';

// Test setup only: Windows TEMP can use an 8.3 name or an ancestor junction.
// Production callers must still supply a plain, canonical path themselves.
export function syntheticRoot(prefix, parent = tmpdir()) {
  assert.match(prefix, /^[a-z0-9-]+-$/);
  const root = realpathSync.native(mkdtempSync(path.join(realpathSync.native(parent), prefix)));
  plainPath(root);
  return root;
}

// Hosted runner tool caches may alias their executable. The candidate input is
// a fresh independent file; production still verifies its pinned bytes/links.
export function syntheticFixedNode(root, source = process.execPath) {
  const target = path.join(plainPath(root), 'fixed-node.exe');
  copyFileSync(source, target, constants.COPYFILE_EXCL);
  plainPath(target);
  assert.equal(lstatSync(target).nlink, 1);
  assert.equal(sha256(readFileSync(target)), sha256(readFileSync(source)));
  return target;
}
