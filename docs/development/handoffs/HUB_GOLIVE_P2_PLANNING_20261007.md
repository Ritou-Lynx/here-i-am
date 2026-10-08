# Hub go-live P2：手机今天 / 本周页审计（2026-10-07）

## 结论

W5 的页面、ViewModel、模型与专项逻辑已覆盖本工作包要求。本轮没有发现需要修改 planning 生产源码的独立缺口；新增一个 widget 回归，补齐“点不做了 → 本地立即显示放弃/待同步 → Core 冲突后恢复权威状态并提示拍板”的完整交互证据。

本结论只针对 `lib/ui/planning/**`、`planning_models.dart` 及相应专项测试。规划页面能否在正式 App 中读写 Core，仍依赖其他工作包提供的领域凭据、`hub.attach`、签名授权 issuer 与 Core host 装配，不能由本页测试代替。

## W5 核对矩阵

| W5 要求 | 当前实现 | 专项证据 |
|---|---|---|
| 订阅三类规划本地副本并自动刷新 | `PlanningService` 读取 `plan_days/plan_weeks/plan_items`，`PlanningViewModel` 订阅 changes，并串行合并刷新 | 新 edition 自动更新且保留主线筛选；流中断保留旧副本，后续事件恢复 |
| 今日队列保持 `plan_days` 顺序 | ViewModel 按六个 queue 的稳定 ID 顺序取事项，不在手机重排 | widget 比较队列中 b、a 的屏幕顺序；服务测试断言 deep 队列为 `[b,a]` |
| 今日单元数据 | 页面显示 edition、generated_at、change_summary、pending_decisions、capacity、noted、lights_out_at | 今日页 widget 场景通过 |
| 本周进度 | 页面显示 expected/actual capacity、主线 minimum/target/maximum、completed、remaining_scheduled、状态、进度条、debt 与逐日容量 | 本周 widget 场景通过；未知数量明确显示“未提供” |
| 完成 / 不做了 | `PlanningStatusAction` 精确映射为 `完成` / `放弃`；页面只在 status writer 可用且无未决操作时开放按钮 | 完成离线→待同步→接受通过；本轮新增放弃→待同步→冲突回退通过 |
| 被拒与冲突提示 | operation 状态区分 rejected、needs_resolution、expired，并按 reason 给出用户可读提示；恢复 Core 权威状态 | rejected 与 needs_resolution widget 场景通过，按钮阻止重复提交 |
| 电脑离线 | 使用本地副本，并显示“今日单生成于 X；新记的事等电脑上线后安排” | 离线 widget 场景通过 |
| `remind_at` 本地提醒 | `PlanningReminders` 派生稳定 reminder ID，登记系统消息与闹钟；重排、终态、删除、凭据轮换均收敛 | reminder 专项覆盖创建、幂等、改期、取消、失败恢复、过期及绑定轮换 |
| 不在手机排程或重排 | 页面没有输入框、拖拽列表或计划编辑入口，只允许状态动作 | widget 明确断言无 TextField / ReorderableListView |

## 本轮修改

- `test/ui/planning/planning_screen_test.dart`：新增“不做了”离线 optimistic 状态与 `needs_resolution` 权威回退场景。
- 未修改 `lib/ui/planning/**` 或 `planning_models.dart`；现有实现已满足该工作包可独立验证的要求。

## 验证

首次依赖准备由本工作包统一执行，App worker 同期未运行 `pub get`。`D:\flutter\bin\flutter.bat pub get` 成功生成 `.dart_tool/package_config.json`，`pubspec.lock` 无 diff。

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/ui/planning/planning_screen_test.dart `
  test/data/personal_data_hub/planning_service_test.dart `
  test/data/personal_data_hub/planning_reminders_test.dart `
  --reporter expanded
```

结果：`28/28` 通过，包含新增 widget 场景。

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/data/services/sync/core_sync_transcript_test.dart `
  --reporter expanded
```

结果：`32/32` 通过。覆盖 companion transcript 的 legacy/PR10/disabled 路由、丢响应原样重试、队列保留、grant 撤销、feed 失败与 wire contract；这是合成上传器证据，不等于生产 host 已接线。

## 剩余上线源码缺口

- App 工作包已补上独立 grant、按 scope 的 captures/三个 planning 域 `hub.attach`、完整 intent 的 `planningAuthorize` 和撤销守卫，主控最终 65 项组合测试包含本 widget 文件。各域默认 route 仍为 phone；正式页面读写 Core 仍需 owner 授予和显式 route 迁移，不能以 attachment 替代。
- P1 深审计已确认 Core 正常 host 尚缺 personal domain hooks、principal 与可信 authorization verifier 装配。P2 的状态按钮必须使用 App worker 提供、Core 能精确校验的签名授权引用，不能以本测试的合成 callback 作为上线依据。
- 未 build、部署、安装或改生产配置；Windows CI 构建和真机交互仍未验证。
