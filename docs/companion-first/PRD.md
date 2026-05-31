# 故我在 / Here I am — Product Development Document

Status: Draft v0.1

Last updated: 2026-05-31

## 1. Product Direction

Memex is evolving from an AI-assisted diary into a companion-first personal
life assistant.

The user should not feel that they are maintaining a database. They open the
app and talk naturally with a character. Memex quietly organizes useful
information in the background and makes it available when the user asks for
it.

The product promise is:

> Talk naturally. Memex remembers carefully, organizes quietly, and shows its
> work when you need it.

## 2. Core Principles

### 2.1 Chat is the home screen

- Opening the app enters the most recently used character conversation.
- The user can switch characters from the chat header.
- There is no contact-list landing page.
- Text, voice, speech-to-text, photos, camera capture, and attachments should
  converge in the chat composer.

### 2.2 Characters have equal system capabilities

Every character can use the same shared system capabilities:

- Query the user's shared life information.
- Record and update shared life events.
- Query and update schedules and reminders.
- Answer questions with visual artifacts when requested.
- Delegate specialized work to background agents.

Characters differ only in persona, relationship history, private memory, and
conversation style.

The legacy `isPrimaryCompanion` flag may remain temporarily as an internal
compatibility mechanism for proactive notifications. It must not grant extra
recording, query, orchestration, or UI privileges. The app entry point uses the
most recently active character instead.

### 2.3 Background understanding, restrained foreground presentation

- Background organization may run automatically.
- Routine organization results remain in Review or Insight views.
- Ordinary conversation should remain ordinary conversation.
- Rich cards, charts, and tables appear in chat when the user asks a question
  that benefits from them.
- The app may surface a lightweight undo affordance after meaningful reversible
  actions.
- Irreversible or external high-risk actions still require confirmation.

### 2.4 Prefer undo over repeated confirmation

For reversible actions:

```text
execute -> show a quiet undo affordance -> keep an audit trail
```

Examples:

- Add an inferred life event.
- Update an event's progress.
- Mark a task complete.
- Move an inferred record to trash.

For high-risk actions:

```text
ask -> receive explicit approval -> execute
```

Examples:

- Spend money.
- Send a message externally.
- Permanently erase data.
- Broaden the visibility of private information.

## 3. Information Architecture

Chat is the only top-level home screen. The app must not present a persistent
bottom tab bar.

The chat header contains a quiet secondary entry. It opens one separate life
space screen with a bottom navigation bar:

| Space | Purpose |
| --- | --- |
| Review | Browse AI-organized life records in chronological order and correct mistakes. |
| Schedule | Review plans, reminders, and todos. |
| Me | Manage characters, models, privacy, storage, and settings. |

Insights remain available inside Review for the first iteration. A separate
Insight space can be reconsidered after the content volume justifies it.

Review is intentionally a clean chronological card feed. It does not carry over
the legacy Memex header, avatars, reminders, assistant shortcuts, tag chips, or
embedded schedule and insight switching controls.

The chat composer has two layers:

1. The always-visible composer handles ordinary text and speech-to-text.
2. A lightweight media tray opens above it for suggested recent photos, album
   selection, and camera capture.

The media tray must not duplicate the text editor or voice recorder. The
existing full Memex recording sheet remains an internal source of reusable
logic, not the target interaction design.

## 4. Memory Model

The system separates memory by audience and purpose.

| Layer | Contents | Visibility |
| --- | --- | --- |
| Raw conversation | Original user and character messages | Current character relationship history |
| Character storyline summary | Compressed narrative continuity and unresolved threads | Current character |
| Character private memory | Relationship-specific preferences, promises, and interaction patterns | Current character |
| Shared life event log | Append-only observations and changes about the user's life | Shared system |
| Shared life entity projection | Current state of schedules, projects, todos, and evolving events | Shared system |
| Global user profile | Durable identity, preferences, habits, and long-term goals | Shared system and all characters |

Switching characters changes the relationship context, not the shared system
brain.

## 5. Conversation Capture

Conversation capture is asynchronous and incremental. It must not run an
additional model call after every user message.

### 5.1 Deterministic slice triggers

A background capture slice may be created after any of these:

- 8 to 15 new messages.
- 1,500 to 2,500 accumulated characters.
- 10 minutes of inactivity.
- Leaving the conversation screen.
- Ending a voice call.
- Approaching character-context compression.
- An explicit request such as "remember this".

Each character conversation tracks a `last_extracted_message_id` so the
organizer processes only new messages.

### 5.2 Capture output

A single model call classifies a slice into multiple destinations:

```json
{
  "shared_operations": [],
  "character_memory_operations": [],
  "ignored_message_ids": []
}
```

Supported shared operations:

| Operation | Meaning |
| --- | --- |
| `create` | Create a new event, task, plan, or durable fact. |
| `append` | Add progress or supporting detail. |
| `update` | Change a field such as time, place, or status. |
| `complete` | Mark an item complete. |
| `cancel` | Mark an item cancelled without deleting history. |
| `correct` | Replace an earlier mistaken interpretation. |
| `derive` | Create a new related item from an existing thread. |
| `ignore` | Do not structure casual or private conversation. |

