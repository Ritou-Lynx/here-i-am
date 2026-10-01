# W4-S — Bilibili 匿名字幕 transport handoff

> 日期：2026-08-23
> 基线：`v3-lab@96f4e95a`
> 状态：实现与自动验证完成；匿名真实成功样本未取得，待 W0 / Windows 真人 Gate

## 1. 现实矩阵

| 能力 | 开始时代码现状 | 本轮 |
|---|---|---|
| Bilibili URL / BV 识别与 LinkIngestor | 已有 | 只读，未重做 |
| Windows 顶层播放与 HTMLMediaElement 时间桥 | 已有 | 只读，未改语义 |
| `TimedTextTrack` / cue / SRT / VTT | 已有 | 复用并组合回归 |
| `UnifiedPlatformTimedTextResolver` / ViewModel 路径 | 已有 | 默认 Bilibili 从 disabled probe 切到匿名 transport |
| Bilibili 自动字幕 transport | 仅 unsupported 占位 | 实现 `BV -> aid/cid -> track -> bcc -> TimedTextTrack` |

## 2. 实现结果

- `BilibiliTimedTextService` 仅请求 HTTPS Bilibili / bilivideo / hdslb 受信主机，不发送 Cookie、不读 WebView 登录态、不请求视频媒体。
- W0 安全返修后，Bilibili 使用独立 `BilibiliSafeHttpTransport`：`package:http` 自动 redirect 已关闭，每一跳都重新验证 HTTPS、443 与 Bilibili / bilivideo / hdslb 主机，最多 3 跳；站外 redirect 在发出下一请求前拒绝，因此 Cookie / Referer 不会泄漏到站外。
- metadata、player、bcc 分别有 512 KiB、1 MiB、8 MiB 流式字节上限；先检查 `Content-Length`，无声明时逐 chunk 累计并在首个超限 chunk 取消。请求与流读取同时受总时长/空闲超时约束。
- 多 P URL 按 `?p=` 选择 `cid`；默认优先中文人工轨，再选 AI 轨。AI 标记 `partial`，人工标记 `reliable`。
- bcc `from/to/content` 转整数毫秒 cue；最多 20,000 cues、单 cue 8,000 字符、总文本 2,000,000 字符，超限返回明确 size failure；无有效 cue 诚实归为解析失败。
- 签名 `subtitle_url` 只在当次 service 栈内使用；`TimedTextTrack.toJson()` 不含 URL、query 或 auth key，没有 Repository/schema 写入。
- 失败分类为来源无效、无轨、匿名不可见/权限、网络、解析器失效；无轨与权限文案保留 SRT / VTT 后路。
- service / resolver 接入 dispose；dispose 后迟到响应不能成为可用轨。ViewModel 原有 lifecycle epoch 继续阻止离页/换 Source 后更新 UI。
- 旧 `BilibiliSameOriginSubtitleProbe` 保留为测试/兼容缝，没有另建 resolver 或改变共享字幕契约。

## 3. 真实联网样本（2026-08-23，无登录 / 无 Cookie）

`BV1GJ411x7h7` 已证明 `view -> aid/cid -> player` 两段请求可达且 `code=0`，但匿名轨数为 0。下列搜索结果页面显式标注 CC / 字幕制作者的候选也均为 `code=0, track_count=0`：

- `BV1xt411o7Xu`
- `BV1L3411J7Yc`
- `BV14V411r7VQ`
- `BV11E411X7jT`
- `BV15J411t7SF`
- `BV1jJ411r7eH`

因此本轮不宣称真实成功 cue 已通过。成功链由 fixture 验证；真实结果只证明匿名元数据/轨清单可达且无轨能诚实降级。若 W0 有当日匿名可见轨的 BV，可直接真人验收；若平台已普遍改为登录可见，应另提安全 ADR，不在本包偷加 Cookie。

## 4. 自动验证

- W4-S 安全 transport + service + resolver 专项：22 / 22 通过，覆盖站外 redirect 拒绝、超跳数、声明/流式体积超限、metadata/bcc 超大、cue/单条/总文本预算及 dispose 迟到。
- 字幕/视频领域/contract/VideoStudy/SourceStudy 最终组合复验：143 / 143 通过，包含 YouTube 全部字幕回归。
- changed-file analyze：`No issues found!`。
- `git diff --check`：提交前通过。

## 5. 契约与边界

- 未改 PlayerAdapter、Card / Source / Anchor / Snapshot 语义、Repository/schema、依赖或生成文件。
- 未改 LinkIngestor、播放器 bridge、Canvas、W7、Cookie UI / WebView profile、ASR、视频下载或 DRM。
- `TimedTextTrack` 与 resolver 失败分类未增字段或改语义，不需要 W0 schema 迁移。

## 6. W0 / Windows 真人验收

1. 未登录环境打开当日已知匿名可见字幕轨的 BV，确认自动出现字幕，cue 点击可跳时间。
2. 打开上述无轨样本，确认“需要字幕”与无轨原因出现，SRT / VTT 导入仍可用。
3. 断网、关闭研读页或迅速切 Source，确认迟到响应不改新页状态且无 dispose 后异常。
4. 关闭重开 App，检查 Source / session 持久化没有 `subtitle_url`、`auth_key` 或 Cookie。
5. 若所有候选都仅登录可见，记录平台现状，不借登录态“帮测”匿名 transport。

## 7. 待集成与风险

- 本 handoff 与实现同提交，完整 hash 由 W4-S session 回传 W0。
- 平台 web API 与 bcc 格式可变，已用 parser failure 诚实降级；fixture 成功不等于平台 SLA。
- 既有 `TimedTextTransport` 把 HTTP 非 200 折叠为 null，无响应体时 403 只能归网络；本窄包未扩共享契约。
- 当日匿名字幕可见率为 0 / 7，是最大产品风险。W0 可决定保留诚实尝试，或另开登录态安全 ADR。
