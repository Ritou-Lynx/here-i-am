# Gate 1A-0 迁移矩阵附录：生活数据领域（2026-10-05）

> **状态：用户已确认的目标矩阵补充（2026-10-05）；未实施。** 依据是[个人数据中枢 ADR](../../PERSONAL_DATA_HUB_ADR_20261005.md) 第 4、7 节和冲突 C6（ADR 第 1.3 节） 的处理。
>
> 本附录**不修改**已冻结的 [Formal32](../gate1a0/FORMAL_MIGRATION_MATRIX.md) 32 行，也不改变其 harness 的机器目录。它用同样的九列，为 Formal32 没有覆盖的生活数据对象补行。判定规则沿用 Formal32：旧 ID 原值保留；迁移和回滚都走领域操作；`blocked` 是 fail-closed，不是待选方案。
>
> 每个领域的字段级映射表由 W6 在本目录另写（总规划 W6 卡第 3 项），本附录只定分类。

| 对象 | 旧身份 / 存储 | 目标身份 / schema | 正文 / 状态权威 | 引用 | 迁移 / 回滚 | 删除 / 恢复 | 索引 / 备份 | blocked 条件 |
|---|---|---|---|---|---|---|---|---|
| Capture（含 i_remember 记录） | i_remote_mcp `notes.note_id`；新捕获无旧身份 | 原 `note_id` / 客户端 UUID → `captures` | captures 领域 op；按处理者分开的处理结果 | 派生记录 id、来源设备 | migrate：notes 带 revision 与删除标记导入，旧记录 planner 记 `skipped`；rollback 恢复 i_remote_mcp 账本为写入方 | `claude_web` 来源删除立即清正文，只留标记；其他来源按领域墓碑规则 | 列表/计数 derive；领域 op 与墓碑必备份 | 用途无法区分（长期记录 vs 待分诊）；同 note_id 不同 revision 内容冲突 |
| Plan item / week / day | WI 本机文件；手机 task/schedule/plan 卡 `memory_cards.id` | 原 ID → `plan_items`；`plan_weeks`、`plan_days` 新建 | 规划领域 op；Codex 是结构唯一写入者，手机只改状态 | 上级、前置、替代为、capture id | migrate：WI 文件导入；旧卡状态 active→待办、completed→完成、cancelled→放弃，主线留空；不自动排程；rollback 回到本机文件和旧卡 | 墓碑；30 天可恢复后清正文 | today.md、思源看板 derive；op 与墓碑必备份 | 重复规则、父子关系目标无法表达；状态值未知 |
| Ledger entry | `ai_finance_ledger.id`；收支卡 `memory_cards.id`（`linkedFactId` 关联） | 原账本 ID → `ledger_entries`；收支卡成为由账本生成的展示 | 账本行是金额权威 | 来源卡、来源消息 `sync_id`、capture id | migrate：卡与账本按关联合为一条业务记录；第一批不含转账/奖励/罚款等共同账户类型；rollback 按 ADR 7.2，切换后先往前修 | 墓碑；删收支卡同时删账本行 | 汇总、面板 derive；op 必备份 | 缺币种；卡与账本金额不一致；未付款/退款无法区分；同一付款重复 |
| Cycle entry | `menstrual_record` 卡 `memory_cards.id` | 原 ID → `cycle_entries` | 经期领域 op；节律是派生 | 来源卡 | migrate：起止日、进行中、症状保留原值，未结束留空、不补；rollback 同上 | 墓碑；只有手机有权限 | `user_rhythms` 经期节律 derive；op 必备份 | 起止日矛盾；进行中状态无法判定 |
| Sleep observation / day | `sleep_record` 卡 `memory_cards.id`；COROS 摘要文件 | 卡 ID / (来源, 日期, 段) → 睡眠观测；`sleep_days` 为日视图 | 各来源观测并存；用户修正是人工修订层 | 来源卡、导入批次 | migrate：多段、多来源原样保存；不插值、不互相覆盖；rollback 同上 | 墓碑 | `sleep_days` derive；观测与 op 必备份 | 时区或跨日归属不明且无法标 unknown；手记与设备记录被迫合成单值 |
| Reminder（林埃给自己的） | `system_message_queue` 行 | 不迁 | 手机本机执行状态 | — | degraded-preserved：留手机，不同步 | 本机规则（过时作废） | 不备份 | 不适用 |
| User rhythm / growth pact / life insight / topic thread | 各自 `id`（memory_v3 表） | 暂不迁 | 手机本地派生产物 | 卡、片段 | degraded-preserved：留手机；需要时导出只读快照 | 本机规则 | 可重建，不要求备份 | 不适用 |
