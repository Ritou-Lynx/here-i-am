# Hub Go-Live Core runtime change inventory

Date: 2026-10-07  
Earlier review baseline: `b19cd3dd4ac74b8f3a2c2d973e4d42b724b998f7`  
Comparison base: `0a24cac2b7db812f34fb845325e27b77d16139dd`  
Branch: `codex/hub-golive-src-20261007`

## Status and evidence boundary

This is a source and static import-dependency inventory. It did not read an active or private database, owner state, configuration, credential, service, or installed release. It did not start Core, build a release, change a launcher, or perform a deployment. Test results quoted from existing handoffs are historical source-candidate evidence and were not rerun for this inventory.

The first table records the earlier reviewed baseline `b19cd3dd`; the second table records the P1 increment delivered with this document. Together they inventory all 16 distinct changed Core runtime source files relative to the comparison base. Use the commit containing this document and its exact CI results as the candidate identity; neither table describes an installed runtime.

No go-live decision should be made from this inventory before the planned post-2026-10-17 review. Source presence and synthetic tests do not establish that an installed schema-6 runtime contains, configures, or safely activates these modules.

## Committed Core runtime changes

The base-to-`b19cd3dd` Core diff is 14 files, 1,691 insertions and 8 deletions. Nine files are runtime source and five are tests.

| File | Committed change | P1 necessity | Direct runtime dependencies and activation |
|---|---|---|---|
| `tools/i_core/i_core_server.mjs` | Adds the optional `domainConfigure` constructor option, rejects all domain authority/configuration options in inspection mode, and forwards the option to `ICoreStore`. The ordinary CLI entry in `b19cd3dd` still calls `createICoreServer(...)` without a personal-domain host. | Required plumbing for an enabled personal-domain host. By itself it does not enable P1. | Existing imports include `i_core_store.mjs`, `domain_http.mjs`, activity, inspection and relay modules. The committed CLI has no import or configuration path for `personal_domain_host.mjs`. |
| `tools/i_core/i_core_store.mjs` | Accepts `domainConfigure`; after a schema-6, non-`backup_read_only` `DomainStore` is built, it invokes the callback synchronously. Missing schema-6/domain store, a non-function callback, or an async callback fails closed and closes the DB on constructor failure. | Required. It is the only committed startup hook that can register and validate the four P1 domains before serving requests. | Uses Node `node:sqlite`, `domain_store.mjs`, and `domain_schema.mjs`. Requires metadata `schema_version=6`, a ready domain schema, a live role, and matching Core identity. |
| `tools/i_core/domain_store.mjs` | Passes `domain` into authorization verification; adds strict optional migration projection proof; binds that proof into adoption request identity; writes Core-HMAC record/binding authenticators to immutable operation metadata; includes the binding authenticator in production adoption receipts. | Required for exact phone/Web actor routing and for the P1 legacy-capture adoption proof. The migration additions are required only if legacy adoption is included in the P1 cutover. | Uses `domain_schema.mjs` and Node crypto. It still depends on injected synchronous authorization/business/adoption hooks; no verifier or domain is enabled by this file alone. |
| `tools/i_core/personal_domain_host.mjs` | Adds default-disabled composition for the four personal domains. It atomically registers an empty registry, validates existing registration exactly, preserves durable mode, composes business/dedup hooks, and routes `user_direct`, `user_via_agent`, and legacy adoption to injected verifiers. | Required host composition for P1. Importing it has no effect; `enabled:true`, an exact four-domain mode map, matching Core identity, and explicit `host.serverOptions` are required. | Imports `domain_store.mjs` and unchanged `personal_data_domains.mjs`. Requires an authority registry and synchronous verifiers. In `b19cd3dd`, no production entry point constructs it. |
| `tools/i_core/personal_domain_owner.mjs` | Adds explicit phone grant/rotate/revoke, private authority registry, capture-source lookup, frozen adoption manifests, migration apply, durable receipt/operation verification, and signed adoption reports. State is supplied by an injected adapter. | Required for P1 phone credentials and for legacy capture adoption. Normal read-only Core startup does not need to construct an owner. | Imports `domain_store.mjs`, `phone_ui_authorization.mjs`, `personal_domain_migration.mjs`, and Node crypto. Requires a protected synchronous state adapter; `b19cd3dd` does not provide a production adapter or recovery policy. |
| `tools/i_core/phone_ui_authorization.mjs` | Adds exact HMAC verification for trusted phone UI actions, bound to full intent plus Core/principal/generation/installation and a bounded action/domain allowlist. | Required when P1 accepts phone `user_direct` capture create/patch/delete or `plan_items` status actions. | Imports `domain_store.mjs` canonical JSON and Node crypto. Requires current grants from the private owner boundary; it does not create grants or store secrets. |
| `tools/i_core/web_action_authorization.mjs` | Adds an Ed25519 proposal/sign/verify candidate for exact Web capture intents, with a five-minute bound and public-key-only verifier registry. | **Not a P1 prerequisite under the current user policy.** Keep disabled unless a later decision explicitly selects it. | Imports `domain_store.mjs` and Node crypto. It creates no listener, key, principal, or trusted UI. A private-key deployment is outside this module. |
| `tools/i_core/personal_domain_migration.mjs` | Adds canonical migration digests and strict HMAC sign/verify for `i-domain-migration-v1` adoption reports. | Required only for the legacy capture takeover proof path. It is not part of steady-state request serving after migration unless reports are still being verified. | Imports `domain_store.mjs` and Node crypto. Requires explicit key material from the owner boundary and a bounded current time. |
| `tools/i_core/phone_capture_migration.mjs` | Adds an explicit adapter from the App frozen projection manifest plus caller-supplied closed-snapshot records into owner freeze/apply operations. It performs no discovery, grant, or automatic apply. | Required only if P1 includes legacy note/capture ownership transfer. | Imports `domain_store.mjs` and `personal_domain_migration.mjs`. Requires a caller-authorized closed snapshot and an already constructed owner. It does not read a store or file itself. |

