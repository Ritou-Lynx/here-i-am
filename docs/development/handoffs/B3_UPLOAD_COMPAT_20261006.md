# B3 / PR10 手机单上传器兼容 — 2026-10-06

## 基线和拥有范围

- 分支 `codex/core-transcript-compat-20261006`；继承已交付 Core commit `736875630f4ac682571c28adc4e0d6397bec917e`。
- 编译依赖由 schema worker 提供原提交 `281bcce7510f69771844b3b201d383916d4c93dc`，经主控授权 cherry-pick 到本分支为 `65b02d3a`。本上传器提交不包含 schema、生成文件或原 worker handoff；主控已有该依赖时只需选择性集成本提交。
- B3 只读参考源码 `3a9336b122b2fda22ff65ed32d9cee263e8fc2da`。未读取真实 `.state`、token、数据库或正文。
- 自身变更仅 PersonaChatService、CoreSyncClient/Protocol/Engine、对应合成测试和本 handoff。CoreSyncRuntimeService 的 PR12 `PersonalDataHub` 调用及现有单次 `_activeSync` 协调完整保留，无修改。没有改 main/DI/notes/finance/Core/MCP/全局状态。

## 路由与队列语义

- 每次 sync 先修复既有 PR10 sender 表达，再独立发送 user，随后查询 capability，最后只选一条 companion 路径并继续 feed。用户批次和 companion 批次独立，未经授权的 companion 不占用 user 的批次额度。
- `legacy_b3`：仅 enabled + 合法 character/cutoff 才按授权范围补本设备纯文字 backlog，并调用 transcripts。兼容现役 B3 不带 `companion_upload_mode` 的 enabled 响应。
- `pr10`：capability 只说明路由，不表示授权；仍要求既有本机 `phone_companion_outbox.<device>` 的 owner 配置，再由 Core 独立验证服务器 grant，使用普通 messages。旧 legacy enabled 不写入或开启 PR10 owner 配置。
- `disabled`、未知模式、缺能力（403/404）：companion 队列保留，user/feed 继续。companion POST 403/404 也保留该队列并继续 feed；401、协议/不可变冲突和传输错误保留队列并按原错误契约上报。不在某一路失败后回退另一 companion 入口。
- 新 companion 仍受本机 owner 入队开关控制，且只对无附注的非空 chat 文字入队；legacy 无本机 PR10 开关的普通聊天，在后续有效 B3 capability 下通过 bounded backlog 入队。不会从 legacy capability 自动启用 PR10 开关。
- B3 的持久 sender、共享 `outbox.max_sequence.<device>`、`companion.enqueued.<sync_id>` marker 原样兼容。backlog 每次最多新增100条，按本机来源/角色/日期/纯文字过滤，并排除已有 serverSequence、marker 或待发队列的消息。
- 既有 PR10 的 schema62 默认 sender=user，但原 PR10 实际发送时从 chat.isFromCharacter 推断 companion：发送前事务仅把匹配本机 provenance 的此类旧行补成 sender=companion，并补 B3 marker。不改变 sync_id、origin_sequence、content、created_at_ms、asset refs；已具备 B3 sender 的行不改。来源不一致拒绝修复，不能错误地作为 user 发送。**schema62 迁移本身仍逐字保留 B3 语义**。
- accepted/duplicate 后删 outbox 与保留 companion marker 在同事务完成；响应出现未提交 ID 或重复 ID 时先拒绝整份回执，不错误清其他待发消息。跨模式重试仍用队列中同一不可变载荷。
- feed 仅归档 Core 的 serverSequence/毫秒时间：本机已存在行保持原 ID/正文/已有时间与序号，首次缺字段才补齐；导入的新行保留 provenance/serverSequence，不产生 outbox 或回复。

## 有限验证结果

- 首轮 `flutter test --no-pub` 对 `core_sync_transcript_test.dart`、`core_sync_engine_test.dart`、`core_sync_protocol_test.dart`、`core_sync_client_test.dart`、`persona_chat_service_test.dart`：**51/51 pass**，包含现有真实临时 Core HTTP round-trip 测试。
- 新增模式/旧 PR10 sender/授权撤销/归档/回执专项后，`core_sync_transcript_test.dart`：**32/32 pass**。其中新增8项，合计 **59 个不同测试通过**；没有把重跑当额外覆盖。
- 已覆盖：队列/marker 失败的原子回滚；user+companion 混排及小批次不饥饿；旧能力缺失/未知模式；授权撤销；丢响应后同载荷 duplicate；legacy→PR10→legacy 不重造 ID/序号、无双发；原 PR10 sender 修复；legacy 不生成 PR10 授权；marker 无 feed echo 仍防重排；feed 同源导入不回传；serverSequence 归档；异常回执不清队列。
- 专项 `dart analyze` 涉及四个变更文件、未改的 runtime_service 和新增测试：**No issues found**。`git diff --check` 通过。保留 Persona 文件原有 CRLF，不提交整文件格式变化。
- 首次分析器在用户 Dart/perf 临时目录 shutdown 报文件系统1920；仅该分析子进程的 LOCALAPPDATA 改到本工作包临时目录后复核通过，没有修改系统环境或删用户文件。本地离线 pub get 在依赖解析完成后遇到 active_roots 路径错误；实际 --no-pub 测试和分析使用已生成解析并成功，无依赖版本/lock 改动。
- 没有 App 构建、安装、ADB、生产部署、真实设备/数据验证。HTTP自动测试与Store专项不等于手机真人 Gate。

## 集成与开放项

- 主控按 schema62 依赖 → 本上传器 commit 的顺序集成，并保留各自责任范围；全局 DEVLOG / I_PROJECT_STATE 和 i closeout 由主控统一完成。
- 真实过渡 Core 仍须显式 legacy_b3，保全原手机 deviceUUID、共享 sequence counter、队列与 marker、外置 grant 和72条 replay绑定。PR10切换须独立 owner grant，旧路径排空/关闭后再切，不以能力存在替代授权。
- 手机实际升级后能力查询、旧队列补交、断线/恢复、无重复气泡和 serverSequence 归档仍需固定构建候选的设备证据。
- 本提交按主控明确授权只使用该次 `SKIP_PROJECT_STATE=1` 例外并 finally 恢复原环境；未 push、未建 PR、未合主线。
