# P5 手机只读服务交接

- 基线：`4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`。仅新增两个 phone 服务及两个专项测试，未暂存/提交/构建/安装，未触及设备或真实数据。
- API：`PhoneMemoryReadServer.instance`、`session/isRunning/start/stop` 遵守工作包契约；session 提供 `connectionCode/expiresAt/port`。测试通过 identity/read/clock/port/timeout 构造注入，不自动启动数据库或 HTTP 服务。
- 会话：固定生产 IPv4 loopback `127.0.0.1:47851`，32 字节安全随机 token，30 分钟到期，内存保存，关闭立即清除。每次请求、查询前后及每秒检查账户、数据库实例身份和既有 `i.yaml` enabled 标志；关闭、到期、身份失效拒绝在途返回。不会调用会自动创建/迁移角色文件的 `getCharacter()`。
- HTTP：认证 status 与固定 read-context 路径；拒绝 Origin/query/额外字段/错误角色与方法；请求 16 KiB/query 2000 UTF-16 单元、响应 32 KiB；字段 UTF-16 裁剪避免拆开 surrogate；单查询并发，body/auth 默认 4 秒、query 8 秒。查询超时后仍保留占用直到底层 Future 完成，避免排队堆积。错误只有固定非敏感码，响应 no-store，无 token/query/body 日志。
- 查询：复用 SearchDao 三个 FTS SELECT 与 QueryMatcher 分词。无 FTS 命中时，从至多 96 Episodes/144 Fragments/32 Sagas 的有效近期候选做至多 12 关键词 substring 匹配；没有无关 recency fill、embedding、LLM、trace 写入或索引修复。任一 FTS/数据库异常返回 unavailable；成功但无可用匹配/严格过滤后无结果是 empty，只表示本次有界查询无命中，不表示手机没有记忆。
- 闭包：单个只读 Drift 事务提供一致快照；Episode/Saga 仅 active，Fragment 仅 active/consolidated。关系展开上限 24 Episodes/96 Fragments；每 Saga ≤16 引用、Episode ≤24、Fragment 每种消息引用 ≤16；非法/重复/超长/缺失引用均拒绝。两套消息来源独立验证，全部必须属于 i、普通 chat 且非 TaskRoom。来源已删除或 hidden/stale 等状态不能通过展开复活。
- 已审计：DreamingOrchestrator 的现有查询会初始化 embedding 并记录 query，故未直接使用；CharacterService.getCharacter 会 seed/migrate，故只读既有文件。FTS 分词仅读 bundled 字典并在内存分词，日志只含固定字典载入状态，无请求内容。
- 验证：四个拥有文件 `dart analyze` 最终 `No issues found!`。首次真实 Flutter 测试 9 通过/3 失败，暴露 FTS 列表协变与超大 chunked body 取消流过早的问题，均已修复；已追加事务并发删除与 Unicode/count 上限测试，现共 14 项。最终复测由主窗串行执行，避免共享 Flutter 测试产物锁；worker 不继续启动 Flutter。
- 测试入口：`test/data/memory_v3/readonly/phone_dreaming_read_service_test.dart`、`test/data/memory_v3/readonly/phone_memory_read_server_test.dart`。真实内存 Drift 测试通过 `PRAGMA query_only=ON` 约束数据写；HTTP 测试使用真实 loopback socket，覆盖认证/边界/空与失败/超时并发/身份在途撤销/关闭到期/响应限额。
- 限制：只读事务提供一次查询的快照；删除与并发查询按 SQLite 顺序观察，下一次查询读取删除后的状态。没有声称所有并发写完成之前已取到的快照能被追溯撤回。未取得真实手机/桌面候选回复或人验，不标记 P5 Gate。
