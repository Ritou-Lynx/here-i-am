# W4 — 视频、字幕与时间 Anchor

**状态**：F4 Windows 原生产品闭环已完成并通过真实窗口验收（2026-08-19 返修）；Flutter Web 仅为技术验证
**权威范围**：平台 provider、`PlayerAdapter`、字幕轨、双向时间跳转、点 / 区间 Anchor、标注恢复
**当前目标**：Windows 原生 `webview_flutter_windows` + WebView2 + 官方 YouTube IFrame API 为 MVP 主路线；Android adapter 保留但不属于 F4 主验收。
**拥有路径**：`lib/domain/whiteboard/video/`、`lib/ui/whiteboard/video/`、`test/domain/whiteboard/video/`、`test/ui/whiteboard/video/`
**共享契约**：只读 `PlayerAdapter`、`TimedTextTrack`、`AnchorContract`、`CardContract`；新增 `time_range` positionSpec 标准 schema（契约变更提案见下）；不改变 W0 `PlayerCapability` 结构或语义。
**明确不做**：绕过 DRM / 登录 / 付费限制、无授权下载、把逐条播放事件写入聊天或记忆、另建视频专用卡片库。

## F4 Windows 产品返修（2026-08-19，待 W0 集成）

### 稳定身份与 Windows 字幕补修（2026-08-19）

- YouTube `contentHash` 只由稳定的 `provider + canonicalId/videoId` 生成，不再包含用户粘贴的 URL 形态、`t`、`si` 等导航参数。`watch`、`youtu.be`、`shorts` 及带参数的等价链接连续确认后仍为 **1 Source / 1 SourceVersion / 1 Card**。
- Windows 原生 `SourceStudyScreen` 会尝试 `YouTubeTimedTextService`。平台轨缺失、请求失败或解析失败时显示具体原因和「需要字幕」，并保留选择文件或粘贴 SRT/VTT 的入口；不承诺任意 YouTube 视频一定有字幕。
- Windows 原生集成不再注入 `initialTrack`：测试从真实「导入字幕」弹窗粘贴 VTT，再验证 cue seek、播放反向高亮、Annotation/Anchor、关闭数据库与重启恢复。平台字幕自动获取触发条件另由可注入 fake service 覆盖，避免网络波动污染自动化结果。
- Fixture surface 的播放态图标已修正为暂停图标、暂停态为播放图标；Fixture 仍仅用于自动化测试。
- 本次补修定向测试 **63/63**，Windows 原生集成 **1/1**；真实构建并启动 `memex.exe`，产品播放器仍为 WebView2 YouTube surface，非 Fixture。

- `/sources/:sourceId` 已从占位页替换为真实 `SourceStudyScreen`：只经 `UnifiedCardRepository` 加载 Source、当前 SourceVersion、关联 Card 与不可变正文对象；普通来源显示真实正文、元数据和版本状态，视频来源按 Source provider/metadata 构造 embed URL 与 `PlayerAdapter`，产品路径没有 Fixture。
- Annotation 已接入统一 Repository：严格按“先建 Card → 关联 Source → 设置 `CardKind.annotation` 与完整 anchor presentation”保存；anchor 保留 `sourceId/sourceVersionId/start/end/status`，用户与林埃分别保存 `ownerSpace/createdBy`。Session JSON 只保留播放位置与 Dock 偏好，不再充当卡片库。
- 标注卡可从顶层统一卡片查询和白板 Repository 查询读取；关闭数据库再打开仍可恢复。SourceVersion 变化时一律保留旧 version 身份并标记 `orphaned`；仅“时间仍落在新时长内”不构成 re-anchor 证据，必须有明确媒体同一性与定位证据或用户确认。
- 字幕优先平台 timedtext，失败或不存在时显示「需要字幕」；用户可直接选择或粘贴 SRT/VTT，损坏内容返回解析错误。cue 点击 seek、播放位置反向高亮和点/区间 Anchor 沿用既有真实逻辑。
- `ContextDock` 支持收起、右侧/底部停靠、拖动比例，并按 source 保存比例与方向。
- `/import` 新增 YouTube URL-native 零写入预览：确认前 Repository 中没有 Source/Card；确认后复用 F3 `commitResult` 创建唯一 Source/SourceVersion/Card，随后直接打开 `/sources/:sourceId`。没有第二套视频身份；卡片库点击仍由拥有者最终接线。
- Windows 采用 `webview_flutter_windows 1.1.1`：真实原生窗口中完成 load/play/pause/current/duration/seek/timeEvents，播放器 surface 不使用 Fixture。定向测试 **88/88**，Windows 原生集成 **1/1**；详细 CMake 构建 0 warning / 0 error。

