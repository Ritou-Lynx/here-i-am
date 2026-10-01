# Wave 1 — 卡片筛选语义与标签闭环

## 范围

- 基线：`v3-lab @ ab066866365621ea336f2c05a0dadd3671922a62`
- 分支：`codex/whiteboard-wave1-card-tags`
- 不改数据库 schema、路由、CardKind、SourceMediaType 或手机端 Memory 标签体系。

## 产品结果

- 卡片库把 Card 的组织角色显示为“卡片角色”，`CardKind.source` 显示为“原件卡”；Source 的内容介质显示为“媒介类型”。“上板”语义暂时保留。
- 卡片库唯一导入入口显示为“导入链接 / 视频”，仍复用 `/import`。
- 新增统一 `CardTagField`：输入 `#标签` 或普通文本后，只有 Enter、候选选择或添加按钮才会生成标签；支持删除、空输入拒绝、大小写不敏感去重、Backspace 删除末项及全库候选。
- 普通 Card 编辑器把标签与富文本一起纳入未保存状态，保存统一调用 `UnifiedCardRepository.updateCardMetadata()`。
- 普通 Source 页直接提供标签区；视频 Source 通过播放器上方的标签按钮打开同一标签编辑器。标签确认后立即写回 Card metadata，失败会回退界面状态。
- Repository 新增 `listDistinctTags()`，每次直接读取真实 Card metadata；卡片库每次查询都同步刷新候选，不保留一次性扫描缓存。
- 正文中的 `#片段` 不会被自动解析或持久化为标签。

## 真相与恢复

- 唯一标签真相仍是 `whiteboardCardExtras.tagsJson` 对应的 `CardContract.tags`，没有新增标签表或第二份缓存。
- Note 与 Source Card 的标签均在 SQLite 连接重建后保持，并可继续被 `CardLibraryQuery(tags: ...)` 大小写不敏感命中。
- 软删除 Card 的标签默认不进入候选；诊断场景可显式请求包含软删除项。

## 验证

- TagField：`#` 清洗、空白、大小写重复、候选、删除按钮、Backspace。
- Note：新建、加标签、保存、返回卡片库、候选立即出现并筛选命中。
- Source：加标签、保存、重新创建消费页后恢复；视频来源保留标签入口。
- Repository：Note + Source 标签、大小写查询、软删除候选、数据库重启恢复。
- 既有四筛选组合、清空筛选、富文本保存/失败/退出守卫、Source 视频路径继续回归。

## 未做与集成边界

- 不建立独立 Tag 实体、层级标签、别名、颜色、计数或手机端 Memory Tag 同步。
- 不从正文、抓取内容或 AI 输出自动提取标签。
- 不改链接抓取、画布、W5、数据库生成文件与冻结路由。
- `source_study_screen.dart` 同时承载 W4 消费页；集成时若 W4 分支也改动该文件，应保留视频播放器能力矩阵与本轮右上标签入口两部分。
