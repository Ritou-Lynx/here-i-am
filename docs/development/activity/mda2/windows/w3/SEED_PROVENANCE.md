# MDA-2 W3 seed provenance

- Task: `01a09699-5a54-7fb0-8b05-f69972c3b118`
- Source baseline: `68307c9ea837f11dc82e148e8f51feff89b50fb6`
- Branch: `codex/mda2-w3-windows-wiring-20260913`
- Frozen W2 source: task `01a09504-2fbf-7963-82a5-d9940f635d70`, tree `C:/Users/ExampleUser/.codex/worktrees/4dd2/memex`
- Frozen W2 patch SHA-256: `52bbb322eb5820a4b1cfa13b432aa6a823a104c1a4f43c4c37575899c0dd0c88`
- Frozen W2 verification SHA-256: `7b6d571623f2cdcf48ca882054960a840dd36995f01f2099532f38bc4b80c167`
- Frozen W2 source manifest SHA-256: `34e287504b377ef12fda1ab9115601eb972b7efafb8c450279ff68ff357962cf`
- Baseline `tools/i_core/activity_control_plane.mjs` checkout SHA-256: `525295357490814c69fb204358e019f862e916c09efc5f5ff85b99043f83f222`
- Baseline `tools/i_core/i_core_store.mjs` checkout SHA-256: `883a35c128ee88f7689b737de2245ef073f0c6b96902385241f30c08eb8f816d`

## Import decision

The seven W2 main execution sources plus two fixture sources (nine total), and the seven W2 historical delivery files were imported from the frozen source. The two W2 Core dependencies were not imported. The current baseline Core remains authoritative. Exact `text eol=lf` rules were added only for the nine executable JavaScript/PowerShell paths. The frozen `SOURCE_MANIFEST.json` has one exact `-text` exception so its reviewed CRLF bytes and published SHA survive in the Git blob; other historical evidence remains separate from W3 results.

## Seed replay

- A first sandboxed replay was rejected by the unchanged Windows ancestor-handle guard with `windows_protection_rejected_ancestor_handles_path_lock_failed_5`; Node exited `1`, no result was parsed, and its named temporary mirror was removed.
- A second replay used the normal reviewed elevation path against a newly created temporary mirror. It passed `35/35`, reported `scratchRemoved=true`, asserted every recorded clean guard exit as code `0` with the database closed, exited Node with code `0`, and removed the named mirror.
- This replay proves only the frozen W2 queue suite against the new baseline Core. It is not W3 acceptance, real collection, real network, production recovery, or a device Gate.
