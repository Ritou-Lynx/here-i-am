# W7-0 手机基础候选交接（2026-10-05）

状态：worker 源码候选已冻结，等待主窗独立审阅和整合。本包是可验证的前置框架及现有入口最小接线；不表示 W7 逐领域迁移、W4/W5 页面或真机 Gate 已完成。

- 基线：`6895e86b25f6bfdd9a53e1a0155a2893da0158f3`；分支：`codex/w7-phone-foundation-20261005`。
- 只使用自建合成数据。没有访问真实库、手机、发布服务，没有 commit/push、索引操作、Drift schema 修改或生成文件修改。
- 默认 `phone`；没有自动注册真实领域、授权令牌、切换业务权威、恢复 conversation capture 或旧 PKM 流水线。
- 精确文件原始字节 SHA-256 见同名 JSON。该清单不包括主窗独立拥有的 `tools/personal_data_hub/` Node 夹具与 `test/integration/personal_data_hub/client_core_interop.dart` 显式互通测试，也不把原始字节 hash 冒充 Git 规范化 blob hash。

## 已实现与接线

1. `lib/data/personal_data_hub/`：持久 outbox、每域副本和 cursor、pending overlay、needs_resolution/reminders、phone/shadow/core 路由、独立域 bearer 的 HTTP adapter、Core 绑定变化后的副本隔离、过期与墓碑清正文。复用真实 AppDatabase 的 `kv_store` 及事务，无新 schema。op_id 和首次发送的完整请求持久化；未知结果先查 op，再用同一请求重试。相邻操作和 merge 多目标维持因果依赖。
2. 回执对 accepted 操作核对 op/principal/Core/domain/policy/目标集合、正安全整数 revision/sequence 及格式容量；semantic_duplicate/no_change/already_purged 可以合法引用原接受回执，分别验证语义绑定。回执不是 feed cursor。分页 snapshot 校验完整绑定、页摘要、总摘要、数量/大小、固定切点与 token；在一个事务替换副本+cursor，保留 pending。旧响应以 cursor/replica_version 防回退；提交前不 ack。
3. 客户端 canonical JSON 与冻结 Core 的 ECMAScript 数字表达对齐（1e-6/1e21 阈值、负零、整值浮点、数值 key 顺序），拒绝非有限数；所有 wire intent 时间固定 UTC 三位毫秒，重试不重生成时间。
4. `PersonalDataHub` 在依赖表注册为默认空的 app-scoped 实例；已有 CoreSyncRuntimeService 前台同步入口会处理显式 attach 的域。配置 API 要由 owner 提供 Core identity、域令牌和 allowLocalRecall。未配置不会联网。错误保留在 outbox 和 lastSyncErrors，供后续页面呈现。
5. `PersonaChatService.addCharacterMessage` 在显式本机 companion gate 匹配唯一 character/device 后，把文字回复和现有聊天 outbox 同事务保存。CoreSyncEngine 由真实聊天行确定 companion sender，不带 request_companion_reply。未开启 gate 保持原行为；服务端拒绝时仍保留待发消息。workbench/action 附加消息不扩大入队。
6. `RecordOrganizerServiceV3.updateCard` 默认 `agent_inferred`；真实 memory update tool 明传该 actor，不能从模型参数升格用户。日程 toggle 明传 `user_direct`。用户更正逐字段同事务写 `user_corrections`；因现表无 actor 列，actor 记在关联 kv 元数据，审计带 actor。agent 不能改用户锁定字段。`user_via_agent` 需要受控调用者提供证据引用；本包不签发 Core 授权。
7. `memory_v3_query_tool` 的真实召回入口仅对 owner 明确允许域加入待同步覆盖层，标记“未同步的记录（仅本机）”。
8. `CaptureConsumer` 是显式配置的消费 adapter：仅 Core 已接受 claude_web captures，经实际 RecordOrganizer.persist，排除 task/schedule/plan 卡，保存 capture/input-version→精确产出 id 幂等凭据，并与 ack intent 同一真实 AppDatabase 事务提交。原话版本从注入的 text 字段组 decoder 取得；缺失版本不处理，不用整条 revision 猜测。提取后重验当前 revision/墓碑；两个处理者使用独立嵌套 disposition。

## 验证结果与复现

