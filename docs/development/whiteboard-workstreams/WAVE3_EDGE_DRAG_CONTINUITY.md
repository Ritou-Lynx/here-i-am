# Wave 3 — 连线拖动连续性修复交接

## 范围

- 基线：`5b55b43f`
- 分支：`codex/whiteboard-wave3-edge-drag-continuity-min`
- 仅修改画布连线创建 / retarget 手势与直接交互测试；未修改 BoardEdge schema、身份语义或 28px 屏幕吸附半径。

## 根因与修复

- 创建连线时，指针从源锚点进入目标卡 body 会切换 `_hoveredItemId`，源锚点 widget 随即移出树，正在持有手势的 recognizer 被取消。
- 创建与 retarget 的 `onPanCancel` 原先共用正常 `onEnd`，取消时可能把刚进入热区的候选错误提交，形成无法继续拖动的“死线”。
- 边拖动期间保持锚点 owner subtree 稳定；body 只参与 hover，不成为提交点。
- 将正常结束和取消分开：创建取消只清理 transient state，retarget 取消同时回滚 logical action。
- Flutter 已接受的 drag 收到原始 `PointerCancelEvent` 时会走 `onPanEnd`；handle 内层 raw listener 先执行回滚，使随后 `onPanEnd` 成为无副作用 no-op。

## 回归覆盖

- 悬浮源锚点拖动先进入目标 body，再移动到合法 anchor，仍可创建边。
- retarget 先进入 body，再移动到合法 anchor，仍可提交端点。
- body 内松手不创建临时边；候选热区内 pointer cancel 也不创建边。
- retarget pointer cancel 保留原边与原端点，并仍显示可继续编辑的端点 handle。

## 验证

- `whiteboard_canvas_direct_interactions_test.dart`：22/22 通过。
- `whiteboard_canvas_edge_geometry_test.dart` + `whiteboard_canvas_interactions_test.dart`：35/35 通过。
- 定向 analyze（实现与直接交互测试）：0 issues。
- `git diff --check`：通过。

## 未完事项

- 本提交只完成自动化回归，不替代主验收窗口的 Windows 真人拖动验收。
- 未重设计吸附灵敏度、连线视觉或数据契约，也未触及其他 Wave 3/W5 工作包。
- 集成提交为本 handoff 所在单一提交；完整 hash 由交接消息提供。
