# UI-T Theme Integrity handoff

> 工作流：W0 AI Workbench Integration — UI-T Theme Integrity
> 目标：在 Desktop Workspace 作用域内完成颜色与组件主题收口，阻断次级弹窗色值泄漏
> 基线：`f88537d72d08531252e2050784d71deba36a517f`

## 2026-08-26 返修交付 — 聊天 Overlay 主题与原生输入连续性

> 返修基线：`7f7af225fe401ce0d7c44964fd8afccb31f24077`
> 分支：`codex/whiteboard-w0-goal1-uit-repair`

### 修改

- `GlobalDesktopChatOverlayHost` 现在以 `DesktopWorkspaceTheme` 包住自身
  `Overlay`。它原本是 router 桌面工作区的同级节点，导致聊天消息
  `SelectionArea` 的右键菜单、Tooltip 等 Overlay surface 回退到上层手机
  白紫主题；现在这些 surface 与桌面主题 token 在同一作用域内。
- Host 回归在 indigo 父主题下只验证生产 `GlobalDesktopChatOverlayHost`
  的 Overlay subtree 已取得 Lieflat Palm token；它不单独声称菜单已打开。
- 消息选择回归在 indigo 父主题下用鼠标拖选后真实 secondary click 打开
  `DesktopTextSelectionToolbar` Overlay entry，并断言该工具栏环境的
  `cardColor` 与 `TextButtonTheme` 仍来自 Lieflat Palm；不再只读取聊天
  widget 本身的 ThemeData。两条回归组合覆盖生产 host 的主题作用域与实际
  SelectionArea toolbar 的 Overlay 传递。
- 新增三轮输入回归：每轮使用框架 `TextInput` editing-state 更新模拟粘贴，
  在 streaming 状态切换后断言同一个 `EditableTextState` 仍存活且输入保持
  enabled，避免把客户端重建或 streaming 禁用伪装成可继续输入。

### 真实支持范围与限制

- 代码与 widget 回归只锁定 Flutter 内的 TextInput editing-state、第三轮连续
  编辑和聊天 SelectionArea Overlay 的主题继承；并不等价于 Windows 真机的
  `Win + H`、Typeless 或系统剪贴板桥接成功。
- 本轮按并发约束未运行 `flutter test`、`dart analyze` 或应用构建；只运行了
  `git diff --check`。主窗须串行验证后再决定是否集成。

### 建议主窗验证

```powershell
flutter test test/ui/desktop/desktop_chat_overlay_test.dart
flutter test test/ui/desktop/desktop_workspace_theme_test.dart
dart analyze lib/ui/desktop/widgets/global_desktop_chat_overlay.dart test/ui/desktop/desktop_chat_overlay_test.dart
```

- 随后在唯一 Windows 候选真人复验：连续至少三轮系统剪贴板粘贴、回复期间
  普通输入与 `Win + H`/Typeless editing-state，以及消息右键的选择菜单。后两项
  没有真人证据前继续保持 Gate 阻塞。

---

## 1. 交付范围与共享契约

- 修改文件：
  - `test/ui/desktop/desktop_workspace_theme_test.dart`（仅补齐可复核断言）
- 读文档：
  - `docs/development/goals/GOAL-20260824-ai-workbench-wave1.md`
  - `docs/development/COLLABORATION_EXECUTION_PROTOCOL.md`
  - `docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md`
  - `docs/development/whiteboard-workstreams/COLOR_LEAK_HANDOFF.md`
- 共享契约影响：仅 `lib/ui/desktop/desktop_workspace_tokens.dart` 的主题边界约束；未触及共享数据模型、白板契约、数据库、依赖和路由。

## 2. 完成定义对应性

- `DesktopWorkspaceTheme` 在当前分支已存在以下 8 类子主题配置：
  `snackBarTheme` / `inputDecorationTheme` / `outlinedButtonTheme` /
  `filledButtonTheme` / `textButtonTheme` / `iconButtonTheme` / `dialogTheme` /
  `popupMenuTheme`。
- 所有已配置条目均使用 `DesktopWorkspaceTokens` 的值；本次补充通过新增断言直接锁定这一事实。
- 未改 Android / Spring Rain 视觉，不改白板业务行为。

## 3. 九项主题泄漏路径复核（自动 + 可复核）

1. SnackBar：`desktop_workspace_theme_test.dart` 断言 `snackBarTheme.backgroundColor`
   与 `contentTextStyle.color/actionTextColor`。
2. InputDecoration（创建白板 / 字幕导入）：同测试断言 `inputDecorationTheme`
   的 `fillColor/filled/focusedBorder/disabledBorder`。
3. OutlinedButton（白板 / 视频弹窗）：断言 `outlinedButtonTheme.style.side.foregroundColor`。
4. IconButton（桌面行为抽屉按钮）：断言 `iconButtonTheme.style.foregroundColor`。
5. PopupMenu：断言 `popupMenuTheme.color/textStyle`。
6. TextButton：断言 `textButtonTheme.style.foregroundColor`。
7. FilledButton：断言 `filledButtonTheme.style.backgroundColor`。
8. Dialog：断言 `dialogTheme.backgroundColor` 与字体。
9. ColorScheme 泄漏：`desktop_workspace_theme_test.dart` 首测仍验证桌面 scheme 与
   父主题紫色不相交，且 `primary/secondary/tertiary/outline/inverseSurface`
   等关键语义不回流上层。

## 4. 自动化结果（本包）

- `dart analyze test/ui/desktop/desktop_workspace_theme_test.dart`（Start-Job 超时封装，90s）
  - 结果：超时，返回 `ANALYZE_TIMED_OUT`（exit 1）
- `flutter test test/ui/desktop/desktop_workspace_theme_test.dart`（Start-Job 超时封装，120s）
  - 结果：超时，返回 `DESKTOP_THEME_TEST_TIMED_OUT`（exit 1）
- `git -c safe.directory=C:/Users/ExampleUser/.codex/worktrees/8e63/here-i-am diff --check`
  - 结果：通过（仅提示 LF/CRLF 边界提醒，无实质 whitespace 冲突）

## 5. 未完事项

- 未执行真实桌面窗口回归（按本工作包约束，交由 W0 统一真人 Gate）。
- `DesktopWorkspaceTheme` 的源码文件当前已包含完整八类子主题定义；后续新增
  次级弹窗入口仍应先走统一入口，不要在调用点逐条补色。