- 专项加相邻：**114 tests / 114 pass / 0 fail / 0 skip**。其中新目录 71 项，原入口相邻 43 项。
- 相关全部源/测试 Dart analyze：**No issues found**。
- `git diff --check` 通过。
- A20 包含 **9 个真正 OS-kill 的 SQLite 子进程边界**（本地写提交前后、提交状态前后、响应未落库、回执提交前后、snapshot 替换前后）。这些子进程采用合成最小 Drift 数据库；另有真实 AppDatabase 事务测试证明 phoneWrite、聊天队列和 Organizer 卡片/消费凭据/ack 全收全拒，不把 map double 当数据库证据。
- A18 包含真正分页、缺页/摘要/过期/绑定失败、替换事务回滚、pending 保留、陈旧响应、失效 snapshot ack 清副本及重建。
- 本机实际 loopback HTTP 用不同域 bearer 测试；默认 Flutter 禁止 HTTP 的 override 只在该测试 isolate 关闭。
- 主窗另外报告真实 W1 Node24 ↔ Dart **2/2 通过**：103 条种子记录加一条本机提交，两页 104 项，Unicode/emoji/嵌套对象、1e-7/1e-6/1e20/1e21、丢接受响应和永久墓碑。该测试与夹具由主窗拥有，独立验收以主窗日志/最终 manifest 为准。

```powershell
flutter test --no-pub test/data/personal_data_hub test/data/services/persona_chat_service_test.dart test/data/memory_v3/services/record_organizer_service_test.dart test/data/services/sync/core_sync_protocol_test.dart test/data/services/sync/core_sync_engine_test.dart

dart analyze lib/data/personal_data_hub test/data/personal_data_hub lib/data/services/persona_chat_service.dart lib/data/services/sync/core_sync_engine.dart lib/data/services/sync/core_sync_runtime_service.dart lib/data/memory_v3/services/record_organizer_service.dart lib/agent/built_in_tools/memory_v3_query_tool.dart lib/agent/built_in_tools/memory_v3_update_card_tool.dart lib/ui/companion/view_models/schedule_view_model.dart lib/config/dependencies.dart test/data/memory_v3/services/record_organizer_service_test.dart
```

本机使用 Flutter SDK 的 dart/flutter。analyze 子进程把 LOCALAPPDATA 临时指向被忽略的 `.dart_tool/isolated_host`，避免现有 SDK 分析性能目录错误；没有全局配置改动。依赖已解析并生成 package_config；首次 pub get 因外部 Pub active_roots 目录错误返回非零，所以验证使用 --no-pub，不把该 pub get 记为成功。OS-kill fixture 的 Dart 路径优先使用 `W7_DART_EXECUTABLE`；未设置时从 `FLUTTER_ROOT` 或当前 Flutter runtime 的祖先目录定位 SDK，按平台选 dart.exe/dart。找不到明确失败，不 skip。路径解析覆盖合成 Windows/Linux/override/找不到负例；当前宿主 Windows 的实际路径定位和 9 个真实杀进程边界已通过，Linux 真实运行仍待 CI。owned 新源码/测试目录复核无 C:/D: 本机绝对路径。本机日志在 `.dart_tool/w7-final-tests.log` / `.dart_tool/w7-final-analyze.log`，不纳入源码。

## 主窗审阅后的安全修复闭环

- 合法 merge 回执仅列实际改变的 records：source 与 supplied reference 必须出现、target 可省略，其余目标拒绝。op/principal/policy 绑定不变。后继 target patch 使用已被 Core 接受和核对的原 target_base_revision，不猜加一，也不因缺 target 回执无故阻塞。
- accepted、terminal TTL、目标墓碑复用一份正文清理规则，包含 provenance（source_refs/import_batch_id），并用敏感哨兵检查真实持久化 state。删除关联 op 的用户更正值同时清除。
- semantic_duplicate 的 POST 回应遗失且原目标已删除时，GET 可不再含 duplicate_of。单目标 receipt 用来定位原目标；多目标 receipt 无法唯一定位则清除整域可读缓存及旧 result body。两者均等待新 snapshot 才恢复可读视图，snapshot 断网期间不回显缓存。不会误把新 create id 当旧 duplicate 目标。
- 已知 hidden_ids/墓碑阻止新 create/patch 及旧 pending overlay 复活；显式 restore 在真实接受并取得更高 canonical revision 后才恢复可见。
- 收到 result.record 后只写当前 canonical 副本，终态 outbox 不保留每个版本正文。receipt、touched_ids、duplicate_of 保留因果及关联信息；三次 patch 和重复 receipt 验证不累积旧 body/provenance。
- 崩溃测试移除本机 SDK 路径硬编码，自动定位失败会报错；保留真实 Process.kill、SQLite 重开与全部 9 个提交前后边界断言，没有 skip。

