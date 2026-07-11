import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, isAbsolute, relative, resolve, sep } from 'node:path';
import { spawnSync } from 'node:child_process';

const POLICY_IDS = new Set([
  'personal_full',
  'work_redacted',
  'confidential_local',
  'ephemeral',
]);
const VISIBILITIES = new Set(['hidden', 'name_only', 'summary']);
const PROVIDERS = new Set(['generic_git', 'markdown', 'here_i_am']);

function readUtf8(path) {
  return readFileSync(path, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
}

function canonicalPath(path) {
  const absolute = resolve(path);
  const canonical = existsSync(absolute) ? realpathSync.native(absolute) : absolute;
  return process.platform === 'win32' ? canonical.toLocaleLowerCase('en-US') : canonical;
}

function isWithin(root, candidate) {
  const pathFromRoot = relative(root, candidate);
  return pathFromRoot === '' || (
    pathFromRoot !== '..' &&
    !pathFromRoot.startsWith(`..${sep}`) &&
    !isAbsolute(pathFromRoot)
  );
}

function sanitizeContextFile(value) {
  const path = String(value?.path ?? value ?? '').trim().replace(/\\/g, '/');
  if (!path || isAbsolute(path) || /^[a-zA-Z]:/.test(path)) {
    throw new Error('context file must be a non-empty relative path');
  }
  const normalized = path.split('/').filter((part) => part && part !== '.');
  if (normalized.some((part) => part === '..')) {
    throw new Error(`context file escapes project root: ${path}`);
  }
  return {
    path: normalized.join('/'),
    kind: String(value?.kind || 'document').trim() || 'document',
  };
}

function normalizeProject(raw, seenIds, seenKeys, seenRoots) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error('project registry entry must be an object');
  }
  const projectId = String(raw.project_id || '').trim();
  const projectKey = String(raw.project_key || '').trim();
  const displayName = String(raw.display_name || '').trim();
  if (!projectId || !projectKey || !displayName) {
    throw new Error('project_id, project_key and display_name are required');
  }
  if (seenIds.has(projectId)) throw new Error(`duplicate project_id: ${projectId}`);
  seenIds.add(projectId);
  if (!/^[a-z0-9][a-z0-9._-]{1,79}$/i.test(projectKey)) {
    throw new Error(`invalid project_key: ${projectKey}`);
  }
  if (seenKeys.has(projectKey)) throw new Error(`duplicate project_key: ${projectKey}`);
  seenKeys.add(projectKey);

  const roots = Array.isArray(raw.roots) ? raw.roots : [];
  if (roots.length === 0) throw new Error(`project ${projectKey} requires at least one root`);
  const normalizedRoots = roots.map((root) => canonicalPath(String(root || '').trim()));
  for (const root of normalizedRoots) {
    if (seenRoots.has(root)) throw new Error(`duplicate project root: ${root}`);
    seenRoots.add(root);
  }

  const provider = String(raw.provider || 'generic_git').trim();
  if (!PROVIDERS.has(provider)) throw new Error(`unsupported provider: ${provider}`);
  const contextFiles = (Array.isArray(raw.context_files) ? raw.context_files : [])
    .map(sanitizeContextFile);
  const policy = raw.policy && typeof raw.policy === 'object' ? raw.policy : {};
  const policyId = String(policy.id || 'ephemeral').trim();
  const requestedVisibility = String(policy.cross_project_visibility || 'hidden').trim();
  if (!POLICY_IDS.has(policyId)) throw new Error(`unsupported policy id: ${policyId}`);
  if (!VISIBILITIES.has(requestedVisibility)) {
    throw new Error(`unsupported visibility: ${requestedVisibility}`);
  }
  const visibility = policyId === 'confidential_local' || policyId === 'ephemeral'
    ? 'hidden'
    : requestedVisibility;

  return {
    project_id: projectId,
    project_key: projectKey,
    display_name: displayName,
    roots: normalizedRoots,
    provider,
    context_files: contextFiles,
    policy: {
      id: policyId,
      classification: String(policy.classification || 'unclassified').trim() || 'unclassified',
      cross_project_visibility: visibility,
      memory_v3: String(policy.memory_v3 || 'none').trim() || 'none',
      allowed_clients: Array.isArray(policy.allowed_clients)
        ? policy.allowed_clients.map((client) => String(client).trim()).filter(Boolean)
        : ['*'],
    },
  };
}

export function resolveIHome(input = process.env.I_HOME) {
  return resolve(input || homedir(), input ? '' : '.i');
}

