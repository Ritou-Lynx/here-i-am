# D3：47862 旧桥保留与单消费者交接（2026-10-06）

## 基线与范围

- 分支 codex/capture-ledger-20261006；基线 72eef3462330f653b5b9521602b7af821d00793c（PR12 收支桥包）。
- B3 来源 3a9336b1；选择性移植 notes 四文件与连接设置 UI/测试。DI 增加 24 行，main 增加 7 行，没有整文件覆盖现有 hub、quick capture、app lock 或 actor 接线。
- 没有修改 schema、tables、generated、Core/MCP、sync/service、全局 DEVLOG/I_PROJECT_STATE。没有构建、安装、ADB、真实数据库、token 或生产写入；没有 push/PR。

## 当前行为

- 默认 owner 为 legacy；保留旧 i_remember notes feed、secure key claude_web_note_feed_v1、URL/token/cursor 元组、external_note_import receipt ID 与已有 card ID。只在主界面启动、回前台和设置页手动执行有界拉取，不增加后台定时轮询。
- phone_quick 独立正常消费。生产 PersonalDataHubRuntime 先用 allowRemoteWeb:false 处理手机来源；Core claude_web 的增改删（含无正文墓碑与未知旧来源）默认拒绝消费。
- 新旧通道共享 SQLite 中 capture_consumer_ownership.v1 行。短 writer 事务 claim；60 秒 lease、15 秒续租、UUID token 与递增 generation；模型/网络期间不持有数据库写事务。新 owner 只在到期后接管；旧 worker 返回时不得提交卡/回执/新 ACK/游标。
- 卡、回执和 Core 旧回执升级事务均在 writer lock 内验证 fence。已经发出的远端 ACK 无法撤回，依旧协议 note_id + revision 幂等；其返回后的本机 secure cursor 写入仍必须过 fence。测试覆盖 ACK 在途与 lease 被接管。
- 同实例配置修改和切换等完整 import/ACK/cursor 队列；其他数据库实例持有活跃 lease 时明确报 busy，不取消工作、不静默 fallback。主 runtime dispose 会 drain 旧桥，动态 importerFactory 随当前数据库更换；quick-capture engine 不拥有该连接生命周期。
- Legacy 新导入走现 PR11 reconciler，保留用户编辑保护，并可处理显式记录中的 planning 卡；普通聊天没有新自动写入路径。旧 B3 卡没有可信 generated baseline 时保留原卡/原来源并产生 pending，绝不伪造 baseline 覆盖用户卡。
- 新 legacy 投影用独立 captures:legacy-note:<base64url(noteId)> sourceRef，回执持久保存 projection_source_ref，避免与 Core captures:<id> 混用。既有旧 note 来源仍通过原 claude_web_note/sourceRef 查询；不会把相同 ID 当同源证明。

## Gate / adoption 边界

- 没有注册生产 Core Gate verifier，没有用户可点击的切换开关；因此当前仍保留旧桥，不能声称已经迁移或通过 captures 实机 Gate。
- selectCore 需要注入的验证器接受 Gate、完整 binding fingerprint 和 origin/adoption proof；每个已导入 note 必须有显式唯一 note→capture 映射，以及预先准备好的 capture_lifecycle 回执，且 origin proof、旧存活卡 ID 集合、删除状态完全匹配。缺映射/仅 ID 相同/另造卡均 fail closed。
- 本包提供 adoption 准入验证，不生成真实 adoption 回执、不迁移旧 source/finance ownership，也不实施生产回切。后续真实迁移必须先准备被验证的来源、卡和账本关联迁移，再完成 create/revise/delete 实机 Gate。合成 adoption 测试不代表该 Gate。
- 租约保证限定于同一安装的同一 SQLite 数据库（包括独立连接/隔离消费者）；不宣称跨不同数据库或跨设备互斥。过期旧进程返回由 generation/token 拒绝；未执行真实 OS 杀进程或手机后台测试。
- 收支仍属于现手机本地账本面板视图桥，不代表 Core ledger 领域迁移。

## 验证

- 最终组合 Flutter：98/98 通过。末次补齐旧回执升级 fence 后，仅重跑 ownership + lifecycle：28/28 通过。
- 新增/移植测试：
  - test/data/personal_data_hub/capture_consumer_ownership_test.dart（9 项；双 SQLite handle 超时接管、旧模型返回拒绝且 ACK=0、续租、配置等待、缺 Gate/映射拒绝、合成 adoption、用户改卡保护、phone quick 保留、在途 ACK 与游标、真实 runtime dispose/换库）
  - test/data/memory_v3/notes/claude_web_note_feed_test.dart
  - test/ui/settings/web_note_connection_viewmodel_test.dart
  - test/ui/settings/widgets/web_note_connection_page_test.dart
- 组合相邻回归：capture_finance_lifecycle_test.dart、personal_data_hub_runtime_test.dart、capture_consumer_multi_connection_test.dart、capture_lifecycle_test.dart、quick_capture_adapter_test.dart、personal_data_hub_runtime_owner_test.dart，均位于 test/data/personal_data_hub/。
- 相关 Dart 路径分析无问题。main.dart 独立存在 25 条既有诊断（13 warning + 12 info）；将 HEAD 原文临时放在同一 lib 分析上下文逐项比较，类型/文本完全一致，仅插入行导致行号平移，临时文件已删除。没有新增 main 诊断。
- 分析仅在当前进程将 LOCALAPPDATA 指向临时隔离目录并 finally 恢复，以绕开 Windows 性能计数器 errno1920。依赖 lock 未改。
- git diff --check 通过。本隔离包提交使用一次 SKIP_PROJECT_STATE=1 并 finally 恢复；主窗负责全局状态与最终整合。
