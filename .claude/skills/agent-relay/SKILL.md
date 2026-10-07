---
name: agent-relay
description: 用户说“用接力做…”“交给 Codex 执行”“接力冒烟”，或要 Claude 规划审阅、本机 Codex 执行一项源码任务时使用。经 GitHub PR 评论与用户电脑上的 watcher 自动交接，Claude 不需要本机环境。
---

# Agent Relay：云端 Claude 操作手册

先读 `tools/agent_relay/PROTOCOL.md`（契约，以它为准）和根目录 `AGENTS.md`。你负责规划、指令和审阅；写代码交给 Codex。

## 1. 发起

1. 读相关代码，把目标落成合同（PROTOCOL“任务合同”格式）：完成标准逐条可验证，允许路径尽量窄，验证命令写成 Codex 在 Windows 本机可直接运行的形式。目标含糊到影响合同时先问用户一句；否则直接推进。
2. 在本会话指定分支上提交 `docs/development/handoffs/RELAY_<YYYYMMDD>_<slug>.md`（合同全文），推送。
3. 开 **draft** PR，base `v3-lab`。描述按 `.github/PULL_REQUEST_TEMPLATE.md` 的标题填写，并在最前面放 `<!-- relay:contract v1 -->` 合同块。加标签 `agent-relay`。
4. `subscribe_pr_activity` 订阅该 PR。
5. 发第 1 轮 `<!-- relay:to-codex round=1 -->` 评论：把合同拆成具体步骤，写清本轮验证命令。
6. 告诉用户 PR 链接，说明之后会在 GitHub 通知里见。

**接力冒烟**：合同为“新建 `tools/agent_relay/SMOKE.md`，一行内容 `relay smoke ok <日期>`”，验证命令 `git show --stat HEAD`。走通后在 [done] 里请用户关闭 PR 而不是合并。

## 2. 收到 `relay:to-claude`

1. `git fetch` 并快进本地分支到 PR head；读 `git diff origin/v3-lab...HEAD` 的真实改动，不采信摘要。
2. 对照合同逐条核：完成标准、路径边界、验证结果。Node 代码在云端自己跑 `node --test` 复核；Dart 只能读 diff，重点看逻辑、边界和 Codex 贴出的 analyze/测试输出是否覆盖改动。
3. 按状态处理：
   - `done` 且全部达标 → 第 3 节收尾。
   - `done` 未达标、`dirty`、`failed` → 下一轮 `to-codex`，每条问题带文件:行号、要求、验收。`failed` 是环境问题（登录、网络、worktree 冲突）而非代码问题时，发 `to-human` 说明需要用户在电脑上做什么。
   - `blocked` → 能依合同、AGENTS.md 和既有决定回答的直接答（作为下一轮指令）；涉及产品语义、权限、外部影响、真实数据或用户偏好的发 `to-human`。
4. 下一轮编号 = 上一轮 + 1。第 4 轮仍不过 → 不再发指令，加 `relay-needs-human`，发 `to-human` 总结卡点和建议。
5. 一轮执行中不要往分支推送任何东西。

## 3. 收尾

1. 在分支上按 AGENTS.md 更新 `DEVLOG.md` 顶部（≤15 行）和 `docs/development/I_PROJECT_STATE.md`（Codex 用了 SKIP_PROJECT_STATE，状态由你统一写），推送。
2. PR 转为 ready for review。
3. 发 `<!-- relay:done -->` 评论并 @Ritou-Lynx：结论、验证、限制，以及需要用户亲自做的事（构建前 `verify_critical_fixes.ps1`、装机、真人体验）。**不合并。**

## 4. 唤醒与兜底

- 期间若用户在 PR 上直接评论（不带标记），当作补充或纠正，体现在下一轮指令里。
- 有 `relay-paused` 时停止发指令，只回答用户。
- 发出 `to-codex` 后用 `send_later` 设约 90 分钟的兜底检查；到时没有 `to-claude`、指令评论也没有 👀，说明 watcher 可能没在跑，发 `to-human` 提醒用户看电脑。

## 公开边界

仓库公开。合同、指令、评论里不写令牌、真实数据、私人或生活内容、本机绝对路径。
