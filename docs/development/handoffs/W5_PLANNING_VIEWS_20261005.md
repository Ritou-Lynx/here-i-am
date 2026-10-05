# W5 今日 / 本周规划视图交接（2026-10-05）

## 范围与基线

- 分支：`codex/w5-planning-views-20261005`；精确基线：`8dde12b312ad83f7475df8bd99a359f1b2d782d6`。
- 只新增 `lib/ui/planning/`、三个 `planning_*.dart` 数据适配文件、对应测试和本交接；未改旧 Schedule、路由、依赖、数据库结构、DomainStore 或全局项目状态。
- 实现前核对仓库 AGENTS、总规划 1–4 / W5 / W7、ADR 8.2–8.3、I_CORE_DOMAIN_CONTRACT 与规划字段契约。主窗负责整合接线和全局状态；本工作包不启用线上连接。

## 实现与 API

- `PlanningService` 是现有 W7 `DomainStore` 的读取 / 状态意图适配层，不新建规划权威或 outbox。分别读取 `plan_days`、`plan_weeks`、`plan_items` 的有效副本、领域错误和共享乐观覆盖。
- `PlanningScreen(service:, reminders:, clock:)` 在 screen 内创建 / 释放 `PlanningViewModel`；异步操作用 `Command` / `Result`。注入 `PlanningReader` 便于测试，不引用 MemexRouter 或旧自动 capture。
- 今日保留 Core 给出的队列顺序、日期、版本、生成时间、变更、待拍板、容量和关灯；缺项显式显示。无当天版本时显示最近一版及真实日期，不伪装为今日新计划。新记录未入队单列展示。
- 本周显示容量预期 / 实际、配额 min / target / max / 完成 / 已排 / 进度、欠账及滚动次数、每日容量。未知容量保持“未提供”。“未归类”保持原值，并可筛选；刷新保留当前筛选。
- 手机只提供“完成”“不做了”；模型和 UI 不提供结构编辑。写入 `kind=status`、`actor=user_direct`、`patch.status=完成|放弃`，绑定当前 canonical revision。未配置、phone / shadow、无初次 cursor、待重同步、隐藏 / 删除 / 终态 / 已替代或已有未解决操作时失败关闭。
- pending / submitting / accepted / duplicate / rejected / expired / needs_resolution 在页面区分；冲突或拒绝不展示成成功。未解决操作仍按 W7 队列语义阻止重复提交，需桌面处理。
- 数据库提交通知与外部连接事件驱动刷新；并发刷新合并，流错误保留最后副本，后续事件恢复。电脑离线显示生成时间及“新记的事等电脑上线后安排”。

## 主窗必须接线

1. 由 owner 已授权的 `PersonalDataHub` 取 `storeFor(domain)`，构造 `PlanningService(stores: {...})`。仅传规划领域，使用同一 owner 的 Core / installation 和原数据库；构造器拒绝跨 owner 组合。默认 `PlanningService()` 不写入、不上传。
2. 注入 `syncDomain: hub.syncOnce`，以及真实 `connection` 读取器和连接事件 `changes`。W7 提交必须发 `kv_store` Drift TableUpdate，回滚不得发；此依赖已与 W7-storage 主窗确认。各领域同步失败独立处理，不阻塞其他领域恢复。
3. `authorize: (db, PlanningUiAuthorization action) async { ... }` 必须是可信交互证据适配器：在传入的同一个数据库事务内持久化证据，并使 Core 验证器能够解析其 `authorization_ref`。`action.toJson()` 包含 op_id、绑定身份 / 代次 / 安装、目标、status patch、UI 来源和时间。服务先生成 op_id，再调用适配器；失败则证据与 outbox 一同回滚。**UUID 本身不是授权，缺适配器时状态按钮禁用；W5 不默认接受自报引用。** 测试使用合成持久化适配器，真实证据传输 / Core 验证器仍需共享基础设施接线。
4. 按 owner 生命周期创建并复用 `PlanningReminders(db:, alarms: const CheckinPlanningAlarmScheduler(), binding:)`。页面会对每次有效副本刷新执行 reconcile；页面外的领域同步、应用重启 / 前台恢复也须由 host 使用最新 `service.read(now)` 的有效 items 调用 `reconcile`，领域失效时传空集合清理旧提醒。不要只依赖页面处于打开状态。
5. 将 screen 接入授权的手机入口；不替换旧 Schedule。共享 main / dependencies / shell / router 由主窗改动。

## 本机提醒边界

- 从当前可见非终态条目的未来 `remind_at` 派生，复用现有 `systemMessageQueue` 和 Checkin 提醒回调。单独 kv metadata 只保存注册签名 / 取消重试标记，不保存第二份规划。
- installation + 领域绑定 + item 的稳定命名空间支持重复刷新幂等、同 ID 改期、完成 / 放弃 / 删除取消、凭据轮换清理；已消费提醒不因重复刷新再投递，重启可恢复 pending 注册。
- 取消失败先删除旧可投递正文，保留重试标记；操作后来被拒绝恢复原状态时可重新注册。失败的 OS 取消仍可能唤醒既有通用 Checkin 回调，不能声称绝无后台唤醒。
- 现有 Checkin 调度封装会内部捕获部分原生失败，因此调用返回不能证明权限或实际送达。精确闹钟权限、重启后系统恢复、真实手机提醒与人格投递尚未验证。

## 验证

- 合成 SQLite service 集成 11 项 + 提醒 7 项 + widget 9 项，共 **27 / 27 通过**。覆盖真实 DomainStore 队列和事务证据、拒绝 / 冲突回执、领域隔离和配置门控、删除 / 重同步、提交通知、ISO 周边界、提醒取消重排 / 重启 / 重试 / 绑定轮换、今日 / 周展示、未归类、离线与生成时间、流恢复、状态反馈、320 px 无溢出和无结构编辑控件。
- 实跑：`D:\flutter\bin\flutter.bat test --no-pub test/data/personal_data_hub/planning_service_test.dart test/data/personal_data_hub/planning_reminders_test.dart test/ui/planning/planning_screen_test.dart`，exit 0。
- 相关三个数据文件、`lib/ui/planning` 与四个测试路径 `dart analyze`：**No issues found**，exit 0。为隔离宿主 Dart perf 文件问题，仅在分析进程设 `LOCALAPPDATA=.migration-validation/w5-localappdata`；未改全局环境。
- `dart format` 已执行；提交前暂存后的 `git diff --cached --check` 验证。测试后仅调整 lint 所需括号及注释，无行为改动。
- 环境说明：新工区首次 `flutter pub get --offline` 已生成依赖解析，但最后写 Pub Cache active_roots 报 errno 2，命令 exit 1；没有 pubspec / lock 变更，随后上述 `--no-pub` 测试完整通过。初次 analyze 因宿主 perf 清理 errno 1920 失败，隔离 LOCALAPPDATA 后成功；不把两次环境失败记为通过。
- 未 build、装机、连接真实 Core、调用模型、变更线上配置或真实数据。测试通过不等于设备 / 权限 / Core 真实验收。

## 提交

按工作包常设授权仅提交自身路径。本次隔离提交可使用已有 `SKIP_PROJECT_STATE=1` 例外，命令结束恢复原环境变量；不修改 hook。未 push / PR / merge。最终 commit 由 worker 回传，主窗复核 diff 后整合。
