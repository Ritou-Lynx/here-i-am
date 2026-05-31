# Here I am / 故我在

[简体中文](README_CN.md)

**Here I am** is an early-stage, local-first personal AI companion for iOS and
Android.

The long-term idea is simple: a companion should not feel like a chat window
attached to a database. It should feel like a continuous presence that knows
your life, remembers carefully, and can eventually move with you across phones,
cars, homes, and future embodied devices. The mobile app is only its first
home.

## Status

This repository is currently an MVP and an active product exploration. It is
not a production release.

The local MVP already contains the first interaction loop. These slices are
being curated into readable public commits:

- The app opens directly into the most recently used character conversation.
- Every character has equal access to shared system capabilities.
- Character switching changes the relationship and private memory, not the
  user's underlying life data.
- Text, voice, photos, album selection, and camera capture converge in the chat
  composer.
- Review, schedule, and personal settings remain available as secondary
  spaces, rather than dominating the home screen.
- A separate Android `hereIAmDev` flavor can coexist with Memex during
  migration.

## Product Direction

The companion-first design separates memory into two layers:

| Layer | Purpose | Shared across characters |
| --- | --- | --- |
| Shared life memory | Objective events, plans, schedules, progress, and user facts | Yes |
| Character-private memory | Relationship history, private conversations, and character-specific emotional context | No |

Conversation should remain natural. Background agents can quietly organize
useful information, while visible cards, charts, and summaries appear mainly
when the user asks for them. For reversible actions, the preferred interaction
is a lightweight undo affordance instead of repeated confirmation prompts.

The fuller product document lives in
[docs/companion-first/PRD.md](docs/companion-first/PRD.md).

## Why Build on Memex?

Here I am is a derivative of the open-source
[memex-lab/memex](https://github.com/memex-lab/memex) project. Memex already
provides a strong local-first foundation:

- On-device workspace storage with per-user isolation.
- Multi-agent event processing and persistent background tasks.
- Timeline cards, facts, knowledge extraction, schedules, and insights.
- Configurable LLM providers.
- Character conversations and long-term memory infrastructure.
- Multimodal capture, backup, and restore.

This project keeps those foundations and changes the center of gravity: the
primary product is the companion relationship, while records and cards become
inspectable supporting surfaces.

## Personal Contribution Areas

The current iteration focuses on:

- Companion-first navigation and a chat-native capture flow.
- Equal system capabilities for every character.
- Shared life memory versus character-private relationship memory.
- Lightweight media suggestions, album selection, and camera capture in chat.
- Inspectable review cards with restrained foreground presentation.
- Data migration fixes and independent development flavors.
- Voice interaction, proactive check-ins, external data ingestion, and
  companion reliability work.

Implementation notes and decisions are recorded in:

- [Product document](docs/companion-first/PRD.md)
- [Development strategy](docs/companion-first/DEVELOPMENT_STRATEGY.md)
- [Iteration roadmap](ROADMAP.md)
- [Development log](DEVLOG.md)

## Development

```bash
flutter pub get
flutter run --flavor hereIAmDev
```

Build an independent Android development APK:

```bash
flutter build apk --flavor hereIAmDev --debug
```

The `hereIAmDev` package is intentionally isolated from the legacy Memex
development package so both apps can remain installed during migration checks.

## Upstream and License

Here I am is based on [memex-lab/memex](https://github.com/memex-lab/memex)
and preserves its Git history for transparent attribution. The original Memex
foundation belongs to its upstream authors. Product direction and additions in
this repository are documented separately so reviewers can distinguish the
work clearly.

This derivative project remains licensed under
[GNU GPL v3](LICENSE).