### 本次三平台事实

| 目标 | 本次状态 | 能力边界 |
|---|---|---|
| Windows 原生 App | **真实 WebView2 内嵌播放通过**：Windows device 构建并启动 `memex.exe`，官方测试视频完成 duration/current/seek/play/timeEvents、字幕双向同步、Annotation/Anchor 与重启恢复 | MVP 主验收；Runtime/网络/禁止嵌入时显示真实错误，不伪装能力 |
| Flutter Web | 保留真实 IFrame 技术验证 | 不是 Windows 产品闭环；平台字幕抓取可能受 CORS 限制，可导入 SRT/VTT |
| Android WebView | 既有 adapter 保留；本轮未做真机验收 | 不属于当前 Windows Desktop MVP 主验收，也不列为 F4 主要未完事项 |

### Windows 原生播放器依赖选型（已按本轮授权落地）

- 采用：`webview_flutter_windows 1.1.1`（BSD-3-Clause，维护中，最低 Flutter 3.44 / Dart 3.12），优于约两年未发布的 `webview_windows 0.4.0`。两者 dry-run 都只新增一个直接依赖；最终没有顺带升级其它包。
- 影响：新增 Windows plugin/C++ 与固定 NuGet/WebView2 构建链；只改 pubspec、锁文件和自动生成的 Windows plugin 注册配置，不改 schema 60、`*.g.dart` 或冻结路由。
- 构建事实：首次 NuGet 还原超过外层 4 分钟超时，但固定 `nuget.exe` 与 WebView2/WIL 包已完整缓存；随后 VS 18 CMake 详细构建 0 warning / 0 error。命令尾部“NuGet 未全局安装”为噪声，不影响插件本地还原与 exe 构建。
- 回退：Runtime 缺失、网络页面失败、YouTube 101/150 禁止嵌入或 153 来源错误时进入诚实失败态，不伪装 seek、字幕或当前位置。本机 Runtime 存在，未通过卸载系统组件做破坏性缺失实测。

### 集成请求与未闭环

1. F0/W0 或卡片库拥有者需把 `CardKind.source` 的正常点击入口接到冻结路由 `AppRoutes.sourceStudyPath(sourceId)`；F4 按本轮禁改清单没有修改 `card_library_screen.dart`，因此当前可由冻结 URL 进入，但顶层卡片库点击仍不是完整产品入口。
2. W0 集成时接受 Windows 依赖与自动生成 plugin 注册变更；无需 schema 或共享 Card/Source/Anchor 身份变更。
3. 平台字幕优先逻辑已存在，但本次真实 Windows 验收使用用户导入 VTT；YouTube 平台轨在具体视频/地区/网络条件下仍可能不可用，UI 保持「需要字幕」与导入入口。

## 历史技术验证（2026-08-16 Flutter Web，不计 Windows MVP 验收）

- 这一轮只证明 Flutter Web + 官方 YouTube IFrame API 的技术可行性；返修后 ADR 已改为 Windows 原生 WebView2 主路线。Chrome 窗口不再被描述为 Windows Desktop 产品闭环。
- **YouTube 真实在线播放全链路**（真实 Chrome 窗口 + 真实视频 dQw4w9WgXcQ，自动化集成验收 `integration_test/whiteboard_w4_youtube_desktop_test.dart`）：
  - load → duration=214000ms（真实元数据）✓
  - seek → 30000ms（可控时间轴真实生效）✓
  - play → 位置实时推进 ✓（自动播放策略：未静音需用户手势，验收先 mute 再 play，属平台事实非缺陷）
  - pause → 位置停住 ✓
  - 字幕 cue 点击跳转 / 反向高亮 / Anchor / 重启恢复：由 198 项领域+UI 测试 + 真实浏览器 localStorage 重启恢复集成测试锁定（见下）。