### 5.3 Preserve evidence

- Raw conversation is append-only.
- Shared event changes are append-only.
- Current state is maintained as a projection.
- Every extracted operation records source message IDs.
- Undo appends a compensating operation instead of rewriting history.

### 5.4 Narrow retrieval before merge

The organizer should not load the entire user history into each model call.

1. Extract cheap keywords, entities, and time expressions from the slice.
2. Retrieve a small set of recent or relevant active entities.
3. Ask the model whether each result creates, updates, completes, cancels, or
   derives from an existing item.
4. Apply validated patches through a service layer.

## 6. Review Cards

Cards remain useful, but their meaning changes.

Old behavior:

```text
one input -> one timeline card
```

Target behavior:

```text
conversation slice -> semantic extraction -> state merge -> a small number of
complete review cards
```

A Review card may span multiple messages and evolve over time. It should expose:

- Current summarized state.
- Timeline position.
- Source conversation evidence.
- Update history.
- Edit, undo, merge, privacy, and trash actions.

Cards are not expected to interrupt routine chat.

## 7. Rich Chat Responses

Characters can answer user questions with:

- Event cards.
- Schedule summaries.
- Todo lists.
- Tables.
- Trend charts.
- Comparison charts.
- Insight cards.
- Supporting source lists.

Rich responses are generally request-driven. Background insights remain in
Review unless the user explicitly opts into proactive presentation.

## 8. MVP Scope

### 8.1 Included in the first runnable shell

- App entry opens directly into the most recently active character chat.
- Character switching remains available in the chat header.
- Switching characters updates the most recently active character without
  changing character privileges.
- Existing text chat, voice input, TTS, voice call, private character timeline,
  and memory behavior are reused.
- Supporting spaces are available from a secondary chat-header entry rather
  than a persistent bottom navigation bar.
- Review temporarily reuses the existing Timeline and Insight experience.
- Schedule temporarily reuses the existing schedule aggregation view.
- Me temporarily reuses the existing personal center and settings.

### 8.2 Next implementation slice

- Lightweight photo suggestions, album selection, and camera capture directly
  in the chat composer.
- `ConversationCaptureService`.
- Shared append-only life event log.
- Shared current-state projection.
- Undo affordances and evidence links in Review.
- Request-driven rich artifacts inside chat messages.

### 8.3 Deliberately deferred

- Frequent proactive insight cards in chat.
- Mandatory confirmation for routine reversible actions.
- Per-message LLM extraction.
- Removing the legacy Timeline or PKM engine before the replacement Review
  pipeline is proven.
- Giving one character broader orchestration rights than another.

## 9. Development Sequence

The product should advance through thin vertical slices. Do not finish the
visual system before validating memory behavior, and do not build the memory
engine without a usable chat interaction to carry it.

### Phase 0: Runnable shell

- Chat is the home screen.
- The most recently used character opens by default.
- Existing Memex capabilities remain reachable as secondary spaces.
- The new app flavor can coexist with Memex during migration.

### Phase 1: Interaction skeleton and first memory loop

- Replace the heavy recording sheet with a lightweight media tray.
- Preserve photo recommendation and photo clustering behavior.
- Extract objective plans or events from conversation slices asynchronously.
- Support `create`, `append`, `complete`, `cancel`, and `correct`.
- Show a quiet "remembered" notice with undo.
- Show the resulting event in Review.

### Phase 2: Shared and private memory separation

- Route objective facts, plans, and schedules into shared memory.
- Route relationship-specific content into character-private memory.
- Leave ambiguous content in raw conversation rather than forcing a category.
- Add later reclassification, merge, and correction paths.

### Phase 3: Memory-aware companion responses

- Retrieve only relevant shared and private memory for each request.
- Let every character answer questions about the user's life.
- Return schedule summaries, event cards, tables, and charts when requested.
- Keep routine background organization out of ordinary conversation.

### Phase 4: Product and visual refinement

- Replace the temporary Review view with complete evolving event cards.
- Refine composer interactions, media previews, motion, empty states, and undo.
- Unify the visual language across chat and supporting spaces.
- Revisit onboarding and migration once the core loop is proven.

## 10. Reused Memex Capabilities

The following existing systems remain valuable:

- Local-first workspace and SQLite storage.
- Per-user isolation.
- `GlobalEventBus` and persistent `LocalTaskExecutor`.
- Facts, PKM, Cards, Schedule, and Insight agents.
- Character private timeline, compression, and history search.
- LLM provider configuration.
- Voice input, TTS, calls, and proactive notification infrastructure.

## 11. Success Criteria

The first product test is behavioral:

- A returning user can open the app and immediately continue talking.
- Switching characters feels like switching the person, not switching the app.
- The user can still inspect organized records and schedules without making
  those views the center of the experience.
- Background organization does not make ordinary chat feel like a form.

## 12. Development Mainline

`Here I am` is the only actively developed product line. The original Memex
project remains the GPL-3.0 upstream foundation and a read-only reference, not a
second product that receives every local change.

See [DEVELOPMENT_STRATEGY.md](DEVELOPMENT_STRATEGY.md) for the repository,
upstream contribution, and portfolio rules.
