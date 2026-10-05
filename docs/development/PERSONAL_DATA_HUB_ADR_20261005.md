# ADR：个人数据中枢的权威、同步与执行位置（2026-10-05）

> **状态：提议，待用户拍板（见第 11 节）。** 只写设计，不改代码、不动数据、不部署。
>
> **代码基线：** `codex/w0-integrate@842a3e9`（PR #5，草稿，尚未合入 `v3-lab`）。下文的 `文件:行号` 都按这个提交；W0 合入后行号可能漂移，以文件内容为准。
>
> **关系：** 本文是 [个人数据中枢总规划](PERSONAL_DATA_HUB_PLAN_20261005.md) 的设计依据，总规划里的 W1、W2、W5、W6、W7 卡已按本文改写。本文继承 [Gate 1A-0](data-authority/gate1a0/AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md) 已冻结的接受语义，并列出需要改文的既有条款（第 1.3 节、第 9 节）。
>
> **没有读到的输入：** W6 草案（17 项待确认，分支 `codex/w6-authority-draft`）和 WI 本机规划文件（分支 `codex/wi-local-planner`）都没有推送到远端，本文没能对照。W6 定稿时要与本文逐项核对。

---

## 0. 结论摘要

| 问题 | 推荐 |
|---|---|
| 宿主可用性（问题 4） | i_core 先留在电脑上，手机按离线优先设计。到上海后实测一到两周，再决定要不要搬到常开主机。W1 的实现不绑定 Windows，搬家时只是部署步骤。 |
| 可变记录同步（问题 2） | 版本号由 i_core 分配，客户端带着"我基于哪个版本改的"提交。i_core 做字段级合并：用户改的字段优先于导入和 AI；两个用户改动冲突时不自动选，进"待处理"。删除写墓碑，30 天内可恢复。AI 重复记的直接判重，用户重复记的提示合并。第一批领域只同步文字。 |
| 处理放在哪端（问题 3） | 手机继续跑林埃回复、Record Organizer、Dreaming、提醒和 check-in，并且是这些工作的**唯一执行者**；产出作为 intent 交给 i_core。排期由电脑上的 Codex 做。i_core 只负责接受、存储和分发。 |
| 权限（问题 5） | 按领域发令牌。需要不同权限的卡片类型拆成独立领域（收支、经期、睡眠、规划），领域就是权限边界。经期只开给手机。 |
| 迁移顺序（问题 6） | 先建没有历史包袱的新领域（记一下、规划，以及并进来的 i_remember 记录）；第一个搬家的手机数据是收支。每个领域走"影子 → 切换 → 退役"三步，每一步都能回滚。 |
| 规划与"记一下"（问题 7） | 三种"记一下"并成一个收件箱，由两个处理者按类型分工：手机 Record Organizer 处理生活记录，Codex 处理待办和时间。Codex 是规划结构的唯一写入者，手机只改状态（完成、不做了）。今日队列成为 i_core 里的一条记录。 |

---

## 1. 背景与约束

### 1.1 本次已定原则（用户确认，2026-10-05）

1. i_core 是个人数据唯一的权威；手机、思源、各个 Agent 都是读写它的客户端或视图。
2. 思源只管成篇的文字；不做双向同步；按领域授权。
3. 手机上的 AI 处理（Record Organizer、Dreaming、提醒、check-in）可以继续在手机上跑，变的是数据以 i_core 为准。

### 1.2 本文继承、不再重新讨论的合同

