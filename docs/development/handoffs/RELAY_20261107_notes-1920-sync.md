<!-- relay:contract v1 -->
## 目标
日摘要白天版每天 19:30 生成（M1，tools/life_digest），要读到当天傍晚写的日记。给家里的笔记副本计划任务 `FeishuNotes-Mirror` 加一个每天 19:20 的触发器，原来每 30 分钟一次（:10/:40）的触发器不变。同一个 PR 里还带上 N2 读笔记模块 `tools/i_remote_mcp/notes_tools.mjs`，日摘要会 import 它的 notesByDate；这一步只加模块和测试，还没接进 MCP，不影响线上服务。

## 完成标准
- [ ] 脚本轮 `tools/relay_scripts/notes/n1-add-1920.ps1`（mode=write）输出 preflight、schedule 两行都 ok，触发器里有 Daily@19:20，每 30 分钟的触发器仍是 PT30M 且无期限。
- [ ] `node --test tools/i_remote_mcp/notes_tools.test.mjs` 通过。

## 允许修改的路径
- tools/relay_scripts/notes/
- tools/i_remote_mcp/notes_tools.mjs、notes_tools.test.mjs
- docs/development/handoffs/RELAY_20261107_notes-1920-sync.md、DEVLOG.md

## 不做 / 边界
- 只改 `FeishuNotes-Mirror` 的触发器，不改它的动作、账户和设置，不立即运行；任务不是 n1-install 建的就停。
- 不碰飞书、lark-cli、副本文件和其他计划任务。
- 不接 i MCP 候选、不换服务（N2 接入另开）。
- 输出不含本机路径或 SID。

## 验证命令
- `node --test tools/i_remote_mcp/notes_tools.test.mjs`
- 脚本轮输出逐行 ok。

## 需要真人的部分
- 在脚本轮评论上点 👍。
