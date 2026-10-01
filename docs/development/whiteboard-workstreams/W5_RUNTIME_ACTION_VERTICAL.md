# W5 — Runtime 工具调用与白板行动卡纵切

> 日期：2026-08-21
> 状态：首个产品接线纵切完成并以 `dc4e97c0` 合入、推送 `v3-lab`；仅使用 fake App Server 验收，未调用真实模型
> 跨设备接续：见 `W5_PRIVATE_PC_HANDOFF.md`

## 1. 本轮闭环

桌面白板打开时，林埃悬浮对话可接收明确指向所选卡片、同时要求“分组”和“连线”的指令。Here I am 把当前 board 与选区绑定为临时 surface context，经 loopback RuntimeAdapter 创建 Codex thread / turn；Codex 只能调用两个动态工具：读取所选对象，以及提交受限的 groups / edges 计划。board、授权、turn、操作批次和实际 Drift 写入均由产品宿主管理。

聊天会持久化一张结构化行动卡，依次显示进行中、已完成、未完成或已撤销。卡片详情只展示产品审计摘要，不保存模型原始日志或本地路径；成功操作可在未发生后续白板变化时整批撤销。

## 2. 冻结边界

- 普通林埃聊天保持原路径；只有带“所选 / 选中 / 这些卡片”等明确目标且同时包含“分组、连线”的桌面指令进入本纵切。
- Runtime 动态工具定义、调用事件和结果回传采用 provider-neutral adapter；Codex App Server 只是首个 provider。
- 读取工具输出有 UTF-8 总预算、路径脱敏和稳定 provenance；写工具不接受 board、授权、turn、batch 或原始快照。
- 产品在用户消息落库后签发一次性授权，绑定当前 turn、board、选区、能力、数量和时效。
- 行动卡复用 `PersonaChatMessages` 的 `messageType=action` 与结构化 attachment，不新增数据库表，也不写 User-truth。
- 写入和撤销使用同一 `WhiteboardAiWriteToolHost` 的进程内恢复记录；应用重启后旧行动卡仍可见，但撤销按钮不会伪装为可用。
- Runtime 不可用、功能开关未开启、选择不足、保存失败、工具参数越界或 turn 非正常结束时，只落“未完成”行动卡，白板不变。

## 3. 实现位置

- Runtime transport：`tools/dev_agent_bridge/runtime_adapter.mjs`、`codex_app_server_adapter.mjs`、`experimental_runtime_api.mjs`
- Flutter loopback client：`lib/data/workbench_ai/workbench_runtime_client.dart`
- 页面上下文：`lib/data/workbench_ai/whiteboard_workbench_surface.dart`
- 产品编排：`lib/data/workbench_ai/whiteboard_workbench_coordinator.dart`
- 行动投影与持久化：`lib/domain/workbench_ai/action/workbench_action_projection.dart`、`lib/data/services/persona_chat_service.dart`
- 桌面呈现：`lib/ui/desktop/widgets/workbench_action_card.dart`、`desktop_persona_chat_view.dart`
- 页面接线：`lib/ui/whiteboard/whiteboard_canvas_route_screen.dart`、`lib/ui/character/widgets/persona_chat_screen.dart`

## 4. 验证

- Bridge 全量 deterministic 回归 33/33；动态工具覆盖定义校验、调用事件、结果回传、重复响应拒绝、close fail-closed 与 HTTP relay。
- Flutter 联合验收 45/45；覆盖 Permission Broker、只读 / 写入 Tool Host、真实 Drift、Runtime coordinator、结构化行动卡、整批撤销、桌面聊天和白板冻结路由。
- 本轮新增与独立接线路径精确 `flutter analyze` 零问题；扩大到整个旧 `persona_chat_screen.dart` 时仅报告该文件既有 19 条 lint，无 error。
- 端到端 fake Runtime 验证：先读 selection，再提交产品外计划；产品自行注入授权 / board / turn / batch；写入后行动卡完成，撤销后 group / edge 从 Drift 消失。
- 修复一个真实恢复缺口：运行时时间带微秒而 Drift 只保存毫秒，原本会让刚完成的操作也误判为“快照后来改变”；写入宿主现统一使用 UTC 毫秒精度，并有回归覆盖。
- 全程未连接真实模型、未新增 schema、未改共享 Card / Source / Anchor / PlayerAdapter 语义。

## 5. 如何试用与当前限制

本地 Bridge 的实验入口仍默认关闭。要进行后续真人验收，需要显式设置 `DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER=1`，并可选设置 App Server `model/list` 中真实存在的 `DEV_AGENT_EXPERIMENTAL_CODEX_MODEL`，然后启动 Bridge。打开白板、选择至少两张卡片，在桌面林埃入口输入例如“请把所选卡片按主题分组并连线”。

当前尚未进行真实模型验收，因此本轮只证明协议、权限、落盘、投影和恢复闭环，不声称 Codex 对任意内容都能给出优质分组。首个 intent matcher 也是刻意收窄的中文纵切；通用自然语言路由、自动启动 / 健康提示、Context Envelope / RuntimeSessionBinding 持久化，以及跨应用重启撤销留后续阶段。

## 6. 恢复策略

关闭 `DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER` 即可撤下 Runtime 入口；旧 `/v1/runs` 不受影响。没有数据库迁移需要回滚。功能未开启时，命中明确白板动作的聊天只会得到一张诚实的“电脑执行能力尚未开启”卡片，不会改白板。