Unchanged but necessary static dependencies for an enabled P1 host are `tools/i_core/domain_http.mjs`, `tools/i_core/domain_schema.mjs`, and `tools/i_core/personal_data_domains.mjs`, plus the existing activity/inspection/relay modules imported by the Core server. Node v24.14.1 is the pinned runtime in the schema-6 release source, and Core uses the built-in `node:sqlite` module rather than an npm SQLite package.

## P1 runtime increment delivered with this document

These changes close source composition gaps but do not change the installed schema-6 runtime:

| File | Behavior in this change | P1 role and dependency boundary |
|---|---|---|
| `tools/i_core/domain_http.mjs` | Extends only the controlled HTTP intent transport allowlist with `trigger_thread_id` and `trigger_sync_id`; no public endpoint or independent authorization mechanism is added. | Required wire plumbing for the host-injected Web session binding. `domain_store.mjs` performs the strict value/format validation and the verifier performs semantic equality checks. |
| `tools/i_core/domain_store.mjs` | Resolves configured Web capture requests from their wire actor into `user_via_agent` or `agent_inferred`. The durable request digest remains the original wire request. An existing op is recovered by original principal/domain/op/digest before re-evaluating an anchor, so a late or later-invalid message cannot promote, erase, or fork an accepted operation. | Required for policy A. The business hook must explicitly opt into actor resolution. The stored actor remains the resolved actor, while retry identity remains the exact wire request. |
| `tools/i_core/personal_data_domains.mjs` | Adds Web-principal actor resolution for `captures` create/patch/delete; permits missing or invalid anchors to become `agent_inferred`; restricts Web sources to configured `claude_web`; permits inferred deletion only through this Web policy; blocks Web deletion of non-`claude_web` records and records whose fields show a revision-after-create by `user_direct` or `user_via_agent`. | Required for current Web P1 semantics. This is policy code, not evidence that downstream App-generated cards or finance outputs have migrated. |
| `tools/i_core/personal_domain_host.mjs` | Passes the exact configured Web-principal set and verifier into personal-domain hooks while retaining phone and legacy-adoption verification. | Required active host wiring. Web principal IDs, source allowlists, processor principals, and modes remain explicit configuration. |
| `tools/i_core/web_user_message_authorization.mjs` | Implements policy A using a real Core `chat_messages` row. It checks Core identity, configured principal/device/installation/character, user sender, chat type, strict `claude_web:t_<thread>:<sequence>` identity, exact equality between authorization ref and host-injected trigger sync ID, exact equality between parsed and host-injected thread ID, and that no later Core message exists in that thread. Missing, wrong, closed, superseded, cross-session, or non-current anchors return false and therefore downgrade to `agent_inferred`. It does not inspect natural-language meaning and does not use Ed25519. | Required for selected Web P1 authority. Direct dependency is the active Core database supplied through `getDatabase`; it performs no file discovery. MCP session state clears its anchor at every start/end attempt, records only a successfully committed start anchor, prevents thread switching, and injects trigger sync/thread outside the model-visible tool schema. This proves exact committed-message identity and session position, not semantic field-by-field consent. |
| `tools/i_core/personal_domain_private_state.mjs` | Adds a Windows-only, CurrentUser DPAPI state adapter. Plaintext passes through pipes; disk holds a path/Core-bound ciphertext envelope. It uses an exclusive lock and durable temporary-file replacement. | Required for production owner grants/manifests. Direct dependencies are Node crypto/child-process/fs/path and Windows PowerShell/.NET DPAPI. Lock recovery, backup and CurrentUser service identity remain deployment concerns. |
| `tools/i_core/personal_domain_runtime.mjs` | Strictly loads an opt-in runtime config, acquires the private-state lock, constructs authority registry/host/server, validates configured Web principals and exposes explicit Web grant support. It dynamically imports `web_user_message_authorization.mjs`. | Required runtime assembly for P1. Direct imports: host, owner, private-state; dynamic import: Web user-message verifier. Requires absolute plain config/state paths, exact Core identity, four domain modes, and pre-provisioned active Web principals for ordinary startup. |
| `tools/i_core/personal_domain_server.mjs` | Adds a dedicated explicit P1 server entry. It imports the existing Core server, the personal runtime, Core protocol/store, and shortcut relay, and requires `I_CORE_PERSONAL_DOMAIN_CONFIG`. | Required executable entry for P1. The ordinary `i_core_server.mjs` main is restored and remains the legacy entry, so the protected old package remains buildable and cannot silently activate P1. |
| `tools/i_core/personal_domain_owner_cli.mjs` | Adds explicit local commands for phone/Web grant, phone rotate/revoke, and capture migration freeze/apply. Inputs and outputs are absolute, strict-shape files; sensitive outputs are written through a CurrentUser-only staging directory. It starts no listener. | Provisioning/migration dependency, not the steady-state server entry. Direct imports: Core server, personal runtime, phone capture migration; Windows ACL and file durability use child-process/fs/path. Its use is a separate owner action, not startup automation. |

