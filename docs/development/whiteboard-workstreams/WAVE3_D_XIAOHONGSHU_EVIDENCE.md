# Wave 3 D：小红书公开证据隔离包 handoff

## 2026-08-23 真人验收返修：真实 SSR 入口闭环

- 根因已由用户真实样本复现：匿名页面 HTTP 200，通用 HTML parser 能看到两个图片 URL，但 XHS parser 只识别测试专用 `data-xhs-note-state`，实际 `window.__INITIAL_STATE__.note.noteDetailMap[exact noteId].note.imageList` 未接入；唯一 candidate 是 low-confidence 站点 OG，processor 按安全规则主动跳过，因此 fixtures 通过而卡片没有本地对象。
- parser v3 现在支持 `/explore/{id}`、`/note/{id}`、`/discovery/item/{id}` 的真实 SSR 结构，并只读取 URL 中 exact note id 对应的 `note`；推荐流、头像、其它 note、site OG 仍不会升级为原图证据。裸 `undefined` 只在 JSON 字符串外安全转为 null。
- 真实用户样本匿名 smoke（无 Cookie / WebView / 登录态）：页面 85,211 bytes，exact note payload 与多张 `urlDefault` 可见；第一张公开 CDN 图片 117,312 bytes 可由现有应用 UA 下载。完整生产入口 `ingestUrl(createCard:true)` 已验证 Source/Card、原图 object evidence、Windows OCR unavailable、卡片 `thumbnail_ref` 安全投影与数据库重启恢复。
- 确认提交后，第一张已验证原图会成为 `thumbnail_url` 候选，并在显式导入边界生成经过解码/重编码的 `objects/thumbnails/*`；卡片库与白板仍只读本地 `thumbnail_ref`，不会在渲染时发起网络请求。原始 OG 只保留为 `xhs_page_og_image` provenance。
- 导入 UI 新增“小红书公开证据”状态：区分检测到 / 已缓存 / 失败的原图、OCR pending / available / unavailable / failed、公开顶层评论数量与匿名 HTML 未呈现原因。公开 gate / 失效分享参数不再生成“成功但空”的卡片，而是明确失败且不可提交。
- 评论边界未扩大：只读取匿名 HTML 已呈现的顶层评论；真实样本 SSR 的 `comments.list` 为空且尚未首轮加载，因此诚实记录 0 条，不调用签名 API、私有接口、登录态或翻页。
- Windows OCR 限制：ML Kit Desktop 不可用时记录 `ocr.status=unavailable` 与 recognizer version，不伪造文字；原图 object evidence 和 thumbnail 仍保留。
- 验证：联合回归 59/59；真实单链接生产 smoke 1/1；9 个增量 Dart 文件 analyze 零问题；`git diff --check` 通过。环境门控 smoke 只从 `XHS_PUBLIC_SMOKE_URL` 读取样本，仓库不保存分享 token。

### 仍受限

- 匿名 SSR 不包含已动态加载的评论时只能显示 0 条及原因；取得更多评论需要未来经产品授权的合规浏览器能力，当前不做。
- XHS 页面结构和分享 token 会变化；exact-note 结构缺失时 fail closed，不回退整页媒体扫描。

> 基线：`427086ae`
> 分支：`codex/whiteboard-wave3-xhs-evidence`
> 范围：XHS-01 / XHS-02 当前无需 schema 的自动闭环

## 已实现

