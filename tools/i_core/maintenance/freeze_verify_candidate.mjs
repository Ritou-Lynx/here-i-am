// Freeze-only source verification. This opens no database and launches no children.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {verifyRelease,PINNED_NODE_SHA256} from '../release_schema6/package.mjs';
assert.equal(process.argv.length,5);
assert.equal(process.version,'v24.14.1');
assert.equal(createHash('sha256').update(readFileSync(process.execPath)).digest('hex'),PINNED_NODE_SHA256);
const verified=verifyRelease(process.argv[2],process.argv[3]);
assert.equal(verified.source_commit,process.argv[4]);
