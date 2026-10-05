# ADR：个人数据中枢的权威、同步与执行位置（2026-10-05）

> **状态：提议，待用户拍板（见第 11 节）。** 只写设计，不改代码、不动数据、不部署。
>
> **代码基线：** `codex/w0-integrate@842a3e9`（PR #5，草稿，尚未合入 `v3-lab`）。下文的 `文件:行号` 都按这个提交；W0 合入后行号可能漂移，以文件内容为准。
>
> **关系：** 本文是 [个人数据中枢总规划](PERSONAL_DATA_HUB_PLAN_20261005.md) 的设计依据，总规划里的 W1、W2、W5、W6、W7 卡已按本文改写。本文继承 [Gate 1A-0](data-authority/gate1a0/AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md) 已冻结的接受语义，并列出需要改文的既有条款（第 1.3 节、第 9 节）。
>
> **W6 草案：** 用户已把 W6 草案和交接发来，收进 [data-authority-preflight/](data-authority-preflight/W6_DATA_AUTHORITY_DECISION_DRAFT_20261005.md)。两者的对照和取舍见第 12 节，正文已按采纳项修改。WI 本机规划文件（分支 `codex/wi-local-planner`）仍未读到。
>
> **2026-10-05 第二轮：** 用户回答了宿主、林埃回复入 i_core、i_remember 迁移三项（第 11 节标"已定"）；第 1.3 节补了每条冲突的推荐处理。

---

## 0. 结论摘要

| 问题 | 推荐 |
|---|---|
| 宿主可用性（问题 4） | **已定：** i_core 留在随身带去上海的笔记本上（除睡觉外都开着），不上云。手机按离线优先设计，夜间 Core 离线是正常状态。W1 的实现仍不绑定 Windows，留着以后搬家的余地。 |
| 可变记录同步（问题 2） | 版本号由 i_core 分配，客户端带着"我基于哪个版本改的"提交。i_core 做字段级合并：用户改的字段优先于导入和 AI；两个用户改动冲突时不自动选，进"待处理"。删除写墓碑，30 天内可恢复。AI 重复记的直接判重，用户重复记的提示合并。第一批领域只同步文字。 |
| 处理放在哪端（问题 3） | 手机继续跑林埃回复、Record Organizer、Dreaming、提醒和 check-in，并且是这些工作的**唯一执行者**；产出作为 intent 交给 i_core。排期由电脑上的 Codex 做。i_core 只负责接受、存储和分发。 |
| 权限（问题 5） | 按领域发令牌。需要不同权限的卡片类型拆成独立领域（收支、经期、睡眠、规划），领域就是权限边界。经期只开给手机。 |
| 迁移顺序（问题 6） | 先建没有历史包袱的新领域（记一下、规划，以及并进来的 i_remember 记录）；第一个搬家的手机数据是收支，然后经期、睡眠。每个领域走"影子 → 冻结切换 → 退役"三步，一次只切一个领域；切换前能整步撤回，切换后优先往前修。 |
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

### 1.3 和既有条款的冲突与推荐处理（拍板后由 W6 改文，见第 9 节）

