// Test-only packaging lab: a real temporary Git repository with synthetic provenance.
// Production BASELINE, Node hash, builder, and launcher are never changed.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { BASELINE, SOURCE_FILES } from '../../runtime_pin/prepare_runtime_pin.mjs';

export const syntheticSourceFiles = [...SOURCE_FILES, 'tools/i_core/activity_control_plane.mjs', 'tools/i_core/domain_http.mjs', 'tools/i_core/domain_store.mjs', 'tools/i_core/domain_schema.mjs'];
function replaceOnce(source, before, after) {
  assert.equal(source.split(before).length, 2, `fixture transform must match exactly once: ${before}`);
  return source.replace(before, after);
}
export async function prepareSyntheticRuntimePin({ root, repository, nodePath }) {
  const fixtureRepository = path.join(root, 'synthetic-repository');
  mkdirSync(fixtureRepository);
  const git = (...args) => execFileSync('git', ['-C', fixtureRepository, ...args], {
    windowsHide: true, encoding: 'utf8', env: { ...process.env,
      GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(root, 'absent-gitconfig'),
      GIT_AUTHOR_NAME: 'Synthetic fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
      GIT_COMMITTER_NAME: 'Synthetic fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid',
      GIT_AUTHOR_DATE: '2026-10-05T00:00:00Z', GIT_COMMITTER_DATE: '2026-10-05T00:00:00Z' },
  });
  for (const name of syntheticSourceFiles) {
    let bytes = readFileSync(path.join(repository, name));
    if (name.endsWith('/i_core_store.mjs')) {
      let text = bytes.toString('utf8');
      const start = text.indexOf('      this.activity = new ActivityControlPlane(this.db, {');
      const end = text.indexOf('      });', start) + '      });'.length;
      assert.ok(start > 0 && end > start);
      // All original public core methods remain. Only activity schema creation is
      // replaced for this test package, which must keep its synthetic DB at v4.
      text = text.slice(0, start) + `      // SYNTHETIC SCHEMA4 FIXTURE: never a historical runtime reconstruction.
      if (activityEnabled || activityRecoveryFloor) throw new Error('synthetic_schema4_activity_unsupported');
      this.activity = Object.freeze({
        schemaStatus: () => ({ ready: false, schema_version: null }),
        isActiveCredentialToken: () => false,
        releaseRuntimeClaim() {},
      });` + text.slice(end);
      bytes = Buffer.from(text);
    }
    const destination = path.join(fixtureRepository, name);
    mkdirSync(path.dirname(destination), { recursive: true });
    writeFileSync(destination, bytes, { flag: 'wx' });
  }
  git('init', '--quiet');
  git('-c', 'core.autocrlf=false', 'add', '--', 'tools');
  git('-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=NUL', 'commit', '--quiet', '-m', 'Public synthetic schema4 runtime test fixture');
  const sourceCommit = git('rev-parse', 'HEAD').trim();
  assert.notEqual(sourceCommit, BASELINE);
  const runtime = path.join(fixtureRepository, 'tools/i_core/runtime_pin');
  mkdirSync(runtime);
  let builder = readFileSync(path.join(repository, 'tools/i_core/runtime_pin/prepare_runtime_pin.mjs'), 'utf8');
  builder = replaceOnce(builder, BASELINE, sourceCommit);
  builder = replaceOnce(builder, "'i_core_server.mjs', 'i_core_store.mjs',", "'i_core_server.mjs', 'i_core_store.mjs', 'activity_control_plane.mjs', 'domain_http.mjs', 'domain_store.mjs', 'domain_schema.mjs',");
  builder = replaceOnce(builder, "release: 'v4-bbb8025d'", "release: 'synthetic-public-schema4-test-only'");
  writeFileSync(path.join(runtime, 'prepare_runtime_pin.mjs'), builder);
  let wrapper = readFileSync(path.join(repository, 'tools/i_core/runtime_pin/start_pinned_i_core.ps1'), 'utf8');
  wrapper = replaceOnce(wrapper, BASELINE, sourceCommit);
  wrapper = replaceOnce(wrapper, "'tools/i_core/i_core_server.mjs', 'tools/i_core/i_core_store.mjs',", "'tools/i_core/i_core_server.mjs', 'tools/i_core/i_core_store.mjs', 'tools/i_core/activity_control_plane.mjs', 'tools/i_core/domain_http.mjs', 'tools/i_core/domain_store.mjs', 'tools/i_core/domain_schema.mjs',");
  wrapper = replaceOnce(wrapper, "@('i_core_server.mjs', 'i_core_store.mjs',", "@('i_core_server.mjs', 'i_core_store.mjs', 'activity_control_plane.mjs', 'domain_http.mjs', 'domain_store.mjs', 'domain_schema.mjs',");
  writeFileSync(path.join(runtime, 'start_pinned_i_core.ps1'), wrapper);
  writeFileSync(path.join(runtime, 'verify_v4_state.mjs'), readFileSync(path.join(repository, 'tools/i_core/runtime_pin/verify_v4_state.mjs')));
  const { prepareRuntimePin } = await import(pathToFileURL(path.join(runtime, 'prepare_runtime_pin.mjs')));
  const result = prepareRuntimePin({ repository: fixtureRepository, output: path.join(root, 'release'), nodePath });
  assert.equal(result.source_commit, sourceCommit);
  return { ...result, fixtureRepository, sourceCommit };
}
