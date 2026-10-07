# W4 快速捕获返修交接

基线 `v3-lab@8dde12b3`，在前候选 `f324e240` 上完成真实适配器返修。仅源码与合成数据验证；没有生产配置、真实 LLM、Core 服务、原库或手机安装操作。

## 实现

- `quick_capture_domain_adapter.dart` 实际调用通用 DomainStore；发送动作与本机授权证据在同一 SQLite 事务。证据含 capture/op/action、绑定、时间、正文 SHA256，不复制正文。相同 ID/相同文本重试不再次入队；编辑沿用 ID。
- `user_direct`、`source=phone_quick`。默认 phone 路由只在本机保存并显示“尚未启用同步”。core/shadow 没有 owner 注入的可信 issuer 时拒绝，不能把随机 UI 引用当 Core 授权。issuer 接收动作证据，需与 Core 验证器真实绑定；这里不新造密钥或线上授权协议。
- CaptureConsumer 使用真实 RecordOrganizerServiceV3.reconcileCapture，支持 phone 本机与 core 离线待发记录；任务、日程、计划留给 planner，生活卡保留结构字段。input digest 与同一来源 ledger 连接本机结果和 Core 收录：同文本只 ack 原产出，旧远端正文不回退较新的本机卡；本机删除需正向墓碑，保留用户改卡并显示问题。
- `QuickCaptureOrganizerAdapter` 使用真实 RecordOrganizerAgentV3；client/modelConfig 由已有“记忆抽取”配置注入。没有模型时保持待处理，不虚构 done。
- 页面位于 `ui/quick_capture/widgets`，在 screen 创建 `view_models/QuickCaptureViewModel`，异步使用 Command/Result。录音校准后编辑，显式发送/取消，持久化后反馈；双处理者状态、产出入口、问题与最近三条可见。恢复传入原 draft ID；发送失败保留草稿。
- `LocalQuickCaptureSpeech` 使用 AudioRecorder + StreamingTranscriber + Whisper 全段校准，只有本机模型就绪才录音；没有模型/权限可用键盘。音频只在内存，限定五分钟；关闭与退到后台停止录音；Android 等解锁后开始，不切云、不下载模型。
- Android 独立 QuickCaptureActivity 继承 MainActivity，单独 affinity、排除最近任务；launcher alias“记一下”、Quick Settings tile；tile 锁屏先解锁。cold initial route `/quick-capture`，warm channel 带去重 action ID。跳过开场视频；锁屏取消与 destroy 释放等待结果。

## 主窗接线

1. 在 main 检查 native initial route `/quick-capture`，直接构造捕获页，绕开陪伴首页启动流程；普通 quick_note 长按也改到新路由。不得继续走旧输入 sheet/MemexRouter。
2. store 使用 hub 已配置 captures store；未配置时用持久本机 installation ID 的本机 DomainBinding 构造 DomainStore，不调用 configureRoute。由主窗统一落 DI/owner 配置。fallback coreInstanceId 与实际 Core 不同的迁移需显式搬运来源 ledger，不能通过换 binding 隐式认领旧记录。
3. `QuickCaptureOrganizerAdapter(client:, modelConfig:).extract` 注入 `CaptureConsumer(db:, store:, organizer:RecordOrganizerServiceV3(db), extract:, decodeText:(d)=>d['text'] as String, inputVersion:(r)=>r['field_meta']?['text']?['rev'] as int?)`。
4. `adapter=QuickCaptureDomainAdapter(store:, consumer:, issueAuthorization:可信issuer或null)`；`service=QuickCaptureService(submit:adapter.submit)`；`QuickCapturePage(service:, speech:LocalQuickCaptureSpeech(), recent:adapter.recent, onClose:, onOpenOutput:)`。onOpenOutput 接 processor/id，由宿主导航到卡或规划。
5. 持久化成功后由宿主调度 consumer.consume 和同步，再刷新近期结果；模型失败不得否认原文已本机保存。默认不启动模型/同步循环。
6. 全局注册一次 `QuickCaptureLaunchBridge.start(openCapture)` 处理 warm；cold initialRoute 已开页，不重复 push。普通页关闭 pop；独立原生 task 调 bridge.close() 返回原应用。

共享 DomainStore 与 domain_row_storage 从主窗复制只用于组合验证，不在 worker 提交；主窗已授权本 worker 唯一修改 CaptureConsumer。其余 main/DI/router/shell/FloatingRecordBall/Organizer 未改。

## 实际验证

- Flutter：W4 UI/语音降级/启动桥 6 项、真实磁盘 SQLite adapter 8 项、相邻 capture_lifecycle 19 项，共 **33/33** 通过；刷新主窗逐行存储候选后再次通过。验证重开恢复、重复发送、同卡改版、Core 离线处理、双处理者分工、授权缺失拒绝、故障回滚、正向本机删除、用户改卡保护及旧远端不回退。
- 相关 `dart analyze`：**No issues found / exit 0**；格式化与 diff whitespace 检查通过。SDK perf_witness 的原 LOCALAPPDATA 路径有 OS1920，分析子进程临时使用独立 TEMP 路径并 finally 恢复，未改全局配置。
- critical fixes：**3/3**。使用本机缓存 Gradle 的 `:app:compileHereIAmV3DebugKotlin --offline` 最终 **exit 1**：现有 integration_test 依赖 `androidx.test:runner:1.2+` 无离线版本列表；未升级或绕开依赖。原生编译仍须 CI 确认，不能报告 Android 已编译通过。

## 接受范围与后续

- 本包生活事实到 Organizer/Memory V3 卡的路径已实现；现有 reconcileCapture 明确不调用 finance bridge。收支/经期/睡眠的 Core intent、领域权威与账本直入属于 W7 后续逐域迁移。本候选不称“已入账”。
- 三星侧键列表是否显示 alias、冷启动两秒、真实录音/VAD、锁屏解锁/取消、warm 返回原应用和布局手感仍需设备 Gate；没有借合成测试关闭。
- worker 提交仅自身源码/测试与此 handoff。允许该次 `SKIP_PROJECT_STATE=1`，提交命令 finally 恢复；主窗负责全局 DEVLOG/项目当前态与最终接线验证。无 push/PR/merge。
