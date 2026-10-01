# W5 — 可撤销白板操作批次

> 日期：2026-08-21
> 状态：Phase C 领域 / 数据基础纵切完成；后续 Runtime / UI 接线见 `W5_RUNTIME_ACTION_VERTICAL.md`
> 分支：`v3-lab` 工作树，未 commit / push

## 1. 本轮闭环

实现第一个 AI 白板写入动作的产品侧安全边界：用户选定一组白板项目并授权“按主题分组并连线”后，工具宿主只接受稳定对象 ID 和受限操作计划，由 Here I am 读取当前白板、构造新快照、一次事务保存，并返回审计回执与整批撤销令牌。

本轮没有让模型提交原始快照，没有修改共享 `Card` / `Source` / `Board` / `WhiteboardOperation` 语义，没有新增 schema、路由或依赖，也没有修改桌面 UI。

## 2. 冻结边界

- 权限由产品签发：绑定 runtime turn、用户授权消息、board、选区、能力、操作数量与过期时间。
- Runtime 只持有不透明 `authorizationId`；board、turn、能力或目标越界时，在读取数据库前拒绝。
- 首个动作只允许 `groupSelection` 与 `connectSelection`；分组必须完整覆盖且只覆盖授权选区。
- Here I am 根据当前统一白板快照追加 group / member / edge，并生成现有 `WhiteboardOperation` 审计项。
- 保存采用 `WhiteboardDriftStore.save` 的单事务全快照语义；失败时释放权限预留，允许同一授权重试。
- 撤销前校验当前完整快照哈希；若用户或其他流程已继续编辑，则返回冲突，不覆盖后续修改。
- 同一 batch 与同一请求幂等；batch 被改写或撤销令牌跨 turn 使用时拒绝。

## 3. 实现位置

- `lib/domain/workbench_ai/permissions/whiteboard_permission_broker.dart`
- `lib/data/whiteboard/ai_write_tools/whiteboard_ai_write_models.dart`
- `lib/data/whiteboard/ai_write_tools/whiteboard_ai_write_tool_host.dart`
- `test/domain/workbench_ai/permissions/whiteboard_permission_broker_test.dart`
- `test/data/whiteboard/ai_write_tools/whiteboard_ai_write_tool_host_test.dart`

## 4. 验证

- 新增权限与写入纵切测试 10/10。
- Runtime contracts、白板只读 / 写入 Tool Host、Drift store 与当前桌面 UI 联合回归 67/67。
- 新增实现与测试精确 `flutter analyze` 零问题。
- 真实 Drift 文件覆盖：执行 → 整批撤销 → 关闭并重开，原项目和卡片仍在，新增 group / edge 不再出现。
- 全程使用本地确定性 fixture，没有调用真实模型。

## 5. 恢复与限制

写入和成功撤销后的白板状态可随 Drift 重启恢复；权限 grant、幂等回执和待撤销前快照目前仅在进程内保存。因此本轮不能承诺“应用重启后仍可用旧令牌撤销”，也尚未把工具暴露给 Bridge / Codex。

Runtime transport、受控白板入口与行动卡片 / 详情 / 撤销已经在后续 [`W5_RUNTIME_ACTION_VERTICAL.md`](W5_RUNTIME_ACTION_VERTICAL.md) 接通。Context Envelope、RuntimeSessionBinding、权限与撤销记录的持久恢复仍留在 Phase D 一并完成。
