import { resolve } from 'node:path';

import { loadProjectRegistry, resolveIHome } from './i_project_registry.mjs';

const registryPath = process.argv[2] ? resolve(process.argv[2]) : undefined;
const registry = loadProjectRegistry({
  iHome: resolveIHome(),
  registryPath,
});

if (registry.status !== 'ready') {
  process.stderr.write('i Project Registry validation failed\n');
  process.exitCode = 1;
} else {
  process.stdout.write(`${JSON.stringify({
    schema_version: registry.schema_version,
    status: registry.status,
    project_count: registry.projects.length,
  })}\n`);
}

