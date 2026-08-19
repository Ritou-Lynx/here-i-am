# Windows 桌面视频播放器路线 ADR

> 状态：已实施并在真实 Windows 原生窗口验收（2026-08-19，F4 返修）
> 产品边界：白板 MVP 是独立 Windows Desktop 软件；Flutter Web 仅作技术验证，Android 不属于本轮主验收。
> 决策：Windows 采用 `webview_flutter_windows 1.1.1` + Edge WebView2 + 官方 YouTube IFrame API。

## 1. 上下文与约束

- 产品目标是**合规在线播放**：可控时间轴（读位置/时长/seek）、可靠字幕、双向时间跳转、可恢复 Anchor；不绕过 DRM / 登录 / 付费，不下载。
- 能力矩阵中，唯一具备**公开稳定可控播放接口**的生产平台是 YouTube（官方 IFrame Player API：`playVideo / pauseVideo / seekTo / getCurrentTime / getDuration`）。Bilibili 可外链嵌入但无稳定第三方控制接口，小红书无可嵌入播放器 —— 两者维持诚实 link-only。
- `/sources/:sourceId` 只消费 `UnifiedCardRepository` 的 Source → SourceVersion → Card，视频不建立第二套身份。
- Flutter Web 的 IFrame 只作技术验证，不能替代 Windows 原生 App 验收。

## 2. 候选路线

| 路线 | 描述 | 新依赖 | 本轮可闭环真实在线播放 |
|---|---|---|---|
| A. Windows 原生 WebView | 引入 `webview_flutter_windows`，在 Windows 原生窗口内嵌 WebView2 + YouTube IFrame | `webview_flutter_windows 1.1.1` | **是，已验收** |
| B. Web IFrame（技术验证） | `flutter run -d chrome`，`dart:js_interop` 直驱官方 IFrame API；`HtmlElementView` 承载 | 无（`dart:js_interop` 属 SDK） | 否，不是 Windows 产品窗口 |
| C. 外部播放器降级 | 无内嵌播放器，点击在系统浏览器打开；仅保留 SRT/VTT 导入 + 时间轴 + 本地 Anchor | 无 | 否（无可控播放面） |

## 3. 决策：采用 A（Windows WebView2），B 仅作技术验证，C 作为合规保底

依赖 spike 对比：

- `webview_flutter_windows 1.1.1`：维护中的 `webview_flutter` Windows 实现，BSD-3-Clause，最低 Flutter 3.44 / Dart 3.12；`pub add --dry-run` 只新增该直接依赖，无其它锁定包升级。
- `webview_windows 0.4.0`：BSD-3-Clause，约两年未发布；dry-run 可解析但维护性和当前 SDK 对齐弱于前者。
- 实际工具链为 Flutter 3.44.0 / Dart 3.12.0。采用前者后，VS 18 CMake/NuGet 详细构建 0 warning / 0 error；schema 保持 60，未改 `*.g.dart`。

`WindowsYouTubePlayerAdapter` 把最小 `player.html` 映射到 `https://hereiam-player.local`，在稳定 HTTPS origin 内加载官方 IFrame API。JS bridge 回传 ready/current/duration/error，每 200 ms 生成 `PlayerTimeEvent`；Dart 侧实现 load/play/pause/current/duration/seek。Runtime 缺失、WebView2 页面网络失败、YouTube 101/150 禁止嵌入和 153 来源错误均进入诚实失败态。

**C 维持为合规保底与现行行为**：Bilibili / 小红书即 C 的现行实现（link-only + 诚实「链接模式」占位）；不伪造可控播放。

## 4. 后果与风险

- `integration_test/whiteboard_f4_source_product_windows_test.dart` 以 `-d windows` 构建并启动真实 `memex.exe`，在 WebView2 Runtime 151.0.4129.93 上使用 YouTube 官方测试视频 `M7lc1UVf-VE`（非 Fixture），完成 30 秒 duration、20 秒 seek、静音播放后 current 推进、字幕点击与反向高亮、Annotation/Anchor 入库、关闭数据库与重建窗口后恢复；1/1 通过。
- 首次构建的固定 NuGet/WebView2 还原超过外层 4 分钟超时，但依赖完整落盘；随后详细 CMake 构建成功。命令行仍打印“NuGet 未全局安装”的噪声，不代表插件固定版本还原失败。
- 平台字幕自动获取的跨域行为以运行时实测为准：失败时诚实显示「需要字幕」+ 原因，并可用户导入 SRT/VTT（本地能力，不依赖平台）。
- 时间范围 positionSpec（`time_range` schema）仍是 W4 提出的契约提案，维持 W0 评审待决，本 ADR 不扩大其范围。
- SourceVersion 变化默认保留旧 `sourceVersionId` 并标记 `orphaned`；仅时间范围仍落在新时长内不构成 re-anchor 证据。只有明确媒体同一性与定位证据或用户确认后才允许 re-anchor。
