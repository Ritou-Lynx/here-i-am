# Wave 3 B：画布正确性与原位编辑 handoff

> 分支：`codex/whiteboard-wave3-b-canvas`
> 基线：`65735eef188334e9f967b2c914da7ac83447ed44`
> 状态：待验收主窗口审计 / 集成 / Windows 真人验收

## 结果

- CV-01：双击空白仍先创建真实 Repository Card、再创建 BoardItem 并保存快照；成功后编辑 surface 直接替换该 BoardItem 卡面。普通 Note / Annotation / Reference / Task Artifact 双击同样原位编辑，不再创建画布顶层编辑浮层；Source Card 仍打开媒介消费视图。
- 原位编辑使用窄 `BoardItemEditSurfaceBuilder` 边界。画布以 `item_id` 定位唯一编辑中的摆放，surface 再以 `card_id` 加载共享内容；同一 Card 的其他 BoardItem 不进入编辑。画布不读取富文本 controller 内部状态；默认实现继续复用现有 `CardRichTextEditor`。编辑面临时扩展到至少 420×360 屏幕像素并钳制在画布内，不把临时尺寸写回 BoardItem。
- 编辑态移除该卡的拖动手势，画布 Pointer 判定也覆盖临时扩展面；只读切换会退出编辑，VM / adapter 的写入拒绝保持不变。放大按钮才调用全屏消费 / 编辑路由。
- CV-02：连线绘制、选取和端点手柄均从当前 BoardItem 边界实时计算，不再使用中心静态点。移动、缩放、旋转、撤销 / 重做后立即重新解析；JSON roundtrip / 重启后仍从稳定 item id 与 anchor side 恢复。
- CV-03：白板卡标题、正文、标签、失效引用和 edge label 改为复用 `fonts.dart` 的全局字体 Token，不再依赖默认 Material 字体或裸 `monospace`。

## BoardEdge 兼容扩展

- 未新增字段、表、schema、依赖或 `*.g.dart`；BoardEdge 身份仍只有既有 `edge_id + from_item_id + to_item_id`，不改变删除、跨板或语义关系。
- 仅使用既有 `BoardEdge.style` JSON 扩展位：稳定 key 为 `from_anchor_side` / `to_anchor_side`，合法值严格为 `top | right | bottom | left`。
- 旧 edge 或非法值走确定性回退：比较两端中心的主方向，水平优先；从端取朝向目标的一侧，到端取相反一侧。不会保存像素坐标。
- 这是画布视觉端点兼容扩展，不是新的共享身份字段，也不创建语义双链；主窗口可审计后决定是否把 key 登记进后续共享样式契约。

## 验证

- `dart analyze lib/ui/whiteboard_canvas ...`：No issues found。
- `flutter test`（edge geometry + direct interactions + product loop）：24 项通过。
- 更广回归（interactions + snapshot roundtrip + product loop + widget）首次共执行 66 项；除产品测试仍期待旧浮层文字外其余通过。该断言已改为检查编辑器属于 BoardItem 且无 Dialog / 顶层浮层，受影响的 geometry + direct + product 套件随后 24 项全通过。
- 覆盖：四向 side JSON、旧 edge 回退、移动 / 缩放 / undo / redo / restart、空白建卡补偿、普通卡 surface 嵌入、同 Card 双 BoardItem 的编辑身份隔离、编辑拖动隔离、Source / readonly 路由、复杂 RichText + 中文 IME 保存、全局字体 Token。
- `git diff --check`：通过。
- 未运行 Windows 真实窗口 / exe 构建；按 Wave 3 协议由验收主窗口统一构建唯一 exe 后执行真人场景，避免与并行窗口争抢运行时和用户数据库。

## 未完事项 / 风险

- 连续富文本跨块选择、合并和 H1–H6 属 Wave 3 A；本提交只提供可替换的嵌入 surface，不实现或复制 A 的内部编辑状态。
- 临时放大的原位 surface 已有 Widget 行为验证，但仍需 Windows 真人检查：接近四边的卡片、非 100% 缩放、中文 IME 候选窗、关闭未保存提示和视觉遮挡。
- BoardEdge 与 Card / block 语义双链继续分层；本提交不提供反链查询或语义关系 UI。
