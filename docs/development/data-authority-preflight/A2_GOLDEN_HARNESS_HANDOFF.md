# A2 Golden Corpus & Isolated Harness Handoff

## Delivery identity

- Goal / work package: `GOAL-20260826-authority-preflight` / A2.
- task/thread ID: `01a03c9b-75f4-7a23-bec4-224f5c77f739`.
- acceptance-main task/thread ID: `01a03c7e-ceda-7351-9ed6-93c48e9c15d5`.
- Worktree: `C:\Users\ExampleUser\.codex\worktrees\2d6b\here-i-am` (detached HEAD).
- dispatched baseline: `e72a5f733bace240312fd5a4b37a771e68d2fe89` (verified clean and a descendant of the required baseline before writing).
- current integrable replacement content commit: `defbfefe` (`fix(preflight): harden fixture isolation`).
- current test-lockdown commit: `225089df` (`test(preflight): lock down A2 classifications`).
- latest prior handoff commit: `2f26abf3`; this revision supersedes its first-screen status.
- current automated evidence: targeted test runner **7 passed**, changed-path `dart analyze` **No issues found**, and `git diff --check` passed before the test-lockdown commit.

## What is delivered

- `tools/data_authority_preflight/fixtures/golden_v1/`: synthetic, Chinese-inclusive corpus only. It covers ordinary Card incorrectly marked `user_truth`; explicit Memory/User-truth origin; matching and mismatching Source/Version/Anchor; unclassified RichText content; duplicate ID; invalid metadata; external move/delete; concurrent conflict; Dreaming promotion; absent Evidence production schema; unauthorized TaskArtifact promotion; unknown schema and object type.
- `tools/data_authority_preflight/lib/isolation_harness.dart`: validate-only harness. It accepts only an explicitly supplied fixture root below the managed synthetic fixture base and an explicitly supplied system-temporary output root outside the repository. It rejects production-like Vault/Gateway ledger/attachment/SQLite paths, repository production-data paths and undeclared fixture inputs.
- `tools/data_authority_preflight/run_harness.dart`: explicit two-root CLI. It never performs a migration and writes only deterministic `report.json` to the approved temporary output root.
- `test/data_authority_preflight/isolation_harness_test.dart`: normal load, every corpus red light, unknown/unsupported classes, byte-level determinism, production/output path rejection, undeclared-input rejection and fixture non-mutation coverage.

## Initial delivery evidence (historical only; superseded)

- Direct CLI: `D:\flutter\flutter\bin\cache\dart-sdk\bin\dart.exe tools/data_authority_preflight/run_harness.dart --fixture-root <golden_v1> --output-root <system-temp>` → validate-only report written, `1884` bytes; `migrationExecuted: false`.
- Targeted tests: direct `test-1.31.0` runner with the existing `.dart_tool/package_config.json` → **5 passed**.
- Changed-file analyze: `dart analyze tools/data_authority_preflight test/data_authority_preflight` → **No issues found**.
- `git diff --check` passed before the content commit.

## Scope and limitations

- No production code, Drift schema/migration, default authority, Runtime/Memory/Record Organizer wiring, A1 material, Goal/Roadmap/`I_PROJECT_STATE.md`/`DEVLOG.md`, real data, build, push or release was changed.
- The harness is deliberately a preflight classifier, not a migration engine. Unknown schemas/object types are `unsupported`; unresolved or policy-violating cases are `blocked`; it never converts either to success.
- A successful A2 report does not decide the formal Authority ADR, approve a TaskArtifact promotion, establish an Evidence schema, or unlock Gate 1A-0.

## Next action

Acceptance main window should audit `defbfefe` plus `225089df`, verify this updated handoff and run the same targeted test plus `git diff --check` during selective integration. Then retain every `blocked` / `unsupported` finding as formal Gate 1A-0 input; do not expand this harness into production migration work.

## Repaired historical deliveries

- The original three commits `7bc17ae9`, `5b5469f8`, and `05c80756` remain in history but are **not accepted for integration**; no amend, rebase, or reset was performed.
- Replacement content commit: `defbfefe` (`fix(preflight): harden fixture isolation`). It resolves every existing root with `resolveSymbolicLinksSync`, requires existing real directories, rejects links in fixture/output trees with `followLinks: false`, and only permits an existing, empty, dedicated strict child of the real system temp root.
- The manifest now requires schema version `1`, `synthetic: true`, the exact purpose string and an exact declared file allowlist. Unknown manifest schema returns `unsupported` before a report can be written. Fixture inputs and case count are bounded.
- The golden corpus now models structured Card/revision/history/empty values, Source/Version/Anchor, RichText block/mark/asset/unclassified payload, actual duplicate `stableId` values, explicit invalid metadata, and both TaskArtifact authorization states.
- Verification after the return: targeted test runner **6 passed**; changed-path `dart analyze` reported **No issues found**; `git diff --check` passed before `defbfefe`.
- Remaining limit: this is still a synthetic, validate-only preflight classifier. It has not defined a production Evidence schema, approved a TaskArtifact promotion, made a formal ADR decision, or run a migration.
