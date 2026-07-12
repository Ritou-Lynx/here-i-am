import { exportSyncPackage, importSyncPackages } from './i_device_sync.mjs';

const [operation, syncRoot] = process.argv.slice(2);
if (!['export', 'import', 'sync'].includes(operation || '') || !syncRoot) {
  throw new Error('usage: node sync_i_devices.mjs <export|import|sync> <sync-root>');
}
const results = [];
if (operation === 'import' || operation === 'sync') results.push({ import: importSyncPackages({ syncRoot }) });
if (operation === 'export' || operation === 'sync') results.push({ export: exportSyncPackage({ syncRoot }) });
process.stdout.write(`${JSON.stringify({ schema_version: 1, operation, results }, null, 2)}\n`);
