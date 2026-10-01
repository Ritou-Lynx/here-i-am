# P6 R7 普通聊天候选入口接线交接

日期：2026-09-14。基线：`v3-lab@389aa735ca6003f3141d12f16c734c9a64441c47`，主目录已有大量其他 dirty；本工作包仅新增下列五个源码/测试文件与本文，未提交。

## 实现与边界

- 新入口 `lib/p6_r7_product_main.dart` 只接受原有严格 owned-host boot；直接复用候选 Startup、RecoveryStart、只读 inspection、OwnedHost、Store、TaskBinding 和 WitnessFinalizer。默认 main 未引用新入口，未修改旧 candidate/native/ACL/schema。
- 首个 Gate 仍是既有固定公开标题/目标、原 scope hash、单任务与单 successor。普通用户原话经共享桌面发送入口→真实 coordinator→原 authorization factory→动态队列工具；没有任务按钮、自动入队或伪造 title/goal。错误目标由 Store.persistTaskId 的现有严格检查拒绝，真实队列记录保留，session sticky freeze。
- 可信 Store.open 后只构造 `TaskRoomService(db: ...)`；恢复任务先完成 Store exact-row 校验/持久绑定、首代 witness 绑定（successor 不补首代 ACK）和本次 Node 注册，再调用 restoreInterruptedTaskRoomsOnce；不自动启动执行。Node 注册使用本次真实 task ID、scope hash 和数据库 goal，严格检查 schema/ID/scope/goal SHA。
- 普通 runtime 经同一 sealed Dio 到 `/p6/r7/product/conversation`，保持标准 runtime prefix。仅注入 queue tool 与独立聊天 writer；关系/搜索/白板不注入，in-memory provider binding 保证 successor 不自动恢复旧普通 provider thread。
- root 使用真实 P6R7ProductChatSurface/DesktopPersonaChatView 和桌面 tokens。didRequestAppExit await close，unknown 返回 cancel、保留窗口且封新输入；detached 仅 best effort。Startup 在 prepare 期间收到退出时也可经 preparedClose 关闭已准备会话，避免根组件尚未挂载时遗漏 Store/VM。
- close 顺序为同步保留 VM/session 两个 quiesce future → POST conversation close `{}` 并验证 exact 六字段、closed、同 conversation、reason null、shared_gateway_stopped false → join VM → join queue calls → lifecycle owner → owned host → execution tails/Store/Dio → 旧 finalizer 的首代 app_closed。finalizer 读 Store 实际持久 task ID，不能把失败的临时 binding ID 当作 witness 绑定。successor 不发送首代 ACK。

## 实际本地验证

- `dart analyze` 仅本文五个新源码/测试路径：exit 0，No issues found。
- `flutter test test/data/workbench_ai/product/p6_r7_product_task_binding_test.dart --no-pub --reporter expanded`：8/8。覆盖 profile/scope/foreign UUID、第二入队、恢复绑定顺序、持久校验或注册失败保留原记录并冻结、固定 goal 拒绝、注册回执以及 conversation close 回执严格验证。
- `flutter test test/ui/p6_r7_product/p6_r7_product_app_test.dart --no-pub --reporter expanded`：1/1。验证根组件等待提示、unknown cancel/窗口与 DB 保留、关闭重试严格顺序。该组件测试使用静态合成聊天流、内存 DB 和禁止调用的 Runtime；真实消息流/聊天持久化由已有独立专项测试覆盖。最初使用真实 Drift watch 流时，Flutter fake-clock 下后续 DB.close 挂起，已中断相应测试并改用静态流；不把挂起记为产品失败或验收成功。
- SDK：`D:\flutter\bin\cache\dart-sdk\bin\dart.exe`，Flutter 工具 snapshot；测试仅为 SDK cache lock 使用已审本地执行权限。未构建、启动 App/Node/provider、读取认证/真实 DB、操作现役服务、提交或派生 worker。

## SHA-256

| 文件 | SHA-256 |
|---|---|
| `lib/p6_r7_product_main.dart` | `cc1e365b24ead3f7a58ea1dce32e808ef6caf987183675189f42e982a6da8d5c` |
| `lib/data/workbench_ai/product/p6_r7_product_task_binding.dart` | `96ec7076e4af03c0d02e35b73157b585d7a038c84f7f52bd2d30b9e845f8412e` |
| `lib/ui/p6_r7_product/widgets/p6_r7_product_app.dart` | `be978b44357bf23d45769417c679694e04f31a76d41bf72be025ff265568f156` |
| `test/data/workbench_ai/product/p6_r7_product_task_binding_test.dart` | `077e4be0b1bff306e0430b04ddf871738330942d0e6f0f0d04957a57fcda0a79` |
| `test/ui/p6_r7_product/p6_r7_product_app_test.dart` | `e20468884233c8529147bb7a68eae6a710011f255bcda5a8cac8b170312b32fa` |

## 主控接续

额外按主控指示导出固定 Node schema：`tmp/p6-r7-review/product-app-schema-export/export_test.dart` 直接读取 `WorkbenchTaskQueueToolHost.dynamicToolDefinition` 并 jsonEncode，未手抄字段或实例化资源。实际 1/1 通过。输出 `queue-tool-definition.json` 865 字节，SHA-256 `1d6883d52d165afb4923877571bc66cbcf9e7df8c22cbc972143fba613f797de`；源 task_queue_tool_host SHA-256 `3b471e14b176366e3685935b765a2f68ecb7c17bf9d2d366bb9ad33f60c34ba8`。真实 runtime tool getter 直接返回此对象，coordinator 在 only-queue composition 下把它作为唯一 dynamicTools 元素；Node 须保留整个 JSON（含 description），运行时工具列表为 `[definition]`。

`suggested-first-turn.txt` 给出建议真实原话；`authorization-check.json` 记录原 factory 实际仅允许 enqueue、无 target/conflict，并包含原固定 title/goal。该原话没有写进 UI。应在真实输入中保留固定目标句内句号并要求原样字段；模型仍可能填错，届时 Store 严格拒绝而非自动纠正。避免附加“不要开始/不启动”等词使原 factory 同时否决 enqueue。

主控需核对 Node product/task 与 conversation HTTP 合同、独立复核新增入口、生成新 source closure/exe/bundle/launch pins 并完成串行构建。此次仅提供源码与合成测试，不能继承旧 App02/App23 binary 通过，不能声称普通入口真实模型/关闭/恢复 Gate 或任意生产目标已启用。全局 DEVLOG、项目状态和 i closeout 由主控统一收口。
