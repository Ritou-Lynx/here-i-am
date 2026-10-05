# W4 Quick Capture worker handoff

基线 `8dde12b312ad83f7475df8bd99a359f1b2d782d6`。本候选只新增 W4 自有路径，未修改 `main.dart`、`dependencies.dart`、路由、CompanionFirstShell、FloatingRecordBall、PersonalDataHub、DomainStore 或 CaptureConsumer。

## 已实现

- `lib/data/personal_data_hub/quick_capture_models.dart`：草稿、状态、双处理者结果与 pending issues 模型。
- `lib/data/personal_data_hub/quick_capture_service.dart`：构造注入的 UI seam；生成 capture id、拒绝空文本，把提交委托给主窗提供的 W7 outbox/domain adapter。无数据库、聊天、MemexRouter、模型或 token 依赖。
- `lib/ui/quick_capture/quick_capture_controller.dart`：编辑、发送、失败状态控制。
- `lib/ui/quick_capture/quick_capture_page.dart`：可编辑捕获页，显示保存状态、organizer/planner 分开结果及问题提示。
- `test/ui/quick_capture/quick_capture_test.dart`：空文本、文本编辑与双处理者结果、失败可见性测试。

## 主窗接线要求

主窗创建 `QuickCaptureService` 时注入 `QuickCaptureSubmit`：将 `QuickCaptureDraft.captureId/text` 作为 `captures` 的 `phone_quick`、`actor=user_direct` 记录，使用 W7 通用 `DomainStore.enqueue`/同步入口；不得另建 `quick_captures` 表或队列。服务成功后返回 `QuickCaptureResult`，分别填入 organizer/planner 结果；失败或未配置保持待发送/错误提示。接线应由主窗统一处理入口、DI、平台 alias/tile/长按 extra、真实 domain token 与 CaptureConsumer 生命周期。

## 验证与限制

已启动 `dart analyze` 与 Flutter widget test，但当前命令会话未返回可核验输出，不能报告为通过；请主窗在集成后重跑。未实现语音录音/StreamingTranscriber、Android alias/tile/launcher wiring、断网真实同步、真实 organizer/planner 消费和真机 Gate；这些需要共享接线或设备证据。默认生产配置不连接 Core，不发送 token。