- **YouTube 平台字幕自动获取（timedtext）已实现**：`YouTubeTimedTextService` + `HttpTimedTextTransport`——watch 页（失败回退 embed 页）解析 `captionTracks`（含签名 baseUrl），按首选语言（zh → en → 首个）选轨，`fmt=json3` 拉取并解析 cues；ASR 轨诚实标记 `partial`，人工轨 `reliable`。**Web 路线实测：浏览器跨域（CORS）限制导致自动获取被拦**，UI 诚实显示「需要字幕」+ 原因并保留 SRT/VTT 导入；native（Android / 未来 Windows 原生）无 CORS，自动获取可用。任何失败均返回诚实 error，**绝不伪造字幕**。
- **重启恢复跨平台**：`VideoSessionStore` 抽象（native=临时目录 JSON 文件，web=`localStorage`），标注创建/暂停时自动保存；真实 Chrome 中验证了「创建标注 → localStorage 落盘 → 新实例恢复」。
- `WebYouTubePlayerAdapter` 新增 `setMuted`（标准播放器控制，用于自动播放策略下的程序化播放验证）。

## Provider 能力矩阵（接口事实，不等同平台验收）

| 维度 | 小红书 | Bilibili | YouTube |
|---|---|---|---|
| 可嵌入播放器 | 无官方嵌入 | **partial**：存在 `player.bilibili.com/player.html` 外链嵌入，但非官方稳定第三方嵌入 API | supported：官方 IFrame API |
| 可控播放接口（公开稳定） | unsupported | **unsupported**：可嵌入 ≠ 可控制，无稳定公开播放控制接口 | supported：playVideo / pause / seekTo / getCurrentTime / getDuration |
| 读当前位置 + 时长 | unsupported | unsupported | supported |
| seek | unsupported | unsupported | supported |
| 平台可能提供字幕 | notConfirmed | partial（部分视频 AI 字幕） | supported（timedtext 运行时自动获取已实现；Web 下受 CORS 限制，native 可用） |
| 用户导入 SRT/VTT | supported（本机） | supported（本机） | supported（本机） |
| 当前 source 已加载可用字幕轨 | **notConfirmed（运行时）** | notConfirmed（运行时） | notConfirmed（运行时） |
| 反向高亮 | unsupported（无可读位置） | unsupported（无可读位置） | partial（需已加载字幕轨） |
| 当前时间 Anchor | unsupported（无可读位置） | unsupported（无可读位置） | partial（需可读位置） |
| 合规播放（无 DRM 绕过） | supported | supported | supported |

**完整研读门槛**：静态 `PlayerCapability.isPlaybackStudyCapable` 仍不由静态声明自动满足（YouTube 静态 `hasTranscript=false` 维持不变，避免静态谎报）；运行时以 `VideoStudyAvailability.isStudyReady`（可读位置 ∧ 已加载字幕轨）判定，自动获取成功后自然升级为就绪。

## Fixture 与真实 provider 边界

- **FixturePlayerAdapter**（`fixture`）：测试 / 演示 provider。声明全能力（含 `hasTranscript=true`）用于可测试的闭环验证，**不属于生产 provider 列表**（`ProviderCapabilityMatrix.productionProviders` 只含 youtube / bilibili / xiaohongshu）。
- 测试明确区分：Fixture 闭环（可读位置 + 字幕 + seek + Anchor + 恢复）、真实 provider 能力契约（Bilibili 不可控、小红书无播放面、YouTube 静态无字幕声明）、以及平台字幕自动获取（fixture 驱动的解析测试 + 真实浏览器诚实失败/成功路径）。

## 实现

**领域层（`lib/domain/whiteboard/video/`）**
- `provider_capability_matrix.dart` — 三平台能力矩阵（7 个独立维度）+ `capabilityFor()` + `productionProviders` / `testProviders` 分离
- `video_availability.dart` — 运行时研读可用性模型 `VideoStudyAvailability` + `CapabilityConsistency` 一致性校验
- `subtitle_parser.dart` — SRT / VTT 解析器
- `timedtext_transport.dart` — `TimedTextTransport`（可注入）+ `HttpTimedTextTransport`（`package:http`，web 用 fetch、native 用 IO）
- `youtube_timedtext_service.dart` — `YouTubeTimedTextService`：watch/embed 页 `captionTracks` 解析、语言选轨、JSON3 解析、诚实失败语义
- `time_range_anchor_spec.dart` — `time_range` positionSpec 标准 schema
- `player_sync_controller.dart` — 双向同步
- `video_annotation_service.dart` — Anchor + Annotation Card + 会话保存 / 恢复；版本变化默认保留旧身份并 orphan
- `fixture_player_adapter.dart` — 测试 / 演示播放器（测试能力）
- `youtube_player_adapter.dart` — YouTube IFrame API（Android `webview_flutter`，非本轮主验收）
- `windows_youtube_player_adapter.dart` — Windows WebView2 + YouTube IFrame API（F4 MVP 主实现）
- `web_youtube_player_adapter.dart` — YouTube IFrame API（Flutter Web `dart:js_interop`，ADR 路线 B 的播放器；含 `setMuted`）
- `platform_player_adapters.dart` — Bilibili / 小红书 link-only adapter

