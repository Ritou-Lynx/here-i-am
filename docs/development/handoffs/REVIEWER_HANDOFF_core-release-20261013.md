# 审核方交接：Core 发布（2026-10-13，10-15 更新：审核方转为 Claude Code）

新审核窗口从这里开始。主合同：同目录 `RELAY_20261012_core-release-r1.md`（R0/R1/R2/D1/L 全文）。两份文档都在分支 `copilot/codexicore-cloud-review-20261011` 上。

## 分工

- 云端模型负责审核、写合同、写提示词。Codex 在用户电脑上执行。
- 10-15 起审核方由 Copilot 交给 Claude Code。PR #29 这一轮仍由用户手动转贴；之后是否改用 GitHub relay（`tools/agent_relay/PROTOCOL.md`，只处理 `claude/`、`codex/` 分支），由 Claude Code 与用户商定。
- 审核方只推送自己的分支，不合并，不建 PR。合入 `v3-lab`、动生产、动真实数据，都要用户明确同意。

## 当前事实

- 已合并：A #26、B #25、C1 #27，以及 R1 #28。v3-lab = `6a063386`，即 #28 的合并提交。
- R1 已审核通过：19 个文件，48 项 INVENTORY 不变。Linux 换行遗留已在 R2 修复。
- 生产：现役任务 `HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2` 状态为 Running。AgentRelay 和 cleanclose 任务都已停用。

## 进行中

| 项 | 状态 | 下一步 |
|---|---|---|
| R2 生成器 + C1 task 选择修复 | R2b 审核通过（10-15，HEAD `010988b8`，CI 两次运行各 9/9 全绿，R2b 各项 ✔，见主合同“R2b 审核”） | 已合并（v3-lab = `fa652c29`，树与 `010988b8` 相同） |
| D1a 准备 | 收尾时 C1 dry-run 被 `inventory_role_missing` 拒绝；修复 PR #31 已审核通过 | 用户合并 #31 后重跑 D1a 收尾（第 3、5 步） |
| D1b 切换 | R2 合并后进行，用户在场 | 逐步写提示词，每步单独同意 |
| L 注销强杀复现 | 用户决定停下（10-15）；PR #30 保持 draft，未复现 | D1 之后再议；重启时修 StrictMode bug |
| 收尾 | 未开始 | DEVLOG（顶部 ≤15 行）与 I_PROJECT_STATE |

### PR #29 第 3 轮复核清单（10-15 已完成：通过）

1. Codex 报告应为：只提交 `maintenance_r2_old_task.test.mjs`，`policyFixture()` 两项 SDDL 经 `GetSddlForm` 规范化，第 144、146 行仍是字面 `assert.equal`。
2. 核 `git diff 6a593a58..HEAD` 只动这一个文件。
3. CI 9/9 全绿；在 Schema6 维护、生命周期两个 job 日志里确认 R2b 各测试（含 inherited round-trip、preview TEMP、真实 RegisterOnly）是 ✔ 而不是跳过。
4. 若 CI 中 R2b 测试失败：止损触发，不再给 Codex 修复轮，向用户报告并给出判断。
5. 通过后：主合同追加“R2b 审核：通过”，请用户合并 #29。然后给 Codex 写 D1a 收尾提示词：以现役任务为 `--from-task` 重跑 C1 `--dry-run`（第 3 步），对现役任务跑 `old-task --preview`（第 5 步）；两步零写入、不停服，三项锚点前后复核。
6. 之后 D1b 按主合同“D1：部署顺序（更正版）”逐步进行，用户在场，每步单独同意；Codex 审批改为手动。

## 关键约束（新窗口必读）

- Core 配置除 `manifest_sha256` 外一律不能改；新包必须保持 48 项 INVENTORY。
- `register-package-switch-login` 只能在离线换包之后运行。停服必须用 `close-schema6-session.ps1`，因为它会产出登记要用的关闭回执。
- Codex 本机执行规则：
  - 所有 PS、node、git 命令直接申请提权；被自动审核拒绝就停下。
  - PS 5.1 子进程运行前去掉 `NODE_*` 和 `I_CORE_*`。
  - git 用 `bin\git.exe`。
  - 不用 `node -e` 或 `-Command` 传多行脚本，先写成文件再执行。
- 从任务参数解析 login 配置时，点源 `stop-schema6-session.ps1`，调用 `Get-Schema6LoginBinding`。它只读，并会核对 `owner_sid`。
- 止损：同一测试名或同一错误码在连续两个提交上失败，就判为 blocked（不按 job 计）。同一 SHA 的 push 和 PR 两次运行只算一次。
- 开发机共享 `%TEMP%` 有其他进程噪声；preview 的 TEMP 监测以 hosted CI 为准。
- hosted Windows runner 是 RID 500 账户，`GetSddlForm` 会缩写成 `LA`；SDDL 字面比较前先规范化。
- 仓库是公开的，文档里不写 SID、本机绝对路径或凭据。

## 审核方法

- Node 改动在云端 `/tmp` worktree 里自己跑 `node --test`。
- Windows 专项看 CI job 日志，确认测试确实执行了，而不是被跳过。
- 每次审核结论追加到主合同对应小节，并推送。
