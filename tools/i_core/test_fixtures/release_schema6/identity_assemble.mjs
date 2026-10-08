import { INVENTORY, prepareRelease } from '../../release_schema6/package.mjs';
import { syntheticRoot, syntheticFixedNode } from './synthetic_paths.mjs';
import { mkdirSync, copyFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const [repository, gitPath] = process.argv.slice(2);
const root = syntheticRoot('schema6-identity-');
const node = syntheticFixedNode(root);
const release = path.join(root, 'release');
const report = prepareRelease({ repository, gitPath, output: release, nodePath: node });
// Export the source-owned exact inventory only after production verification.
// The PowerShell fixture must not pin an obsolete package file count.
assert.equal(report.files, INVENTORY.length);
const maintenance = path.join(root, 'source/tools/i_core/maintenance');
mkdirSync(maintenance, {recursive:true});
for (const name of readdirSync(path.join(repository, 'tools/i_core/maintenance')))
  if (/\.(ps1|mjs)$/.test(name)) copyFileSync(path.join(repository,'tools/i_core/maintenance',name),path.join(maintenance,name));
const maintenanceNames = readdirSync(maintenance).sort();
assert.deepEqual(maintenanceNames,readdirSync(path.join(repository,'tools/i_core/maintenance')).filter(name=>/\.(ps1|mjs)$/.test(name)).sort());
for (const name of ['owned_artifacts.ps1','acl-cutover-maintenance.ps1','prepare-production-login.ps1','prepare-production-login.mjs','register_task_primitives.ps1']) assert.ok(maintenanceNames.includes(name),name);
mkdirSync(path.join(root,'source/tools/i_core/release_schema6'));
copyFileSync(path.join(repository,'tools/i_core/release_schema6/package.mjs'),path.join(root,'source/tools/i_core/release_schema6/package.mjs'));
process.stdout.write(JSON.stringify({root,release,maintenance,maintenanceFiles:maintenanceNames.length,inventory:[...INVENTORY],...report}));
