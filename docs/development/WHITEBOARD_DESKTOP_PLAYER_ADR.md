# 桌面视频播放器路线 ADR

> 状态：已定稿（2026-08-16，W4 桌面播放器闭环轮）
> 决策者：W4 工作流；依赖新依赖的后续路线以「契约变更请求」形式交 W0 集成评审（见 `W0_INTEGRATION.md`）。
> 背景出处：`docs/development/whiteboard-workstreams/W4_VIDEO.md`「桌面播放器方案待 W0 决策（ADR 待选项）」。

## 1. 上下文与约束

- 产品目标是**合规在线播放**：可控时间轴（读位置/时长/seek）、可靠字幕、双向时间跳转、可恢复 Anchor；不绕过 DRM / 登录 / 付费，不下载。
- 能力矩阵中，唯一具备**公开稳定可控播放接口**的生产平台是 YouTube（官方 IFrame Player API：`playVideo / pauseVideo / seekTo / getCurrentTime / getDuration`）。Bilibili 可外链嵌入但无稳定第三方控制接口，小红书无可嵌入播放器 —— 两者维持诚实 link-only。
- 本轮分支约束：**不在本分支改 pubspec**；如路线需要新依赖，先向 W0 追加契约变更请求。
- 桌面形态：Windows 平台工程（W6 补入）可原生构建；`webview_flutter` 不支持 Windows。

## 2. 候选路线

| 路线 | 描述 | 新依赖 | 本轮可闭环真实在线播放 |
|---|---|---|---|
| A. Windows 原生 WebView | 引入 `webview_windows` / `desktop_webview_window`，在 Windows 原生窗口内嵌 WebView2 + YouTube IFrame | 需要（归 W0） | 否（依赖未批准，pubspec 不可动） |
| B. Web IFrame（Flutter Web 桌面形态） | `flutter run -d chrome`，`dart:js_interop` 直驱官方 IFrame API；`HtmlElementView` 承载 | 无（`dart:js_interop` 属 SDK） | **是** |
| C. 外部播放器降级 | 无内嵌播放器，点击在系统浏览器打开；仅保留 SRT/VTT 导入 + 时间轴 + 本地 Anchor | 无 | 否（无可控播放面） |

## 3. 决策：本轮采用 B（Web IFrame），A 作为原生后续路线，C 作为合规保底

**B 是本轮唯一可在「零新依赖 + 合规 + 真实可控播放」三者下同时成立的路线：**

1. **能力事实**：YouTube IFrame API 是矩阵中唯一 `supported` 的可控接口；`WebYouTubePlayerAdapter`（`lib/domain/whiteboard/video/web_youtube_player_adapter.dart`）已用官方 API 实现 load / play / pause / current / duration / seek / timeEvents，且在 W4 首轮已通过真实 Chrome 窗口验证（landing、65:35 布局、字幕渲染、播放按钮、字幕点击 seek）。
2. **零新依赖**：`dart:js_interop` 属 Dart SDK；Flutter Web target 与 `web/` 平台工程已在仓库中；不需要 pubspec 变更，不与「pubspec 变更归 W0」的纪律冲突。
3. **合规**：只用官方嵌入与公开字幕端点（timedtext），不下载、不绕 DRM/登录/付费；平台自身限制（地区、登录）在 IFrame 内由平台 UI 呈现。
4. **桌面窗口验收**：Chrome 桌面窗口即真实桌面窗口；与 W4 首轮「真实 Chrome 窗口验证」方法论一致。
5. **失败诚实**：平台字幕自动获取通过公开 timedtext 端点进行；网络 / 跨域 / 无字幕时诚实标记「需要字幕」并给出原因，不伪造支持。

**A（Windows 原生 WebView）作为推荐的原生后续路线**：解决「Flutter 原生窗口内嵌播放器」的最终形态，但必须引入第三方依赖（`webview_windows` 等，维护状态需 W0 评估）——已以「契约变更请求」追加至 `W0_INTEGRATION.md`，W0 批准依赖后再实现 native adapter。本机环境观察：YouTube 流量需经系统代理（127.0.0.1:7890）；timedtext 端点对非浏览器 TLS 指纹返回 200 空 body（bot-block），因此 native HTTP 拉字幕需在 W0 路线评审中一并评估浏览器内核内请求方案。

**C 维持为合规保底与现行行为**：Bilibili / 小红书即 C 的现行实现（link-only + 诚实「链接模式」占位）；不伪造可控播放。

## 4. 后果与风险

- 桌面播放器 UI 与领域层（PlayerAdapter / TimedTextTrack / Anchor / VideoAnnotationService）**与路线无关**，A 落地时只需新增一个 Windows 平台的 adapter 实现与 surface，UI/VM/服务层复用。
- B 的形态是 Chrome 窗口内的 Flutter Web；在未内置 WebView 的原生壳场景（Windows 原生窗口）不可用，这正是 A 的接续理由。
- 平台字幕自动获取的跨域行为以运行时实测为准：失败时诚实显示「需要字幕」+ 原因，并可用户导入 SRT/VTT（本地能力，不依赖平台）。
- 时间范围 positionSpec（`time_range` schema）仍是 W4 提出的契约提案，维持 W0 评审待决，本 ADR 不扩大其范围。
