# P5 Phone Desktop Read-only Handoff

## Scope and result

- Baseline: `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`.
- Added process-memory-only `PhoneMemoryReadClient` at
  `lib/data/memory_v3/readonly/phone_memory_read_client.dart`.
- The client accepts only exact-shape bounded `p5v1` codes, validates an
  authenticated status response before replacing a session, fixes transport to
  `127.0.0.1:47851`, bypasses proxies, disables redirects, and streams with a
  32KiB hard response cap plus one monotonic overall deadline. Each request
  owns a cancel token and closes its response stream on every exit path.
  Credentials and query text are not persisted, logged, returned in receipts,
  or added to prompts.
- A monotonically increasing connection generation revokes a pending
  connect/read after disconnect or replacement; old work cannot restore a
  credential, receipt, or Dreaming result.
- The bounded phone DTO carries only a process-local, credential-free lease.
  Prompt rendering rechecks it, so a disconnect or expiry between assembly and
  Runtime submission emits `dreaming_status: unavailable` with no phone body.
- `WorkbenchRelationshipContextAssembler` now uses the configured phone client
  only for `persona:i` Dreaming. Persona and recent desktop chat remain local.
  Once selected, phone expiry/failure is surfaced as `unavailable` with
  `phone_v3_live` source metadata; it never silently substitutes local
  Dreaming. Explicit `disconnect()` is the only return to local selection.

## Verification

- The earlier focused `flutter test --no-pub` client/context run passed 10
  tests before the transport/revocation hardening follow-up.
- Follow-up static analysis of the changed client and test is clean. Per main
  window instruction, the newly added stream/deadline/revocation/expiry
  fixtures were not run here; main window will run the serial combined
  verification.
- No build, install, real device, data operation, commit, or staging was done.

## Integration note

- The main window owns the real Drift-to-HTTP-to-client-to-assembler-to-Runtime
  composition fixture and the final serial test run.
