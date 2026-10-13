# 审核方交接：Core 发布（2026-10-13）

新审核窗口从这里开始。主合同：同目录 `RELAY_20261012_core-release-r1.md`（R0/R1/R2/D1/L 全文）。两份文档都在分支 `copilot/codexicore-cloud-review-20261011` 上。

## 分工

- 云端模型负责审核、写合同、写提示词。Codex 在用户电脑上执行。
- 两边之间靠用户手动转贴，不用 relay watcher。
- 审核方只推送自己的分支，不合并，不建 PR。合入 `v3-lab`、动生产、动真实数据，都要用户明确同意。

## 当前事实

- 已合并：A #26、B #25、C1 #27，以及 R1 #28。v3-lab = `6a063386`，即 #28 的合并提交。
- R1 已审核通过：19 个文件，48 项 INVENTORY 不变。
  - 遗留一项：`maintenance_safe_switch_r1_no_rollback.test.mjs` 的 byte-for-byte 测试在 Linux 的 LF 检出下失败，已列入 R2 第 4 条。
- 生产：现役任务 `HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2` 状态为 Running。AgentRelay 和 cleanclose 任务都已停用。

## 进行中

| 项 | 状态 | 下一步 |
|---|---|---|
| R2 生成器 | 待 Codex 从 `6a063386` 开分支 | 等报告，审核 PR |
| D1a 准备 | 第 0–2 步通过：新包 manifest `4e003c0b…`，候选 login `e8bdf4fe…`，准备 XML `bc94778d…`，MCP 候选 `f7d4872f…`。第 3 步 C1 dry-run 被拒，错误码 `backup_task_attachment_required`（update-mcp-source.mjs:107 要求备份中恰有 1 条非 `preserved/` 的 task 条目，生产备份共有 4 条 task 条目） | 让 Codex 只读列出 4 条 task 条目的形状（生产备份与候选备份各一份）；第 4 步可先做。拿到数据后再定是否在 R2 修改 C1 的选择规则 |
| D1b 切换 | R2 合并后进行，用户在场 | 逐步写提示词，每步单独同意 |
| L 注销强杀复现 | 未开始 | 另立合同 |
| 收尾 | 未开始 | DEVLOG（顶部 ≤15 行）与 I_PROJECT_STATE |

## 关键约束（新窗口必读）

- Core 配置除 `manifest_sha256` 外一律不能改；新包必须保持 48 项 INVENTORY。
- `register-package-switch-login` 只能在离线换包之后运行。停服必须用 `close-schema6-session.ps1`，因为它会产出登记要用的关闭回执。
- Codex 本机执行规则：
  - 所有 PS、node、git 命令直接申请提权；被自动审核拒绝就停下。
  - PS 5.1 子进程运行前去掉 `NODE_*` 和 `I_CORE_*`。
  - git 用 `bin\git.exe`。
  - 不用 `node -e` 或 `-Command` 传多行脚本，先写成文件再执行。
- 从任务参数解析 login 配置时，点源 `stop-schema6-session.ps1`，调用 `Get-Schema6LoginBinding`。它只读，并会核对 `owner_sid`。
- 止损：同一检查在连续两个提交上失败，就判为 blocked。同一 SHA 的 push 和 PR 两次运行只算一次。
- 仓库是公开的，文档里不写 SID、本机绝对路径或凭据。

## 审核方法

- Node 改动在云端 `/tmp` worktree 里自己跑 `node --test`。
- Windows 专项看 CI job 日志，确认测试确实执行了，而不是被跳过。
- 每次审核结论追加到主合同对应小节，并推送。
