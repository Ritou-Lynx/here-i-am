<!-- relay:contract v1 -->
## 目标
M6：盘点并清理各 AI 工具里本机连续性网关（i bootstrap）留下的配置；先只读盘点，用户确认清单后再删。

## 完成标准
- [ ] 第 1 个脚本轮（read）`tools/relay_scripts/m6/m6-inspect.ps1` 跑完，列出：各工具里名为 `i` 的 MCP 条目（区分本机网关 / 远端 i）、`i-continuity` 全局指导块、Codex `i-realtime-voice` 语音块、`~/.i` 目录概况、相关计划任务与网关进程。
- [ ] 用户在线程里确认要删的项目。
- [ ] 删除轮（write，等用户 👍）只删确认过的项目，先备份到 worktree 外，再复查一遍为 0。

## 允许修改的路径
- tools/relay_scripts/m6/
- docs/development/handoffs/RELAY_20261107_m6-i-bootstrap-cleanup.md

## 不做 / 边界
- 不动思源、FlexNote 自带的 MCP 配置（保留它们的 MCP 调用通道）。
- 不动远端 i（i_context / i_chat_turn 那套）的条目和令牌缓存。
- 不改生产 Core / MCP 服务、不启停现役任务。
- 输出不含本机绝对路径、网址、令牌、指导块正文。

## 验证命令
- 脚本轮输出本身（每行一个 JSON）。

## 需要真人的部分
- 确认删除清单；在删除轮评论上点 👍。