**UI 层（`lib/ui/whiteboard/video/`）**
- `video_study_screen.dart` — 65:35 左右 / 70:30 上下可拖研读布局；`hasAnyPlaybackSurface` 判定 link-only；注入 `sessionStore` / `timedTextService`
- `widgets/context_dock.dart`、`subtitle_list_view.dart`、`timeline_anchor_bar.dart`、`annotation_editor.dart`、`video_player_panel.dart` — 字幕列表显示自动获取失败原因；dock 头显示获取中 / 平台字幕状态
- `view_models/video_study_view_model.dart` — 运行时 availability、YouTube 平台字幕自动获取（`SubtitleAutoFetchStatus`）、`VideoSessionStore` 持久化
- `session_store.dart` / `session_store_io.dart`（文件）/ `session_store_web.dart`（localStorage）
- `video_study_demo.dart` — 桌面 / web 验证入口（web 自动获取字幕，失败诚实「需要字幕」）

## 验证

- F4 返修定向领域 / 数据 / UI：88/88 通过；Windows 原生集成：1/1 通过。
- Windows 集成由 `flutter test ... -d windows` 构建并启动真实 `memex.exe`，测试视频不是 Fixture；覆盖 duration/current/seek/play、字幕双向同步、Annotation/Anchor、数据库关闭与重建恢复。
- VS 18 CMake 详细构建成功，0 warning / 0 error；critical-fixes 构建守门通过。
- 验收主机 WebView2 Runtime 为 151.0.4129.93；生成的 Debug `memex.exe` SHA-256 为 `D1B9F80A15E4FD1BE3036FE95F8B5D32632E10DE1983985C31BD892C552EAE36`。
- 全仓 `flutter analyze --no-pub` 在 4 分钟外层时限内无输出并超时；覆盖全部本轮 16 个 Dart 文件的精确定向 analyze 为 0 error / 0 warning、13 条 info，未把全仓超时伪报为通过。
- 2026-08-16 的 198 项与 Chrome 3 项属于历史 Web 技术验证，保留作回归依据，但不替代 Windows 验收。

## 受限状态（如实）

- **平台字幕仍是运行时能力**：真实 Windows 主闭环使用用户导入 VTT；平台轨缺失、损坏或请求失败时仍显示「需要字幕」，不能把 provider“可能有字幕”当成当前 Source“已有字幕”。
- **Windows 环境**：本机 WebView2 存在且真实播放通过；Runtime 缺失走显式错误分支，但未卸载系统 Runtime 做破坏性实测。首次固定 NuGet 还原较慢，全局 NuGet 缺失会产生噪声。
- **自动播放策略**：未静音播放需要用户在 IFrame 内点击（平台事实）；程序化播放需先 `setMuted(true)`。

## 契约变更提案（提交 W0 集成评审）

1. `AnchorContract.positionSpec` 的 `time_range` 标准 schema（W4 定义了第一个结构化 position_kind schema）：`{ start_ms, end_ms, is_point, cue_id }`，实现见 `time_range_anchor_spec.dart`。
2. **Windows 依赖集成请求**：接受 `webview_flutter_windows 1.1.1`、锁文件和自动生成 Windows plugin 注册配置；不涉及 schema 或共享身份语义。
3. 建议 W0 评估：`PlayerCapability.hasTranscript` 的语义是否需要新增「平台字幕可自动获取」与「当前已加载字幕轨」的运行时字段（W4 当前以 `VideoStudyAvailability` 承载，不改共享结构）。

## 待集成提交

- 分支：`codex/whiteboard-f4-video-product`（返修提交，未 push / 未 merge）

## 未完事项

- 本机 ASR（仅内容权利允许时）
- 卡片库拥有者把 Source 卡点击接到已可用的 `/sources/:sourceId`
- 平台轨在更多真实 YouTube 视频、地区和网络条件下的覆盖验证
- 明确媒体同一性证据或用户确认后的 re-anchor 产品交互；当前默认只 orphan，不自动迁移