export function loadProjectRegistry({ iHome, registryPath } = {}) {
  const home = resolveIHome(iHome);
  const path = resolve(registryPath || process.env.I_PROJECT_REGISTRY || home, registryPath || process.env.I_PROJECT_REGISTRY ? '' : 'projects.json');
  if (!existsSync(path)) {
    return { schema_version: 1, status: 'missing', path, projects: [], error_code: null };
  }
  try {
    const parsed = JSON.parse(readUtf8(path));
    if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.projects)) {
      throw new Error('registry must contain a projects array');
    }
    const seenIds = new Set();
    const seenKeys = new Set();
    const seenRoots = new Set();
    const projects = parsed.projects.map((project) => (
      normalizeProject(project, seenIds, seenKeys, seenRoots)
    ));
    return {
      schema_version: Number(parsed.schema_version) || 1,
      status: 'ready',
      path,
      projects,
      error_code: null,
    };
  } catch {
    return {
      schema_version: 1,
      status: 'invalid',
      path,
      projects: [],
      error_code: 'registry_invalid',
    };
  }
}

function runGit(cwd, args) {
  const result = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
    timeout: 5000,
  });
  if (result.status !== 0) return null;
  return String(result.stdout || '').trim();
}

function inferGitRoot(candidate) {
  const root = runGit(candidate, ['rev-parse', '--show-toplevel']);
  return root ? canonicalPath(root) : null;
}

function slug(value) {
  return String(value || 'workspace')
    .normalize('NFKD')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLocaleLowerCase('en-US') || 'workspace';
}

function hashPath(value) {
  let hash = 2166136261;
  for (const character of value) {
    hash ^= character.codePointAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

function clientAllowed(project, clientId) {
  const allowed = project.policy.allowed_clients;
  if (allowed.includes('*')) return true;
  const normalized = String(clientId || 'unknown').toLocaleLowerCase('en-US');
  return allowed.some((client) => normalized === client.toLocaleLowerCase('en-US'));
}

export function resolveActiveProject({ workspaceRoot, registry, clientId = 'unknown' } = {}) {
  const candidate = canonicalPath(workspaceRoot || process.env.I_WORKSPACE_ROOT || process.env.CLAUDE_PROJECT_DIR || process.cwd());
  const gitRoot = inferGitRoot(candidate);
  const lookupRoots = [candidate, ...(gitRoot ? [gitRoot] : [])];
  const matches = [];
  for (const project of registry.projects) {
    for (const root of project.roots) {
      if (lookupRoots.some((lookup) => isWithin(root, lookup))) {
        matches.push({ project, root });
      }
    }
  }
  matches.sort((a, b) => b.root.length - a.root.length);
  if (matches.length > 0) {
    const { project, root } = matches[0];
    const allowed = clientAllowed(project, clientId);
    return {
      ...project,
      active_root: root,
      registered: true,
      access_status: allowed ? 'allowed' : 'client_not_allowed',
    };
  }

  const activeRoot = gitRoot || candidate;
  const rootName = basename(activeRoot) || 'workspace';
  return {
    project_id: `ephemeral-${hashPath(activeRoot)}`,
    project_key: `ephemeral-${slug(rootName)}-${hashPath(activeRoot)}`,
    display_name: rootName,
    roots: [activeRoot],
    active_root: activeRoot,
    provider: 'generic_git',
    context_files: [],
    policy: {
      id: 'ephemeral',
      classification: 'unclassified',
      cross_project_visibility: 'hidden',
      memory_v3: 'none',
      allowed_clients: ['*'],
    },
    registered: false,
    access_status: 'registration_required',
  };
}

export function resolveContextFile(project, contextFile) {
  const root = project.active_root || project.roots[0];
  const candidate = resolve(root, contextFile.path);
  if (!isWithin(root, canonicalPath(candidate))) {
    throw new Error(`context file escapes project root: ${contextFile.path}`);
  }
  if (!existsSync(candidate)) return null;
  const realCandidate = canonicalPath(candidate);
  if (!isWithin(root, realCandidate)) {
    throw new Error(`context file symlink escapes project root: ${contextFile.path}`);
  }
  return candidate;
}

export function publicProjectDescriptor(project) {
  return {
    project_id: project.project_id,
    project_key: project.project_key,
    display_name: project.display_name,
    registered: project.registered,
    access_status: project.access_status,
    provider: project.provider,
    policy: {
      id: project.policy.id,
      classification: project.policy.classification,
      cross_project_visibility: project.policy.cross_project_visibility,
      memory_v3: project.policy.memory_v3,
    },
  };
}

export function projectsVisibleToClient(registry, clientId) {
  return registry.projects.filter((project) => (
    project.policy.cross_project_visibility !== 'hidden' && clientAllowed(project, clientId)
  ));
}
