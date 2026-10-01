# Wave 3 — Desktop 配色隔离与白板工具字体 handoff

> 工作流：Wave 3 / Desktop color & font
> 分支：`codex/whiteboard-wave3-color-font`
> 基线：`57240fcc95fdf2ac44bc0ad62c931b2fd313790a`
> 状态：隔离实现与自动化验证完成，待集成和 Windows 真人验收

## 1. 本轮闭环

1. `DesktopWorkspaceTheme` 不再从上层主题 `copyWith` 少数字段，而是用
   `DesktopWorkspaceTokens` 建立完整的桌面 `ColorScheme`，覆盖 primary、
   secondary、tertiary、container、surface、outline、inverse、error 与
   tint / shadow / scrim 语义；indigo / 春雨上层颜色不再进入桌面白板子树。
2. 统一补齐 SnackBar、InputDecoration、Outlined / Filled / Text / Icon
   Button、Dialog 与 PopupMenu 主题。白板、卡片库、来源 / 视频研读的次级
   弹窗沿用同一主题入口，不在各页面逐点补颜色。
3. `whiteboardUiTextStyle` 的显式回退链新增 Cascadia Code 与系统等宽字体；
   中文 UI 仍以汇文明朝体为首选，英文、数字与时间码具备 Cascadia 回退。
4. 画布标题、可见操作标签、选择提示和卡片库标题改走
   `whiteboardUiTextStyle`；纯数字缩放值改走 `richTextCodeTextStyle`。

## 2. 契约与边界

- 只改桌面主题、白板字体 token、画布核心标题 / 工具调用与对应测试。
- 未改 `desktop_sidebar`、`workbench_action_card`、`workbench_ai`、AI tools、
  Bridge、W5 文档、数据库 schema、依赖或 `*.g.dart`。
- 未修改 Card / Source / Anchor / Snapshot / PlayerAdapter 语义。
- 组件仍可按交互态使用 `DesktopWorkspaceTokens` 的透明度派生值；没有引入
  新色板，也没有把上层 `ColorScheme` 值复制进桌面作用域。

## 3. 自动化证据

- `desktop_workspace_theme_test.dart`：2 条通过。indigo parent 下检查完整
  scheme 不含 parent primary / secondary / indigo，并校验提示条、输入框、
  四类按钮、Dialog、PopupMenu 的 token 与字体消费。
- `whiteboard_canvas_visual_acceptance_test.dart`：6 条通过。新增直接渲染
  “交互验收版”、中文工具 / 状态与 `100%` 的字体链断言。
- 回归：卡片库、Source Study、Video Study 三个 Widget 测试文件共 27 条通过。
- 合计：35 条定向动态测试通过。
- 定向 analyze（5 个修改源 / 测试文件）：`No issues found`。
- `git diff --check`：通过（只有 Windows CRLF 转换提示，无 whitespace error）。

## 4. 真人验收建议

1. 用当前春雨 / indigo 上层主题进入桌面白板，依次打开建组、连线、退出未保存、
   卡片库筛选、视频字幕导入等次级面；确认焦点框、按钮、菜单和 Dialog 不出现
   紫 / 蓝紫色。
2. 触发成功与失败 SnackBar，检查背景为深绿、动作文字为浅草绿。
3. 在画布名使用“交互验收版 2026”，确认中文标题与工具标签为汇文明朝体，
   缩放百分比、时间码与纯英文数字为 Cascadia Code / 等宽回退。

## 5. 未完事项

- 本隔离窗口未构建 / 启动 Windows exe，字体的真实字形选择、系统回退结果与
  GPU 渲染仍需集成窗口真人观察；自动化只验证 Flutter `TextStyle` 契约。
- 单个 `TextStyle` 只能按缺字形走 fallback；若汇文明朝体资产本身含拉丁字形，
  混排字符串中的拉丁字形可能仍由主字体渲染。纯英文 / 数字 / 时间码入口应
  继续显式使用 `richTextCodeTextStyle`，本轮已对缩放百分比落实并锁测。
- 集成提交：本 handoff 所在提交；准确 hash 由主窗口从 cherry-pick 来源记录。
