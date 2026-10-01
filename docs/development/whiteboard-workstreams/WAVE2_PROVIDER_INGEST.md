# Wave 2：平台链接预览与存储故障解耦

## 范围

- 基线：`codex/whiteboard-wave1-integration@c15a3eb9`。
- 只审计 Bilibili / 小红书 URL 识别、预览状态和确认提交的错误呈现。
- 不修改 schema、`UnifiedCardRepository` 生命周期、路由、图片 OCR、评论提取或播放器能力声明。

## 真实诊断

### Bilibili

- 用户提供的 `/video/BV1E8KV6QEu7/` 分享链接可稳定识别为 `provider=bilibili`、`canonicalId=BV1E8KV6QEu7`。
- Bilibili 当前是纯本地 `linkOnly` 预览，不发 HTTP，也不声明可控播放、seek 或字幕。
- 本次“预览失败”发生在预览已经生成之后：导入页为核对是否已导入而调用 `getSource()`，关闭的 Drift isolate connection 抛错，外层又把它误写成“抓取失败”。保存失败同样来自已关闭的数据库连接，不是 Bilibili provider。

### 小红书

- 对用户提供的公开 note URL 做了两次匿名、只读真实检查：普通 HTTP 请求返回 `200`、`text/html`、约 61.5 KiB；产品自身 `SafeHttpClient + LinkIngestor` 返回 `status=ok`，解析出真实标题、正文和媒体候选。
- 因此这一次小红书“抓取失败”也不是平台拒绝，而是抓取成功后查询已导入状态时被同一个关闭数据库连接连坐。
- 平台未来仍可能按链接、地区或时效返回登录墙 / 反爬状态；现有 401/403 `needsAuth` 语义保留，不绕登录，也不虚构正文、图片或评论。

## 修正

- provider / 网络预览与“查询是否已导入”解耦：后者失败时仍展示已生成的预览，只提示暂时无法核对卡片库状态。
- 预览不再无意义地刷新“最近导入”；只有确认保存成功后刷新。
- 保存遇到关闭连接时显示“存储连接已失效、当前预览尚未写入、重开应用后再保存”，不再泄露 `Bad state`、SQL、request id 或 isolate channel。
- 生产数据库为何被关闭不在本流修复；应由统一 Repository / App 生命周期工作流处理。

## 验证

- 精确覆盖 Bilibili BV 分享 URL 和小红书 discovery/item 分享 URL 的 provider / canonical ID。
- Widget 覆盖：Bilibili link-only 与小红书已解析结果在 `getSource()` 抛 closed connection 时仍成功预览；Bilibili 确认提交失败时保持零写入并只显示用户可理解状态。
- URL canonicalizer、ingestion service、import UI 合计 56/56 通过；定向 analyze 零问题。

## 未完事项

- 修复生产数据库连接被提前关闭导致首页、卡片库、白板库同时失败的根因。
- 小红书图片安全缓存、OCR 和重要评论证据仍等待独立资产 / `object_ref` 契约；本轮不冒充完成。
