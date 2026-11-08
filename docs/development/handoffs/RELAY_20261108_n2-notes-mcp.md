<!-- relay:contract v1 -->
## 目标
让 Claude、ChatGPT、Gemini、Antigravity 能通过 i MCP 自己读家里的飞书笔记副本（「日记/日报」和「工作」，N1 每 30 分钟同步）。新增三个只读工具：`notes_recent`（最近几天或某一天的文档列表加开头预览，日记日以北京时间 04:00 为界）、`notes_search`（关键字搜标题和正文）、`notes_read`（按 token 分段读全文）。Sesame 不开放。i_context 不加笔记段（日摘要 M1 已覆盖近况）。

候选构建器在 EXPENSE 之后加 `NOTES_PATCHES`，legacy server 原样内嵌 `tools/i_remote_mcp/notes_tools.mjs`；只有 MCP 状态目录里有 `notes.json`（`{"format":"notes-config-v1","notes_dir":"<副本目录>"}`）才开放，格式不对时启动报 `notes_config_invalid`。server 候选哈希 `4b1014e0`，其余五个文件不变。

部署用脚本轮 `tools/relay_scripts/notes/n2-deploy.ps1`（mode=write）：预检锁定现役 e3-expense（server 63acb514、mcp 838810b2、release ded493e5）、维护副本 tools-4603fb79 与提交版一致、副本 index.json 能被 notes_tools 读出；写 notes.json，建并复制候选（受保护 ACL），update-mcp-source 先 dry-run 再登记新任务 `HereIAm-iCoreSchema6-n2-notes-20261108`（disabled），切换（停服约 1 分钟，失败自动退回 e3-expense），最后核对心率监听 47866。

## 完成标准
- [ ] `node --test tools/i_remote_mcp/*.test.mjs` 全部通过（含 notes 候选测试：四个前端能列出并调用三工具，Sesame 没有；无 notes.json 时不开放）。
- [ ] 脚本轮输出 step0–step3 和 done 都 ok，新任务 Running、旧任务 Disabled。
- [ ] 部署后云端用 i MCP 调 `notes_recent` 能拿到近几天的日记列表。

## 允许修改的路径
- tools/i_remote_mcp/chatgpt_candidate.mjs、chatgpt_candidate.test.mjs、notes_tools.mjs、notes_tools.test.mjs
- tools/relay_scripts/notes/
- docs/development/handoffs/RELAY_20261108_n2-notes-mcp.md、DEVLOG.md

## 不做 / 边界
- 只换 MCP 候选，不换 Core 包，不动 Core 数据、凭证和其他计划任务。
- 工具只读副本目录，不连飞书，不写任何文件；副本里的符号链接和越界路径一律拒绝。
- 不碰 lark-cli 配置和登录，不改 FeishuNotes-Mirror。
- 输出不含令牌、登录名、域名、本机路径、SID、文档标题或正文（只报数量）。
- 切换失败时退回 e3-expense；退回也失败时停下报告，不手工修。

## 验证命令
- `node --test tools/i_remote_mcp/*.test.mjs`
- 脚本轮输出逐行 ok。

## 需要真人的部分
- 在脚本轮评论上点 👍（会短暂停服约 1 分钟）。
