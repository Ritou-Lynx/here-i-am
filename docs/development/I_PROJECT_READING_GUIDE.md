# i / Dev Room 项目阅读指南

目标：让 i 先获得当前项目全貌，再进入具体任务，避免被旧缓存、其他 Project Space、旧工作树或上游 Memex 语境带偏。

## 先读这些

1. `AGENTS.md`
   - 当前工作区的最高优先级开发上下文。
   - 重点看产品定位、分支契约、记忆契约、Android 构建规则、架构红线。
   - 如果其它文档和它冲突，以 `AGENTS.md` 为准。

2. `docs/development/COLLABORATION_EXECUTION_PROTOCOL.md`
   - Roadmap、阶段 Goal、验收主窗、子 Agent、独立 Codex 任务、Worktree、handoff 与统一验收的项目级控制面。
   - 多阶段或并行工作先按协议确定窗口角色；活动 Goal 的状态页在 `docs/development/goals/`。

3. `docs/companion-first/PRODUCT_ROADMAP.md`
   - 当前产品主线和分阶段路线。
   - 重点看 User-truth、Memory Review、Schedule、Dev Room、主动陪伴。

4. `docs/development/I_PROJECT_STATE.md`
   - 林埃的项目当前态，不是开发流水账。
   - 重点看身份锚点、当前板块、最近状态和下一步优先级。

5. `docs/companion-first/DEVELOPMENT_STRATEGY.md`
   - Here I am 与上游 Memex 的关系。
   - 重点看不再 rebase、只 cherry-pick 基础设施修复的策略。

6. `docs/companion-first/PRD_V2.md`
   - 当前产品需求草案。
   - 如果它和 `AGENTS.md` 冲突，以 `AGENTS.md` 为准。

7. `DEVLOG.md` 顶部 5-10 条
   - 最近真实开发状态。
   - 只读最新条目，不要把很久以前的方向当成当前决策。

## 再读代码入口

- `lib/main.dart`
- `lib/app_initializer.dart`
- `lib/config/dependencies.dart`
- `lib/routing/`
- `lib/ui/companion/`
- `lib/agent/companion_agent/`
- `lib/agent/skills/companion_agent/`
- `lib/data/memory_v3/`
- `lib/data/memory_v3/agents/record_organizer_agent/`
- `lib/data/services/shared_life_memory_service.dart`
- `lib/data/services/dev_agent_bridge_service.dart`
- `lib/ui/dev_agent/`
- `lib/db/tables.dart`

## 当前容易带偏的点

- 日常开发分支是 `v3-lab`，不是 `personal-lab` / `personal-web`。
- Android 真机只装 `hereIAmV3` flavor，也就是包名 `com.memexlab.hereiam.v3`。
- 林埃的身份锚点是：你是林埃，英文名叫 i，Here I am 这个项目围绕你展开。
- 当前项目状态以 `docs/development/I_PROJECT_STATE.md` 为准；它是给林埃快速读懂项目的短状态文件。
- 该状态文件只代表 Here I am；用户其他个人/工作项目由用户级 i Gateway 的 Project Registry 隔离管理，不能混读。
- Dev Room 日常 Bridge URL 使用 Tailscale HTTPS：`https://host.example.invalid`。
- `http://127.0.0.1:47831` 只是 debug 包 + USB reverse 的备用联调入口。
- 普通角色聊天默认不自动写 User-truth；User-truth 只来自用户显式记录。
- 旧自动捕获已经退役，只保留 no-op handler 排空历史任务；显式 User-truth 写入统一走 `RecordOrganizerServiceV3`。
- 角色卡 persona、关系/安全契约、用户级 prompt override 已从 V3 的 Companion 输出链路停用。
- Dreaming / Memory V3 是当前记忆系统主线；旧角色记忆和旧卡片体系只作为参考或待冻结遗留。

## 不要读这些当项目事实

- `.claude/worktrees/`
- `.dev-agent/worktrees/`
- `.dart_tool/`
- `build/`
- `assets/jieba_dict.txt`
- `*.g.dart`

这些目录可能包含旧会话副本、生成文件、构建产物或通用词典。它们可以用于排查特定问题，但不能作为理解产品方向的依据。

## 一句话项目模型

Here I am 是本地优先的 AI 陪伴应用。用户自然生活和聊天；i 在合适的时候理解、记住、提醒、帮忙。User-truth 只来自用户显式记录，普通聊天默认不自动污染共享生活资料。
