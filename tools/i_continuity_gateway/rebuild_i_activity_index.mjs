import { createIActivityStore } from './i_activity_store.mjs';
import { loadProjectRegistry, resolveIHome } from './i_project_registry.mjs';

try {
  const iHome = resolveIHome();
  const store = createIActivityStore({
    iHome,
    registryProjectsProvider: () => loadProjectRegistry({ iHome }).projects,
  });
  const index = store.rebuildActivityIndex();
  process.stdout.write(`${JSON.stringify({
    schema_version: 1,
    status: index.status || 'rebuilt',
    event_count: Number(index.event_count) || 0,
    storage_status: store.getStorageStatus(),
  }, null, 2)}\n`);
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
