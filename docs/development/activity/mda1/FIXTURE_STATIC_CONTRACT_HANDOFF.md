# MDA-1 fixture static contract handoff

`tools/i_core/activity_fixture_contract.mjs` is a no-HTTP, no-Core static
fixture gate. It reads the MDA-0 manifest and four declared case files, parses
all five documents, performs the raw-document privacy scan before symbolic
references can be resolved, and then validates the closed fixture structure.

The gate requires the four manifest filenames and all 26 manifest case names
exactly once. It locally freezes the ADR v1 event-kind, nested-payload, and
coverage dictionaries and consumes the manifest outcome, HTTP-error, clock,
and sequence vocabularies.
It validates required scalar contract/schema fields (while retaining deliberate
negative vectors), every operation's required and forbidden fields, pairing
captures and their response types/producers, paired source/kind/coverage
registration, materialized-event and receipt references, the
three required-and-only allowlisted overrides, outbox binding, and the `1/3/2`
gap-recovery fixture order. It rejects unknown fields, a known field placed
where the closed schema does not consume it, missing or cross-case symbolic
references, skipped operations, normal templates containing `event_id`, and
overrides outside the three declared cases. Errors contain only a code and
structural path; they do not include captured prefix, token, event, request, or
response values.

Negative fixture cases are self-proving: the cross-device case must retain a
device/probe mismatch, missing and unknown field cases must retain their named
wire witnesses, and expected HTTP status/result/error combinations are checked
against a local, auditable protocol mapping. The sequence case additionally
locks `1,2,3` creation, `1,3,2` delivery, logical kinds, contiguous time and
coverage edges, gap diagnostics, and final recomputation to locked state.
The non-event projection witness and the three request witnesses are also
closed: their method/path/body/input shapes and declared denial properties are
checked without claiming that any HTTP route was exercised.
Each request witness is keyed by its fixed fixture case name, so swapping an
outcome, route, or case identity cannot repurpose another denial scenario.
The runner also freezes the canonical 26 scenario names plus their high-level
execution shape and declared primary result combinations. This prevents a
manifest and case document from being synchronously renamed or repurposed while
leaving actual HTTP execution to a later runner.

`materializeEvent` and `materializeAndQueue` are pure helpers. The latter
stores the exact UTF-8 JSON bytes that the materialized event would have, but
does not deliver anything. This is deliberately not an HTTP runner and does
not exercise Core behavior.

Run the static checks with:

```powershell
node --test tools/i_core/activity_fixture_contract.test.mjs
```

The test mutates copies in the system temporary directory only and cleans them
in `finally`; it never edits the checked-in fixture source documents. The
mutation suite includes the eight P1 regressions (kind, contract, vocabulary,
rotate principal, setup capture, fake materialization, override-to-recipe, and
outbox materialization) plus operation, coverage, HTTP-vocabulary, and receipt
reference negatives. It also locks payload closure/types, pair-registration
mismatches, sibling capture type, top-level outbox-only binding, and direct
submit substitution in the sequence-gap fixture.