This Core increment also adds focused tests for the runtime/owner workflow, private state (including a real-Windows DPAPI case), and the exact-session Web user-message policy. The main window reported the final six-test Web group passing, including cross-session rejection and the case where a new same-thread user message has not reached Core and the old Core tail must not be reused. These are focused local results for the shared working tree, not a completed branch CI run.

## P1 minimum and optional groups

The complete branch changes form three separate groups and should be reviewed that way:

1. **Mandatory Core host plumbing:** `i_core_server.mjs`, `i_core_store.mjs`, `domain_store.mjs`, `personal_domain_host.mjs`, plus `domain_http.mjs`, `personal_data_domains.mjs` and unchanged `domain_schema.mjs`; the new formal server, runtime and private-state modules are also mandatory.
2. **Mandatory authority for the selected P1 surfaces:** phone actions require `personal_domain_owner.mjs` and `phone_ui_authorization.mjs`. The current Web policy requires `web_user_message_authorization.mjs`, actor-resolution changes in `domain_store.mjs` and `personal_data_domains.mjs`, and exact configured Web principal mapping.
3. **Conditional legacy takeover:** `personal_domain_migration.mjs`, `phone_capture_migration.mjs`, the adoption portions of `personal_domain_owner.mjs`, and the adoption proof changes in `domain_store.mjs`. These are necessary only when the old note/capture outputs are actually transferred. They do not authorize or trigger the transfer themselves.

`web_action_authorization.mjs` is retained source, not the selected P1 Web authority and not a blocker for P1. It must not be silently enabled as a substitute for the current `sync_id` policy.

## Current user-message authorization policy versus PR11

PR11 local commit `5e06c3da8a40ddb746f48e7651865d3b697f66c9` anchored a Memory V3 `user_via_agent` card edit to the triggering local user-chat row's `sync_id`. Its tool checked that the local row existed, belonged to the same character and ordinary chat, came from the user, and had a non-empty `sync_id`; otherwise it rejected the write.

The current user decision keeps the real-user-turn anchor but changes where and how it is resolved:

- a real triggering user message's Core `sync_id`, verified against Core's message data, is the credential for `user_via_agent`;
- the caller or model cannot promote itself merely by supplying an arbitrary `sync_id`; Core must resolve the actor from the verified message anchor and current request context;
- if no valid user-turn anchor exists, the write is not rejected solely for that reason: it is handled as `agent_inferred` and remains subject to that actor's ordinary field/business policy;
- there is no per-item trusted-UI confirmation requirement;
- the Ed25519 Web action implementation remains disabled and is not a P1 prerequisite.

