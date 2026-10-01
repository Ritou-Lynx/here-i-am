# F0：统一数据层与功能收口地基

## 裁决

白板内容的唯一生产入口是 `UnifiedCardRepository`。F0 在隔离基线中不新增表、不创建迁移、不修改生成代码，所需白板字段在 schema 59 时已经齐备；合入 `v3-lab` 时，主线已因独立的 Dev Room 配置功能升级到 schema **60**，F0 沿用该版本，不覆盖、不回退。

| 语义 | 唯一真相 / 维护者 |
|---|---|
| Card 稳定身份 | `MemoryCards.id`；`WhiteboardCardExtras.cardId` 以同一 ID 扩展 `cardKind/sourceId/tags/presentation/body/deletedAt` |
| Source | `WhiteboardSources.id`；canonical URL、provider、媒体元数据在 metadata，当前版本由 `currentVersionId` 指向 |
| SourceVersion | `WhiteboardSourceVersions`；同一 Source 按 `contentHash` 幂等，内容变化只新增版本，不复制 Card |
| RichTextDocument | `<app-support>/whiteboard/rich_text/card_<cardId>/rich_text.json`；完整 JSON 使用可恢复的 `.tmp/.bak` 交换，Drift 只保存可搜索正文投影 |
| 标题 / 正文 / 类型 / 标签 / 缩略图 / 更新时间 | Repository 在一个写入口更新 `MemoryCards` 投影和 `WhiteboardCardExtras` 扩展；富文本标题取首个非空可见行，来源卡取抓取标题/描述/OG 图 |
| 文件对象 | 继续使用文档内稳定相对 `object_ref`；来源正文对象位于 `whiteboard/objects/sources/`，版本保存稳定 object ref |
| 白板摆放 | `WhiteboardBoardItems` 只引用 `cardId`；删除 BoardItem 不删除 Card、Source、Version 或富文本文件 |

## 写入语义

1. `LinkIngestionService.ingestUrl()` 默认只返回预览 `IngestionResult`（`createCard:false`），对 Drift 和对象目录均为零写入；只有 `commitResult()` 或显式 `createCard:true` 才提交。
2. 用户确认后 `commitIngestion(result)` 先持久化可恢复的来源对象，再在一个 Drift transaction 中写入/复用 Source、写入/复用 SourceVersion、写入/更新同一 Card。
3. canonical Source + 相同 content hash 重导不新增任何身份；内容变化新增 SourceVersion，Source.currentVersionId 前移，Card ID 保持不变。
4. `saveRichText` 要求 Card 已存在；先以可恢复文件交换保存完整文档，再同步标题、正文投影和更新时间，不允许生成只有目录、没有 Card 的孤儿身份。
5. `softDeleteCard` 只写软删除；`restoreCard` 恢复原身份。删除 BoardItem 永远不级联删除 Card。

SQLite 与文件系统无法共享物理事务。当前顺序选择“对象先落盘、Drift 后提交”：崩溃最多留下可扫描的未引用对象，不会让数据库指向不存在的新对象；读取端用 `available / missing / corrupt` 三态诚实呈现，并可从 Drift 正文投影降级恢复。

RichText、Source object 和 migration report 的单文件替换均先写入并校验 `.tmp`，旧目标改名保留为 `.bak` 后再安装新文件；启动或读取会按“有效目标 → 有效临时文件 → 有效备份”恢复遗留交换。这个机制保证中断后仍有可验证副本，但 Dart 无法在所有平台对父目录执行 `fsync`，因此它是可恢复交换，不宣称为跨崩溃的文件系统原子事务。

## Repository API

- 查询：`getCard`、`listCards(CardLibraryQuery)`、`getSource`、`listSourceVersions`、`getCardForSource`、`isCardPlaced`。
- Card：`createTextCard`、`updateCardMetadata`、`saveRichText`、`linkSourceToCard`、`softDeleteCard`、`restoreCard`。
- Ingestion：`commitIngestion`；Link UI 用 `commitResult` 提交已经展示给用户的结果，不二次抓取。
- 迁移专用：`importLegacyCard`、`backfillLegacyMemoryCardExtra`、`importLegacyIngestion`。
- 查询组合：类型、标签、来源类型、全文投影、boardId、是否已摆放、是否含软删除、limit。

