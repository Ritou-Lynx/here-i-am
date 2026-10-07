# PR9 / PR10 用户委托编辑返修

- 基线：`21a813ef717ad4698dadcb31cdc39a18611b87e9`；分支：`codex/pr9-pr10-review-fixes-20261005`。
- 仅修改工具、其工厂接线与独立回归测试；未提交、推送、构建、安装或接触真实数据。

## 实现与调用链证据

`persona_chat_screen.dart` 将持久化后的 `primaryMessageId` 传给 `CompanionAgent.chat(userMessageId)`；`CompanionAgent._createAgent` 每轮新建 `CompanionAgentSkill(currentUserMessageId)`，继而调用 `CharacterToolsFactory.buildCompanionTools`。本次工厂把此 ID 和 `characterId` 绑定在 `memory_v3_update_card` 的实例闭包中。

工具只查询这个精确 ID。必须是当前角色的用户 `chat` 消息、没有 `taskRoomId`、并拥有非空 `sync_id`，才以 `actor=user_via_agent`、`authorizationRef=sync_id` 调用真实 Organizer。缺少触发上下文、消息不存在、错误会话、非用户聊天或无稳定 ID 均返回具体失败码；没有最近消息回退或 `agent_inferred` 降级。普通 companion 表以 character 隔离；工作台 task room 在此工具上拒绝。

模型参数不暴露 actor、消息 ID 或授权引用。改用 object 参数模式，运行时拒绝 schema 外参数，防止注入授权字段；同时消除原有 `presentation_module` 与 `time_overrides` 的位置错配。

Organizer 的 `_authorization_ref` 审计字段由拥有该文件的 capture worker 配套实现；本 worker 未修改 service。

## 回归与状态

新增 `test/agent/built_in_tools/memory_v3_update_card_user_turn_test.dart`，直接调用真实 factory 生成的工具 executable：

1. 真实 ScheduleViewModel 勾完成 → PersonaChatService 写用户消息 → 工具改回 active；验证当前值、两种 actor、触发消息 sync_id 和 user correction actor。
2. 缺失上下文与不存在 ID 不借用最新真实消息。
3. 非用户消息、非 chat 消息拒绝。
4. 跨角色与错误 task room 拒绝。
5. null / 空 / 空白 sync_id 拒绝。
6. actor、authorizationRef、authorization_ref、消息/角色 ID 参数伪造拒绝。
7. 两个异步重叠工具调用各自保留触发消息，后建或更新消息不串授权。

worker 只运行格式化与 diff 空白检查。**主窗尚未跑测试**；不得将本交接视为测试通过或真机接受。建议主窗顺序执行：

```powershell
flutter test test/agent/built_in_tools/memory_v3_update_card_user_turn_test.dart
dart analyze lib/agent/built_in_tools/memory_v3_update_card_tool.dart lib/agent/skills/character_tools_factory.dart test/agent/built_in_tools/memory_v3_update_card_user_turn_test.dart
```

冻结 SHA-256（主窗后续返修或格式化后应重新记录）：

| 文件 | SHA-256 |
| --- | --- |
| `lib/agent/built_in_tools/memory_v3_update_card_tool.dart` | `361E48558EC03177C0CFE3984F9ED5B0575BEF02CC5C4526401C4A023422F7C8` |
| `lib/agent/skills/character_tools_factory.dart` | `8517B81A7480A6D29E54FD11977170A7ECA7BD964AB1582A5BAF47A373BFA715` |
| `test/agent/built_in_tools/memory_v3_update_card_user_turn_test.dart` | `D30EE39EB5F78EC65FADACE22CB8D577F5378D2D4EDAF8226B8962D2378CF8BC` |

边界：测试验证真实 UI ViewModel、消息服务、factory、工具和数据库组合，不调用真实模型或手机。它证明请求来源绑定，不声称具备自然语言语义授权分类器；工具既有“仅用户要求修改时调用”契约仍生效。
