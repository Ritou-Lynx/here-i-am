<p align="center">
    <picture>
      <img src="https://github.com/user-attachments/assets/c603127f-98a5-4bf1-8946-778fec2b76f6" width="400">
    </picture>
</p>
<p align="center">
  An AI-powered personal knowledge management app that runs entirely on your device.
</p>

<p align="center">
  <a href="https://github.com/memex-lab/memex/releases"><img src="https://img.shields.io/github/v/release/memex-lab/memex?style=flat-square&label=release" alt="Release"></a>
  <a href="https://discord.gg/ftae8GeubK"><img src="https://img.shields.io/badge/discord-join-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Discord"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/memex-lab/memex?style=flat-square" alt="License"></a>
  <a href="README_CN.md"><img src="https://img.shields.io/badge/文档-中文-blue?style=flat-square" alt="中文文档"></a>
</p>

<div align="center">
  <img src="https://github.com/user-attachments/assets/450eb6e5-8adf-4c1f-bc46-a63c9836f22c" width="300" />
</div>

## What is Memex?

Memex is a local-first, AI-native personal knowledge management app built with Flutter. Capture text, photos, and voice — a multi-agent system automatically organizes your records into structured timeline cards, extracts knowledge, and generates insights across your entries.

All data stays on your device. You just need to pick your preferred LLM provider.

## Features

### Multi-Modal Input
- Text, images, and voice recording in a single input flow
- Long-press to record audio, release to send
- Automatic EXIF extraction (timestamp, GPS location) from photos
- On-device OCR and image labeling via Google ML Kit

### AI-Powered Organization
- Multi-agent architecture: each agent handles a specific domain (PKM, card generation, insights, comments, memory summarization, media analysis)
- Automatically generates the most fitting card for each type of input:
  - Life & productivity (task, routine, event, duration, progress) — track todos, habits, schedules and goals
  - Knowledge & media (article, snippet, quote, link, conversation) — capture notes, references and dialogues
  - People & places (person, place) — log contacts and locations with map preview
  - Data & metrics (metric, rating, transaction, spec sheet) — record measurements, reviews and expenses
  - Visual (gallery) — preserve moments through photos
- Auto-tagging, entity extraction, and cross-reference linking
- Conversational AI assistant for discussing any card or topic

### Knowledge & Insights
- P.A.R.A-based knowledge organization (Projects, Areas, Resources, Archives)
- Insight cards that surface connections across records:
  - Charts (trend, bar, radar, bubble, composition, progress ring) — visualize patterns, distributions and goal progress over time
  - Narrative (highlight, contrast, summary) — surface key conclusions, before/after comparisons, and periodic reviews
  - Spatial & temporal (map, route, timeline) — reconstruct where and when things happened
  - Gallery — visual memory from your photos

### Privacy & Local-First
- All data stored locally (filesystem + SQLite)
- Built-in local HTTP server for asset serving
- App lock with biometric authentication
- No cloud dependency — your data never leaves your device

### Multi-LLM Provider Support

| Provider | API Type | Notes |
|----------|----------|-------|
| Google Gemini | Gemini API | Recommended for cost efficiency |
| OpenAI | Chat Completions / Responses API | GPT-4o, o1, etc. |
| Anthropic Claude | Claude API | Direct API access |
| AWS Bedrock | Bedrock Claude | For AWS users |

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.6.0
- Xcode (for iOS)
- Android Studio (for Android)

### Installation

```bash
git clone https://github.com/your-username/memex.git
cd memex
flutter pub get
```

### Run

```bash
flutter run
```

## Roadmap

- [ ] OAuth login for Claude and Gemini (no API key management)
- [ ] Cloud sync & backup (iCloud, Google Drive, etc.)
- [ ] Video and file attachments
- [ ] Agent Soul — Agent Soul — personalize agent behavior and personality
- [ ] Customization — choose your own knowledge methodology, tagging rules, chat personas, and card styles
- [ ] Event Bus & Hook System — a global event bus that decouples data sources from agent execution. Any input source (Share Extension, URL Scheme, Directory Watcher, Cron Scheduler) emits typed events onto the bus; a multi-dimensional Hook Registry intercepts them at key lifecycle points to trigger the right agent at the right moment — making both data source integration and agent scheduling fully extensible without touching core logic.
- [ ] Extension Market & Plugin Architecture — a cloud registry serves as a marketplace for agents, card styles, and persona configs. Users can browse and install extensions with one tap, and changes hot-reload instantly without restarting the app.

## Architecture

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart ≥ 3.6) |
| Platforms | iOS, Android |
| Database | Drift (SQLite) |
| State Management | Provider + MVVM |
| LLM Providers | Gemini, OpenAI, Claude, Bedrock Claude |
| Agent Framework | dart_agent_core |

### Project Structure

```
lib/
├── agent/          # Multi-agent system
│   ├── pkm_agent/        # Personal knowledge management
│   ├── card_agent/       # Timeline card generation
│   ├── insight_agent/    # Cross-record insight discovery
│   ├── comment_agent/    # AI commentary
│   ├── memory_agent/     # Memory summarization
│   ├── persona_agent/    # User profile modeling
│   ├── super_agent/      # Orchestrator agent
│   └── skills/           # Composable agent skills
├── data/           # Repositories & services
├── db/             # Drift database schema
├── domain/         # Domain models
├── l10n/           # i18n (English, Chinese)
├── llm_client/     # LLM client abstraction layer
├── ui/             # Presentation layer (MVVM)
│   ├── timeline/         # Timeline feed
│   ├── knowledge/        # Knowledge base
│   ├── insight/          # Insight cards
│   ├── chat/             # AI chat interface
│   ├── calendar/         # Calendar view
│   └── settings/         # App settings
└── utils/          # Shared utilities
```

### Data Flow

```
User Input (text/image/voice)
    ↓
Input Processing & Asset Analysis (ML Kit)
    ↓
PKM Agent → Knowledge extraction & linking
    ↓
Card Agent → Structured timeline card
    ↓
Insight Agent → Cross-record pattern discovery
    ↓
Local Storage (filesystem + SQLite)
```

## Contributing

Contributions are welcome. Please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
