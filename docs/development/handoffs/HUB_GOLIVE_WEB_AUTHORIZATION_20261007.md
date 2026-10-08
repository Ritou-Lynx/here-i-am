# P1 Web exact-action approval source candidate

Scope: non-release source and synthetic tests only. No trusted UI, signing key,
owner grant, service, endpoint, production data, or device was provisioned.

## Executable interface

`tools/i_core/web_action_authorization.mjs` separates three operations:

1. `createWebActionChallenge` constructs an untrusted proposal from the complete
   wire intent (including protocol, Core ID, schema, operation ID, target ID,
   revision, payload, provenance, actor and timestamps), current principal binding,
   intended signer ID and a validity window of at most five minutes.
2. `approveWebActionChallenge` is a local trusted UI boundary. It rechecks the
   exact full request/binding against the displayed proposal and signs its
   canonical digest envelope with an Ed25519 private key. This function MUST NOT
   be exposed as an MCP tool, OAuth-authorized HTTP endpoint, or model command.
3. `createTrustedWebAuthorizationVerifier` is a synchronous DomainStore callback.
   It verifies the signature against CURRENT owner-controlled public keys, exact
   principal/generation/installation/Core binding, operation kind, digest and
   validity. Missing, duplicate, malformed, asynchronous or failing key
   configuration denies. The default key list is empty.

The `wua1` reference contains no capture body or private key. It binds the full
canonical request digest. Only captures create from claude_web, text-only patch,
and delete using user_via_agent are supported. It grants no planner authority.
No OAuth token, request actor label, chat text or random UUID becomes approval.

The caller fixes the final complete wire intent BEFORE approval. Client-side
normalization, rebasing, timestamp changes or a new operation ID after approval
invalidate it. A changed request requires fresh human review.

## Replay and recovery

DomainStore provides the durable operation ledger and idempotency check; there is
no new schema or second approval ledger. Exact retries within validity return the
existing receipt with one effect. After expiry/revocation, an unexecuted action is
denied. For a lost response, use the existing scoped operation lookup to determine
the prior result. Web MCP exposes the read-only `capture_operation({op_id})`
and `i_remember({action:"operation",op_id})` paths for this recovery. They require
the current principal and scopes, preserve unknown/hidden/error outcomes, and
cannot submit a replacement write. Opaque authorization refs allow up to 4096
characters in both the published schema and runtime checks.
Do not replace the authorization reference on the same operation
or issue another operation merely because the response was lost.

Public-key removal, action narrowing and principal rotation prevent outstanding
unexecuted approvals. They cannot undo already accepted writes. Owner key changes
must be serialized with host operations by the eventual configuration adapter.

## Remaining product decision and real Gate

Recommended reviewable integration: an owner-controlled local confirmation screen
displays the exact proposed action, content, target and current binding, holds the
Ed25519 private key outside model/MCP access, and returns only the signed reference
after a deliberate confirmation. A separately approved phone confirmation surface
could implement the same protocol. Parent must decide the trusted surface and
secure key provisioning/recovery policy before any production enablement.

Tests call the signing function with synthetic keys; that proves cryptographic
and storage behavior, not an actual human confirmation or trusted-UI deployment.
The host defaults to deny until owner policy supplies a verifier/key registry.

## Validation

Eight tests cover no-authority proposals/OAuth/chat identifiers, exact request and
principal binding, altered rendered requests, short validity, revocation,
replacement, narrowed grants, malformed proofs, and real DomainStore acceptance
with one durable receipt, rejected asynchronous key sources, and private-key
misconfiguration in the public-key registry. All eight passed on Node 24.14.1 on
2026-10-07 using in-memory synthetic data only. The full MCP group passed 102
tests, including a real long wua1 ref through the handler and same-operation
lookup after response loss, approval expiry and signing-key removal.
