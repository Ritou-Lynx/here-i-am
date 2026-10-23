<!-- relay:contract v1 -->
# C1 合同：App 聊天时间线按 origin_device_id 显示来源

## 目标
D1b 之后，ChatGPT 和 Claude 分别以 `frontend:chatgpt_web`、`frontend:claude_web` 写入 Core（`tools/i_remote_mcp/writeback.mjs` 第 9–10 行），App 同步时已把它存进 `persona_chat_messages.origin_device_id`（`core_sync_engine.dart` `_applyChatUpsert`）。但：

- v3-lab 的聊天界面完全不读 `originDeviceId`，网页端写回的消息和手机本机消息看不出区别。
- 唯一的来源标签 `ChatMessageSourceLabel` 只在未合入的 `codex/b3-writeback-local-20261003` 分支上，对所有 `frontend:*` 一律写“网页端”。

改为：v3-lab 上加来源标签，按设备 ID 精确映射显示名，手机和桌面聊天界面都显示。

## 完成标准
**来源映射（纯函数，单一位置）**
- [ ] 新建 `lib/ui/character/widgets/chat_message_source_label.dart`，内含一个顶层纯函数 `chatSourceLabelFor(String? originDeviceId)` 和 `ChatMessageSourceLabel` 组件。
- [ ] 映射表写成一个 `const Map<String, String>`（device_id → 显示名），以后加 Sesame、Gemini 等来源只需加一行和一条测试。映射只按完整 device_id 精确匹配（不做前缀拼接或大小写折叠）：
  - `frontend:claude_web` → `Claude`
  - `frontend:chatgpt_web` → `ChatGPT`
  - 其他以 `frontend:` 开头的 → `网页端`（兜底，D1/D2 新增前端时只需在映射表加一行）
  - `null`、空串、本机或其他手机的安装 ID、`core-companion:*`、`v3-history-*` 等 → 不显示（返回 `null`，组件渲染 `SizedBox.shrink()`）
- [ ] 来源只取 `originDeviceId`，不读消息正文、`syncId` 前缀或附件。

**界面**
- [ ] 手机：`persona_chat_screen.dart` 的消息列表两处分支（多选模式与普通模式，各在 `if (showDate)` 日期分隔线之后、消息气泡之前）插入标签，颜色用 `_personaTextMuted`。对齐：林埃消息靠左，用户消息靠右。
- [ ] 桌面：`desktop_persona_chat_view.dart` 消息项同样显示（工作台动作卡片不显示）。
- [ ] 不改气泡样式、长按菜单、复制内容、排序、未读和同步逻辑；标签文字不进入复制、分享、导出或给模型的上下文。

**测试（合成数据，放在 `test/` 下，CI 的 Flutter full suite 会自动选中）**
- [ ] 新建 `test/ui/core/widgets/chat_message_source_label_test.dart`：
  - 纯函数：上述每类 ID 的映射结果，含 `null`、空串、`frontend:`（空名）、`Frontend:claude_web`（大小写不同应走兜底或不显示，写明结果）。
  - 组件：Claude/ChatGPT 文案；用户消息靠右、林埃消息靠左；非 frontend 来源无 Text。
  - 可读性：沿用 b3 分支测试的做法，在 `springRainDaydream` 深色聊天背景上传入 `textSecondary` 时对比度 ≥ 4.5。
- [ ] 手机聊天屏 widget 测试：插入两条 `frontend:chatgpt_web` / `frontend:claude_web` 消息和一条本机消息，断言分别出现 `ChatGPT`、`Claude`，本机消息无标签。可放进现有聊天屏测试或新文件。
- [ ] 现有测试不改断言。

## 允许修改的路径
- `lib/ui/character/widgets/chat_message_source_label.dart`（新建）
- `lib/ui/character/widgets/persona_chat_screen.dart`（只插入标签）
- `lib/ui/desktop/widgets/desktop_persona_chat_view.dart`（只插入标签）
- `test/ui/core/widgets/chat_message_source_label_test.dart`（新建）
- 聊天屏 widget 测试文件（新建或在现有文件追加用例）
- `docs/development/handoffs/RELAY_20261023_c1-chat-source-label.md`（只由 Claude 改）

## 不做 / 边界
- 不改数据库表、迁移、同步协议、Core、MCP、i_memory 读取策略。
- 不合并或 cherry-pick `codex/b3-writeback-local-20261003` 分支的其他内容；只参考它的标签组件和测试写法。
- 不读取 Core 的设备列表或 `display_name`（那是 D1 前端身份注册表的范围）。
- 不构建、不安装 App，不碰手机和生产。
- 止损：同一测试名或同一错误码在连续两个提交上失败，即判为 blocked。最多 3 轮。

## 验证命令
- `flutter analyze lib/ui/character/widgets/chat_message_source_label.dart lib/ui/character/widgets/persona_chat_screen.dart lib/ui/desktop/widgets/desktop_persona_chat_view.dart`
- `flutter test test/ui/core/widgets/chat_message_source_label_test.dart <聊天屏测试文件>`
- `flutter test test/data/services/sync/`（回归，确认同步不受影响）
- `git status --short`（只出现允许修改的路径）
- Claude 在云端核对 diff 与 CI（云端没有 Flutter，Dart 测试以 PR 的 CI 结果为准）。

## 用户决定（10-23）
- 合并后用 v3-lab 构建 App，替换手机上现装的版本（现装版本来自未合入的 b3 分支）。
- 未知前端兜底显示“网页端”；手机和桌面都显示标签。
- 显示名先写在 App 的映射表里；是否改为读取 Core 登记的设备显示名，留到 D1 再定。

## 需要真人的部分
- 合并由用户进行。Codex 回帖并收到 `relay:done` 前不要合并。
- 合并后用户自行构建并安装 App，真人验收：ChatGPT 和 Claude 各写一轮，手机时间线分别显示“ChatGPT”“Claude”，手机本机消息无标签。
