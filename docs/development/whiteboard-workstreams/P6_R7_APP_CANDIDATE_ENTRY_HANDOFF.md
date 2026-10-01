# P6 R7 App candidate entry handoff

- 基线：`1b6a2961`；工作树：`p6-r7-app-entry`。本交接只覆盖候选 UI 与 ViewModel，未改启动、真实数据源或生产入口。
- 新增 `P6R7CandidateViewModel`：只保存调用方提供或 host 输出 `task_id` 的精确 task id；创建任务固定为“公开文字验收”和 `Reply exactly: P6_R7_NATIVE_OK`。每次操作生成独立 request id，并由宿主构造精确 target 的可信 authorization；每次回读同时校验固定 id 与候选 scope。
- `persistTaskId` 在 enqueue 返回后执行；若持久化 marker 失败，内存 id 仍保留并禁止第二次 enqueue，同时只保留 status/cancel，不能开始、继续或重试无法在重启后绑定的工作。恢复仅发出 exact-id 的 status 请求，不自动 start/resume/retry。
- 新增候选根页面：根层监听 Flutter 生命周期，仅 `detached` 对注入的 owner 调用 `closeForHostLifecycle()`（best effort）；导航、paused、hidden 和 dispose 不关闭 owner。根页面的状态观察只发 status 读取，dispose 只停止该观察。页面有持续状态子页，以验证根层对象不随导航释放。
- 新增内存 TaskRoomService 和 lifecycle probe 测试。当前环境未发现 `dart` / `flutter` 可执行文件；按工作包约束未运行 Flutter wrapper，待主窗统一验证。
