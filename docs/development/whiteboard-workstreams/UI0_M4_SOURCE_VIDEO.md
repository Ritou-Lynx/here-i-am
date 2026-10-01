# UI-0 — Whiteboard Desktop M4 来源与视频研读视觉迁移 handoff

> 工作流：UI-0（Whiteboard Desktop · M4 source / video study）
> 状态：完成并由 W0 集成到 `v3-lab`（2026-08-20）
> 隔离分支：`codex/whiteboard-ui0-m4`
> 开工基线：`057da4b32bb9dc6c8ce410398498ecb90b42ef89`

## 1. 交付闭环

1. 普通来源移除页面内常驻 AppBar，改为 Lieflat Palm 沉浸阅读面；桌面正文列稳定在 680–760px，窄于该范围时安全收缩。
2. 来源标题、站点 / 作者 / provider 保持轻量可见；版本链、对象状态和完整元数据收进按需展开的“来源信息”，正文继续来自 Repository 对象并保留卡片 / description 诚实回退。
3. 视频右侧停靠默认保持播放器 65% / Dock 35%，底部停靠默认保持 70% / 30%；1024×720 下播放器与 Dock 分别保持 420/320px 最小宽度和 300/220px 最小高度。
4. splitter 直接调整真实宽高，拖动方向与视觉位置一致；调整后的比例继续写入既有 `VideoSessionStore`，重开后恢复方向和比例。窗口小于 760px 时自动下移到底部。
5. `ContextDock` 可右 / 下切换，也可完全关闭；关闭后 Dock 与 splitter 均离树，播放器回收全部窗口，保留单一按需恢复按钮。
6. 字幕来源、自动获取中、平台失败原因和“需要字幕”都读取真实运行时状态；保留 SRT / VTT 导入，不生成演示字幕。
7. 时间码、字幕 seek、反向高亮、时间轴 seek、点 / 区间 Anchor、标注编辑、短暂保存确认和点击批注返回精确画面均保留；标注仍写入统一 Repository Card / Anchor。
8. Bilibili、小红书和未知 provider 显示诚实链接模式、原链接及外部打开动作，不伪装 current / duration / seek、播放器或字幕能力。

## 2. 视觉与交互收口

- 来源与视频辅助面统一消费 `DesktopWorkspaceTokens.lieflatPalm` 和白板字体入口；未修改全局 Spring Rain 手机主题。
- 视频媒体面使用共享 `workspaceDark`，Palm 绿只承担跳转、进度、焦点和主动作；普通字幕行、元信息与纸面继续使用暖灰层级。
- 当前字幕行不再使用规范禁止的左 / 右实心竖线，改为低浓度 Palm 选中底 + 发丝分隔。
- 字幕标注入口保持 12px 绿色方块语义，但交互目标扩大为 36×36，并提供 tooltip / 键盘可聚焦按钮。
- 保存标注后立即离开或重启时，页面先撤下确认态再销毁 ViewModel，避免延迟确认回调访问已释放对象。

## 3. 拥有路径

- `lib/ui/whiteboard/source_study_screen.dart`
- `lib/ui/whiteboard/video/video_study_screen.dart`
- `lib/ui/whiteboard/video/widgets/**`（仅实际视觉组件）
- `test/ui/whiteboard/source_study_screen_test.dart`
- `test/ui/whiteboard/video/video_study_widget_test.dart`
- `integration_test/whiteboard_f4_source_product_windows_test.dart`（仅把旧裸色断言改为共享 token）

## 4. 共享契约影响

**零领域、数据库、Repository、ingestion、router 与 provider 能力契约变更。**

- 未修改 `PlayerAdapter`、Windows / Web YouTube adapter、timedtext service、Anchor / Annotation domain、`RepositoryVideoAnnotationStore` 或 session schema。
- 未改变 YouTube 静态字幕能力声明；当前 Source 是否有可用字幕仍由运行时轨道决定。
- 未新增播放器私有便签、Card / Source 身份或视频专用数据源。

## 5. 验证结果

- 指定五组测试：来源研读、视频 widget、session store、YouTube timedtext、annotation repository，**45/45 通过**。
- UI 新增覆盖：680–760px 阅读列、元数据按需展开、65:35 / 70:30、1024×720 最小尺寸、splitter 实际改宽 / 改高并保存、Dock 两方向 / 完全退场、窄屏自动下移、三类 link-only provider、时间轴 seek、批注返回精确时间和重启比例恢复。
- Windows 原生产品集成：真实 `memex.exe` + WebView2 + YouTube **1/1 通过**；覆盖 preview 零写入、duration/current/play/seek、用户导入字幕、cue seek / 反向高亮、Repository Annotation/Anchor、关闭数据库与重建窗口后播放位置 / 标注恢复。Fixture 未进入产品路径。
- `scripts/verify_critical_fixes.ps1`：3/3 通过。
- 本轮生产 UI、测试和 Windows 集成文件定向 analyze：No issues found。
- `git diff --check`：通过。

## 6. 未实现 / 下一接入点

- 未新增本机 ASR；字幕仍按平台 / 创作者 → 用户导入 → 权利允许时本机转写的既有顺序。
- WebView2 Runtime 缺失、平台禁止嵌入和网络错误继续走 F4 既有诚实失败态，本轮未做卸载 Runtime 的破坏性验证。
- 隔离分支提交 `3dc5ad9` 已由 W0 作为主线提交 `2577b0d` 集成；最终集成树再次通过 Windows 原生产品链，未 push。
