# Wave 3 C — Windows Desktop 视频研读 handoff

> 工作流：Wave 3 / C（VD-01、VD-02、VD-03）
> 分支：`codex/whiteboard-wave3-c-video`
> 基线：`65735eef188334e9f967b2c914da7ac83447ed44`
> 状态：隔离提交已完成，待集成与 Windows 真人验收

## 1. 本轮闭环

1. Windows 新增 `WindowsBilibiliPlayerAdapter`，只通过 WebView2 打开
   `player.bilibili.com/player.html?bvid=...`，用户给出的
   `BV1E8KV6QEu7` 可解析为 BV 身份并进入 App 内嵌播放面。
2. Bilibili 仍如实声明没有稳定公开的 `current / duration / seek`；播放器
   面与 Dock 同时标记“可播放 · 时间研读受限”，不把可嵌入等同于研读级。
3. 对所有能读当前位置的真实播放器，Dock 始终提供“在当前位置添加标注”、
   “开始区间 / 以当前位置结束并标注”；这条路径不读取字幕 cue。点 / 区间
   继续写既有 `time_range` Anchor + 统一 Annotation Card，并沿用 Repository
   与重启恢复链。
4. YouTube timedtext 会保留全部发现的 CC 轨道，默认选择后仍提供轨道下拉，
   可切换人工 / ASR 或不同语言轨；SRT / VTT 文件与粘贴导入保留。
5. 平台字幕失败新增稳定分类：无轨、地区 / 权限、网络、解析器失效；另有
   来源无效。UI 同时显示分类与可操作原因，不再把所有失败合成一句猜测。

## 2. 共享契约与数据语义

- 未修改 `PlayerAdapter`、`TimedTextTrack`、`AnchorContract`、Card / Source
  身份、数据库 schema、依赖或 `*.g.dart`。
- Bilibili adapter 复用现有静态能力矩阵：`canEmbedPlayer=true`，时间读写与
  seek 均为 false；没有伪造时间事件。
- YouTube 多轨 / 失败分类是 timedtext service 的向后兼容结果扩展；旧调用者
  仍可只读取 `track / error / isSuccess`。
- 字幕 cue 的标注入口现按 `canCreateTimeAnchorNow` 禁用；无法读取播放时间的
  Bilibili 不会因导入字幕而伪造可恢复时间 Anchor。

## 3. 自动化证据

- 新增 Bilibili BV 解析与合规 embed URL 单测，固定验收样例
  `BV1E8KV6QEu7`。
- YouTube 单测覆盖多轨发现、显式切轨、无轨、网络、地区 / 权限、解析器
  失效与无效来源分类。
- Widget 测试覆盖无字幕点 Anchor、无字幕两段式区间 Anchor、CC 轨选择器与
  失败分类呈现。
- 既有 Repository 重启测试继续覆盖 Annotation Card / Anchor 关闭数据库后
  恢复；本轮没有另建播放器私有便签。
- `git diff --check`：通过（仅工作区 CRLF 提示，无 whitespace error）。
- 直接 Dart 定向分析 `youtube_timedtext_service.dart`：`No issues found`；该检查
  发现并修正了显式切轨后 track id 构造的作用域问题。
- 定向 analyze / test：Flutter 全局锁等待超过 5 分钟且无输出，按主窗口指令
  仅中止本工作树自己的命令，未结束或干预其他 Flutter / Dart 进程；集成前
  必须在锁释放后重跑下列命令。

```text
flutter analyze --no-pub lib/domain/whiteboard/video lib/ui/whiteboard/video lib/ui/whiteboard/source_study_screen.dart
flutter test --no-pub test/domain/whiteboard/video/youtube_timedtext_service_test.dart test/domain/whiteboard/video/windows_bilibili_player_adapter_test.dart test/ui/whiteboard/video/video_study_widget_test.dart test/data/whiteboard/repository_video_annotation_store_test.dart
```

## 4. 真人验收与失败状态

1. 在 Windows App 导入 `https://www.bilibili.com/video/BV1E8KV6QEu7`，确认
   视频在 App 内出现且角标为“可播放 · 时间研读受限”；不能把角标写成研读就绪。
2. 用可控 YouTube 视频（不要求字幕）播放到任意位置，分别建点标注和两段式
   区间标注；重启后点标注卡应 seek 回起点。
3. 用明确有 CC 的 YouTube 视频确认轨道下拉可见、切轨后 cue 更新、cue seek
   与播放反向高亮仍成立。
4. 分别模拟 / 观察无轨、地区或登录限制、断网、页面结构变化，确认 UI 分类；
   每种情况下都应保留 SRT / VTT 导入。

## 5. 真实支持与未完事项

- 代码只使用平台允许的嵌入页；未下载媒体、去水印、读取登录态或绕过
  DRM / 付费 / 地区限制。
- Bilibili 的公开嵌入页、该 BV 在当前网络下是否允许播放，尚未在本隔离窗口
  真实启动 Windows `memex.exe` 验证；不能在合入前宣称真人通过。
- Bilibili 当前不能建时间 Anchor，这是平台公开控制能力不足导致的明确降级，
  不是待伪造的 UI 能力。
- YouTube 平台轨可受视频、地区、权限、网络和页面结构影响；自动化用固定响应
  验证分类与选择，真实样例仍需验收主窗口联网验证。
- 现有 `TimedTextTransport` 只返回 `String?` 或异常；HTTP 403 等没有可读响应体
  时仍可能归为 `network`，地区 / 权限分类依赖能够读取到平台限制页。这是当前
  transport 能力边界，不应把所有 403 都宣称为已精确识别。
- 若平台后续提供稳定 Bilibili 时间控制 API，应由 W0 审查后升级能力矩阵；本轮
  没有修改共享 `PlayerCapability`。

## 6. 待集成提交

- 实现提交：`f933344ebdbf8f18467d40b3dc3180e6d1ccf268`
