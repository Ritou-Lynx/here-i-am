# B3 网页记录拉取 worker 交接

- 基线：`2d92a8d74828fa2513bf1a7cb5c4ab233e757f3a`；分支 `codex/b3-writeback-local-20261003`；已由主窗整合源码与验证，统一提交。
- 新代码：`lib/data/memory_v3/notes/`（model、secure storage、importer、feed service），专项测试 `test/data/memory_v3/notes/claude_web_note_feed_test.dart`。
- 既有文件仅改 `RecordOrganizerServiceV3.persist` 的可选 `deduplicate=true` 参数及新增 `replaceOrganizedCard` 用户修订路径；无 schema / 生成代码 / 依赖修改。

## 公共接口

`ClaudeWebNoteFeedService(storage: ClaudeWebNoteFeedStorage(), importer: ClaudeWebNoteImporter(db: db, organizer: RecordOrganizerServiceV3(db), organize: callback), client: optionalHttpClient)`。

- `organize`：`Future<OrganizedRecord> Function(RecordSource)`；生产回调使用现有 `RecordOrganizerAgentV3.organize` 和记忆抽取模型，分析在事务外执行。
- `readConfig()` → `Future<Result<ClaudeWebNoteFeedConfig?>>`，配置含 `baseUrl/token/cursor`。
- `configure({required String baseUrl, required String token})` / `clearConnection()` → `Future<Result<void>>`。
- `syncOnce()` → `Future<Result<ClaudeWebNoteSyncReport>>`，含 `status` (`notConfigured/unauthorized/synced`)、`processed/cursor`。
- 同实例连接变更与拉取串行，重叠拉取合并；父窗负责 Provider、设置页及前台触发。

## 数据约束

- URL、手机令牌与游标存同一个 FlutterSecureStorage 值，不进入配置同步；更换 URL 从 0 重拉，换同 URL 令牌保留游标。
- 禁止 HTTP 非本机地址、URL 用户信息/路径/查询/片段；请求禁跳转、20 秒超时、响应最多 2 MiB，每页最多 200 条，每次最多 10 页。
- 来源精确为 `source_kind=claude_web_note/source_ref=note_id`。真实 Organizer 结果通过 V3 persist 写入，可含多张卡；外部记录禁用跨来源去重，避免偷绑/误删其他记录。
- 新卡、修订/删除、来源、无正文 revision receipt 在同一 Drift 事务提交。receipt 位于既有 `memory_card_operations`，`operation_type=external_note_import`；不新增表或字段。
- 修订保留对应 card id，记录 user correction，替换展示/检索/结构字段/实体链接/原始输入；多卡增减精确处理该 note 的投影。删除清投影，旧 revision 重放不会复活。
- 每条成功入库后 ack，ack 成功后保存该条游标；模型、事务、网络或 ack 失败不越过该条。重启/重拉依赖数据库 receipt 幂等，ack 可重试。
- 此 B3 仅接入显式 Memory V3 记忆卡；未引入高层 organizeAndPersist 的异步财务/出行/LifeInsight 副作用，父窗已确认此范围。

## 验证

- 新增 12 项合成测试全部通过；加现有 Record Organizer 18 项回归共 30/30 通过。
- 覆盖 secure storage 读取重建、URL 边界、重复/服务重建重试、更新清旧字段和实体、多卡 2→3→1、删除/旧 revision 重放、来源隔离、receipt 故障整事务回滚、401/未配置、ack 失败游标不前进、第二条失败不越过、分页游标校验/并发合并、空 organizer 输出。
- 最终专项 `dart analyze lib/data/memory_v3/notes lib/data/memory_v3/services/record_organizer_service.dart test/data/memory_v3/notes`：exit 0，No issues found。
- 分析使用仅本进程 LOCALAPPDATA 指向工作树内 `.dart_tool/b3-note-analysis-local`，避开本机 Dart perf socket 清理故障；未改全局环境。首轮因 DAO 生成输出缺失的编译失败及默认 perf 退出错误不计通过；父窗重新生成后完成以上重跑。
- 合成测试 mock Organizer/HTTP/secure storage；未调用真实模型、真实服务、账号、policy、数据库或手机。构建/安装/真人验收由主窗管理。
