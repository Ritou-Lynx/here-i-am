# 白板外部参考与内容采集审计

> 日期：2026-08-14
> 状态：第一轮审计完成，尚未引入第三方生产代码
> 相关契约：`docs/design/whiteboard-ui-spine-contract.md`

## 1. 结论

两个仓库都有参考价值，但是否直接复用受不同许可证约束：

- `feitangyuan/kankan-shoucang` 是 AGPL-3.0-or-later，Here I am 当前根许可证为 GPLv3。两者可以依照 AGPLv3 第 13 节组合，但复制进入的部分仍受 AGPL 约束，必须保留许可证、提供对应源码，并在该部分支持网络交互时履行网络源码提供义务。若 Here I am 未来闭源或采用不兼容分发方式则不能这样复用。当前策略仍是借鉴架构、以自有接口和测试独立重写；若确实需要直接搬代码，再单独确认接受 AGPL 边界。
- `larashero3-dotcom/lieflat-charts` 使用 PolyForm Noncommercial 1.0.0，商业使用需要另行许可。当前仅作为本地视觉研究样本；生产图表直接基于 Apache ECharts / Chart.js 或 Flutter 图表库重新实现，不复制它的模板代码、SVG 几何或动效骨架。

## 2. 本地参考仓库

`lieflat-charts` 已浅克隆到本机忽略目录：

```text
.dev-agent/reference-repos/lieflat-charts
```

- 来源：`https://github.com/larashero3-dotcom/lieflat-charts`
- 当前 HEAD / 标签：`1547bb3fbb1c707786db743168f6fd099f3b8138` / `v1.2.0`（2026-08-14 已 fast-forward 同步）
- 目录被 `.dev-agent/` 规则忽略，不进入 Here I am Git 提交。
- 重点文件：`catalog.md`、`report-catalog.md`、`templates/`、`templates/reports/`、`color-presets.js`、`mono-tokens.js`、`docs/assets/preview-*.png`。
- 此次上游更新没有扩充原 49 种图表目录，主要新增 12 组双语报告模板与 report mode；它们用于研究首页信息密度和叙事编排，不改变生产端独立重写的许可边界。

`kankan-shoucang` 本轮通过 GitHub 文件接口审计，没有克隆或复制到生产仓库。

## 3. `kankan-shoucang` 值得借鉴的部分

### 3.1 单链接、用户触发的导入边界

它不是收藏夹批量爬虫，而是只处理用户手动拖入的一条公开笔记：

1. 识别并限制允许的小红书页面域名；
2. 匿名请求公开页面，显式不携带 credentials；
3. 从页面初始状态找到笔记、图片和视频候选；
4. 图片 / 视频下载再次做 CDN 域名白名单、重定向限制、超时、内容类型和大小上限；
5. 临时 `.part` 成功后原子改名；
6. 本地 OCR / Speech 产出可搜索文字与分段文稿；
7. 失败即停，不回退到用户浏览器登录态。

这套“手动单条 + 最小权限 + 失败不越界”的行为契约很适合白板内容捕获。

### 3.2 可复用的是接口思想，不是 AGPL 代码

独立实现时保留以下测试行为：

- URL canonicalize 与 provider / canonical id 稳定身份；
- 页面域名和媒体 CDN 分开白名单；
- 最多重定向次数、响应超时、HTML / 图片 / 视频大小上限；
- 内容类型校验，拒绝 HTML 伪装媒体；
- 流式写入、临时文件与原子完成；
- 原始 URL、解析版本、媒体来源和失败原因可审计；
- transcript 使用 `{start, duration, text}` 分段，而不是只有一坨全文；
- 本地服务只监听 loopback；Agent 检索默认只读。

默认不直接复制的重点文件包括 `anonymous-note-resolver.mjs`、`video-import.mjs`、`media-import.mjs` 及其测试实现。若后续决定接受 AGPL 覆盖，则必须连同许可证、版权说明、对应修改源码与网络源码入口一起设计，不能只摘几段代码而不保留义务。

## 4. 与 Here I am 现状的重合与缺口

