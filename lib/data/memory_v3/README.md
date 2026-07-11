# memory_v3 — Here I am 记忆系统 V3 实现

权威设计文档：[`docs/memory-research/MEMORY_PROPOSAL_V3.md`](../../../docs/memory-research/MEMORY_PROPOSAL_V3.md)

## 这个目录的边界

**任何新增记忆相关代码只允许在这个目录下。**

旧的 `lib/data/services/shared_life_*.dart`、`conversation_capture_service.dart` 等只能改 `@deprecated` 标记或删除，不允许扩展功能。原因和细则见 V3 § 15。

写代码前先读 V3 文档对应章节，不要先猜后写。

## 目录布局

```
memory_v3/
├── README.md                    # 本文件
├── models/                      # Dart 数据模型（不含 Drift table）
├── db/                          # Drift 表定义 + DAO
│   ├── tables.dart
│   └── dao/
├── services/                    # 业务服务层
│   ├── record_organizer_service.dart       # 写入端（§ 9）
│   ├── dreaming_orchestrator_service.dart  # 后台任务调度（§ 10）
│   ├── memory_query_service.dart           # 检索（§ 7）
│   └── user_correction_service.dart        # 用户修正记录（§ 11）
├── agents/                      # AI agent 实现
│   ├── record_organizer_agent/
│   │   ├── agent.dart
│   │   └── prompt.dart
│   ├── dreaming_agent/
│   │   ├── fragment_extractor.dart       # Daily Dreaming：聊天 → fragments
│   │   ├── prompt.dart
│   │   ├── episode_consolidator.dart
│   │   └── saga_weaver.dart
│   └── prompts/                 # 共享 prompt 片段
└── retrieval/                   # 检索基础设施
    ├── intent_classifier.dart   # 4 类 intent 分类
    ├── fusion_ranker.dart       # 排序融合
    ├── embeddings.dart          # 本地 / API embedding
    └── fts_index.dart           # SQLite FTS5
```

## 数据库表

V3 schema 完整字段见 V3 § 4 / § 5 / § 6 / § 7。涉及的表：

**用户确认资料层**
- `memory_cards` / `memory_card_sources` / `memory_card_structured_fields`
- `memory_card_relations` / `memory_card_assets`

**Dreaming 自动产物层**
- `memory_fragments` / `memory_entities` / `memory_entity_links`
- `memory_episodes` / `memory_sagas`

**Project Memory 特殊领域**
- Here I am 项目，以及其他项目政策明确允许进入个人语义层的当前态、开发事件、模块决策和回流摘要
- 属于 Memory V3 的 domain / facet，不另起第二套记忆系统
- 不写入普通 User-truth，不混入关系记忆或角色 sandbox
- 跨工具 i Identity Capsule、外部 ingress 与 closeout 边界见 `docs/companion-first/LIN_AI_CROSS_TOOL_CONTINUITY.md`
- Phase 2 用户级实现位于 `tools/i_continuity_gateway/`：Project Registry 只做路由/授权，加密 closeout ledger 负责当前 Project Space 交接，加密 Activity Index 只做可重建薄索引；三者都不是第二套语义记忆，也不允许直接写入本目录的 projection

**原始资料与审计层**
- `assets` / `asset_analysis` / `user_corrections` / `memory_card_operations`
- `chat_messages` 继承现有结构

**索引层**
- `memory_recall_events` / `memory_embeddings` + FTS5

## 核心契约（V3 § 2）

1. User-truth 只由用户显式动作产生
2. 用户主权高于审计完整性（I 工具不读 operation log）
3. 按 affect 不按 engagement（不为留存优化）

## 实施顺序（V3 § 15.3）

1. Asset 层
2. Memory Card 写入端
3. 检索端
4. Memory Review UI
5. Dreaming 自动产物
6. Project Memory domain（项目状态 / 开发事件 / Dev Room 回流）
7. Insight 体系 UI

### 当前 Dreaming MVP

- `DreamingFragmentExtractorV3` 只做低层证据抽取：输入一批主聊天消息，输出 `fragments` JSON。
- `DreamingOrchestratorServiceV3` 维护每个角色的抽取水位线，成功后写入 `memory_fragments` / `memory_entity_links`。
- `EpisodeConsolidatorV3` 已接入 Daily Dreaming 和 Lab 手动入口，把 active fragments 凝结为第一人称 `memory_episodes`。
- Companion 每轮对话会自动查询最近/相关 episodes + active fragments，并以 `dreaming_context` 注入。
- Dreaming recall log 会记录每轮 query、命中的 episodes / fragments、bm25 分数和最终注入内容，供 Lab 调试。
- Fragment 记录 `eventTime`（原始事件时间，非抽取时间）；Episode 的 `occurredAtRange` 由源 fragment eventTime 代码算出，不依赖 LLM。见 V3 § 5.6。
- Companion 注入 dreaming context 时在 narrative 前加日期前缀（例："(07-08 · 2 天前)"），让模型能区分过去和现在。
- Dreaming 自动产物写入 Dreaming 表族（fragments / episodes），不直接写 `memory_cards`。它承载的是事件+关系记忆，可信度中等（AI 观察）；Card 是用户显式确认的高置信版本。用户可以在 Memory Review 把高置信 Episode 升格成 Card。详见 V3 § 2.5。
- Saga / Deep Dreaming 还未接入；当前版本以 Fragment + Episode + 召回观测为 MVP 闭环。

### Project Memory 边界

- `docs/development/I_PROJECT_STATE.md` 是林埃快速读取的当前态快照。
- DEVLOG / commit / Dev Room run / closeout 产生的是项目事件史；先进入用户级隔离 Project Space，只有项目政策允许的内容才投影到 Project Memory domain，而不是 `memory_cards` 的普通 User-truth 流。
- 原始 run / diff / approval 仍归 Dev Room 表管理；Project Memory 只保存可检索摘要和决策。
- 林埃只有在项目相关问题中检索 Project Memory，普通生活聊天默认不注入。
- Phase 3 使用独立 `project_memory_items` / `project_memory_sources` 与 `project_memory_fts`，不复用 `memory_cards`，因此不会污染 User-truth。
- `ProjectMemoryService` 只接受 `personal_full/project_summary` 或已清空细节的 `work_redacted/redacted_summary` envelope；`local_only`、`private`、`confidential_local` fail closed。
- `project_memory_query` 经过本地项目意图门禁；普通生活与关系问题即使误调用也生成零候选。明确项目问题先读 Project Memory 概况，需要当前代码/UI/diff 时再走 Dev Room。
- Dev Room Bridge 只导出 Registry 当前政策允许的投影，不发送原始加密 ledger、完整 transcript 或 shell 输出；App 在 Bridge health 成功后幂等拉取。
- `confidential_local / ephemeral` 项目不得进入 Here I am；FTS / embedding 必须先按 project / policy 过滤，再做 top-k。

每切完一段，旧的对应代码可以删。

## 不要做的事

- 不要 import `lib/data/services/shared_life_*.dart` 或 `conversation_capture_service.dart`
- 不要 import `MemexRouter`（CLAUDE.md 红线）
- 不要新增 Drift 表跟 Memex 卡片体系建外键
- 不要绕过 `user_corrections`，让 AI 直接覆盖用户改过的字段
- 不要让 Dreaming 自动产物（Fragment / Episode / Saga）写入 `memory_cards` 表
- 不要把 Project Memory 写成普通 User-truth 或关系记忆
- 不要让 I 的工具能读 `memory_card_operations`
