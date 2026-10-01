# Wave 3 D/P1 本地媒体卡面交接

> 分支：`codex/whiteboard-wave3-media-cards`
> 基线：`427086ae`
> 范围：工作包 D 中可自动闭环的本地图片卡面，以及 3.7 全局创建的“导入图片”子项；不表示 D 或 F 全部完成。

## 1. 已实现

- 画布 `BoardItem` 与左上卡片库均会直接显示 RichText 首个图片块；同一 Card 的多个 BoardItem 共享内容、各自渲染。
- Source 卡只显示已缓存、经安全解析的本地缩略图；渲染时不传递远程 candidate/canonical URL，不触网。
- 对象丢失或校验失败显示“图片对象缺失”，不用文件名、路径或 URL 冒充预览。
- 全局画布工具增加明确“导入图片”：复用现有 `file_picker`、`RichTextObjectStore` 和 `UnifiedCardRepository`，创建真实 Card，再放到当前 viewport；多图轻微错位，只保存一次快照。
- 图片为首个有意义块的卡片双击进入现有完整查看/编辑面；混合文档仍保持普通卡面原位编辑，不因正文中含图而强制跳转。
- 只读状态禁用导入且不调用 picker。布局保存失败回滚 BoardItem 和 Card，同时删除 RichText 文档与图片对象；软删失败时保留可见重试，全部对象清理完才收起提示。

## 2. 对象解析路径与契约

1. RichText：`RichTextStorage.loadWithStatusSync(cardId)` → image block 的 `asset_ref_id` → document `assetRefs` → `RichTextObjectStore.resolveFile`。
2. Source：Card projection 的 `thumbnail_ref` → `UnifiedCardRepository.resolveCachedThumbnail` → `SafeThumbnailResolver.resolveCached`。
3. UI 只接受上述安全本地 `File`；没有 URL `ImageProvider`，没有渲染期下载或自动修复。
4. 本包没有改动 `RichTextObjectStore.importBytes`，没有新增依赖、schema 或生成文件。

## 3. 失败、恢复与验证

- 新增 7 条 Widget 回归：多 BoardItem + 卡片库预览、Repository 重建，本地对象丢失，Source 缓存证据且零网络，导入/当前 viewport/双击完整打开，只读，持久化失败全补偿，补偿失败可重试。
- 联合回归：卡片库 12 + 本地媒体 7 + 画布直接交互 22 = **41/41 通过**（`--concurrency=1`，避免 Windows `Image.file` 测试销毁句柄竞态）。
- 6 个实际变更/新增 Dart 文件精确 `dart analyze`：零问题；`git diff --check` 通过。
- 本功能包不构建 exe；由验收主窗口集成后统一构建。

## 4. 3.7 清单状态（本包交付后）

| 3.7 分组 | 已实现 / 本次新增 | 受限 | 未实现（本包不改变） |
|---|---|---|---|
| 单卡直接操作 | 既有的空白双击建卡、单击选择/双击原位编辑、四向锚点与 BoardItem 跟随保持；新增图片卡面直接预览与图片主卡双击完整打开。 | 完整打开已有能力，尚未纳入 F 统一命令层。 | 悬浮放大/换色/添加到白板/更多快捷栏。 |
| 右键 / 更多 | 本包无新增。 | 既有全屏打开、移除 BoardItem 底层语义仍受限于未统一接入。 | 换色、复制 Card/链接、ContextDock/Pop/新标签页、信息/版本恢复、Markdown/PDF/Word 导出与 Markdown 复制、标签、添加/移除/全局删除语义。 |
| 多选批量 | 本包无新增。 | 既有多选基础仍受限于没有 3.7 就地完整栏。 | 填充/文字/文字背景色、聚焦、四种对齐、分组及二级操作、跨板复制/添加、批量标签。 |
| 全局常驻工具 | **“导入图片”子项已实现**：真实 Card + 当前 viewport + 失败补偿。 | 3.7 的通用“创建卡片”仍只有双击路径和图片子入口，尚未形成统一本地/链接创建面。 | 画笔、荧光笔、橡皮擦、稳定笔迹身份/撤销重做/保存/重启恢复。 |

## 5. 明确受限 / 未实现

- Source 卡面只展示已有本地缓存证据；不会为了卡面自动抓取、OCR 或下载。
- 本隔离包自身不生产小红书证据；验收主窗口已另行集成匿名公开图片 / OCR / 顶层评论证据。小红书视频仍只有 link-only 证据，播放 / Anchor 未实现。
- 未修改 XHS fetcher/evidence 生产者、视频 resolver、BoardEdge、F 菜单/批量/手绘、W5/Bridge 文件。
- 未 push，未合并 `v3-lab`，未运行 build_runner。

## 6. P1 审计返修

- 单项在 import/create 后 save 失败也进入统一补偿队列；一项清理失败不阻塞其余项，已软删但媒体文件未删完时仍可重试。`importFile` 的随机对象仍做物理清理；共享 digest 对象的 GC 语义由 XHS 包处理。
- 卡面本地缓存解析只信任 `SafeThumbnailResolver.resolveCached`；其他 resolver 直接 missing，测试证明滚动和渲染全程零调用。
- 预览在 card id、updatedAt、thumbnail_ref 或 sourceId 投影键变化时重新解析；导入与补偿错误只显示稳定文案，不暴露绝对路径。
- 最终联合回归：卡片库 12 + 媒体卡 9 + 画布直接交互 22 = **43/43 通过**；5 个本次变更/测试文件精确 analyze 零问题。