现有代码已经有主干：

```text
系统分享
  → ReadingShareParser
  → ReadingCaptureService
  → reading_item / 聊天 addendum
  → ReadingFetchCoordinator
  → platform ReadingFetcher
  → 正文文件 + 图片 OCR
```

已有能力：

- 能识别小红书短链、微信文章和通用网页；
- `ReadingFetcher` 已是按平台分发的接口；
- 小红书已有隐藏 WebView 抽取正文、图片和部分评论；
- 图片下载与 OCR 已存在；
- 捕获后形成阅读条目，并能在聊天卡片里打开。

主要缺口：

- 当前小红书 fetcher 依赖用户登录 WebView，尚无“匿名单链接优先、失败即停”的路径；
- `ReadingFetchResult` 只有文章与图片字段，没有视频原地址、播放模式、时长、文稿与时间段；
- 隐藏 WebView 尚未把视频源抽取到领域结果；
- 当前 `reading_item` 属于 SharedLife 实体，桌面白板还需要映射到统一 `SourceContent / Card`，不能继续新增一套视频专用数据；
- 尚无哔哩哔哩与 YouTube provider。

因此不另建“看看收藏子系统”。正确方向是把现有 `ReadingFetcher` 演进为更宽的 `ContentResolver` / `VideoResolver`，并保持旧阅读抓取兼容。

## 5. 三个平台的视频方案

### 5.1 统一返回

每个 provider 至少返回：

```text
provider
canonical_id
canonical_url
title / author / description / thumbnail
duration_ms
playback_mode
embed_url 或可刷新播放引用
seek_capability
timeline_status
default_transcript_track_id（可空）
availability_status
rights_policy
resolver_version
```

白板只认统一结果；平台签名、短链跳转、临时地址刷新留在 resolver 内部。

播放器与字幕由统一消费契约收口：`PlayerAdapter` 必须提供 duration、current position 与 `seek(position)`；`TranscriptTrack` 保存来源、语言、版本与带时间码的 segments。点击字幕跳转播放器，播放器进度反向高亮字幕，二者都可以建立稳定点 / 时间段 Anchor。字幕优先使用平台或创作者提供版本，其次允许用户导入 SRT / VTT；只有媒体权利允许时才做本机 ASR。

### 5.2 小红书

第一阶段：

- 分享或粘贴单条公开笔记链接；
- 展开短链并建立 note id；
- 匿名解析标题、作者、正文、图片、视频候选；
- 媒体 URL 只允许小红书 CDN；
- 成功后优先在线播放，是否保存本地副本由设置、来源权限和大小限制共同决定；
- 优先取得创作者提供的字幕；没有字幕时允许用户导入，只有媒体权利允许才在用户设备或核心上本地转写并保存时间段。

现有登录 WebView 保留为兼容实验，不作为无提示回退。匿名失败后由用户选择“仅保存链接”或“本次允许使用已登录页面”。

### 5.3 哔哩哔哩

第一阶段不做裸媒体下载：

- 解析 `BV / av / bangumi` 链接为稳定 id；
- 取得允许公开读取的元数据；
- 使用官方 `player.bilibili.com/player.html` 外链播放器，支持 `bvid / aid / cid / p / t`；
- 白板时间 Anchor 保存 `canonical_id + page/cid + start_ms/end_ms`；
- 多 P 视频每一 P 作为同一 SourceContent 下的子段，不复制成互不相关的卡。

开放平台目前主要面向账号授权与稿件管理。直接流媒体解析、下载和字幕 / 弹幕抓取应单独做规则与稳定性评估；若官方字幕不可得，则以用户导入或有权 ASR 补齐，不能只因播放器能打开就宣称已达到研读播放级。

### 5.4 YouTube

第一阶段严格使用官方能力：

- 从常规、短链和 Shorts URL 解析 video id；
- YouTube Data API 读取标题、频道、封面、时长与可嵌入状态；
- IFrame Player API 在消费视图播放，并用 player time 生成时间 Anchor；
- 不下载、缓存、备份或分离 YouTube 音视频，不提供离线播放；
- 字幕 / transcript 只有在官方能力与权限允许时接入；也允许用户导入自有字幕，或在用户对媒体拥有相应权利时本机转写。若三种路径都不可用，则仅保存为“需要字幕”的链接卡，不纳入正式研读播放支持。