| # | 既有条款 | 冲突点 | 推荐处理 |
|---|---|---|---|
| C1 | [PRODUCT_ROADMAP 第 92 行](../companion-first/PRODUCT_ROADMAP.md#L92)：客户端不能各自运行 Memory V3；Core 不可达时手机只留草稿和捕获队列；"依赖 Core 才能形成的关系回复、检索和权威写入等待 Core 恢复"。 | 原则 3 让手机继续跑 AI 处理。手机现在离线也能完整聊天、整理记录。 | **改条款，保留它要防的两件事。** 改成：手机是聊天回复、Record Organizer、Dreaming、提醒、check-in 的指定执行者，Core 不在时照常运行，产出是 `pending` intent，界面和手机上的林埃都能看到但标"未同步"。保留：不共享原始 SQLite；同一类产物不由两台设备各自生成再合并；`pending` 不冒充已接受。 |
| C2 | [CORE_SYNC_DATA_INVENTORY 第 30 行](../companion-first/CORE_SYNC_DATA_INVENTORY.md#L30)：check-in/提醒"只由核心调度"；[第 46–52 行](../companion-first/CORE_SYNC_DATA_INVENTORY.md#L46-L52)：Dreaming 等"由核心唯一生成"。 | 同 C1。 | **"核心唯一生成"改成"单一执行者（手机）"。** 提醒拆成两类：林埃给自己留的提醒是手机本机状态，不同步；用户的定时事项属于规划领域，在 i_core，手机据此派生闹钟。 |
| C3 | [PRODUCT_ROADMAP 第 77 行](../companion-first/PRODUCT_ROADMAP.md#L77)：主电脑持续运行 Core。 | 笔记本会关机睡觉。 | **基本不用改，补一句。** 改成"主电脑（目前是随身笔记本）除睡眠时段外常开；夜间 Core 离线是预期状态，客户端离线优先"。不上云（第 3 节）。 |
| C4 | [PRODUCT_ROADMAP 第 80 行](../companion-first/PRODUCT_ROADMAP.md#L80)：手机新功能暂停，不新增页面。 | 总规划的 W4（记一下页）、W5（今天/本周页）是新页面。 | **只给 W4、W5、W7-0 开例外，其余照旧暂停。** 同一行本来就允许"用户明确提出只能由移动场景完成的高频 companion 需求"，侧键记一下和今日单正是这类需求，用户确认一次即可，不用推翻暂停原则。 |
| C5 | [PRODUCT_ROADMAP §7](../companion-first/PRODUCT_ROADMAP.md#L455)：1A-1（中性 Card）→ 1A-2（Markdown Vault）→ 1A-3（Core intent/outbox）依次解锁。 | W1 直接实现 1A-3 的一部分，而白板已于 10/02 停止开发。 | **生活数据领域不等 1A-1、1A-2。** W1 只做 1A-3 里本项目马上要用的部分（intent、outbox、回执、按领域 cursor、墓碑）。epoch、fencing、换宿主接管先不做（宿主不搬），记录里预留 `core_instance_id`。1A-1、1A-2 跟白板一起搁置；迁移通用记忆卡之前再单独决定（决定 17）。 |
| C6 | Gate 1A-0 的 Formal32 对象清单（[FORMAL_MIGRATION_MATRIX 第 54–93 行](data-authority/gate1a0/FORMAL_MIGRATION_MATRIX.md#L54-L93)）。 | 没有收支、经期、睡眠、规划、提醒、节律、成长契约、生活洞察、话题这些对象。 | **不改已冻结的 32 行，加附录。** 按同样九列为收支、经期、睡眠、规划、captures 补行；节律、成长契约、洞察、话题标"手机本地派生产物，暂不迁"。 |
| C7 | B3 决定 2：i_remember 记录"只存 i_remote_mcp 本机账本"。 | 原则 1 要求个人数据以 i_core 为准。 | **已定：** 迁进 i_core，"删除立即清正文"保留（决定 14）。 |

---|---|---|
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

**前提（2026-10-05 用户确认）：** 电脑是一台随身带去上海的笔记本，除睡觉时关机外都开着。

| 选项 | 做法 | 好处 | 代价 |
|---|---|---|---|
| **A. 电脑继续做宿主，手机离线优先** | 不动部署。手机所有写入先进本地待发队列，电脑开机后补交。 | 零迁移风险；数据不离开自己的机器。 | 电脑关着时 claude.ai 连接器整体不可用（读不到记忆，也写不回）；Codex 不排期；网页端说的"帮我记一下"直接失败。 |
| **B. 搬到常开主机** | i_core + i_remote_mcp 搬到一台常开的机器：云主机，或者家里一台不关的小机器。电脑和手机都变成客户端。 | claude.ai 随时可用；手机随时能同步；"唯一权威"不需要额外机制。 | 包括私密聊天在内的数据放到别人的机器上（`node:sqlite` 不支持库加密，只能靠磁盘加密）；要换一次权威宿主（停服、备份、搬库、轮换令牌）；i_core 里还挂着两块 Windows 专属功能，不能随迁：activity 控制面（默认关闭；MDA-0 约定"Windows 是唯一夜间活动 Core"）和快捷指令邮件测试（DPAPI，仅 debug）。 |
| C. 电脑做权威，外加常开中继 | 常开的地方只放加密信箱（收 intent）和一份按出站策略过滤后的只读快照，给 claude.ai 读。电脑开机后从信箱取件。 | 权威不出电脑。 | 要部署两套 MCP；claude.ai 只能读明文，快照里的可分享数据照样放在外面，隐私上接近 B，复杂度更高。 |

（还考虑过让手机当宿主：claude.ai 要从公网访问手机，耗电、网络和 Node 运行环境都不现实，不列入。）

**已定：A。** i_core、i_remote_mcp 和隧道继续跑在笔记本上，不上云。

理由：
1. 笔记本白天和晚上都开着，只有睡觉时离线；这段时间手机上的提醒、check-in 都不依赖电脑，claude.ai 也基本不用，A 的主要缺点基本消失。
2. 不用换宿主，Gate 1A-0 里还没实现的换宿主流程（新 instance、epoch、旧令牌作废）可以继续搁置。
3. W1 仍按"宿主无关"实现，以后真要搬也只是部署动作。

**笔记本要注意的三件事：**
- 合盖、电池模式下 Windows 默认会睡眠。要把"合盖不睡眠"（接电源时）设好，否则白天也会断。
- 如果笔记本会带去公司，公司网络可能拦 Tailscale 或 Cloudflare 隧道（**不确定**，第 10 节）。断了时按下表的"离线"处理。
- 关机、睡眠前不需要任何操作；i_core 用 WAL，正常关机不丢已接受的数据。开机后登录自启（[i_core README"Windows 登录自启"](../../tools/i_core/README.md#L33)）。

**关于云主机会不会过滤私密内容（用户提问）：**
- 普通云主机（自己装系统、自己跑程序的那种）一般不会去读你磁盘里的数据库，也没有在写入时拦内容的机制。服务商的使用条款主要禁止违法内容，通常在接到投诉、或内容对公网公开时才处理。具体到某家服务商，以它的条款为准，这里**不确定**。
- 国内地域的云主机不一样：要实名备案，内容监管严格，成人内容在国内属于违规。如果以后要上云，应选境外地域。
- 真正会"过滤"的地方不在宿主，而在模型服务商：手机林埃调用的模型、claude.ai，都按各自的政策处理发给它们的内容。哪些内容能给 claude.ai 看，由 i_memory 的私密规则决定（B0.2），和 i_core 放在哪无关。
- 手机和 i_core 之间走 Tailscale，是端到端加密的，私密聊天同步不经过 Cloudflare。现在经 Cloudflare 隧道出去的只有按私密规则过滤后、给 claude.ai 的内容。上云后这条也应保持。

**电脑离线（睡觉时，或网络断开）各端的表现：**

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

夜里这些表现基本无感：用户在睡觉，手机提醒和 check-in 照常；早上开机后，待发队列自动补交，Codex 出今日单。

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
7. 领域可以声明"连带字段组"，例如金额和币种、入睡和醒来时间。组里任一字段被并发改过，就按整组处理，不拆开合并。
8. 删除、恢复、合并三种 op 从不自动合并：基准版本过旧就返回冲突（采纳 W6 D07 的谨慎做法）。

（W6 D07 原建议首版连"不同字段并发"也一律报冲突。本文没有采纳：Codex 重排和手机点完成几乎总是改不同字段，一律报冲突会让待处理列表天天出现与用户无关的条目。第 12 节有对照。）

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
- 手机旧库没有墓碑（删除是物理删除，F2），迁移时导不出旧的删除记录；只有 i_remember 的旧删除标记能原样带过来（W6 E5、E6）。
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
- **幂等键分两层**（采纳 W6 D06）：记录 `id` 管"是哪一条"，每次修改另有 `op_id` 管"是哪一次"。重试复用同一 `op_id`；HTTP 超时先查这个 `op_id` 的结果再决定要不要重发。同一条记录的修改按先后顺序发，后一次以前一次的回执版本为基准；没确认的删除不能被后面的修改越过。
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
| 1 影子 | 仍写本地表，**同时**把同样的改动作为 intent 交给 i_core（影子数据只有对账脚本能读，其他端读不到，所以不存在第二份权威）；先回填全部旧记录（先 dry-run 再执行，保留旧 ID） | 手机 | 连续 7 天比对为零差异：条数、ID、每月金额合计（收支）、墓碑数；重启和离线补交测过；在副本上演练过回滚 | 关掉提交；i_core 里的影子数据可以留着或清掉；手机不受影响 |
| 2 冻结切换 | 先冻结：停该领域的旧写入、启动去重、账本桥接等自动动作，排空并核对待发队列，做最终对账和备份；再切成只提交 intent，本地表变成 i_core 的副本 | i_core | 至少 4 周无回滚；其他端已改读 i_core | 见下 |
| 3 退役 | 删除旧写入代码；旧表只读保留 | i_core | — | 先从 Git 恢复旧写入代码，再按状态 2 的回滚步骤做 |

**一次只切一个领域**（采纳 W6 D04）：上一个领域进入观察期之后，下一个领域才进冻结切换。开发可以并行。

**切换后的回滚（状态 2 → 0）：** 切换后 i_core 已经接受了新写入，默认先**往前修**，不回退（采纳 W6 D12）。确实要退回旧路径时，按下面的步骤，而且要先在副本上演练、另外取得用户授权；任何情况下都不能用旧备份覆盖整个 i_core 库，那会抹掉其他领域的新写入。
1. i_core 把该领域设为冻结，新的写入返回 `domain_frozen`（发起方的 intent 保持 pending，不会静默丢失）。
2. 手机拉完该领域的最后一段变更流。
3. 手机用副本确定性地重建旧表（旧 ID 没变，所以引用都还在）。别的端在切换期间写进来的记录（例如网页端、Codex）也在副本里，一起重建进去。
4. 手机切回"写本地表"。i_core 的数据只读保留，留作审计。

**每一步之前：** i_core 整库离线备份（沿用 `.state/backups/` 的做法）；手机建本机安全快照（`BackupService.createSafetySnapshot`，[memory_data_sync_service.dart](../../lib/data/services/sync/memory_data_sync_service.dart) 里已有调用）。真实数据的每次切换都要用户点头（AGENTS 常设授权之外）。

### 7.3 顺序

| 步 | 领域 | 说明 | 前置 |
|---|---|---|---|
| 0 | 公共前置 | 旧卡先分类（采纳 W6 D01）：按"来源是否是显式记录 → 业务类型 → 通用类型"三步判断，每张卡都落进"迁移 / 明确排除 / 待核实"之一，白板卡、未知类型不迁；i_core 领域框架（W1）；手机端：字段级修正写入、按领域 outbox 与副本、领域开关、林埃回复入队（W7-0） | — |
| 1 | 记一下 captures、规划 plan_* | 新领域，没有手机旧数据；WI 本机文件用导入脚本搬入 | W1 |
| 2 | i_remember 记录 | 并入 captures（`source=claude_web`）；i_remote_mcp 改写 i_core；手机经 i_core feed 取，不再单独做 47862 拉取端（F7） | 1 |
| 3 | **收支 ledger（第一个搬家的手机数据）** | 账本行是金额的权威；收支记录卡改成由账本生成的展示；修掉"删卡不删账本行"（F5）。按 W6 D02a 收窄第一批：缺币种不默认人民币；未付款、取消、退款的订单不当支出；账本里的转账、奖励、罚款等林埃共同账户类型先列明、不并入本批 | 0、W6 映射表 |
| 4 | 经期 cycle | 私密；起止日、进行中、症状保留原值，未结束留空、不补；节律由副本重新派生 | 3 进入观察期 |
| 5 | 睡眠 sleep_days | 按 W6 D02c、D08：保存多段、多来源的原始观测，`sleep_days` 只是按规则生成的日视图；手记和 COROS 并存，不互相覆盖；时区、跨日、"大概"这类不确定性保留 | 4 进入观察期 |
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
- 从 i_remember 旧账本迁过来的记录，`planner` 一律记 `skipped`：它们当初的语义是"帮我记住"，已经交给手机成卡，迁移不能把它们变成一批新待办（采纳 W6 D03）。新的 i_remember 记录照常两边处理。
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
| 笔记本带去公司时，公司网络是否拦 Tailscale / Cloudflare 隧道 | 没有实测 | 第一次在公司用时：手机"立即同步"；claude.ai 调一次 `i_context` |
| 上海网络下 Tailscale、Cloudflare 隧道、claude.ai 的可达性 | 没有实测 | 到上海第一天：手机"立即同步"；claude.ai 调一次 `i_context` |
| 线上 i_remote_mcp 的真实行为 | 运行副本有 5 个文件和仓库不同（F10） | Codex 在本机对比差异后再动 W3 和记录迁移 |
| i_remember 记录是否真的都停在电脑上 | Flutter 拉取端在仓库里不存在，但本机可能有未推送的改动 | 在网页端调 `i_remember list`，看 `phone_status` 是否都是 `waiting_for_phone` |
| 手机上林埃的回复是否真的不进 i_core | 按代码是不进；没有查过真实库 | Codex 在本机只读查 i_core：导入日期之后、`origin_device_id` 为手机、`sender=companion` 的消息条数（预期为 0） |
| 各类记忆卡的数量（决定迁移规模） | 没读真实数据 | 用已有 i_memory 快照按 `type`、`structured_type` 计数，只报数字 |
| 手机库里有没有白板普通卡（`type=note`） | 白板主要在桌面端写 | 同上，按 `type=note` 计数 |
| WI 的 `plan.json` 字段 | 分支没推送 | 读 WI 交接，对照本文第 8.2 节 |
| 具体云服务商对私密内容的条款 | 已定不上云，目前不需要 | 以后要上云时再查目标服务商的使用条款 |

---

## 11. 需要用户拍板

每条后面是推荐项。没拍板的条目，对应任务卡不开工。

> 用户 10/05 第二轮回复"1…… 2.要 3.要"。这里按上一轮对话里三个问题的顺序理解：1 = 宿主（第 1 项），2 = 手机林埃回复写入 i_core（第 4 项），3 = i_remember 迁入 i_core（第 14 项）。如果指的是本节的第 2、3 项，请指出，这里再改。

**宿主与执行**

1. **i_core 宿主** —— **已定（2026-10-05）：A，留在随身笔记本上，不上云。** 原推荐：A 起步，按实测再定。
2. **手机作为 Record Organizer、Dreaming、提醒、check-in 的唯一执行者，电脑离线时照常运行，产出作为待同步 intent**（改 PRODUCT_ROADMAP 第 92 行、CORE_SYNC_DATA_INVENTORY 第 30、46–52 行）。**推荐：是。**
3. **待同步的记录可以被手机上的林埃读到，注入时标"未同步"。** **推荐：可以。**
4. **已定（2026-10-05）：要。** **手机生成的林埃回复也写入 i_core**（i_core 放开：普通手机设备可以提交自己生成的 companion 消息；电脑 worker 保持 shadow，不和手机同时生成）。**推荐：是。**

**同步规则**

5. **冲突规则**：用户的改动 > 导入 > AI 推断；两个用户改动冲突时不自动选，进"待处理"。**推荐：是。**
6. **删除**：默认 30 天内可恢复，之后清正文、保留墓碑；网页端 i_remember 的记录和"永久删除"立即清正文。**推荐：是。**
7. **重复**：经 Record Organizer、林埃工具或导入生成的重复记录直接判重，不新建（和现在手机一样）；用户在界面上手动新建的重复照收，并提示合并。**推荐：是。**
8. **附件**：第一批领域只同步文字，图片留在手机；迁移通用记忆卡之前上 i_core 对象库。**推荐：是。**
9. **待同步的有效期**：60 天，超过 7 天提醒。**推荐：是。**

**权限**

10. **按第 6 节的权限表发令牌**，重点是：经期只给手机；网页端能读收支（按出站策略）但不能读经期；Codex 规划助手只看收支周汇总，不看明细。**推荐：按表。**

**迁移**

11. **迁移顺序**：记一下和规划 → i_remember 记录 → 收支（第一个搬家的手机数据）→ 经期 → 睡眠 → 待办卡并入规划 → 通用记忆卡，一次只切一个领域；Dreaming 等派生产物先留手机。**推荐：按此顺序。**
12. **侧键"记一下"里的生活事实（如"午饭 30 元"）直接进收支等领域。** **推荐：是。**
13. **手机的待办、日程、计划卡并入规划库；Record Organizer 不再产出这三类卡；日程面板改读规划。** **推荐：是（第 7.3 节第 6 步）。**
14. **已定（2026-10-05）：要。** **i_remember 的记录从 i_remote_mcp 本机账本移到 i_core**（改 B3 决定 2 的存放位置，保留"可以真删"）。**推荐：是。**
15. **收支以账本行为准，收支记录卡改成由账本生成的展示；删除收支卡时同时删账本行。** **推荐：是。**

**流程与路线**

16. **治理方式**：沿用 10/02 的"轻量通道"（能用即验收），但保留硬安全栏：每步前备份、影子期零差异、副本上演练回滚，真实数据的每次切换由你点头。**推荐：是。**
17. **生活数据领域不以 Gate 1A-1（中性 Card）、1A-2（Markdown Vault）为前置；通用记忆卡迁移前再单独决定要不要先做 1A-1。** **推荐：是。**
18. **W4（记一下页）、W5（今天/本周页）作为路线图"手机暂停新页面"的明确例外。** **推荐：是。**
19. **思源看板先由 Codex 用只读令牌单向生成文档，插件以后再做。** **推荐：是。**
20. **三种"记一下"并成一个收件箱，手机 organizer 和 Codex 按类型分工（第 8.1 节 c）。** **推荐：是。**

---

## 12. 与 W6 草案的对照

W6 草案（[决定草案](data-authority-preflight/W6_DATA_AUTHORITY_DECISION_DRAFT_20261005.md)、[交接](data-authority-preflight/W6_AUTHORITY_DRAFT_HANDOFF_20261005.md)）和本文大方向一致：i_core 用版本号裁决、用户修正不被 AI 覆盖、删除写墓碑防复活、按领域授权、先迁旧记录再搬收支。下表只列有差别或本文据此修改的地方。

| W6 项 | W6 的建议 | 本文原来的写法 | 取舍 |
|---|---|---|---|
| D01 分类 | 先看来源资格，再看业务类型，再看通用类型；未知的隔离，每张卡必须有去处 | 没有专门写 | **采纳**，写进第 7.3 节第 0 步 |
| D02a 收支 | 不默认币种；未付款/退款不算支出；账本里的额外类型不进本批 | 收支整体迁移 | **采纳**，收窄第一批（第 7.3 节） |
| D02c、D08 睡眠 | 多来源观测 + 日视图；保留不确定性 | 按日期一条 | **采纳**（第 7.3 节） |
| D03 旧 notes | 并入 captures，但要区分"长期记录"和"待分诊"，旧记录不能变成规划待办 | 并入 captures，两个处理者都处理 | **采纳**：旧记录的 planner 记 `skipped`（第 8.1 节） |
| D04 顺序 | notes → 待办 → 收支 → 经期 → 睡眠；一次只切一个领域 | 收支 → 睡眠 → 经期 → 待办 | **部分采纳**：经期移到睡眠前（睡眠口径复杂），一次一域；待办卡仍放在收支之后，因为要先有 W5 今天页、并改 Record Organizer 和日程面板，比收支牵涉更多手机代码 |
| D05 写路径 | 禁止双写；冻结旧写入后整体切换 | 影子期手机同时写本地表和交 intent | **合并**：保留影子期（用真实流量比对，最能发现整理结果到 intent 的映射错误），但影子数据只给对账脚本读，不形成第二份权威；切换那一步加上 W6 的冻结、排空、最终对账（第 7.2 节） |
| D06 离线 | outbox 或只允许离线草稿；mutation 键与记录 ID 分开 | outbox | **采纳 outbox**，补上两层幂等键和因果顺序（第 4.7 节）。"只允许离线草稿"不采纳：笔记本夜间离线，草稿方案会让夜里的记录都不算数 |
| D07 冲突 | 首版不做字段级合并，不同字段也报冲突 | 字段级合并 + 主体分级 | **本文为主，吸收 W6 的谨慎**：加"连带字段组"，删除/恢复/合并从不自动合并（第 4.3 节） |
| D11 删除保留期 | 没定之前不承诺 30 天 | 建议 30 天 | 不冲突：30 天仍是待拍板项（决定 6），W1 实现前不对外承诺 |
| D12 回滚 | 切换后优先往前修；逆向迁移另演练另授权；不整库覆盖 | 用副本重建旧表 | **采纳**（第 7.2 节） |
| D13、G0–G6 | 分 Gate 放行 | 影子 → 切换 → 退役 | 一致；W6 的 G0–G6 作为第 7.2 节每一步的验收清单使用 |
| D14 权限 | 最小授权；规划助手只拿睡眠摘要 | 第 6 节权限表 | 一致 |
