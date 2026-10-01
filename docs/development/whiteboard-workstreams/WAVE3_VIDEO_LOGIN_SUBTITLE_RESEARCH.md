# Wave 3 — Bilibili 登录、时间桥与字幕调研

> 状态：方案调研完成，尚未实现；不绕过登录、DRM、会员、地区或风控。

## 结论

- 当前“可播放但时间研读受限”是适配器能力限制：站外播放器没有已验证的 `currentTime / duration / seek / time events`，不是 Bilibili 天生不能做时间笔记，也不是网络失败。
- 推荐主路线是“Bilibili 顶层原页 + 固定 WebView2 User Data Folder + 运行时媒体桥”。用户在应用内完成一次真实网页登录，Cookie 与网页存储随专用 profile 跨重启保留；平台令牌过期或风控时仍需重新验证。
- 只有页面确实暴露并验证可读写的标准 `HTMLMediaElement` 时才上报时间能力；DOM 变化、跨域隔离或受保护播放使桥失效时立即降级。不得抽取媒体地址或改用自有播放器规避平台约束。
- 播放、时间桥、字幕 resolver 是三个独立能力。字幕不可用不阻止点 / 区间 Anchor；时间桥可用也不代表字幕一定可拉取。

## Bilibili 持久登录与时间能力

`webview_flutter_windows` 支持在第一个 controller 前初始化固定 `userDataPath`，并提供脚本、Web message 与 Cookie 能力；WebView2 User Data Folder 会保存 Cookie、DOM storage、权限与缓存。登录页和播放页应共享应用专用 UDF，并提供显式退出 / 清除站点数据；Cookie 不写日志、数据库、备份或遥测。

站外播放器继续作为轻量 / 降级入口；顶层 `www.bilibili.com/video/...` 最接近网页登录后的合法播放效果，并可尝试窄媒体桥。桥只读写 `ready/currentMs/durationMs/paused` 与 `seek/play/pause`，监听标准媒体事件并处理 SPA 更换节点；握手与读写验证成功前不得声称完整时间研读。

依据：[WebView2 User Data Folder](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder)、[Windows WebView2 控件说明](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/webview2)、[webview_flutter_windows](https://pub.dev/packages/webview_flutter_windows)。

## YouTube 字幕

- 官方 `captions.list` 需要 OAuth；`captions.download` 只适用于当前用户拥有编辑权限的视频，不能覆盖任意公开视频 CC，但可输出 VTT / SRT 等格式。
- 任意公开视频字幕只能走实验性网页 extractor；当前 `captionTracks` 与更成熟的 yt-dlp 都不是 YouTube 公开稳定 API。若采用 yt-dlp，必须固定版本、能力探测、显式标注非官方，并把 PO Token / Cookie / extractor 变更归为可恢复或需用户处理的失败，而不是“网络错误”。
- 不静默导出用户常用浏览器的全站 Cookie；账号模式需要单独授权与风险提示。SRT / VTT 本地导入永久保留。

依据：[YouTube Captions 指南](https://developers.google.com/youtube/v3/guides/implementation/captions)、[captions.download](https://developers.google.com/youtube/v3/docs/captions/download)、[yt-dlp 字幕选项](https://github.com/yt-dlp/yt-dlp/blob/master/README.md#subtitle-options)、[yt-dlp YouTube extractor](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#youtube)。

## Bilibili 字幕

Bilibili 公开开放平台目录中未发现面向普通观看者的通用字幕下载 API。成熟非官方实现可参考 yt-dlp Bilibili extractor：按 BV / CID 发现 `data.subtitle.subtitles` 与 `subtitle_url`，解析 Bilibili JSON cue；接口可能返回 `need_login_subtitle`。这条路线必须标明“非官方、易失效、可能要求登录”，优先在已登录页面同源上下文内请求，只把轨道元数据与正文传回应用，不导出 Cookie。

依据：[Bilibili 开放平台](https://openhome.bilibili.com/doc)、[yt-dlp Bilibili extractor](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/bilibili.py)。

## 统一 resolver 与失败分类

统一管线：`discover(source, authContext) → Track`，`fetch(track) → bytes`，`parse(JSON/VTT/SRT) → normalized Cue`。只缓存规范化 cue、来源版本与抓取时间，不缓存 signed URL 或 Cookie；signed URL 过期后重新 discover。

至少区分：`no_track`、`login_required`、`permission_denied`、`region_or_entitlement`、`risk_control`、`network`、`signed_url_expired`、`parser_changed`、`empty_or_invalid_track`、`drm_or_protected_playback`。

## 最小真人验收

1. 应用内登录 Bilibili，完全退出并重启，确认同一合法网页登录态仍在；日志中无 Cookie / token。
2. 公开片与登录后可观看片分别验证播放；页面时间桥成功时读 duration/current、seek 到指定秒并创建 Anchor，失败时明确降级。
3. 点 / 区间 Anchor 重启后仍能回跳；无字幕视频仍可标注。
4. 分别验证 Bilibili 自动字幕、YouTube 手工 CC、YouTube 自动 CC、无字幕、断网与本地 SRT / VTT。
5. 退出并清除 Bilibili 站点数据后，受限内容恢复为登录要求；验证码、会员、地区或 DRM 场景不自动规避。
