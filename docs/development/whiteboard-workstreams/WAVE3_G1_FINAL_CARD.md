# Wave 3 G1 — 卡面最终收口 handoff

> 分支：`codex/whiteboard-wave3-final-card`
> 基线：`693050e9`
> 状态：自动门禁通过，待集成窗口真人复核

## 结果

- `CompactCardEditor` 不再维护 title `TextField` 与 body editor 两套输入状态；标题首行与正文共用一个 `CardRichTextEditor` 和一个原生连续文本值。
- 标题在编辑会话中是带私有 marker 的 synthetic 首块；保存时只依该 marker 拆分 title / body，所以旧正文第一块即使是 H1 也不会被误拆。marker 不落盘，不新建或轮换 block id。
- 新建 Note 以空标题进入单一卡面并直接 autofocus；旧 `saveRichText` 调用者的标题回退规则不变，仅同面编辑显式要求保留空标题。
- 卡外点击与 Esc 继续走同一保存退出路径；保存失败显示错误且保留编辑态。BoardItem 外形、`item_id` 隔离、撤销重做和 Repository 持久化路径保持不变。
- 左上角卡片库展开后的卡名与类型元信息统一使用 `whiteboardUiTextStyle`。

## 契约影响

- 未改 Card / Source / Anchor / Snapshot / PlayerAdapter / TimedTextTrack 身份或 schema，未改数据库迁移、依赖或生成文件。
- `UnifiedCardRepository.saveRichText` 只增加默认关闭的 `preserveEmptyTitle`，不改变旧调用者语义；用于表达 Card 契约本已允许的显式空 title。
- 未修改 W5 Runtime/Search、视频、来源抓取、双链或其他 FlexNote 3.7 命令。

## 验证

- 新增 `compact_card_editor_test.dart`：空标题 + 正文 H1、synthetic marker 不落盘、IME composing、撤销/重做、SQLite 关闭重开恢复、保存失败保留与重试，2/2 通过。
- 画布直接交互 20/20 通过，其中包含单一无框输入面、标题/正文保存、同 Card 多 BoardItem 隔离、复杂文档和卡片库字体。
- 卡面 + 直接交互 + 产品闭环 + 视觉字体 + 富文本 + `UnifiedCardRepository` 联合回归 76/76 通过。
- 6 个实际修改源/测试文件定向 analyzer：`No issues found`；关键修复守门 3/3，`git diff --check` 通过。

## 真人验收与残余风险

- 集成窗口需用新 Windows Debug 验收版复核：新建空卡直接输入；普通卡双击后外形不变；中文 IME 候选、卡外点击 / Esc、长文卡内滚动；卡片库中文字形。
- 列表、引用、代码和媒体等非线性 block 仍沿用旧兼容 surface；它们已无输入框外观，但本包没有把这些异构 block 重做为跨块连续选择。
- 本分支不 push、不合并；待集成审计后由主窗口合入并构建唯一验收 exe。
