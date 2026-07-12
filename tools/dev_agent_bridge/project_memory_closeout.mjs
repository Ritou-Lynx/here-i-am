import { createIActivityStore } from '../i_continuity_gateway/i_activity_store.mjs';
import {
  loadProjectRegistry,
  resolveActiveProject,
} from '../i_continuity_gateway/i_project_registry.mjs';

function clientIdForRun(run) {
  return run?.agentType === 'claude_code' ? 'claude-code' : 'codex';
}

function normalizedSummary(value) {
  const text = String(value || '').trim().replace(/\s+/g, ' ');
  return text.slice(0, 2000);
}

export function runHasPersistedCloseout(run) {
  return Array.isArray(run?.transcript) && run.transcript.some((entry) => {
    const text = String(entry || '');
    return /"persisted"\s*:\s*true/.test(text) &&
      /"event_type"\s*:\s*"session_closeout"/.test(text);
  });
}

export function buildDevRoomCloseoutInput(run) {
  if (!run || run.status !== 'done') return null;
  const summary = normalizedSummary(run.summary);
  if (!summary) return null;
  return {
    session_id: String(run.sessionId || run.id),
    idempotency_key: `dev-room-${String(run.id)}:closeout-v1`,
    presence_mode: 'delegated_tool',
    sensitivity: 'project_default',
    summary,
    decisions: [],
    open_loops: [],
    artifact_refs: [],
    ...(run.endedAt
      ? { occurred_at: new Date(Number(run.endedAt) * 1000).toISOString() }
      : {}),
  };
}

export function persistDevRoomCloseout({
  run,
  iHome,
  loadRegistry = loadProjectRegistry,
  createStore = createIActivityStore,
} = {}) {
  const input = buildDevRoomCloseoutInput(run);
  if (!input) return { persisted: false, reason: 'run_not_closeable' };
  if (runHasPersistedCloseout(run)) {
    return { persisted: true, duplicate: true, reason: 'agent_closeout_already_persisted' };
  }
  const registry = loadRegistry({ iHome });
  if (registry.status !== 'ready') {
    return { persisted: false, reason: 'i_registry_unavailable' };
  }
  const clientId = clientIdForRun(run);
  const project = resolveActiveProject({
    workspaceRoot: run.project?.rootPath,
    registry,
    clientId,
  });
  if (!project.registered) {
    return { persisted: false, reason: 'project_registration_required' };
  }
  if (project.access_status !== 'allowed') {
    return { persisted: false, reason: 'client_not_allowed' };
  }
  return createStore({ iHome }).closeSession({ project, clientId, input });
}
