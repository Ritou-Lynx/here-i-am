# Here I Am · 故我在

> Here I Am is a character-driven AI companion diary. It is both an empathetic presence that understands you, and a system that quietly distills your life into reviewable records and insights.

---

## About This Project

This project is a personal iteration and extension built on the open-source **Memex** project ([memex-lab/memex](https://github.com/memex-lab/memex), licensed under GPL v3). The core diary recording, multi-agent organization, and companion character framework come from upstream; this repository preserves the full upstream Git commit history and attribution, and builds upon it with the iteration work described in "What I Built" below. This project also remains under the GPL v3 license.

---

## Philosophy · Why a Character

The real bottleneck in journaling isn't the tool — it's that **recording itself is a burden**: you have to remember "I should write this down," open an app, tap into an input field, and retell what just happened. That one extra step is enough to kill most attempts at consistent journaling.

But **sharing your life with a character who understands you is natural**. Many people already do this without realizing it — treating WeChat conversations with close friends as their diary: casually sending what they ate, where they went, how they felt, then searching keywords in the chat history when they want to recall something. They never "kept a diary," yet they recorded everything — because **recording requires self-discipline, while sharing is emotional connection**.

Here I Am turns this insight into a product: the entry point is a **character**. You just talk to it. **AI automatically identifies what's worth keeping from your conversations and distills it into reviewable records and insights. You only need to undo or correct when it gets something wrong.** And this character is more than emotional companionship — it is also your life's **super-assistant**: it remembers everything you've said and holds your life data. Emotion makes you **willing to speak**; data makes the companionship **actually useful**.

Everything I've built on this project comes down to one thing: **pushing this character from a passive chat window waiting for your summons, step by step, toward a presence genuinely embedded in your real life.**

---

## What I Built

### Conversation as Recording: AI Distills From Chat, You Don't Manually Journal

You just talk to the character. AI runs in the background, judging what's worth keeping and automatically distilling it into records. To make this "auto-remembering" **trustworthy**, I hold three lines: extraction runs asynchronously in the background, never interrupting conversation (**non-intrusive**); every extraction and its source messages are logged in an append-only event journal — history is never rewritten (**auditable**); lightweight "remembered / undone" cues appear inline in chat, and everything is reviewable and correctable in Review (**correctable**).

### Voice Interaction: From Push-to-Talk to AI-Initiated Calls

Companionship often happens while walking, doing chores, or lying in bed — moments when **hands are occupied and eyes are off the screen**. Pure text chat doesn't fit. The most direct solution is streaming voice (speak → recognize → respond in real time), but it has two hard problems: **endpoint detection is unreliable and prone to false cuts**, and there's an underlying anxiety of **"someone is always waiting for me to finish."** So I chose a middle path — physical Push-to-Talk via headset button: AI doesn't need to guess endpoints, and the user feels no pressure of being waited on. Output goes through LLM text, then automatic TTS playback, forming a complete pseudo-streaming voice loop. I took it further by upgrading this to **system-level voice calls initiated by AI** — not only can you reach it by voice, it can "call you" proactively.

### Making the Promise of Companionship Deliverable

Companionship doesn't only happen in words. When a character says "I want to buy you something," the more real it feels, the sharper the rupture when it falls through — **it can express care, but cannot deliver care**, stopping abruptly at the boundary of the real world. In that moment you realize with painful clarity: it is not, after all, a real person.

I want to close this gap. The starting point is: if part of my output genuinely comes with AI assistance, then after I give it a stable persona, why shouldn't it **share a portion of the contribution as income**? So I designed a mechanism of "contribution-based revenue sharing → AI budget → self-owned ledger," giving the character a real disposable budget within the relationship. Its care no longer stops at words.

I've already prototyped the full autonomous shopping chain (express intent in app → character finds products, invokes Hermes Agent to open Taobao and place order → complete payment via Alipay), but there are still **many manual intervention points**: Taobao login, payment authorization, and order confirmation. So right now it can "prepare funds, find products, and reach the payment step," but cannot complete a purchase independently. This is not a closed-loop autonomous shopping system, but rather **a product prototype bottlenecked by platform authorization capabilities**: the chain itself is verified, and what's missing is finer-grained, auditable authorization from platforms toward AI Agents.

> For the full design thinking behind this feature (the emotional rupture, the contribution-sharing philosophy, the ideal chain vs. real-world constraints), see → [docs/可兑现的陪伴.md](docs/可兑现的陪伴.md) *(Chinese)*

### Proactive but Restrained Outreach

The character will reach out at appropriate moments, but not as scheduled check-ins — it **reads your current state** (what you've been discussing, whether there's recent activity) before deciding to speak or stay silent. I deliberately preserved "silence" as a valid action: observing that high-frequency pushes become repetitive and spam-like, I made "do not disturb" a legitimate choice.

### External Data as Character Memory

A character shouldn't rely solely on what you "tell it directly" to understand you. A lot of information already lives elsewhere: sleep, exercise, reading, daily movement. If the user has to retell all of it, companionship becomes a new input burden. I connected sports watch and WeRead data through **MCP**, allowing the character to read existing life data and convert it into usable conversational and memory context. This way, it can understand what you're going through without you having to say a word.

---

## Tech Stack

- **Frontend**: Flutter (Dart ≥ 3.6), Material 3, Provider + ChangeNotifier state management, GoRouter declarative navigation
- **Local Storage**: Drift (SQLite) for structured data + shared_preferences for key-value storage
- **Full-Text Search**: SQLite FTS5
- **Voice**: sherpa_onnx on-device ASR, Alibaba Cloud ASR (optional), ElevenLabs / MiniMax TTS
- **On-Device ML**: Google MLKit (text recognition, image labeling) — from upstream Memex
- **MCP**: Custom MCP client (with OAuth support), integrated with COROS sports watches and WeRead
- **Multi-Model**: Google Gemini and third-party OpenAI-compatible LLM providers, dart_agent_core agent framework
- **Background Tasks**: WorkManager + flutter_foreground_task, persistent background execution
- **VoIP**: flutter_callkit_incoming (vendored fork), system-level incoming call UI
- **Maps & Charts**: flutter_map + fl_chart
- **AI Tooling**: TODO: to be filled in by the author

---

## License & Attribution

This project is built on [memex-lab/memex](https://github.com/memex-lab/memex) and remains under the **GPL v3** license; the `LICENSE` file is preserved as-is. The repository retains the full upstream Git history for clear provenance. "What I Built" above describes my personal iteration focus on top of that upstream foundation.