Therefore the PR11 `sync_id` remains the authority concept, but its local App lookup and reject-on-missing behavior are not the P1 enforcement boundary. The current Core path verifies a strict Core message anchor, resolves the actor centrally, and preserves the original wire request for idempotency. It proves the existence, binding and per-thread tail position of the message; it does not prove that the message's natural language semantically authorizes every field in the capture intent.

## Packaging and active schema-6 replacement boundary

The protected schema-6 packager currently inventories the existing Core server/store/domain/schema/HTTP and `personal_data_domains.mjs`. It does **not** inventory `personal_domain_server.mjs`, `personal_domain_runtime.mjs`, `personal_domain_private_state.mjs`, `personal_domain_host.mjs`, `personal_domain_owner.mjs`, either active/candidate Web authorization module, phone authorization, the owner CLI, or the migration adapters. Its import validator also rejects unlisted relative imports and dynamic imports from packaged Core sources.

Consequences for the complete candidate:

- packaging the changed `i_core_server.mjs`, `i_core_store.mjs`, `domain_store.mjs`, and current policy files alone preserves the legacy entry behavior because ordinary `i_core_server.mjs` never constructs the P1 host;
- copying the new host modules beside an installed runtime is insufficient because they are neither pinned nor imported/configured by the committed entry point;
- the new `personal_domain_server.mjs` is the explicit P1 entry, but neither it nor its closure is in the protected old package manifest;
- its static closure includes personal runtime, host, owner, private state, existing Core server/store/domain HTTP/schema/personal policy, phone authorization/migration proof modules, activity/inspection/relay dependencies, and Node built-ins; `personal_domain_runtime.mjs` also dynamically imports the user-message verifier. Reusing the old packager would reject that dynamic import and the unlisted files;
- an enabled P1 runtime therefore needs a newly reviewed package choice and complete dependency inventory with exact hashes, explicit four-domain modes, private-state adapter, user-message actor resolver, current principals/scopes, and rollback/recovery handling. It must not bypass or weaken the protected old package's import validator;
- the old schema-4 runtime pin is a different frozen package and is not a source for schema-6 P1 activation;
- no current source result proves compatibility with an active private schema-6 database, current WAL/SHM state, owner data, installed task, or service lifecycle.

A replacement candidate therefore requires, at minimum, one frozen commit, one complete direct and dynamic dependency closure for the new entry, the pinned Node executable, separately reviewed packaging/lifecycle support for that entry, and a configuration whose Core identity and four domain modes match durable registration. It must still pass offline copy preflight, backup/recovery review, one-runtime ownership checks, synthetic regression, cross-language App/Core checks, and the separately authorized human/device migration Gate. None of those deployment actions occurred in this audit. The earliest intended decision window is approximately after Lynx is settled in Shanghai on 2026-10-17; this source review does not authorize touching the current runtime before then.

## Test inventory and limits

Base-to-`b19cd3dd` added these focused tests:

- `personal_domain_host.test.mjs`: 7 cases;
- `phone_capture_migration.test.mjs`: 1 case;
- `phone_ui_authorization.test.mjs`: 7 cases;
- `web_action_authorization.test.mjs`: 8 cases.

It also adjusted `domain_adoption.test.mjs`, whose 12 cases cover dry-run/apply, authority, conflict, rollback, privacy, mode, and lost-response replay. This gives 35 directly relevant test cases, with overlap between host and adoption coverage.

The existing P1 host handoff records a 53-test scoped run, a 175-test Core integration recheck, a 20-test adapter/host/adoption group, and a separate 1-test source-adapter run. Those counts overlap and describe the earlier candidate. They are not additive and were not independently rerun here. The main window separately reported the unchanged protected schema-6 release group passing 32/32 after the ordinary server entry was restored; this proves the old package remains internally build/test compatible, not that it contains or can start P1.

Before a later integration decision, rerun the explicitly enumerated Core files against the frozen final commit, verify the package import closure, and record source hash, Node hash, test count, and exit status. A successful source test run still does not constitute deployment, migration, service, or human Gate evidence.

## Main-window package review checklist

The main window should attach the following deployment-specific evidence:

1. the final commit containing `personal_domain_server.mjs`, `personal_domain_runtime.mjs`, protected private-state handling, Core-backed user-message authorization, actor resolution, and host/policy changes;
2. whether each new module is statically included in the schema-6 package inventory and lifecycle configuration, or deliberately deferred beyond 2026-10-17;
3. exact P1 modes and principal/processor/Web mappings, without embedding secrets or private paths;
4. final test commands and non-overlapping counts for the frozen tree;
5. an explicit statement that package build, private-copy preflight, installed runtime replacement, migration apply, and user/device Gate remain separate approvals and evidence windows.
