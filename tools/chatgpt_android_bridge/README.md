# ChatGPT Android sleep voice bridge PoC

This is a Windows/ADB experiment for the consumer ChatGPT Android app. It
validates one visible, user-authorized chain:

New-chat mode:

`ACTION_SEND draft -> Send -> completed response -> Read Aloud -> audio stop -> Voice`

Exact Project-conversation mode:

`/c/<conversation-id>?q=<draft> -> exact Project title -> Send -> completed response -> Read Aloud -> audio stop -> Voice`

It is not an OpenAI API, a supported Android deep-link contract, a scheduler, a sleep
detector, or a production call-delivery path. It does not bypass the lock
screen, enable Accessibility, read chat text into its receipt, save screenshots,
or retain UI XML. Once the bridge has issued a Read Aloud or Voice tap, a later
failure force-stops ChatGPT as emergency cleanup even when the corresponding
audio or microphone start could not yet be confirmed; failures before any
media tap do not close the user's app.

## Safety model

- The default invocation is DryRun. Live UI mutation requires `-Execute`.
- Device, ChatGPT version, phone model, display, locale, and keyboard must match
  an exact checked-in profile.
- Controls are selected from version-profiled layout relationships, not fixed
  screen coordinates. Nodes must belong to the ChatGPT package, and foreground,
  unlock, and awake state are rechecked immediately before every tap. Any
  missing or ambiguous relation stops the run.
- Project mode requires both an exact conversation ID and the expected Project
  title. The app must open the `/c/<id>` route with the UTF-8 `q` draft, and the
  expected title must occur exactly once in the version-profiled top header
  region before every state-changing tap. Matching text in a message body does
  not count. The receipt stores only SHA-256 hashes of those two identifiers.
- The complete Project URL, including `q`, is Base64-wrapped before it enters
  the ADB command and decoded only inside the device shell. This keeps the
  prompt out of routine plain command arguments; Base64 is transport encoding,
  not encryption against a privileged observer.
- Send is confirmed only when the populated composer becomes empty.
- A response is ready only when a unique completed-response action row appears.
- Read Aloud must create a new `com.openai.chatgpt` audio player with a recorded
  start followed by stop.
- Voice succeeds only while Android reports `RECORD_AUDIO` as `(running)`.
- Receipts contain state and boolean evidence, never prompt or response text.
- UI hierarchy XML uses `/data/local/tmp`, is removed after every read, and its
  absence is verified. Cleanup failure is a hard failure with a bounded retry.
- DryRun never launches ChatGPT. A successful run intentionally leaves Voice
  active for the user. A failed run performs no further coordinate UI actions.
  After an attributable media tap or observed active audio/recording, it always
  targets only `com.openai.chatgpt` with `force-stop`; foreground, lock, and
  screen checks are retained as receipt diagnostics and cannot suppress this
  emergency cleanup. Failures before any media action record why cleanup was
  skipped.

## Current supported profile

- Samsung `SM-S9110`
- display `1080x2340`
- locale prefix `zh`
- WeType input method `com.tencent.wetype`
- ChatGPT `1.2026.223` / version code `2622320`
- ChatGPT `1.2026.230` / version code `2623032`

Project-conversation mode is currently profiled only for `1.2026.230`. Its
populated composer has one left anchor plus exactly four non-overlapping right
controls whose start position, widths, gaps, and right edge match the observed
layout. Its empty composer may expose either controls to the right of the editor
or two non-overlapping controls overlaid inside the editor's right edge. These
variants remain separate from the ordinary new-chat selector.

Any app update or environment change returns `E_PROFILE_UNKNOWN` until a new
profile is inspected and tested.

## Run

Preflight only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\chatgpt_android_bridge\invoke_sleep_bridge_poc.ps1 `
  -Serial RFCWC01PBKK
```

One authorized live test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\chatgpt_android_bridge\invoke_sleep_bridge_poc.ps1 `
  -Execute `
  -Serial RFCWC01PBKK `
  -Prompt "只回复一句简短、自然、低刺激的睡前开场。"
```

One authorized live test in an existing ChatGPT Project conversation:

```powershell
$sleepPrompt = Get-Content -Raw `
  tools\chatgpt_android_bridge\sleep_intervention_prompt_zh_v1.txt
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\chatgpt_android_bridge\invoke_sleep_bridge_poc.ps1 `
  -Execute `
  -Serial RFCWC01PBKK `
  -ConversationId "<conversation-uuid>" `
  -ProjectTitle "<exact-visible-project-title>" `
  -Prompt $sleepPrompt
```

The conversation ID and Project title are runtime inputs and should not be
committed into a shared script. Project instructions are an official ChatGPT
Project feature, but this Android routing and UI selection remain a
version-specific observed bridge rather than a supported automation API.

Sleep-intervention language trial (the v1 prompt carries a second copy of the
sleep contract; it remains a normal per-chat user message, not an app-level
system instruction):

```powershell
$sleepPrompt = Get-Content -Raw `
  tools\chatgpt_android_bridge\sleep_intervention_prompt_zh_v1.txt
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\chatgpt_android_bridge\invoke_sleep_bridge_poc.ps1 `
  -Execute `
  -Serial RFCWC01PBKK `
  -Prompt $sleepPrompt
```

The ChatGPT Project instructions are available for manual review/paste at
`chatgpt_project_instructions_zh_v1.md`. That user-edited Project file is the
final authority for both the canonical sleep paragraph and the Project NSFW
block. `sleep_intervention_contract_zh_v1.txt` mirrors its sleep paragraph
verbatim; the per-call prompt embeds that exact paragraph and adds only the
necessary identity, device-event, and first-line wrapper. These relationships
are guarded by `prompt_contract.test.mjs`. The Project copy deliberately omits
the app-only subject-ownership self-check and every Here I am tool protocol. A
`.230` fail-closed Project-conversation profile passed one real-device
route/send/audio/Voice Gate on 2026-08-30; this does not make the consumer App
UI a stable product API.

The `.230` exact profile accepts the observed three-control short and
four-control long new-chat draft rows. Project mode separately accepts the
observed five-control row with its narrower Project-only geometry. Every form
still requires one left anchor plus one forward, non-overlapping right-side
cluster and rejects extra, malformed, overlapping, or duplicate candidate rows.

The command prints one JSON receipt. It exits non-zero for `failed`, and zero
for `dry_run` or `success`.

## Test

```powershell
node --test tools\chatgpt_android_bridge\*.test.mjs
```

The tests use sanitized synthetic UI and audio fixtures. They do not contact a
phone or launch ChatGPT. The bridge implementation suite currently has 22
passing cases, and the user-authoritative prompt-contract suite has 5 passing
cases, for 27/27 across this directory.
