# Wave 3 — 视频研读 ContextDock 双 Tab

## 2026-08-23 第三轮真人验收返修

### 已实现

- 点标注单击仍只跳到 `start_ms`；区间标注单击会从起点播放，到 `end_ms` 自动暂停。区间卡片内提供克制的“循环片段”开关，开启后到终点会回到起点继续播放。
- 片段播放是播放器会话态，不改 `AnchorContract`。切换标注、切回字幕 Tab、隐藏 Dock、播放器时间能力降级或离开页面都会撤销当前片段；切换片段严格等待旧 WebView pause 完成后再 seek/play，避免迟到 pause 反向覆盖新播放。
- 视频笔记按 `start_ms` 升序；同时间用 Card 创建时间、`card_id` 作确定性 tie-breaker。单击执行点/区间播放语义，连续双击在卡片内部展开无框连续文档编辑，保存更新原 Annotation Card，取消不落盘，不弹全局 Dialog。
- “编辑视频标签”移入 ContextDock header，与停靠和关闭使用同一 36px 图标按钮层级；原先覆盖播放器右上角的独立悬浮按钮已移除。链接级无 Dock 时不伪造该 header。
- 右侧、底部、640×520 窄窗口均由 Widget 回归检查无 overflow；原有字幕/视频笔记双 Tab、点/区间创建、Bilibili 动态能力与字幕降级保持不变。

### 自动化证据

- W4 领域 / Repository / Session / Source route / Widget 联合回归：143/143。
- `video_study_widget_test.dart`：33/33；含 start→end pause、loop、point-only、Tab/隐藏/降级取消、delayed pause 竞态、排序、原位编辑保存/取消、Dock header 与窄窗 overflow。
- `repository_video_annotation_store_test.dart`：3/3；新增编辑 Card 后 Anchor JSON 完全不变、重读仍为原时间范围。
- `source_study_screen_test.dart`：4/4；真实 provider 路由与 link-only 诚实降级通过。
- 修改的 8 个 Dart 文件定向 analyze：0 issue；`git diff --check` 通过（仅 Windows 换行提示）。

### 集成边界

- 未改共享 Anchor / PlayerAdapter / TimedTextTrack schema，未改字幕私有 resolver、依赖、生成代码、抓取、卡片库或 W5。
- 隔离分支不构建最终 Windows exe；由验收主窗口 cherry-pick 后统一构建，并在真实 Bilibili/YouTube 播放器上检查终点 pause 精度、循环手感、底部 Dock 和标签入口。

## 状态

- 基线：`5b55b43f`
- 分支：`codex/whiteboard-wave3-video-notes-tab`
- 状态：已完成隔离实现与自动化验证，待集成及 Windows 真人验收。

## 产品闭环

- ContextDock 主体拆为“字幕”和“视频笔记”两个明确 Tab，字幕轨道/状态只在字幕上下文呈现。
- 已保存的视频标注不再横排堆在 footer；视频笔记 Tab 使用窄栏友好的纵向可滚动列表，展示点/区间时间、标题和摘要，点击从 Anchor 起点回跳。
- 开始点标注、区间标注或字幕标注时自动进入视频笔记上下文；编辑、保存确认和保存后的列表都留在同一上下文。
- 无字幕与无笔记分别保留诚实空状态；无字幕不阻止具备时间能力的播放器创建笔记。
- Dock 关闭仍完整退场；既有右侧 65:35、底部 70:30、自适应底部及拖拽比例契约由回归测试覆盖。

## 自动化证据

- `video_study_widget_test.dart`：21/21 通过。
- 新增覆盖：双 Tab 切换、无笔记空状态、多卡纵向排列和滚动、笔记点击回跳。
- 既有覆盖继续通过：Dock 布局/关闭/恢复、点与区间标注、重启恢复、字幕回跳、Bilibili 能力分级、YouTube 字幕状态。
- `dart analyze`（`context_dock.dart` + `video_study_widget_test.dart`）：No issues found。
- `git diff --check`：通过（仅工作区换行提示）。

## 兼容性与边界

- 未改 Annotation、Card、Anchor、PlayerAdapter、TimedTextTrack 或持久化 schema；只重组现有 ViewModel 数据的呈现与交互。
- 未触碰字幕抓取架构、卡片库、BoardEdge、F 菜单、W5、生成文件或依赖。
- 未做 Windows exe 真人视觉验收；集成后仍需确认窄右栏长标题/长摘要、底部 Dock 和真实播放器回跳的视觉与手感。

## 集成交接

- Cherry-pick 本分支提交后，复跑视频研读 Widget 测试与目标平台 analyze。
- Windows 真人验收重点：多张笔记只在“视频笔记”Tab 纵向出现；新建编辑自动进入该 Tab；保存后可见且点击准确回跳；关闭 Dock 后不残留 footer/侧栏。
