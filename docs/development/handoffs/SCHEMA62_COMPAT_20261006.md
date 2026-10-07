# Schema 61/62 B3 compatibility — 2026-10-06

- Worker: `schema62_compat`; isolated branch `codex/schema62-compat-20261006`; base `d9a8498264d349f8593cd421e76db3e77ad102fd`.
- Authority: B3 `8770aa6048daa78ed192212022ca2c2ff92bb394`; checked B3 `3a9336b122b2fda22ff65ed32d9cee263e8fc2da` has no differences in the three database source/generated files.
- Mainline schema advances 60 → 62. Version 61 adds nullable `persona_chat_messages.created_at_ms INTEGER` and `server_sequence INTEGER`; version 62 adds `sync_outbox_messages.sender TEXT NOT NULL DEFAULT 'user'`. Future migrations must start at 63.
- Both complete table class regions and the complete 61/62 migration region match B3 literally after line-ending normalization. Removing that migration region and reverting only the schema version reproduces the base `app_database.dart` exactly: all prior migrations, including 60, and lifecycle handling are preserved.
- No sender backfill beyond B3's default, no sync runtime changes, no production access. Old PR10 companion rows whose new sender defaults to user remain a runtime compatibility concern for the transcript worker.

## Generation and fixture provenance

- `flutter pub get --enforce-lockfile` succeeded without dependency/lockfile changes.
- `dart run build_runner build --build-filter=lib/db/app_database.g.dart` succeeded (96 s). No generated file was hand-edited. Incidental unrelated generated-file deletions and Flutter plugin registration output were restored to their clean baseline.
- The target generated file includes the three new fields and one pre-existing `DevAgentRun.model` documentation comment automatically brought up to date by the generator; no unrelated generated semantics changed. Generator emitted existing DevAgent table reference warnings; those table source definitions were not changed.
- `dart run drift_dev schema dump <B3>/lib/db/app_database.dart .dart_tool/b3_schema62.json` exported 78 exact SQLite `fixed_sql` statements from the authority source. `test/db/fixtures/b3_schema62.sql` stores those statements plus six SQL index statements extracted from B3 `_createGameIndices`, which runs during `beforeOpen`. Other runtime-only indices are outside this table/schema fixture.
- Fixture SHA256: `7ADA80F5EACE1A79745CDC2CEA55C80DF826297DAB2C25BD6715D0961C309780`. The fixture contains DDL only; all rows used in tests are synthetic.

## Verification

- PASS, exit 0, 14 tests: `flutter test --no-pub --concurrency=1 test/db/b3_schema62_compatibility_test.dart test/db/persona_chat_sync_migration_test.dart test/db/stable_message_ref_migration_test.dart test/db/dev_agent_codex_options_migration_test.dart test/db/app_database_lifecycle_test.dart`.
- Four new tests cover exact B3 schema62 original/copy separation and two reopens; all schema objects and all inserted chat/outbox/cursor rows preserved; original bytes untouched; user/companion sender, integer IDs, sync/origin IDs, millisecond timestamp and server sequence retained; SQLite integrity check; 60→62 and 61→62 matching independently applied B3 ALTER SQL exactly; fresh mainline chat/outbox column definitions equal the frozen B3 definition.
- Installation identity is a SharedPreferences mock and remains unchanged through `DeviceIdentityService.getOrCreate`; actual preferences/secure storage are outside the SQLite fixture and were not accessed.
- Existing v59 migration test now expects `db.schemaVersion` rather than hard-coded 60 while retaining its complete Codex-column and row-preservation assertions.
- Initial run exposed a test import collision (fixed), missing six fixture startup indices (fixture completed), and the old hard-coded version assertion (updated). Two old migration tests timed out in that failed concurrent compilation run; the complete sequential rerun passed without increasing timeouts or skipping tests.
- PASS, exit 0, no issues: `dart analyze lib/db/app_database.dart lib/db/tables.dart test/db/b3_schema62_compatibility_test.dart test/db/dev_agent_codex_options_migration_test.dart`. A repeated normal-environment check hit known Windows Dart perf shutdown errno 1920; final check used a process-only `.dart_tool/analysis-local` LOCALAPPDATA and restored the original value in `finally`.
- `git diff --check` passed. No dependency upgrades, test suppression, app build, phone installation, ADB, services, or real database access occurred.

## Integration

- Authorized package-only commit uses the existing one-shot `SKIP_PROJECT_STATE=1` exception; the environment is restored in `finally`. Global DEVLOG and project state remain owned by the main agent. No push or PR is authorized for this worker.
- Main agent must independently review/integrate this package, perform the protected real-B3-copy exercise and any combined candidate build, and retain those separate evidence boundaries.