## 6. `lieflat-charts` 首页借鉴

### 6.1 可以借鉴的设计原则

- 先判断数据形状，再选择图形，不先挑一张好看的皮；
- 首页属于几秒快读，采用 Glance 的阅读速度，但不照搬其模板；
- 标题直接说结论，图表是证据，不让用户自己猜“这张图想表达什么”；
- 一张小图只回答一个问题；
- 真实记录才有 hover / 点击，不给装饰元素制造假交互；
- 色彩只承担状态和重点，春雨昼眠仍由自己的 token 控制。

### 6.2 首页第一轮候选映射

| 首页模块 | 数据形状 | 参考图型思想 | 自有实现建议 |
|---|---|---|---|
| 作息 / 情绪 / 阅读节律 | 14–30 天单序列或日区间 | G1 Range Capsules、F2 Hairline Line | ECharts / Flutter 折线与区间，自有春雨 token |
| 一周负荷 | 星期 × 小时 × 数量 | G14 Single Axis、F10 Dot Heat | 小型热力图，点击进入日程 |
| 生活变化 | 有正负的分类变化 | G10 Diverging Bar | 横向正负条，叠加林埃判断 |
| 目标进度 | 单值 0–100% | F11 Tick Gauge、G18 Counter | 数字 + 极简进度，不做仪表盘装饰 |
| 卡片来源 / 记忆构成 | 100% 构成 | G4 Dot Waffle、F4 Tick Donut | 点阵优先，类别少才用环形 |
| 时间去向 / 内容空间 | 两层层级 + 权重 | F13 Treemap | ECharts treemap，点击进入对应空间 |

不建议把 B1 / B2 力导向关系图缩进首页。它们适合独立观察面或白板分析页，不适合几秒快读模块。

### 6.3 许可策略

当前只能：

- 在本机打开模板、截图和动效做设计研究；
- 记录数据形状、信息层级、标题策略和交互原则；
- 使用原始第三方库（Apache ECharts、MIT Chart.js）按各自许可重新实现。

若以后希望直接使用 Lieflat 模板代码或其派生图形，需要取得商业许可，或确认 Here I am 的分发形态始终符合 PolyForm Noncommercial；在此之前不进入生产代码。

## 7. 建议实施顺序

1. 先扩展统一 SourceContent / VideoSourceProfile 契约和 resolver fixture；
2. 在现有 ReadingShareParser 中识别 XHS / Bilibili / YouTube 稳定身份；
3. 先做三平台“链接级”，确保卡片库与跨端同步成立；
4. 建立统一 PlayerAdapter、TranscriptTrack 和时间 Anchor fixture，再分别接官方播放器与合法字幕来源；
5. 以独立重写实现小红书匿名单链接 resolver，并与现有登录 WebView 做显式双路径；
6. 以“小红书 / B站 / YouTube 各一条 fixture 都能双向时间跳转、字幕高亮、建立 02:14–02:36 Anchor 并在重启后恢复”为研读播放级验收；缺字幕时必须清楚降级；
7. 最后评估小红书本地化、OCR / 文稿和可恢复下载；
8. 首页先用 6–8 个真实模块重做伪前端，再决定哪三种图形进入 Flutter / 桌面生产实现。

## 8. 一手参考

- `https://github.com/feitangyuan/kankan-shoucang`
- `https://github.com/larashero3-dotcom/lieflat-charts`
- YouTube IFrame Player API：`https://developers.google.com/youtube/iframe_api_reference`
- YouTube Data API Videos：`https://developers.google.com/youtube/v3/docs/videos/list`
- YouTube Developer Policies：`https://developers.google.com/youtube/terms/developer-policies`
- 哔哩哔哩外链播放器：`https://player.bilibili.com/`
- 哔哩哔哩开放平台：`https://openhome.bilibili.com/doc`
