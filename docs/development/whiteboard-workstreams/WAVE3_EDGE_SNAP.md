# Wave 3 / W1 连线锚点吸附 handoff

> 分支：`codex/whiteboard-wave3-edge-snap`
> 基线：`57240fcc95fdf2ac44bc0ad62c931b2fd313790a`
> 状态：实现完成；Flutter 定向验证通过

## 结果

- 新建连线与既有连线端点重定向统一使用四向锚点候选。
- 热区固定为 `28.0` 屏幕像素，包含阈值边界，不随 viewport zoom 缩放。
- 候选按旋转后的真实 BoardItem 四向边界点计算，在所有合法候选中选择屏幕距离最近者。
- 自环目标与折叠组内隐藏 Item 排除；空白松手不产生修改。
- 进入热区后预览终点立即吸到锚点，并显示 22px Palm 实心圆 + ring；离开热区恢复自由预览并移除高亮。
- 小尺寸、旋转卡与非 100% 缩放由 geometry 测试覆盖。
- 绘制与点击检测共享同一条屏幕空间三次贝塞尔曲线；非水平连线可直接点击可见线身重新打开编辑器。

## 契约影响

- 无 schema、依赖或共享身份语义变更。
- `BoardEdge` 继续只保存 `from_item_id / to_item_id` 与既有 style anchor side；没有保存屏幕坐标。
- 没有修改 compact editor、Desktop theme、Card / Source / Anchor / Snapshot 或 W5 路径。

## 测试与验证

- 新增 geometry：28px 边界内外、最近合法点、小旋转卡、0.4 zoom、排除自环。
- 新增/更新 Widget：候选 ring 出现并定位到真实 anchor、离开消失、空白松手取消、靠近锚点创建。
- 保留既有 endpoint retarget、空白取消、快照恢复覆盖。
- `git diff --check`：通过（仅仓库既有 LF/CRLF 提示）。
- 直调 Flutter snapshot：目标创建 / 编辑 / 恢复 Widget 用例通过（1 test）。
- 直调 Flutter snapshot：edge geometry 全套通过（9 tests）。
- 直调 Flutter snapshot：既有 endpoint retarget Widget 回归通过（1 test）。
- 定向 analyze：4 个实现 / 测试文件 `No issues found`。

## 集成后建议复跑

```text
flutter test test/whiteboard_canvas/whiteboard_canvas_edge_geometry_test.dart test/whiteboard_canvas/whiteboard_canvas_direct_interactions_test.dart test/whiteboard_canvas/whiteboard_canvas_interactions_test.dart
flutter analyze lib/ui/whiteboard_canvas/edge_geometry.dart lib/ui/whiteboard_canvas/whiteboard_canvas_screen.dart test/whiteboard_canvas/whiteboard_canvas_edge_geometry_test.dart test/whiteboard_canvas/whiteboard_canvas_direct_interactions_test.dart
```

## 未完事项

- 需要在 Windows 真实窗口用 40% / 100% / 180% 缩放、旋转卡和小卡确认 28px 手感；若真人反馈过黏或过窄，只调整单一屏幕像素常量，不改变数据契约。
- Windows 真人窗口验收仍由集成窗口执行。
