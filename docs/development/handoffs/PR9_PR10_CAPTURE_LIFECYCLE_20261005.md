# PR9/PR10 capture 生命周期返修交接

- 基线：`21a813ef717ad4698dadcb31cdc39a18611b87e9`；工作分支 `codex/pr9-pr10-review-fixes-20261005`。
- 范围：已接受 `claude_web` capture → Memory V3 生活卡。没有改 phone_quick、DomainStore、schema、生成文件、finance 桥接、旧自动对话记录流水线或手机/服务部署。
- 当前状态：worker 已完成实现、专项测试源、格式化及限定 diff whitespace 检查。**尚未主窗验证**；以下不是测试通过声明。由主窗串行执行 Flutter/分析并记录最终候选证据。

## 实现

- `capture_consumer.dart`：每个 Core/capture 一个 `capture_lifecycle` ledger，仅当前 input version、拥有的卡 ID、当前生成摘要和保护原因；不保存原话或每个旧版本内容。字段版本未变不重新提取；整条 revision 单独改变不重跑；提取期间同 text 版本的新 revision 使用提交时 revision ack。
- `capture_card_reconciler.dart`：Organizer 的 capture 专用 part，通过实际 AppDatabase 事务更新原卡 ID、删除过时输出、新增可明确识别的新输出，并严格同步 FTS/清理过时 embedding。没有借普通 `persist` 对其他来源去重，也没有假冒用户 actor。
- 提取在事务外；事务内再次确认 capture 当前版本、来源、墓碑、路由、可读 cursor，及另一设备刚完成的相同版本 disposition。生成投影/源/审计、ledger、保护提示和 ack 共同提交或回滚。
- 同源单卡保留原 ID，允许合法类型/分类改变；多卡先唯一内容匹配，再唯一标题/类型/分类匹配。完全相同内容且新旧数量相同视为可交换组，保留所有旧 ID。顺序不作为身份。
- 只有一侧未匹配时可明确纯增/纯减；两侧都有未匹配输出则 `output_identity_ambiguous`，不猜旧卡对应关系，不整套复制。已有明确匹配仍可安全更新。
- 所有受保护卡整卡保留：`user_corrections`、structured fields / relation `userCorrected`，或与当前生成投影摘要不符。最后一种只说“生成后另有变动”，不声称是用户修改。已被用户删除的输出留下 ID-only 缺失标记，不自动复活。
- 只凭明确 tombstone 或匹配、已验证的删除收据处理源删除；`hidden_ids` 单独存在、merge 隐藏、权限丢失、cache/snapshot 缺项都不代表删除。已验证 GET `target_state=deleted` 的明确 primary target（包括原操作是 ack）也可提供删除证明；多目标 semantic duplicate 不猜目标。
- tomb 后不产生 ack；未改卡删除，保护卡保留，退休 ledger 去掉生成摘要，仅保存输出 ID/原因。W4 可直接调用 `pendingIssues()`，得到 capture/card ID、稳定 reason 和简短中文 message。
- 旧 `capture_consumed.<core>.<id>.<version>` 迁移为单一映射并删除旧 receipt 键；只保留 ID 和最新输入版本，不复制 payload 原话。旧记录没有可信生成基线，保守保留旧卡并提示待确认，不把今天的投影臆断为原生成快照。不能自动清理旧版本重复卡。
- `updateCard` 的 `user_via_agent` 操作审计新增 `_authorization_ref`；没有改变既有用户 actor 判断规则。
- 版本更新复用原实体连接时不重复递增实体 mention 计数；本次没有承担独立实体投影退休/共享实体删除。

## 明确限制

- 自动审批拒绝了“清空保留用户修改卡的 source.rawInput”，理由是原任务只授权删除未改生成卡并保留修改卡，不包含可能不可恢复地清空保留卡来源。已遵守拒绝，未改道执行/重试。
- 因此，保留用户改卡时，其既有来源原话也仍保留；**不声称该来源正文已清理**。源已删除的提示与退休 ledger 均可查询。需要清空这些保留卡来源时须另有明确授权。
- 多卡身份歧义/旧无基线卡通过 pending disposition 和本地 issue 表达，暂不提供自动猜测或 W4 解决页面。`phone_quick` 由 W4 后续统一设计。

## 主窗验证入口

```powershell
& D:\flutter\bin\flutter.bat test test/data/personal_data_hub/capture_lifecycle_test.dart test/data/personal_data_hub/app_integration_test.dart
& D:\flutter\bin\dart.bat analyze lib/data/personal_data_hub/capture_consumer.dart lib/data/personal_data_hub/capture_card_reconciler.dart lib/data/memory_v3/services/record_organizer_service.dart test/data/personal_data_hub/capture_lifecycle_test.dart
```

专项覆盖：同 ID 新版本、多卡差异、等价重复卡组、歧义、重复消费、实际 SQLite 关库重开、墓碑/GET 删除、无证明不删、user_direct/user_via_agent 编辑、快照变动保护、extract 竞态（改源/删源/远端完成/改卡）、ack/删除事务故障、旧 ledger 与敏感字段迁移、实体计数稳定。

首次冻结 SHA-256（主窗验证前，后续修复须重新核）：

| 相对路径 | SHA-256 |
|---|---|
| `lib/data/memory_v3/services/record_organizer_service.dart` | `8BBEA41BC3B8BB7B962C6E05FDF512BF7A76FD5154B82A951EF872922D2B25CB` |
| `lib/data/personal_data_hub/capture_consumer.dart` | `DEAA231AEBAD805D6EE236A250F329FA4289555C234945EECA82D2670A18F401` |
| `lib/data/personal_data_hub/capture_card_reconciler.dart` | `C7A519A4B1653076C66EE72150A7D223D36135B2D7C827B8F964D32E7CA860AB` |
| `test/data/personal_data_hub/capture_lifecycle_test.dart` | `A215887D2EE066C7D607105C6B26BF88FA3885F99F532B212A16142E62B7D2D1` |

未 commit / push。全局 DEVLOG、项目状态和最终 i closeout 由主窗统一记录。
