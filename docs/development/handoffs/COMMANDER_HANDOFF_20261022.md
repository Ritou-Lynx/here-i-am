# 总指挥交接（2026-10-22，D1b 之后）

## 角色与规则（用户原话要点）
- Claude 负责审核、写合同、写可直接粘贴的 Codex 提示词；Codex 在用户的 Windows 电脑上执行。
- Claude 只推送自己的分支，从不合并 PR。合入 v3-lab、操作生产、动真实数据，都要用户明确同意。
- 回复用简洁中文。每次审核结论都追加到对应合同，同步本文件的“进行中”表格，然后推送。
- 止损：同一测试名或同一错误码在连续两个提交上失败，判为 blocked。
- 仓库是公开的：不写 SID、本机绝对路径、域名、凭据或私人内容。
- 交接方式：源码类工作走 Agent Relay（PR 评论标记 `relay:to-codex` 等，watcher 每 3 分钟轮询，用法见 `agent-relay` skill），用户只需合并。生产步骤走手动粘贴，每次粘贴即视为用户同意。

## 现状
- 生产：schema6 Core 已上线（D1b，10-22 完成）。现役登录任务为 P′（`HereIAm-iCoreSchema6-d1a-mcp-20261013-6a063386`），旧任务和 P 停用保留。claude_web 和 chatgpt_web 都已配对，真人验收通过。全过程见 `RELAY_20261012_core-release-r1.md` 的“D1b 执行记录”。
- relay watcher：10-22 已恢复（Enabled），VBS PATH 指向当前 codex 目录。Codex 更新后路径会再次失效（见 A4）。
- 运维注意：STATE 中有旧 shortcut-mail 日志库的 -wal/-shm。stop 最后一步会报 `database_sidecars_present`，只要 `stop.receipts` 已通过，就说明会话已干净关闭。不要绕过闸门去改 STATE 内的文件（教训：第 7 步做了 checkpoint，状态树指纹随之改变，导致启动被拒）。注销前先手动停服。

## 计划（按顺序）

| 编号 | 内容 | 方式 | 生产影响 |
|---|---|---|---|
| A1 | stop 的 `closed_files` sidecar 规则与启动闸门统一。只拒绝 `i-core.sqlite` 的 sidecar 和被占用的 relay lock；其他 sidecar 记录在案，不报失败（启动闸门的状态树已覆盖它们）。补合成测试。 | relay | 维护工具，需在 `<OUT>` 换一份受保护的工具副本，不换包 |
| A2 | ready 检查碰上宿主正在退出时，`Open` 返回 null，不再抛 `session_host_window_mismatch`。等待 ready 失败时读出新会话 `child.json` 的 `error_code` 一并报告。 | relay（可与 A1 合为一份合同） | 同上 |
| A3 | close/register 入口透出内部错误码；D1a 换包配置生成器直接产出受保护的 backup 配置。 | relay | 同上 |
| A4 | relay watcher 自己解析 codex 路径；headless 启动器写进安装脚本并入库。 | relay | 只影响 watcher |
| C1 | App 时间线按 device_id 显示来源（“ChatGPT”/“Claude”），不再统一写“网页端”。 | relay | 需用户构建并安装 App |
| D1 | 前端身份注册表：redirect URI 与 frontend 一一对应，未知回调默认拒绝。当前 `frontendForRedirectUri` 遇到非 ChatGPT 回调默认归为 claude_web，白名单一旦放宽就会记错来源。 | relay | MCP 源码，用 C1 `update-mcp-source` 流程部署 |
| D2 | 接入 Sesame：先让 Codex 只读查 MCP 日志，拿到它被拒时使用的 redirect_uri；然后加回调与 `sesame` 身份，配对，更新读取策略。 | 只读 → relay → 生产（手动） | 有 |
| D3 | Gemini：先确认消费者版是否支持自定义远程 MCP，支持再照 D2 做。 | 调研 | — |
| R1 | shortcut-mail relay 关闭时确认已 checkpoint（属于运行包 INVENTORY 内的改动）。 | 留到下次换包一起做 | 换包 |
| L | 注销强杀复现（PR #30 已关闭）：暂停，有需要再重开。 | — | — |

## 进行中
| 项 | 状态 | 下一步 |
|---|---|---|
| PR #32（文档合入） | 待用户合并 | — |
| A1+A2 | 待写合同 | 新窗口第一件事 |
