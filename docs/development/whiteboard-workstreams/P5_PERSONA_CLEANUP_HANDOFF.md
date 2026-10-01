# P5 — Desktop Persona Prompt Cleanup Handoff

> Goal / work package: `GOAL-20260824-ai-workbench-wave1` / P5 Persona cleanup
> Baseline: `455be35e114a6b34f30388938e3177abbc42009f`
> Branch / worktree: `codex/whiteboard-w0-p5-persona-cleanup` / `D:/memex/.worktrees/p5-persona-cleanup`

## Result

- Desktop Workbench now owns `workbench_desktop_persona_prompt.dart`, whose
  text is the user-approved cleaned prompt verbatim. It is not derived from
  the mobile Companion prompt.
- The production turn input no longer frames identity as an external role to
  follow. It retains the existing host-owned relationship context wrapper,
  read-only search guidance, and all authorization guidance.
- The real `WorkbenchRelationshipContextAssembler` injects the desktop text
  for the accepted `persona:i` / `i` scope. Dreaming empty, Dreaming failure,
  and the bounded relationship-context fallback still carry that fixed text.
- Rejected conversation scope, unsupported character scope, missing character,
  and disabled character do not carry the desktop text. No new role is created
  for another character.

## Status semantics

`persona_status: available` now means the fixed, product-owned desktop persona
was available. It does not claim that a Character backend read succeeded. When
that read fails, the prompt still records `character_backend_unavailable`, and
the recent/Dreaming statuses remain `unavailable`; this does not turn a failed
Dreaming lookup into `empty`.

## Scope and contract impact

- No Card / Source / Anchor contract, schema, migration, dependency, generated
  file, tool permission lane, or User-truth write path changed.
- Mobile keeps its existing `CompanionPersonaPromptBuilder` output unchanged.
- This is deliberately a desktop-only prompt source, not a cross-runtime
  identity refactor.

## Verification

- `D:\\flutter\\bin\\flutter.bat test --no-pub test/data/workbench_ai/context/workbench_relationship_context_test.dart test/data/workbench_ai/workbench_conversation_coordinator_test.dart test/agent/companion_prompt_test.dart --concurrency=1`
- `D:\\flutter\\bin\\dart.bat analyze lib/data/workbench_ai/context/workbench_desktop_persona_prompt.dart lib/data/workbench_ai/context/workbench_relationship_context.dart lib/data/workbench_ai/workbench_conversation_coordinator.dart test/data/workbench_ai/context/workbench_relationship_context_test.dart test/data/workbench_ai/workbench_conversation_coordinator_test.dart`
- `git diff --check`

Result summary: after `D:\\flutter\\bin\\flutter.bat pub get --offline`
completed successfully, the targeted Flutter run exited successfully with
**37/37 tests passing** (7 relationship-context, 25 conversation-coordinator,
and 5 mobile Companion regression tests). The changed-file analysis and diff
check also exited successfully with no reported issues. This is a terminal
summary rather than a checked-in test log; the command above is the exact,
reproducible invocation.

The coordinator test exercises `productionComposition` with the real
relationship-context assembler and a fake backend, rather than injecting a
prebuilt relationship context. It also covers backend failure/timeout fallback
and rejected-scope non-injection. No build or real-user-data read was run.

## Integration and remaining gate

- Review and selectively integrate this single commit after checking the
  retained host-owned context, tool authorization, and scope behavior.
- The existing desktop application remains a separate candidate. A fresh build
  and the P5 human Gate are still required after integration; this worktree did
  not build, launch, read private data, or control UI.