- 匿名 `SafeHttpClient` 页面结果解析为图片 / 视频 / 纯文本 note；不读取 Cookie、WebView profile 或旧 `XiaohongshuFetcher` 的登录态。
- 只从明确 note root 或限定 `note/noteDetail.imageList|images` 的结构化 state 读取媒体；不扫描整页 app state / 通用正文图片。`og:image` 只保存为 `confidence=low` 的回退线索，不负责分类或下载。
- 图片仍经过既有 DNS pin、每跳 SSRF、重定向、MIME、流式字节上限，并追加 PNG / JPEG / WebP / GIF 像素与单边尺寸限制；PNG 必须具备完整签名和 IHDR，GIF 必须为 GIF87a / GIF89a，所有格式拒绝非正尺寸。尚未支持 AVIF，因此请求 Accept 不再声明 AVIF。
- 网络证据字节通过 `RichTextObjectStore.importBytes` 以 SHA-256 内容寻址。digest 对象可能被多个卡片/证据共享，普通 `deleteRef` 对其保守不做物理删除；独占 `importFile` 对象仍可删除。
- 每张图保存原 URL、最终 URL、`object_ref`、SHA-256、MIME、顺序、尺寸、抓取时间、解析器版本和安全失败原因。
- ML Kit OCR 已抽象为可注入 `OcrRecognizer`。证据区分 available / unavailable / failed，保存派生文本、可用时的置信度、recognizer 版本和原图 object ref；ML Kit Flutter API 不提供校准置信度时明确为 null。
- 公开评论只提取匿名页面已出现的顶层 DOM：作者、文本、可解析时间 / 原始时间、顺序、selector、来源 URL、匿名访问声明。拿不到时为空，不回退登录态。
- 视频 note 只保存 `SourceMediaType.video`、`link_only` 能力与 `stream_extraction=not_attempted`，不请求或保存 `og:video` 流地址。
- 有序图片 SHA / OCR / 评论生成稳定 `xhs_evidence_manifest` 与 `xhs_evidence_hash`，并与原页面 base hash 合成 SourceVersion content hash；同 URL 返回不同 bytes 会新建版本，重复处理同一证据不会链式变 hash，旧 SourceVersion 对象继续保留。
- 同一 canonical source 的 `process + commit` 在进程内串行化，避免双击/并发提交竞争固定 SourceVersion 临时文件或重复插入；证据随 `Source.metadata` / `IngestionResult.metadata` 进入统一 Repository，SQLite 重开后仍可读。
- 持久化错误只保留稳定 failure code 和脱敏/截断摘要，本机绝对路径不会进入 evidence metadata。
- 对象解析/删除拒绝 symlink / Windows reparse point，并校验 regular file 的 canonical target 仍位于真实 `objects/` 根内，避免媒体预览越权读取或删除根外文件。

## 数据落点

- `Source.metadata.xhs_public_comments`
- `Source.metadata.xhs_media_candidates`
- `Source.metadata.xhs_image_evidence`（图片 note）
- `Source.metadata.xhs_media_evidence`（视频 note）
- `Source.metadata.xhs_evidence_manifest / xhs_evidence_hash`
- `<whiteboardRoot>/objects/<sha256>.<ext>`（受限原图对象）

同名字段也保留在 commit 后的 `IngestionResult.metadata`，供确认结果和 UI 使用。没有新表、schema、依赖或生成文件。

## 安全 / 失败状态

- SSRF、DNS、重定向、错误 MIME、超字节、畸形尺寸、超像素分别 fail closed，并在候选 evidence 中保留 `rejected/failed + failure`。
- 单图失败不抹掉公开页面 Source，也不伪造 OCR；其余候选继续处理。
- 预览阶段零对象写入；只有确认 commit 进入媒体处理。

## 受限与未实现

- `SourceVersion` 仍没有独立 metadata 字段；旧版本证据保存在既有 SourceVersion JSON object 内，可由 Repository 读取，但不能仅靠 Drift 的 `SourceVersion` 行直接投影评论/OCR。若未来需要纯数据库版本历史筛选，W0 仍需增加兼容 projection；本包未私改 schema。
- 无引用索引时无法安全判断 XHS `importBytes` digest 文件是否仍被其他证据使用，因此其物理删除采用保守 no-op；XHS 提交失败可能留下不可见孤儿，由未来引用表或 mark/sweep GC 清理。普通媒体卡 `importFile` 使用独占 `obj_<ts>_<rand>` 引用，仍可由既有失败补偿物理删除，不受此限制。
- canonical source 串行锁只覆盖当前 Dart isolate；跨进程同时写同一 whiteboardRoot 仍不受支持，符合现有单工作区单写 session 纪律。
- 公开评论只覆盖匿名 HTML 中实际渲染的顶层评论；JS 后加载、地区限制、登录墙或反爬页面会诚实为空。
- 未进行登录兼容、隐藏 WebView 抓取、私有 API、评论翻页或“重要性”模型排序；当前最多保留页面出现的前 10 条。
- 未实现白板卡面媒体预览 / OCR 搜索 UI、统一本地导入 UI、视频播放 / Anchor；这些分别属于后续 UI/F0/W4 接缝。
- 未做真实 XHS 网络或 Windows 窗口验收；本提交仅交付可重复 fixture、安全失败和 Repository 重启证据。

## 验证

- 定向 Flutter tests：48 / 48（XHS processor / parser、object store、既有 LinkIngestion 回归）。
- 覆盖新增：整页推荐视频/头像/site OG 负例、限定结构化 state、宽泛正文/comment 负例、伪造 PNG/GIF/零尺寸、错误路径脱敏、同 URL 换 bytes 新版本、重复 evidence hash 稳定、Future.wait 双提交、共享 digest 删除保留。
- 精确 analyze：本增量 7 个 Dart 文件，零问题。
- `git diff --check`：通过。
