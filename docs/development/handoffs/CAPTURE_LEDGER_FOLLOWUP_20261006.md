# Capture 收支卡本地账本桥交接（2026-10-06）

- 基线：`d9a8498264d349f8593cd421e76db3e77ad102fd`；分支：`codex/capture-ledger-20261006`。
- 工作包：PR12 收支复核①；仅实现已授权的 capture 收支卡进入现手机账本面板，以及删除 capture 时精确清理其派生账本行。
- 状态：本包源码与合成测试完成，待主窗复核、整合。无 push、PR、合主线、App build、ADB、手机安装或生产数据写入。

## 行为与关联

1. `capture_card_reconciler.dart` 在生产 CaptureConsumer 已有 SQLite 事务内同步等待 Organizer 的收支桥；复用 `expense_entry` / `shopping_order` / `income_entry` 的金额、收入分成和日期解析，不恢复自动聊天记账。
2. `ai_finance_service.dart` 为 capture 投影使用稳定 UUID v5（capture sourceRef + 卡片 ID），并在现有 `character_id` 写入 `system:capture_bridge:captures:<capture-id>` 来源标识。`linked_fact_id` 仍指向卡片供面板读取，但它可由现有编辑 API 清空，不作为唯一级联凭据。
3. 同一生成槽位修订原账本 ID；金额/收入支出分类变化覆盖原行，改为非收支或明确移除槽位则删该行。不同 capture 的同额同用途行不参与启发式合并，通用写入路径也不能借用 capture 行作为其去重结果。
4. 删除仅匹配稳定生成 ID + capture 来源标识；同卡片 ID 的手工账本行、其他 capture 行均保留。用户通过现有账本编辑 API 改金额/备注乃至清空 linked_fact_id 后，来源删除仍能清理确切派生行。
5. 原 PR11 卡片保护不变：用户修改、缺失、来源不独占、旧基线不明和多卡对应不明确均保持原行为/提示。来源删除时，其明确生成的账本投影仍删除，修改过的卡片保留。来源修订遇受保护卡片时也保留其旧账本内容并提示待确认。
6. 无金融字段、缺金额或非法金额的收支产出抛错；模型失败、桥接失败、ACK/提交失败都不会留下半成卡片或账本。卡片、FTS、账本、处理回执、ACK 共用已有事务；不另建平行存储、不新增 schema。

## 验证

使用真实 AppDatabase、生产 CaptureConsumer / CaptureCardReconciler / AiFinanceService，合成来源与合成 SQLite。面板断言调用 LedgerViewModel 使用的 `getRecentEntries` / `getLedgerOverview`，不是仅断言原始表。

- `flutter test --no-pub test/data/personal_data_hub/capture_finance_lifecycle_test.dart test/data/personal_data_hub/capture_consumer_multi_connection_test.dart test/data/personal_data_hub/capture_lifecycle_test.dart test/data/personal_data_hub/quick_capture_adapter_test.dart test/data/services/ai_finance_service_test.dart --reporter expanded`：**57/57 通过**。
- 上述新增生命周期文件共14项，Core/phone各7项：面板可见、版本修订稳定ID、重复消费/重复feed、同额独立来源、无关行保留、改卡保护与级联、明确减卡/重分类、模型失败/非法金额、ACK/提交/删除故障回滚和重试。
- 双独立 SQLite 连接原并发测试增加真实账本断言：两版本、两路由均只保留2卡/2账本行；每个版本两个消费者均先完成提取，写锁失败方显式观测 SQLITE_BUSY 后收敛，重试不再提取；行ID跨版本稳定。
- `flutter test --no-pub test/data/personal_data_hub/capture_finance_lifecycle_test.dart test/data/memory_v3/services/record_organizer_service_test.dart --reporter expanded`：**32/32 通过**（新增14项复跑 + Organizer相邻18项）。合计75个不重复测试通过。
- 相关3个生产文件和2个测试文件 `dart analyze`：**No issues found**；`git diff --check`通过。
- 初轮2项新测试把“多卡同时改变分类并减卡”误期望为可直接匹配；真实逻辑正确触发既有身份不明确保护。改为先明确减卡、再单卡重分类，保留PR11保护，最终全部通过。
- 首次 analyze 遇宿主 Dart perf 目录 errno1920；仅分析子进程 LOCALAPPDATA 暂设独立 Temp，finally 恢复后通过。依赖锁文件未变；pub/test自动改写的三个 Windows 插件生成文件只有换行差异，已按 HEAD 与Git过滤规则恢复，无生成文件交付。

## 有限边界与集成提醒

- 这是 W7 渐进边界下的现手机本地账本视图桥，**不代表 Core ledger 领域权威、收据迁移或跨设备账本迁移完成**。未改领域路由、授权 issuer、Core/MCP/main、schema61/62或生成模型。
- 本包适用于新生成和后续修订的 capture 产出；没有重放已消费未修订的旧 capture。旧通用账本行缺少明确 capture 来源标识时不猜测归属，不自动回填/认领/删除。
- 用户改过卡片的内容仍遵守PR11保护；单独编辑派生账本不改变其来源所有权。后续未受保护的来源修订会重建该派生行内容，来源删除清理该行。
- 全部证据是合成自动层；未做手机实际面板视觉或真实模型验收。
- 本工作包已获隔离提交授权；提交时仅本次进程临时 `SKIP_PROJECT_STATE=1` 并 finally 恢复，worker不改全局DEVLOG/I_PROJECT_STATE，由主窗整合时统一更新。
