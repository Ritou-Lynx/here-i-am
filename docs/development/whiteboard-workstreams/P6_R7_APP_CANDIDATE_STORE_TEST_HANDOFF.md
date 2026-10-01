# P6 R7 candidate store test handoff

2026-09-12

- Added `test/data/workbench_ai/candidate/p6_r7_candidate_store_test.dart`.
- The test uses a temporary candidate root and a loopback-only fake attestation
  server with a fresh challenge response. It covers admission rejection before
  a database exists, required live-host proof, a real fixed-file schema-60
  store, tool-host enqueue persistence, and a restart that keeps the durable
  row pending without automatic dispatch.
- Restart admission also rejects an altered manifest marker, unowned file,
  wrong SQLite user version, changed database identity marker, and invalid
  stored task identity.
- `dart` and `flutter` were not present on this worker's PATH, so this worker
  could not format or execute the test. The integration owner should run the
  targeted Flutter test from the worktree after the local Flutter runtime is
  available.
