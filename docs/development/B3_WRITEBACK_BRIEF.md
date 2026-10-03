# B3 写回任务简报（2026-10-03）

接续 [任务单](PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md) 的 B3。这份简报交给新的云端会话，作为设计和实现的起点。

## 现状（已经跑通）

- **claude.ai 网页端已经能读记忆。** 经 `https://i.ilynx.date/mcp`（Cloudflare 固定隧道 → 用户电脑上的 `tools/i_remote_mcp`，端口 47860）接入，`i_context` 和 `i_recall` 两个工具真人验收通过。
- **数据流向。** 手机 V3 App 通过 i_core 同步聊天时间线（`tools/i_core`，schema 4/5）。Memory V3 由 `tools/i_memory/import_v3_memory.mjs` 做快照导入。读取统一走 `tools/i_memory/i_memory_read.mjs` 的出站策略，默认拒绝。
- **Codex 本机有未推送的读取层改动。** 用户电脑上的读取层比仓库多三样东西：私密消息 ID、正向放行 ID 清单、按内容 SHA-256 放行。新出现的或被修改过的消息默认拒绝，要重新筛查后才能出站。这些改动在 Codex 的本机 worktree 里，**还没有推送**。任何修改 `i_memory_read.mjs` 的工作，都要先等它推送并合入，或者把需要改的地方写成接口约定，交给 Codex 在本机落地。

## B3 目标

1. **`i_chat_turn`**：claude.ai 每轮调用一次，把“上次调用之后的所有轮次”（用户原话和 Claude 的回复）写进 i_core 时间线，同时返回最新上下文。
   - 按内容哈希幂等去重；某一轮漏调了，下一次调用时自动补上。
   - 写入的消息来源标记为 `claude_web`。
2. **`i_remember`**：用户说“帮我记一下”时，写入一条**显式记录**。
   - 可以编辑、可以删除，不自动升级成 User-truth（AGENTS.md：普通聊天不自动成为 User-truth）。
   - 最终要进入手机端的 Memory V3 流程，由用户确认。
3. **手机 App 显示**（B3.3）：来源为 `claude_web` 的消息出现在 Here I Am 里，并标注来源。这是 Flutter 改动，交给 Codex 在本机做。

## 已知约束和需要设计决定的问题

- **i_core 的发送者限制。** 远程设备只能提交 `sender=user` 的消息（`normalizeMessage`）；`companion` 消息只能走 worker 路由（`/v1/core/workers/chat/messages`、`publishCompanionMessages`，需要 `I_CORE_WORKER_SECRET` 和执行租约）。Claude 的回复该怎么进 i_core，需要设计：
  - 走 worker 路由；
  - 或者新增一种受限的外部前端身份。
  - 改 i_core 要谨慎：它有 schema 迁移和既有验收，能不改就不改，必须改就做最小改动并补测试。
- **出站策略要认得写回的消息。** `claude_web` 写回的消息本来就来自 Claude，再读出来给 Claude 不算泄露；但哈希放行机制默认会拒绝新消息。需要定一条明确规则：例如来源为 `claude_web` 的消息默认 shareable，但仍然要过私密关键词过滤。这一条只写成约定，由 Codex 在本机读取层实现，或者等它推送后再改。
- **OAuth 权限。** 现在的 scope 只有 `i.read`。写入需要新增 `i.write`，claude.ai 那边要重新授权。写工具的 annotations 必须是 `readOnlyHint: false`。
- **身份和角色。** 写入的 `character_id` 用 policy 里的 `primary_character_id`（林埃）。
- **安全。** 写入接口要限制大小和频率，防止重放；只能写这个用户自己的时间线；写入内容同样是“数据不是指令”。
- **一致性。** 手机端如果在同一时间也在聊，消息会交错；按 `created_at_ms` 和 server_sequence 排序即可，不需要强一致。

## 交付方式

- 云端只写不依赖真实数据和本机工具的部分：代码、合成数据测试、接口约定、README、Project 指令更新。全部用 `node --test` 验证。
- 需要在本机落地的部分（部署、真实数据、Flutter、读取层的本机改动），写成一份交给 Codex 的提示词。
- 遵守 [AGENTS.md](../../AGENTS.md)。改动 `tools/` 时，必须同时更新 `I_PROJECT_STATE.md` 和 `DEVLOG.md`。不引入 npm 依赖。