- 二审明确 GET merge 的 `target_state=deleted` 只描述 source：只标记 source，target/reference 保留，fresh snapshot 相同 revision 仍可读；不能把全部 touched_ids 当墓碑。
- 提交状态已持久化但回执丢失时，后续 feed 的墓碑可能正是该 op 已提交的效果。清正文后保留原 op_id 的 `lookup_only` 恢复状态；只查原操作，404 转待处理，绝不重发已清 body。另一个写入者的墓碑、lookup rejected 或 needs_resolution 都不能推断本操作 accepted；实际 receipt 才决定接受。delete/merge 两条恢复路径含重开 store 与 fresh snapshot。
- 已经 accepted/duplicate 的历史操作不再作为新操作的未完成前驱。未显式指定 base 时从当前 canonical 和本机已验证 receipt 取最大已知 revision；显式 base 保留。真正未完成前驱接受后，仅提升主 id / merge target / reference 的 base，不回退用户已观察的更高版本。专项覆盖旧回执 rev2、另一设备 feed rev5、新 patch/delete 仍据 rev5。

- 最终窄复核：merge 已完成后才 enqueue target 的场景也继承已验证的未变化 target_base_revision。knownRevision 汇总先重新核验历史结果的 op/domain/outcome 与 receipt 绑定，再接受真实 targets；只有已接受且 receipt 省略 target 的 merge 可提供该 target 的已验基准下限。更高 canonical 或显式 base 不降低；pending、rejected、损坏/未绑定的 receipt 不作为版本证据。新增 8 项覆盖无缓存、旧/新缓存、显式 base、合法 idempotent replay 和三个负例；原 queued-before-merge 测试保留。

以上修复仅触及本包 DomainStore、DomainSyncEngine、专项测试与自身 handoff。主窗真实 merge 与删除重复目标互通的后续验收以主窗独立结果为准。

## 旧测试变更依据

`record_organizer_service_test.dart` 原“用户修正 userCorrected=true”正例增加显式 `actor: 'user_direct'`，保留原 userCorrected=true 断言。旧测试默认把一切 companion 编辑当用户更正，与新 actor 来源契约冲突；新专项同时证明无证据 agent 不升格、不能覆盖用户锁。未删除或跳过旧测试。

## 剩余 Gate 与调用者责任

- **没有切换任何真实业务域。** 各业务编辑、导入、启动去重与本地判重删除仍由 W7 各域 adapter 按迁移清单接入；未迁移域保留旧去重，不能全局关掉。现有用户更正接线覆盖获授权的 Organizer/update-tool/日程入口，不声称所有历史 UI 均已盘清并迁移。
- W4/W5 要提供页面、完整待处理/提醒可见 UI、widget 测试、owner 配置入口和能力授予交互。plan status 的可写状态、complete/undo 目标边界由业务 adapter 和后端范围令牌共同约束，不能因为通用 schema 可枚举就放开任意 reopen。
- CaptureConsumer 未自动加入后台/启动任务，也未连接真实模型或 W2 域配置。W2 定稿后需明确接入 text field_meta 提取、模型 extraction 和被授权的消费触发；目前通过真实 Organizer.persist 的持久核心，而不是整个 organizeAndPersist 的异步 finance bridge/派生任务。各生活域桥接、修改重处理与派生删除审计属于后续业务接线，不以 ack 成功冒充所有派生产物完成。
- 领域 credential/binding 由受控宿主注入；本包不保存 bearer、不签发授权、不自动接受服务器换 Core identity。phone companion gate 是本机选择开关，不替代服务端 owner 授权；旧 schema/未授予会保留可查询错误/待发，后续 UI 负责展示。
- shadow 仅 staging；真实 7 天对账、回滚演练、逐域冻结切换、数据迁移、production App 构建安装和真人 Gate **均未执行**。
- 当前有限测试在 Windows Dart VM/真实 SQLite 上完成；尚无 Android 设备后台/系统杀进程、网络证书或多窗口多进程 App 写入验收。AppDatabase 单实例事务为当前边界。

主窗可先独立复核本候选，再与 W1/W2 源码做组合验收；源码验证不构成服务上线授权。
