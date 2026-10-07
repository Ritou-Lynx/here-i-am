<!-- relay:contract v1 -->
## 目标
用一次最小改动跑通 Agent Relay 端到端链路：Claude 发指令 → watcher 接单 → Codex 执行 → watcher 提交推送回帖 → Claude 审阅。

## 完成标准
- [ ] 新建 `tools/agent_relay/SMOKE.md`，内容恰好一行：`relay smoke ok 2026-10-07`
- [ ] 本轮改动只有这一个文件
- [ ] watcher 用 COMMIT 行提交并推送到本 PR 分支，回帖 `relay:to-claude status=done`

## 允许修改的路径
- tools/agent_relay/SMOKE.md

## 不做 / 边界
- 不改其他文件，不构建、不安装 App，不碰真实数据库、令牌和账户。

## 验证命令
- `git status --short`（应只出现 `tools/agent_relay/SMOKE.md`）
- `Get-Content tools/agent_relay/SMOKE.md`

## 需要真人的部分
- 本 PR 同时携带 Agent Relay 全部源码；冒烟通过后由用户决定是否合并到 v3-lab。
