# P6 R7 candidate HTTP lifecycle probe

2026-09-12; baseline `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5` with existing P6 candidate changes. This worker added only `workbench_text_task_http_probe.mjs`, its test, and this handoff. No native CLI, UAC, provider/model request, production route, installed host, or existing service port was touched. Root owns independent review, freezing, and any actual acceptance.

## Explicit entry

`runHttpNativeProbe({ executable, sha256, scenario })` uses the real `ExperimentalRuntimeApi`, `WorkbenchTextTaskRuntimeAdapter`, broker/native-owner/client factories, and `createBridgeRuntimeShutdown`. It binds a new candidate HTTP listener to `127.0.0.1:0`. The generic adapter factory always rejects. Native executable and lowercase SHA-256 come only from explicit host options; HTTP supplies only the fixed text profile and a fresh execution epoch. No production availability flag is changed.

CLI arguments are exactly one of `--session-close`, `--create-disconnect`, or `--host-graceful`, followed by absolute executable path, lowercase SHA-256, and absolute report path. The report is reserved with exclusive `wx` before acquiring native resources. The report is emitted as bounded JSON; exit 0 requires actual candidate evidence and all checks, otherwise exit 2. There is no implicit/default execution mode.

The exported fixed input is `Reply exactly: P6_R7_NATIVE_OK`, reserved for later explicitly scoped work. None of these three scenarios calls `startTurn`. Probe facades additionally reject any attempted broker arm or `turn/start`, retaining counters. The original resources and three-pipe owner transport remain unchanged; the facade also supports frozen broker objects without modifying their methods.

Local HTTP requests use one private `http.Agent({keepAlive:false, proxyEnv:{}})` with a frozen empty map, and finally destroy it. Node v24.14.1 bundled `_http_agent` and `internal/http` source were read locally: explicit `options.proxyEnv` alone feeds this Agent's parser, an empty map yields no proxy URL, and no proxy config means direct routing. Thus `--use-env-proxy` on the acceptance Node host does not route this candidate HTTP client through the global proxy. Process environment, global Agent/proxy configuration, and broker default upstream transport are unchanged.

## Scenarios

- `session-close`: actual HTTP create must return 200 and the exact v2 execution receipt. HTTP DELETE must return 200 and an exact bound `closed_without_turn` receipt, including null turn/terminal identifiers and false provider-terminal/cancellation facts.
- `create-disconnect`: await the real client's successful `startThread` result, hold its return to the adapter, destroy the requesting HTTP client, then wait for the adapter's actual AbortSignal event before releasing that same held result. Wait for the server handler and owned cleanup. Success requires no execution receipt issued, no task stop receipt, and complete native/resource closure. A missing abort event or early HTTP completion fails.
- `host-graceful`: after actual create 200, call the real Bridge shutdown helper with permanent API stop. Retrieve the existing adapter's bound no-turn tombstone afterward; this scenario issues no HTTP DELETE.

## Evidence and closure

The report stores only fixed scenario/stage strings, generated attempt ID, selected supervisor hash, finite counters, booleans, and filtered native diagnostics. It does not store account values, model text, HTTP bodies, notification/native messages, paths, raw exceptions, or credentials. Account checking remains the existing runtime adapter's cached type-only operation; the probe observes only that `refreshToken:false` was used. Local binding values exist transiently to compare exact receipts and are omitted from the report.

Native success requires one owner, ready/start/config/requirements/cached-account/thread observations, all six actual native close facts, owner exit 0, no native failure, `cleanup_pending:false`, broker drain, finished handlers, and actual HTTP socket close events. A closed HTTP listener or API return alone cannot attest native cleanup. A failed/unknown creation can prove resource cleanup without receiving a task success receipt.

No-model checks permit the broker's existing bounded local metadata 404 behavior: all counters must be valid and bounded, `parsed_requests == metadata_rejections <= 8`, `admitted_connections == metadata_rejections`, rejected connection/request counts zero, upstream attempts zero, no released response, and no arm/start attempts. The admission equality follows the existing broker's `maxRequestsPerSocket=1` and metadata response `connection:close`. Other requests, admissions without an explained metadata request, or malformed counters fail.

The main flow deadline is 180 seconds. Finally permanently stops the same API/adapter, releases any test hold, closes the same native owner if still unconfirmed, drains its broker, and waits for held HTTP handlers and socket close events. Cleanup stages are independently bounded at 150 seconds (socket observation at one second); a hung creation can therefore leave an explicitly unsuccessful report even if native resource closure is separately observed. These bounds do not fabricate process EOF/Job/rule evidence or abandon ownership to a replacement owner. This is graceful/current-process acceptance only, not forced host death or a durable witness.

## Synthetic verification

The optional second argument accepts only full injected bottom-level factories and bounded test deadlines. The real API/runtime/ledger/shutdown and local HTTP remain in use. Any injection forces `evidence:synthetic`, `actual_native:false`, and `passed:false`; only `checks_passed` may be true. It cannot claim actual acceptance.

**10/10** probe tests pass under `node --use-env-proxy --test tools/dev_agent_bridge/workbench_text_task_http_probe.test.mjs`. Coverage includes all three scenarios, exact no-turn receipts, actual local disconnect-to-signal ordering, same-owner cleanup, rejected config/account, failed native handles/exit/drain, bounded metadata 404s versus unexpected requests, sanitized finite native diagnostics, deadline/unknown creation, explicit CLI validation, and private Agent routing/destruction with no global Agent dependency. Combined probe/API/shutdown regression was **27/27** before the final Agent test was added; root can rerun the final combination when freezing.

Hashes:

- probe: `5349A89EC54C58EBB287E963B75B219DE99D86277D64FCE2AC03F62140FC508E`
- tests: `AE7A2CA9F8FBF75C8A614392F407D319F25F6669C5AD32F5C9C9B7198E2173E9`

The default real factory sequence is kept in one explicit runner for later reuse. Forced-host termination, native durable final receipts, or witness processes are outside this implementation. This worker produced no actual native acceptance result.