生产 UI 通过 `WhiteboardDataBootstrap.productionRepository()` 共享同一个初始化 Future；卡片库、富文本编辑器、链接导入和白板画布不再直接查询 `MemoryCards`、扫描 RichText 目录或把 `IngestionStore` 当作卡片库真相。旧 `RichTextSearchIndex` 只保留为既有 widget test 的注入兼容面。

## 三套遗留数据的幂等迁移

`LegacyWhiteboardDataMigrator` 在生产 Repository 首次打开前运行一次，并写 `whiteboard/migrations/f0_data_convergence_report.json`：

- Drift：为 `user_truth/note` 的旧 `MemoryCards` 补 `WhiteboardCardExtras`，不复制 Card。
- RichText：按目录中的 `cardId` 导入；没有 Card 时补建同 ID Card，只有文件时间不早于数据库更新时间时才更新正文投影，不用旧文件覆盖新编辑。
- Ingestion JSON：读取旧 `whiteboard/ingestion/sources/*.json`，把 Source、全部 Version 和 Card 导入现有 Drift 表，按 ID/hash 幂等。
- 单条损坏只进入 failures，不阻断其他记录；疑似 `itest/integration_test/test_card/perf/demo` 数据只加入报告标记，仍照常无损迁移并可从 Repository 查询。迁移绝不自动跳过或删除，清理必须是独立、显式确认的后续操作。

迁移测试使用三类临时夹具连续运行两次，第二次不产生重复身份；同时验证“数据库较新不被覆盖”和“损坏项不阻断、疑似测试数据被标记但仍可查询”。本任务没有对真实用户数据库执行清理或试迁移。

## 测试隔离与验证

- 新增 Repository / migrator / ingestion / UI 测试全部使用独立 `Directory.systemTemp` 和 `NativeDatabase`，重启测试先关闭旧连接再打开同一临时 sqlite。
- 两条 desktop integration test 已改为临时 DB + 临时对象根，不再调用 `app.main()`、不再创建/读取真实用户 ID 和 Documents 数据库。
- 最终核心与受影响 UI 集合 76/76 通过，覆盖 Repository、迁移、ingestion、链接 UI、卡片库、富文本保存、冻结路由和画布交互；此前失败点定向复验 28/28。
- Windows 原生 integration 构建曾暴露并已修复测试中的 `createBoard` 返回类型错误；本机还出现一次插件并发构建头文件错误，原生窗口用例未取得全绿结果，不能记为通过。

## F1–F4 最小接入方式

- F1（画布交互）：只持有 `cardId`，卡片库通过 Repository 查询；摆放/移除只写 BoardItem。
- F2（富文本）：新建先 `createTextCard`，编辑只 `getCard + saveRichText`；不得直接调用 RichTextStorage 形成孤儿目录。
- F3（来源/链接）：抓取阶段只保留 `IngestionResult`；明确确认后调用 `commitIngestion`，来源页按 `sourceId` 查询版本链。
- F4（视频/媒体）：视频也是 Source + SourceVersion + Card；二进制继续走稳定 object_ref，转写/摘要作为新版本或 Card 投影更新，不另建卡片库。

## 未解决风险

- 文件系统与 SQLite 不是同一物理事务；`.tmp/.bak` 交换也没有父目录 `fsync` 保证。当前只承诺启动/读取时恢复有效副本和显式降级状态，后续可增加未引用对象清扫器。
- 遗留迁移在进程内只启动一次；若报告含 failures，需要产品入口提示用户重试/导出报告。
- Memory V3 的诊断导出页面仍会直接读取 MemoryCards 及其专属关系表；它不是白板卡片库入口，F0 未改其审计导出语义。
- 未 push、未 merge；集成目标仍为 `v3-lab`。