- **接受语义（Gate 1A-0，已冻结）**：只有 Core 能接受写入；客户端只提交带幂等键的 intent，本地最多是 `pending`；状态词为 `pending / accepted / rejected / expired / needs_resolution`；一个领域同一时刻只有一个接受者；Core 不可用时不能在本地产生"已接受"。见 [AUTHORITY_ROOT…ADR 第 42–75 行](data-authority/gate1a0/AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md#L42-L75)。
- **outbox、cursor、墓碑（Gate 1A-0，已冻结）**：outbox 状态机、按领域分开的 cursor、落后保留水位时返回 `resync_required`、删除先写墓碑再异步清理、旧备份不能复活已删对象。容量和 TTL 要由实现 ADR 定成版本化常量（[OUTBOX…ADR 第 36 行](data-authority/gate1a0/OUTBOX_CURSOR_RETENTION_RECOVERY_ADR.md#L36)）。本文第 4.7 节给出建议值。
- **迁移规则（Gate 1A-0，已冻结）**：旧 ID 原值保留；迁移和回滚都走领域操作，不能整表复制后直接改开关（[FORMAL_MIGRATION_MATRIX 第 13–14 行](data-authority/gate1a0/FORMAL_MIGRATION_MATRIX.md#L13-L14)）。
- **记忆契约（Memory V3）**：普通聊天不自动成为 User-truth；`user_corrections` 是换方案时保住用户修正的依据；删除的内容不进入任何召回（[MEMORY_PROPOSAL_V3 §2、§6.4](../memory-research/MEMORY_PROPOSAL_V3.md)）。
- **B3 用户决定**：claude.ai 的"帮我记一下"可以真删（决定 2）；记录到手机后直接成卡，不用确认（决定 4）（[B3_WRITEBACK_DESIGN 第 7–14 行](B3_WRITEBACK_DESIGN.md#L7-L14)）。

### 1.3 和既有条款的冲突（都需要拍板后改文，见第 9 节）

| # | 既有条款 | 冲突点 |
|---|---|---|
| C1 | [PRODUCT_ROADMAP 第 92 行](../companion-first/PRODUCT_ROADMAP.md#L92)：客户端不能各自运行 Memory V3；Core 不可达时手机只留草稿和捕获队列；"依赖 Core 才能形成的关系回复、检索和权威写入等待 Core 恢复"。 | 原则 3 让手机继续跑 AI 处理。手机现在离线也能完整聊天、整理记录。 |
| C2 | [CORE_SYNC_DATA_INVENTORY 第 30 行](../companion-first/CORE_SYNC_DATA_INVENTORY.md#L30)：check-in/提醒"只由核心调度"；[第 46–52 行](../companion-first/CORE_SYNC_DATA_INVENTORY.md#L46-L52)：Dreaming 等"由核心唯一生成"。 | 同上。本文改成"单一执行者是手机"，保留原条款要防的事：不让多台设备各自生成再合并。 |
| C3 | [PRODUCT_ROADMAP 第 77 行](../companion-first/PRODUCT_ROADMAP.md#L77)：主电脑持续运行 Core。 | 10/12 起在上海，电脑可能不常开。 |
| C4 | [PRODUCT_ROADMAP 第 80 行](../companion-first/PRODUCT_ROADMAP.md#L80)：手机新功能暂停，不新增页面。 | 总规划的 W4（记一下页）、W5（今天/本周页）是新页面。 |
| C5 | [PRODUCT_ROADMAP §7](../companion-first/PRODUCT_ROADMAP.md#L455)：1A-1（中性 Card）→ 1A-2（Markdown Vault）→ 1A-3（Core intent/outbox）依次解锁。 | W1 直接实现 1A-3 的一部分（intent、outbox、按领域 cursor），而白板已于 10/02 停止开发。 |
| C6 | Gate 1A-0 的 Formal32 对象清单（[FORMAL_MIGRATION_MATRIX 第 54–93 行](data-authority/gate1a0/FORMAL_MIGRATION_MATRIX.md#L54-L93)）。 | 没有收支、经期、睡眠、规划、提醒、节律、成长契约、生活洞察、话题这些对象。 |
| C7 | B3 决定 2：i_remember 记录"只存 i_remote_mcp 本机账本"。 | 原则 1 要求个人数据以 i_core 为准。 |

---

## 2. 现状盘点（以代码为准）

### 2.1 每类数据在哪、谁写、谁读、怎么同步

| 数据 | 存在哪 | 谁写 | 谁读 | 怎么跨端 |
|---|---|---|---|---|
| 聊天·用户消息 | 手机 `persona_chat_messages` + `sync_outbox_messages`；i_core `chat_messages` | 手机：本地行和待发行同一事务写入（[persona_chat_service.dart:110-153](../../lib/data/services/persona_chat_service.dart#L110-L153)）；claude.ai 经 `frontend:claude_web` | 手机；i_memory 读取层 → claude.ai | 待发队列 → `POST /v1/core/chat/messages` → change feed 拉回（[core_sync_engine.dart:67-170](../../lib/data/services/sync/core_sync_engine.dart#L67-L170)）。只在前台、写入后和手动时同步，不跑后台（[core_sync_runtime_service.dart:38-41](../../lib/data/services/sync/core_sync_runtime_service.dart#L38-L41)） |
| 聊天·手机上林埃的回复 | 只在手机 | 手机 `addCharacterMessage`，不进待发队列（[persona_chat_service.dart:245-274](../../lib/data/services/persona_chat_service.dart#L245-L274)） | 手机 | **不同步**。待发队列只交 `sender=user`（[core_sync_engine.dart:81](../../lib/data/services/sync/core_sync_engine.dart#L81)）；i_core 也拒绝普通设备提交 companion（[i_core_store.mjs:465](../../tools/i_core/i_core_store.mjs#L465)）。i_core 里已有的回复来自一次性导入（[i_core README 第 116 行](../../tools/i_core/README.md#L116)） |
| 聊天·网页端双方轮次 | i_core；i_remote_mcp 账本 `turns` 表 | i_remote_mcp（`frontend:claude_web`） | 手机经 feed；claude.ai | 已实现。手机上"网页端"来源标注还没做（`lib/` 里没有 `claude_web` 的引用） |
| 聊天附件 | 手机 `attachmentsJson` | 手机 | 手机 | 不同步。协议里有 `CoreAssetRef`，手机不发；导入器跳过附件（[i_core README 第 116 行](../../tools/i_core/README.md#L116)） |
| 记忆卡（fact/event/task/schedule/plan + 结构化字段） | 手机 `memory_cards` 表族（[tables.dart:25-123](../../lib/data/memory_v3/db/tables.dart#L25-L123)） | `RecordOrganizerServiceV3` 的 persist / updateCard / deleteCard；启动时自动去重；白板 store 直接 upsert（[whiteboard_drift_store.dart:332](../../lib/data/whiteboard/whiteboard_drift_store.dart#L332)） | 手机林埃召回、Memory Review、日程面板、出门建议（[proactive_outing_service.dart:106](../../lib/data/services/proactive_outing_service.dart#L106)）；电脑上 i_memory 快照 → `i_recall` | 没有实时同步。i_memory 用 ADB 导出后整库替换（[i_memory README 第 39 行](../../tools/i_memory/README.md#L39)）；`.memexdata` 是整库快照、后写覆盖（[memory_data_sync_service.dart:21](../../lib/data/services/sync/memory_data_sync_service.dart#L21)） |
| 用户修正 `user_corrections` | 表已建（[tables.dart:336-351](../../lib/data/memory_v3/db/tables.dart#L336-L351)） | **没有写入方**：`recordUserCorrection`（[record_organizer_service.dart:960](../../lib/data/memory_v3/services/record_organizer_service.dart#L960)）全仓无调用 | — | 实际只有结构化字段整行的 `userCorrected=true`（同文件 1615、1624、1639 行） |
| 操作审计 `memory_card_operations` | 手机 | organizer 的 create / update / delete | 修订历史页 | 不同步 |
| 收支 `ai_finance_ledger` | 手机（[tables.dart:406](../../lib/db/tables.dart#L406)） | ① 记忆卡成卡后单向桥接（[record_organizer_service.dart:1129](../../lib/data/memory_v3/services/record_organizer_service.dart#L1129)）；② 林埃的 ai_finance 工具直接记；③ 账本面板删除（[ai_finance_service.dart:396](../../lib/data/services/ai_finance_service.dart#L396)） | 账本面板、林埃 | 不同步。删卡不删账本行（deleteCard 不碰账本，[1405-1475](../../lib/data/memory_v3/services/record_organizer_service.dart#L1405-L1475)） |
| 经期 | `menstrual_record` 卡 → 派生 `user_rhythms`（[record_organizer_service.dart:1107](../../lib/data/memory_v3/services/record_organizer_service.dart#L1107)） | organizer | check-in、林埃 | 不同步 |
| 睡眠 | COROS 摘要写成手机文件（[coros_sync_service.dart:10-13](../../lib/data/services/coros_sync_service.dart#L10-L13)）；手记 `sleep_record` 卡；COROS MCP 实时查 | COROS 同步、organizer | 洞察、林埃 | 不同步 |
| Dreaming（片段、经历、长期叙事、实体） | 手机（[tables.dart:131-290](../../lib/data/memory_v3/db/tables.dart#L131-L290)） | 手机 DreamingOrchestrator | 手机林埃 | 不同步 |
| 节律、成长契约、生活洞察、话题 | 手机（[tables.dart:478-836](../../lib/data/memory_v3/db/tables.dart#L478-L836)） | 手机后台 | check-in、面板 | 不同步 |
| 提醒 | `system_message_queue`，`triggerType=reminder`（[reminder_service.dart:23-68](../../lib/data/services/reminder_service.dart#L23-L68)）+ 精确闹钟（[checkin_service.dart:268-296](../../lib/data/services/checkin_service.dart#L268-L296)） | 林埃 `reminder_create` / `system_checkin`（[checkin_tool.dart:225-306](../../lib/agent/built_in_tools/checkin_tool.dart#L225-L306)） | 手机闹钟回调 | 只在手机。普通提醒过时 15 分钟作废，来电提醒 2 小时（[checkin_service.dart:620-670](../../lib/data/services/checkin_service.dart#L620-L670)） |
| check-in | 同表 `triggerType=checkin`；闹钟自续链（[checkin_service.dart:316-333](../../lib/data/services/checkin_service.dart#L316-L333)、[866 起](../../lib/data/services/checkin_service.dart#L866)） | 手机 | 手机后台跑林埃 | 只在手机。i_core 有 `checkin` 等 workload 名（[i_core_store.mjs:22-28](../../tools/i_core/i_core_store.mjs#L22-L28)），但只有 `companion_reply` 有任务接口 |
| 日程面板 | 读 task / schedule / plan 卡（[memory_card_query_service.dart:409-439](../../lib/data/memory_v3/services/memory_card_query_service.dart#L409-L439)） | 勾选 = `updateCard(status)`（[schedule_view_model.dart:99-120](../../lib/ui/companion/view_models/schedule_view_model.dart#L99-L120)） | 手机 | 不同步 |
| claude.ai"帮我记一下"（i_remember） | i_remote_mcp `.state/writeback.sqlite` 的 `notes` 表（[writeback.mjs:158-170](../../tools/i_remote_mcp/writeback.mjs#L158-L170)）；删除即清正文（[566 行](../../tools/i_remote_mcp/writeback.mjs#L566)） | claude.ai | claude.ai（`i_context`）；手机拉取的服务端已写（[server.mjs:258-270](../../tools/i_remote_mcp/server.mjs#L258-L270)） | **手机端拉取没实现**（`lib/` 里没有引用），记录目前到不了手机 |
| 规划 | WI 本机文件 `plan.json` / `week.md` / `today.md`（分支未推送，未核对） | Codex | dot、用户 | 无 |
| 快速捕获 | 只有设计（[QUICK_CAPTURE_DESIGN](QUICK_CAPTURE_DESIGN_20261005.md)） | — | — | — |
| 学习账本、招聘日历 | 思源数据库 | 学习导师（Codex） | 规划助手只读 | 思源自带同步 |
| 活动（MDA） | i_core activity 域，默认关闭 | probe | — | 独立 feed |

### 2.2 直接影响设计的发现

- **F1 聊天只同步了一半。** "手机本地 + 待发队列 → i_core → 变更流拉回"只对用户消息成立。导入之后，手机上林埃的回复都不在 i_core 里：claude.ai 的 `i_context` 看到的是只有用户一侧的手机对话，电脑端 worker 也拿不到完整上下文。
- **F2 记忆卡没有版本，也没有墓碑。** `deleteCard` 物理删除卡和附属行，只留一条审计记录（[1405-1475](../../lib/data/memory_v3/services/record_organizer_service.dart#L1405-L1475)）；编辑时故意不更新 `updatedAt`（[1682 行](../../lib/data/memory_v3/services/record_organizer_service.dart#L1682)）。现在没有任何字段能用来做增量同步或判断冲突。
- **F3 "用户修正优先"在手机上也没有字段级依据。** `user_corrections` 一直是空表，只有结构化字段整行的布尔标志。
- **F4 手机会自己删卡。** 启动时跑 `dedupeExistingScheduleCards`（[272 行](../../lib/data/memory_v3/services/record_organizer_service.dart#L272)、[320 行起](../../lib/data/memory_v3/services/record_organizer_service.dart#L320)）；写入时按 ±2 小时窗口复用已有卡（[741-805](../../lib/data/memory_v3/services/record_organizer_service.dart#L741-L805)）。这条保护来自真实问题（AI 把同一顿饭重复记了三次，见同文件注释），迁移后要保留效果，但客户端直接删除要改成 i_core 判重。
- **F5 收支有两个写入口、两份表示。** 卡和账本行各自存在，删除不联动。
- **F6 同一张表里混着生活事实和白板普通卡。** 白板卡复用 `memory_cards`，`memoryScope=user_truth`、`type=note`（[tables.dart:962-965](../../lib/data/memory_v3/db/tables.dart#L962-L965)），Gate 1A-0 已标为迁移红灯。
- **F7 i_remember 记录停在电脑上。** B3 决定 4 的闭环还没通。
- **F8 读取层直接打开 i_core 数据库。** `i_memory_read.mjs` 以只读方式打开 i_core 的 SQLite（[201 行](../../tools/i_memory/i_memory_read.mjs#L201)）。i_core 加领域表后，这条路能读到所有领域，权限要在读取层另设白名单。
- **F9 三个服务压在同一台电脑上。** i_core（[README 第 31–33 行](../../tools/i_core/README.md#L31-L33)）、i_remote_mcp 和 Cloudflare 隧道都在这台 Windows 电脑上。电脑一关，手机同步、claude.ai 连接器、规划助手同时停。
- **F10 线上运行的代码和仓库不一致。** 本机运行的 i_remote_mcp 有 5 个源码文件和候选不同（[W0 交接"运行一致性"](handoffs/W0_INTEGRATION_20261005.md)）。本文对线上行为的判断都要再核。

---

## 3. D1 宿主与可用性（问题 4）

**前提：** 用户 10/12 起在上海，电脑可能不常开。电脑是随身带的笔记本还是留在家里的台式机，**不确定**（见第 10 节）。

| 选项 | 做法 | 好处 | 代价 |
|---|---|---|---|
| **A. 电脑继续做宿主，手机离线优先** | 不动部署。手机所有写入先进本地待发队列，电脑开机后补交。 | 零迁移风险；数据不离开自己的机器。 | 电脑关着时 claude.ai 连接器整体不可用（读不到记忆，也写不回）；Codex 不排期；网页端说的"帮我记一下"直接失败。 |
| **B. 搬到常开主机** | i_core + i_remote_mcp 搬到一台常开的机器：云主机，或者家里一台不关的小机器。电脑和手机都变成客户端。 | claude.ai 随时可用；手机随时能同步；"唯一权威"不需要额外机制。 | 包括私密聊天在内的数据放到别人的机器上（`node:sqlite` 不支持库加密，只能靠磁盘加密）；要换一次权威宿主（停服、备份、搬库、轮换令牌）；i_core 里还挂着两块 Windows 专属功能，不能随迁：activity 控制面（默认关闭；MDA-0 约定"Windows 是唯一夜间活动 Core"）和快捷指令邮件测试（DPAPI，仅 debug）。 |
| C. 电脑做权威，外加常开中继 | 常开的地方只放加密信箱（收 intent）和一份按出站策略过滤后的只读快照，给 claude.ai 读。电脑开机后从信箱取件。 | 权威不出电脑。 | 要部署两套 MCP；claude.ai 只能读明文，快照里的可分享数据照样放在外面，隐私上接近 B，复杂度更高。 |

（还考虑过让手机当宿主：claude.ai 要从公网访问手机，耗电、网络和 Node 运行环境都不现实，不列入。）

**推荐：A 起步，按实测切到 B；不做 C。**

理由：
1. 10/5–10/11 是搬家周，这时换宿主风险最大。Gate 1A-0 的换宿主流程（新 instance、epoch 提升、旧令牌作废）还没实现，现在搬只能手工拷库。
2. B 的主要代价是隐私，必须由用户决定，不能默认。
3. C 在隐私上并不比 B 好多少（claude.ai 能读的快照必须是明文），却多一套部署。
4. W1 按"宿主无关"实现：核心路径不依赖 Windows，配置走环境变量，备份脚本跨平台。这样以后切到 B 只是部署动作。

**切换触发条件（建议）：** 到上海后两周内，满足任一条就提出切 B：claude.ai 连接器不可用超过 5 天；手机待同步记录积压超过 3 天；用户觉得每天开电脑是负担。

**电脑离线时各端的表现（按 A）：**

| 端 | 表现 |
|---|---|
| 手机聊天 | 照常聊（模型调用不经过电脑）。消息和林埃回复进待发队列，显示"未同步到核心"。 |
| 手机记录 | Record Organizer 照常整理，记录立即可见，标"待同步"；林埃召回时能读到，但标明未同步（见第 4.7 节）。 |
| 手机提醒 / check-in | 不受影响，都在手机上。 |
| 手机今天/本周页 | 显示最后一版今日单和生成时间；可以点完成（待同步）；新记的事显示"等电脑上线后安排"。 |
| 网页端"帮我记一下" | 失败。Project 指令要求林埃说明"核心不在线，这条请在手机上再记一次"。 |
| claude.ai 聊天 | 连接器不可用，林埃失去记忆和写回；这段对话不进时间线（i_remote_mcp 本身也没运行）。 |
| Codex 规划 | 不运行；开机后补处理。 |
| 思源只读看板 | 停在最后一次生成。 |

**按 B 时的不同：** 只有 Codex 规划和思源看板依赖电脑开机；其他端都正常。

---

## 4. D2 可变记录怎么同步（问题 2）

聊天消息是不可变的，只要按 `sync_id` 去重就够了（[i_core_store.mjs:572-588](../../tools/i_core/i_core_store.mjs#L572-L588)）。记忆卡、收支、规划都会被改、被删、被合并，需要下面这套规则。

### 4.1 每条领域记录的公共字段（交 W1 定稿）

| 字段 | 说明 |
|---|---|
| `id` | 客户端生成的 UUID。迁移时沿用旧 ID（Gate 1A-0 规则）。 |
| `revision` | i_core 分配，每次接受的改动加 1。客户端不能自己改。 |
| `field_meta` | 每个字段最后一次被谁、在哪个 revision 改的：`{字段: {rev, actor, at}}`。字段级合并和"用户优先"都靠它。 |
| `created_at` / `updated_at` | i_core 时间。`updated_at` 是最后一次被接受的时间。 |
| 业务时间 | 由领域定义，例如收支的 `occurred_at`、规划的 `planned_date`。不和系统时间混用（V3 §5.6 的教训）。 |
| `deleted_at` / `deleted_by` / `merged_into` | 墓碑和合并去向。 |
| `provenance` | 来源：原话、来源消息的 `sync_id`、`capture_id`、导入批次。 |
| `origin` | 最初由哪个主体、哪台设备创建。 |

另外每个领域有一张**只追加的操作表** `domain_ops`：`op_id`（客户端幂等键）、主体、`actor`、目标、`base_revision`、改动内容、结果和回执。它同时是审计日志，也是 Core 端的 `user_corrections`：`actor` 为用户的那些行就是用户修正记录，换方案重新生成时先查它。这样第 2.2 节 F3 的问题在 Core 端有了落点。

### 4.2 版本

| 选项 | 说明 |
|---|---|
| **a. i_core 分配整数版本 + 客户端带基准版本提交（推荐）** | 客户端提交"我基于 revision N 改了这些字段"。和 Gate 1A-0 的"Core 唯一接受者"一致。 |
| b. 客户端时间戳 / 混合逻辑时钟，后写者赢 | 手机时钟漂移、离线几天后补交，都会让旧改动覆盖新改动。违反"不能以较新时间静默接受"（[CORE_IDENTITY…ADR 第 7–11 行](data-authority/gate1a0/CORE_IDENTITY_EPOCH_FENCING_ADR.md#L7-L11)）。 |
| c. CRDT | 能自动合并，但冲突也会被静默合掉，同样违反上条；而且单用户、少量设备，用不上它的长处。 |

### 4.3 字段级合并与"用户修正优先"

**主体分级**（`actor`），借用现有表里已有的 `agent_inferred / user_confirmed / user_adjusted` 用法（[tables.dart:590](../../lib/data/memory_v3/db/tables.dart#L590)）：

| 等级 | actor | 例子 |
|---|---|---|
| 3 | `user_direct` | 用户在界面上改、点完成、删除 |
| 3 | `user_via_agent` | 用户在这一轮明确让林埃改（op 里带触发消息的 `sync_id`） |
| 2 | `import` | COROS 同步、外部账单导入 |
| 1 | `agent_inferred` | Record Organizer 首次整理、Dreaming、洞察、Codex 自动排期 |

**合并规则**（i_core 在接受时执行）：

1. `base_revision` 等于当前版本：直接接受。
2. 否则逐个字段看：这个字段在 `base_revision` 之后没被改过，就接受这个字段的新值。
3. 同一字段被并发改过：等级高的赢；输的一方记进操作表（`superseded`），不丢。
4. 两边都是用户（等级 3）：**不自动选**。字段保持当前值，生成一条 `needs_resolution`，在手机上让用户选，或由林埃在聊天里问。
5. 两边等级相同、都不是用户（都是 AI，或都是导入）：后到的拒绝（`stale_base`），附上最新记录，由执行者基于新版本重算。
6. 字段最后一次是用户改的，AI 的改动一律拒绝（`user_locked`），除非这次 op 本身是 `user_via_agent`。这就是"用户修正优先"：重新整理、换模型、重跑 Dreaming 都盖不掉用户改过的字段。

### 4.4 删除与墓碑

| 选项 | 说明 |
|---|---|
| a. 删除即清除正文 | 符合 B3 决定 2；但误删无法恢复。 |
| **b. 默认 30 天可恢复，之后清正文、保留墓碑（推荐）** | 和路线图对 Card 的 30 天恢复窗口一致（[PRODUCT_ROADMAP §2.3](../companion-first/PRODUCT_ROADMAP.md#L129)）。 |
| c. 永久保留正文 | 违背"用户主权高于审计完整性"（V3 契约 2）。 |

推荐 b，并保留两个例外：
- **i_remember 来的记录**沿用 B3 决定 2，删除立即清正文。
- **用户选"永久删除"** 时立即清正文。

规则：
- 删除是一条 op，生成墓碑：`deleted_at`、`revision+1`。在线读取立即看不到。
- 对已删除记录的修改一律拒绝（`deleted_target`），手机提示"这条已在别处删除"，提供恢复。
- 墓碑永远保留 id 和 revision。用旧 id 再"创建"会被拒，旧副本、旧备份不能让它复活（Gate 1A-0 时间线 E）。
- 用户删除和别处的 AI 修改并发时，删除赢；AI 发起的删除如果基准版本过旧，拒绝。
- 删除一条原始记录（例如一条"记一下"）时，由它生成、之后没被用户改过的派生记录一起删；改过的保留，并提示用户（沿用 B3 §7 的语义）。

### 4.5 去重与合并

分三层：

1. **重发去重（精确）**：同一 `op_id` + 同一内容，返回原回执；同一 `op_id` + 不同内容，返回 `idempotency_conflict`（Gate 1A-0 已定）。客户端生成的 `id` 也保证同一条记录不会建两次。
2. **语义判重（按领域）**：每个领域定义一个判重键，规则沿用手机现有的、来自真实问题的条件（[record_organizer_service.dart:741-805](../../lib/data/memory_v3/services/record_organizer_service.dart#L741-L805)）：收支按"类型 + 金额 + 时间 ±2 小时"，待办按"规范化标题互相包含 + 时间"。
   - 经 Record Organizer、林埃工具或导入生成的新建命中（包括用户说"记一下"、由 organizer 整理出来的）：不新建，返回 `duplicate_of` 和已有记录。这和现在手机在写入时复用已有卡的行为一致，保住防"AI 把同一顿饭记三次"的效果。
   - 用户在界面上手动新建（`user_direct`）命中：照常接受，同时标 `possible_duplicate`，由林埃下次聊天时提出合并建议（V3 §9.6"不自动合并，用户确认后才合并"）。
3. **合并**：一条显式 op，只能由用户发起或确认。被合并的记录写墓碑并填 `merged_into`；指向它的引用由 i_core 改指过去。

| 选项 | 说明 |
|---|---|
| **a. 上面三层（推荐）** | 兼顾防 AI 重复和不替用户做主。 |
| b. i_core 命中判重键就自动合并 | 省事，但会替用户合掉两笔真实的同价消费。 |
| c. 只在客户端判重 | 手机离线几天时，本地副本缺网页端新记的内容，判不准。 |

手机启动时的自动去重（F4）在对应领域切换后必须关掉。

### 4.6 附件和媒体

| 选项 | 说明 |
|---|---|
| **a. 第一批只同步文字，附件留在手机（推荐起步）** | 第一批领域（记一下、规划、收支、经期、睡眠）基本没有附件。记录里的附件引用标 `local_only`。 |
| b. i_core 内容寻址对象库 | `PUT /v1/core/objects/<sha256>`，先传对象、再提交引用它的记录；i_core 校验哈希，引用缺失的对象就拒绝。和 [CORE_SYNC_DATA_INVENTORY §6](../companion-first/CORE_SYNC_DATA_INVENTORY.md#L80) 一致。 |
| c. 外部对象存储（已有的 S3 配置）+ 客户端加密 | 宿主空间小时可用；多一套密钥管理。 |

推荐 **a 起步，迁移通用记忆卡（带图片）之前上 b**。如果 D1 选了 B 且主机空间小，再考虑 c。

### 4.7 离线

- **手机待发队列**：把现有聊天待发队列推广成按领域的 outbox，状态按 Gate 1A-0：`pending / submitting / accepted / duplicate / rejected / expired / needs_resolution`。网络超时、进程崩溃都不能删 `pending`。
- **建议常量**（Gate 要求版本化，W1 定稿）：用户发起的 intent TTL 60 天，超过 7 天未同步就在手机上提示；单设备队列上限 5000 条、50 MB（不含附件）。TTL 定得长，是因为电脑可能连续多天不开。
- **本地副本**：手机为它要用的领域保存一份副本，按领域 cursor 增量拉取；cursor 落后保留水位时收到 `resync_required`，用快照整体替换（Gate 1A-0 时间线 D）。
- **待同步内容的可见性**：界面上显示并标"待同步"。手机上的林埃可以读，注入上下文时单独标为"未同步的记录"。这不违反 Gate 1A-0：这些内容仍是 `pending`，没有被当成已接受；它们只在手机本机可见，别的端看不到。这一条要改 PRODUCT_ROADMAP 第 92 行（C1）。

### 4.8 变更流

每个领域一条独立的变更流，发的是**记录的最新状态**（包括墓碑），不是操作本身。客户端按 `revision` 应用，旧版本直接丢弃，所以重放、乱序都安全。聊天流和活动流保持现状，不混入。

---

## 5. D3 各类处理放在哪一端（问题 3）

| 选项 | 说明 |
|---|---|
| **a. 手机是这些处理的唯一执行者，i_core 只接受和存储（推荐）** | 符合原则 3。也守住了原条款真正要防的事：同一类产物只有一个生成者，不会多台设备各自生成再合并（[CORE_SYNC_DATA_INVENTORY 第 52 行](../companion-first/CORE_SYNC_DATA_INVENTORY.md#L52)）。 |
| b. 全部搬到电脑 worker | 电脑一关，记录、提醒、check-in 全停，和上海的现实冲突。 |
| c. 两端都跑，事后合并 | 明确被既有文档禁止，冲突难解释。 |

**处理位置与写入路径（推荐 a）：**

| 处理 | 在哪跑 | 读什么 | 写入路径 | 电脑离线时 |
|---|---|---|---|---|
| 林埃回复（手机） | 手机 | 本地聊天 + 本地副本 | 回复进待发队列，以 `companion` 身份提交 i_core（需要 i_core 放开：普通手机设备可提交自己生成的 companion 消息，见决定 4） | 照常 |
| 林埃回复（网页端） | claude.ai | i_remote_mcp | `i_chat_turn`（已有） | 不可用（A） |
| 林埃回复（电脑 worker） | 电脑，保持 shadow | — | 不启用 live，避免和手机同时生成 | — |
| Record Organizer | 手机 | 原话 + 本地副本（判重上下文） | 整理结果 → 对应领域的新建 intent（`agent_inferred`）。领域未切换前仍写手机本地表 | 照常，记录为待同步 |
| 记一下的分流 | 手机 organizer 处理生活记录；Codex 处理待办（见第 8 节） | captures 副本 | captures 上记处理结果 | 生活记录照常；待办等电脑 |
| Dreaming | 手机 | 本地聊天（含 feed 拉回的网页端轮次，片段已有 `sourceSyncIds`，[tables.dart:138](../../lib/data/memory_v3/db/tables.dart#L138)） | 先留在手机本地，作为可重建的派生产物；以后需要时再导出只读快照（第 7 节第 8 步） | 照常 |
| 提醒 | 手机 | ① 林埃给自己的提醒：本机状态；② 用户的定时事项：规划领域的本地副本 | ① 不同步（只对这台设备有意义）；② 由副本派生本地闹钟，规划记录本身在 i_core | 照常 |
| check-in | 手机 | 本地副本 + 本机状态 | 产生的数据（如成长契约检查）在对应领域切换后作为 intent 提交；之前留在本地 | 照常 |
| 节律、洞察 | 手机 | 本地副本 | 派生产物，先留本地 | 照常 |
| 排期、出今日单、周账 | 电脑 Codex | captures、plan 领域 | 规划领域 intent（`agent_inferred`） | 不运行，开机补 |
| COROS 睡眠导入 | 手机（已有同步服务） | COROS | `sleep_days` 新建/更新（`import`，按日期幂等） | 照常 |
| 判重、合并建议 | i_core 接受时 | 领域记录 | 标 `duplicate_of` / `possible_duplicate` | 补交时判 |
| 思源只读看板 | 电脑 Codex | 只读令牌 | 单向生成思源文档 | 停在最后一版 |

---

## 6. D4 权限（问题 5）

| 选项 | 说明 |
|---|---|
| **a. 按领域发令牌；需要不同权限的卡片类型拆成独立领域（推荐）** | 收支、经期、睡眠、规划都是独立领域，"按卡片类型授权"就落成"按领域授权"，不需要表达式。 |
| b. 按领域 + 卡片类型过滤表达式 | 灵活，但令牌规则复杂，容易写错导致泄漏。 |
| c. 一把令牌 + 读取层过滤（现状） | 现在 i_memory 靠 policy 过滤（[i_memory README §3](../../tools/i_memory/README.md)）。领域增多后容易漏。 |

**令牌范围的写法：** `<领域>:<动作>`，动作有 `read`、`create`、`patch`、`status`（只改状态）、`delete`、`ack`。聊天沿用现有设备令牌，再细分出 `chat:append_user`、`chat:append_companion`、`chat:read`。现有设备令牌默认只有聊天权限，行为不变。

**推荐的权限表**（"—"表示没有任何权限）：

| 领域 | 手机 App（用户 + 手机上的林埃） | 电脑林埃 worker | Codex 规划助手 | Codex 学习导师 | 网页端 claude.ai（经 i_remote_mcp） | 看板（只读） |
|---|---|---|---|---|---|---|
| 聊天 | 全部（含 companion 追加） | 读；追加 companion（shadow 期不发布） | — | — | 追加本端轮次；读按出站策略过滤 | — |
| 记一下 captures | 新建、改、删本设备的；读处理结果 | — | 读、写处理结果（ack） | — | 新建、改、删自己的（i_remember） | — |
| 规划 plan_items / plan_weeks / plan_days | 读；改状态（完成、不做了） | 读 | 全部 | — | 读今日单和本周进度 | 读 |
| 收支 ledger | 全部 | 读 | 读本周汇总（建议不开明细） | — | 读（按出站策略） | 读汇总 |
| 经期 cycle | 全部 | — | — | — | — | — |
| 睡眠 sleep_days | 全部（导入） | 读 | 读 | — | 读 | 读 |
| 通用记忆卡（迁移后） | 全部 | 读 | — | — | 读（按出站策略，同现状） | — |
| Dreaming 等派生产物 | 本地 | — | — | — | — | — |

**执行点：**
- i_core API 按令牌范围拦截。
- i_memory 读取层直接读库（F8），要在 policy 里加**领域白名单**，未列出的领域一律不读（fail closed）。长期改为走 API。
- 给 Codex 的入口只监听本机，令牌没有聊天权限（总规划 W3 已有）。i_core 搬到常开主机后，Codex 改用远程地址，令牌不变。
- 思源看板：先由 Codex 用只读令牌单向生成思源文档；思源插件直接读 i_core 以后再做。

---

## 7. D5 迁移顺序与回滚（问题 6）

### 7.1 从哪类数据开始

| 选项 | 说明 |
|---|---|
| **a. 先建新领域，再把收支作为第一个搬家的手机数据（推荐）** | 新领域没有旧数据，风险最低；收支数量够、有金额合计能对账，能把"新建、修改、删除、判重"整条链路都验一遍，验完就是其他领域的模板。 |
| b. 先搬通用记忆卡 | 价值最大，但牵涉白板卡混存（F6）、Gate 1A-1 的中性 Card 问题和图片附件，最难回滚。 |
| c. 先搬经期做演练 | 数据量小、风险小，但验证信号也弱；而且经期只有手机读，搬过去的跨端价值最低。 |

### 7.2 每个领域都走同一套状态

| 状态 | 手机怎么写 | 以谁为准 | 进入下一步的条件 | 回滚 |
|---|---|---|---|---|
| 0 未迁移 | 写本地表 | 手机 | W6 出领域映射表；用户同意 | — |
| 1 影子 | 仍写本地表，**同时**把同样的改动作为 intent 交给 i_core；先回填全部旧记录（先 dry-run 再执行，保留旧 ID） | 手机 | 连续 7 天比对为零差异：条数、ID、每月金额合计（收支）、墓碑数；重启和离线补交测过；在副本上演练过回滚 | 关掉提交；i_core 里的影子数据可以留着或清掉；手机不受影响 |
| 2 切换 | 只提交 intent；本地表变成 i_core 的副本 | i_core | 至少 4 周无回滚；其他端已改读 i_core | 见下 |
| 3 退役 | 删除旧写入代码；旧表只读保留 | i_core | — | 先从 Git 恢复旧写入代码，再按状态 2 的回滚步骤做 |

**切换后的回滚（状态 2 → 0）：**
1. i_core 把该领域设为冻结，新的写入返回 `domain_frozen`（发起方的 intent 保持 pending，不会静默丢失）。
2. 手机拉完该领域的最后一段变更流。
3. 手机用副本确定性地重建旧表（旧 ID 没变，所以引用都还在）。别的端在切换期间写进来的记录（例如网页端、Codex）也在副本里，一起重建进去。
4. 手机切回"写本地表"。i_core 的数据只读保留，留作审计。

**每一步之前：** i_core 整库离线备份（沿用 `.state/backups/` 的做法）；手机建本机安全快照（`BackupService.createSafetySnapshot`，[memory_data_sync_service.dart](../../lib/data/services/sync/memory_data_sync_service.dart) 里已有调用）。真实数据的每次切换都要用户点头（AGENTS 常设授权之外）。

### 7.3 顺序

| 步 | 领域 | 说明 | 前置 |
|---|---|---|---|
| 0 | 公共前置 | i_core 领域框架（W1）；手机端：字段级修正写入、按领域 outbox 与副本、领域开关、林埃回复入队（W7-0） | — |
| 1 | 记一下 captures、规划 plan_* | 新领域，没有手机旧数据；WI 本机文件用导入脚本搬入 | W1 |
| 2 | i_remember 记录 | 并入 captures（`source=claude_web`）；i_remote_mcp 改写 i_core；手机经 i_core feed 取，不再单独做 47862 拉取端（F7） | 1 |
| 3 | **收支 ledger（第一个搬家的手机数据）** | 账本行是金额的权威；收支记录卡改成由账本生成的展示；修掉"删卡不删账本行"（F5） | 0、W6 映射表 |
| 4 | 睡眠 sleep_days | COROS 导入，按日期幂等；手记 `sleep_record` 卡并入 | 0 |
| 5 | 经期 cycle | 私密；节律由副本重新派生 | 3 跑稳 |
| 6 | 待办卡并入规划 | 手机 task / schedule / plan 卡迁入 `plan_items`；Record Organizer 不再产出这三类卡；日程面板改读规划副本 | 1、W5、决定 13 |
| 7 | 通用记忆卡（fact / event） | 要先解决白板卡混存（F6）和对象库（4.6 b）；是否需要先做 Gate 1A-1，单独决定 | 决定 17 |
| 8 | Dreaming、节律、洞察、成长契约、话题 | 都是可重建的派生产物，先留在手机；需要给网页端读时，再导出只读快照（参照 i_memory） | 7 之后再评估 |

---

## 8. D6 规划层和"记一下"（问题 7）

现在"记一下"有三种互相冲突的含义：
- V3：明确说"记一下" = 显式记录 → 记忆卡（User-truth）（[MEMORY_PROPOSAL_V3 §2 契约 1](../memory-research/MEMORY_PROPOSAL_V3.md)）；
- 快速捕获：侧键"记一下" = 给规划助手的原始输入，**不**变成记忆（[QUICK_CAPTURE §2](QUICK_CAPTURE_DESIGN_20261005.md)）；
- B3：网页端"帮我记一下" → 手机 Record Organizer → 记忆卡（决定 4）。

### 8.1 收件箱怎么分

| 选项 | 说明 |
|---|---|
| a. 一个收件箱，由 Codex 统一分诊 | Codex 判断每条去规划还是交给手机记成生活记录。电脑不开就全卡住。 |
| b. 两个入口分开 | 侧键只进规划；"帮我记住"只进记忆。用户要记住两个入口的区别，说错就进错地方。 |
| **c. 一个收件箱，两个处理者按类型分工（推荐）** | 所有"记一下"（侧键、网页端 i_remember、dot 经 Codex）都进 `captures`。手机 Record Organizer 处理生活记录（消费、睡眠、经期、事实、事件），Codex 处理待办、时间和容量变化。两边各自在这条 capture 上记处理结果。 |

推荐 c 的理由：用户只需要一个入口；类型分工避免同一句话被处理两次（Record Organizer 不再产出 task / schedule / plan 卡）；电脑不开时，生活记录照样当场记上。

**capture 的处理结果**（每条一个，按处理者分开记）：

```
dispositions: {
  organizer: { status: pending | done | skipped, outputs: [记录 id] },
  planner:   { status: pending | done | skipped, outputs: [规划 id], note: "记下了 / 容量变化 / …" }
}
```

- 一句话里既有生活记录又有待办（"午饭花了 30，周五前交报告"），两边各取各的。
- 纯感想：organizer `skipped`，planner 写进今日单的"记下了"。
- capture 不进聊天时间线，不触发林埃回复（沿用 QUICK_CAPTURE §2）。
- 侧键"记一下"里的生活事实是否直接进收支等领域，是一个要拍板的点（决定 12）：推荐"是"，因为这是用户显式发起的记录，符合 V3 契约 1。

### 8.2 规划领域

| 表 | 内容 | 来源 |
|---|---|---|
| `plan_items` | 事项。字段按 [PLANNER_AGENTS"规划库字段"](../../tools/life_planner/PLANNER_AGENTS.md#L51)，去掉思源专用部分；上级、前置、替代为都用 id；加 `remind_at`（给手机派生闹钟） | Codex 写；手机只改状态 |
| `plan_weeks` | 每周容量（预计、实际）、各主线配额和完成块数、欠账 | Codex 写 |
| `plan_days` | **新增**：今日队列（有序的事项 id）、版本号、"这次改了什么"、待拍板、今晚关灯时间 | Codex 写；`today.md` 变成它的投影 |

新增 `plan_days` 的理由：手机的今天页要显示队列顺序和"这次改了什么"。原 W8 打算把顺序写回 `plan_items`，这样每次重排都要改很多行，也表达不了"第 N 版"。

`areas.md`（主线、作息、配额定义）留在电脑上作为 Codex 的配置；手机需要的部分（主线名、本周配额和进度）已经包含在 `plan_weeks` 里。学习线的 `study-quota.md` 文件接口不变。

### 8.3 谁写什么、怎么并发

- **Codex 是规划结构的唯一写入者**：新建、拆分、排期、重排、周账。
- **手机**只改状态：完成、不做了。走 `plan:status` 范围，`actor=user_direct`。
- 并发：用户在手机上点了完成，Codex 同时在重排。按第 4.3 节，状态字段用户赢；Codex 下次运行时看到"完成"，把它移出队列。
- **电脑离线时**：手机显示最后一版今日单和生成时间，可以点完成；新的待办显示"等电脑上线后安排"。不在手机上另做一个小排程器，保持规划只有一个写入者。

### 8.4 对两份设计稿的修改（推翻项）

| 原设计 | 改成 | 理由 |
|---|---|---|
| QUICK_CAPTURE §5：电脑端用 `I_CORE_WORKER_SECRET` 取捕获 | 规划助手用 `captures:read`、`captures:ack` 范围令牌 | worker 密钥是万能后台钥匙，B3 已经避免用它（[B3 §1](B3_WRITEBACK_DESIGN.md)） |
| QUICK_CAPTURE §2、§9 第 1 条：捕获完全不让林埃看到 | 按 8.1 c：生活记录部分由手机 organizer 处理 | 一个入口，减少记错地方 |
| QUICK_CAPTURE §4：手机新建 `quick_captures` 本地表做待发队列 | 用 W7-0 的通用领域 outbox | 避免第二套待发队列 |
| QUICK_CAPTURE §7：今日单摘要单独推回手机 | 手机直接读 `plan_days` 副本 | 规划数据本身就在 i_core |
| B3 §3、§7：记录存 i_remote_mcp 账本，手机走 47862 拉取 | 记录存 i_core captures；手机走 i_core 变更流；"删除立即清正文"保留 | 原则 1；47862 的手机端从没实现（F7），不必再做 |
| life_planner README：规划不放 Here I Am | 规划放 i_core | 10/05 已改，本文确认 |
| W8：今日单写回 `plan_items` 的顺序 | 写 `plan_days` | 见 8.2 |

---

## 9. 拍板后需要同步修改的文档（由 W6 执行）

1. PRODUCT_ROADMAP：第 77 行（宿主）、第 80 行（手机新页面的例外）、第 92 行（手机作为唯一执行者；待同步内容的可见性）、§7（生活数据领域不以 1A-1、1A-2 为前置）。
2. CORE_SYNC_DATA_INVENTORY：第 30 行和第 46–52 行，改成"单一执行者（手机）"。
3. Gate 1A-0：补一份附录，把收支、经期、睡眠、规划、captures 的处理方式写成和 Formal32 同格式的行（不改已冻结的 32 行）。
4. B3_WRITEBACK_DESIGN：§3、§7 标为被本文替代。
5. QUICK_CAPTURE_DESIGN：按 8.4 修订。
6. PERSONAL_DATA_HUB_PLAN：第 2 节现状表按本文第 2.1 节更正（"帮我记一下"的记录目前到不了手机；林埃回复不在 i_core）。

---

## 10. 不确定的事项和验证方法

| 事项 | 为什么不确定 | 怎么验证 |
|---|---|---|
| 电脑是随身笔记本还是留在家的台式机；在上海每天开多久 | 文档里没有 | 问用户；到上海后用手机 `CoreSyncRuntimeService` 的最后成功时间、claude.ai 连接器失败天数统计两周 |
| 上海网络下 Tailscale、Cloudflare 隧道、claude.ai 的可达性 | 没有实测 | 到上海第一天：手机"立即同步"；claude.ai 调一次 `i_context` |
| 线上 i_remote_mcp 的真实行为 | 运行副本有 5 个文件和仓库不同（F10） | Codex 在本机对比差异后再动 W3 和记录迁移 |
| i_remember 记录是否真的都停在电脑上 | Flutter 拉取端在仓库里不存在，但本机可能有未推送的改动 | 在网页端调 `i_remember list`，看 `phone_status` 是否都是 `waiting_for_phone` |
| 手机上林埃的回复是否真的不进 i_core | 按代码是不进；没有查过真实库 | Codex 在本机只读查 i_core：导入日期之后、`origin_device_id` 为手机、`sender=companion` 的消息条数（预期为 0） |
| 各类记忆卡的数量（决定迁移规模） | 没读真实数据 | 用已有 i_memory 快照按 `type`、`structured_type` 计数，只报数字 |
| 手机库里有没有白板普通卡（`type=note`） | 白板主要在桌面端写 | 同上，按 `type=note` 计数 |
| WI 的 `plan.json` 字段和 W6 草案的 17 项 | 分支没推送 | W0 合入后读两份交接，对照本文第 8.2 节和第 11 节 |
| 云主机的磁盘加密和所在地区 | D1 选 B 时才需要 | 选 B 时由用户定服务商；W1 实现前不需要 |

---

## 11. 需要用户拍板

每条后面是推荐项。没拍板的条目，对应任务卡不开工。

**宿主与执行**

1. **i_core 宿主**：A 电脑起步、按实测切到常开主机 / B 现在就搬 / C 中继。**推荐 A 起步，两周实测后按第 3 节的条件决定是否切 B。** 同时请回答：电脑会不会随你去上海？能不能接受包括私密聊天在内的数据放在云主机上（只用磁盘加密）？如果以后切 B，i_core 里的 activity 控制面和邮件测试保持关闭、不随迁（要相应改 MDA-0 "Windows 是唯一夜间活动 Core"的约定）。
2. **手机作为 Record Organizer、Dreaming、提醒、check-in 的唯一执行者，电脑离线时照常运行，产出作为待同步 intent**（改 PRODUCT_ROADMAP 第 92 行、CORE_SYNC_DATA_INVENTORY 第 30、46–52 行）。**推荐：是。**
3. **待同步的记录可以被手机上的林埃读到，注入时标"未同步"。** **推荐：可以。**
4. **手机生成的林埃回复也写入 i_core**（i_core 放开：普通手机设备可以提交自己生成的 companion 消息；电脑 worker 保持 shadow，不和手机同时生成）。**推荐：是。**

**同步规则**

5. **冲突规则**：用户的改动 > 导入 > AI 推断；两个用户改动冲突时不自动选，进"待处理"。**推荐：是。**
6. **删除**：默认 30 天内可恢复，之后清正文、保留墓碑；网页端 i_remember 的记录和"永久删除"立即清正文。**推荐：是。**
7. **重复**：经 Record Organizer、林埃工具或导入生成的重复记录直接判重，不新建（和现在手机一样）；用户在界面上手动新建的重复照收，并提示合并。**推荐：是。**
8. **附件**：第一批领域只同步文字，图片留在手机；迁移通用记忆卡之前上 i_core 对象库。**推荐：是。**
9. **待同步的有效期**：60 天，超过 7 天提醒。**推荐：是。**

**权限**

10. **按第 6 节的权限表发令牌**，重点是：经期只给手机；网页端能读收支（按出站策略）但不能读经期；Codex 规划助手只看收支周汇总，不看明细。**推荐：按表。**

**迁移**

11. **迁移顺序**：记一下和规划 → i_remember 记录 → 收支（第一个搬家的手机数据）→ 睡眠 → 经期 → 待办卡并入规划 → 通用记忆卡；Dreaming 等派生产物先留手机。**推荐：按此顺序。**
12. **侧键"记一下"里的生活事实（如"午饭 30 元"）直接进收支等领域。** **推荐：是。**
13. **手机的待办、日程、计划卡并入规划库；Record Organizer 不再产出这三类卡；日程面板改读规划。** **推荐：是（第 7.3 节第 6 步）。**
14. **i_remember 的记录从 i_remote_mcp 本机账本移到 i_core**（改 B3 决定 2 的存放位置，保留"可以真删"）。**推荐：是。**
15. **收支以账本行为准，收支记录卡改成由账本生成的展示；删除收支卡时同时删账本行。** **推荐：是。**

**流程与路线**

16. **治理方式**：沿用 10/02 的"轻量通道"（能用即验收），但保留硬安全栏：每步前备份、影子期零差异、副本上演练回滚，真实数据的每次切换由你点头。**推荐：是。**
17. **生活数据领域不以 Gate 1A-1（中性 Card）、1A-2（Markdown Vault）为前置；通用记忆卡迁移前再单独决定要不要先做 1A-1。** **推荐：是。**
18. **W4（记一下页）、W5（今天/本周页）作为路线图"手机暂停新页面"的明确例外。** **推荐：是。**
19. **思源看板先由 Codex 用只读令牌单向生成文档，插件以后再做。** **推荐：是。**
20. **三种"记一下"并成一个收件箱，手机 organizer 和 Codex 按类型分工（第 8.1 节 c）。** **推荐：是。**
