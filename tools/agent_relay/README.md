# Agent Relay：Claude 规划审阅，Codex 本机执行，经 GitHub PR 自动接力

不再手动在两个窗口之间复制粘贴。Claude 只能用网页端，所以它留在 claude.ai/code 云端；Codex 在电脑上执行；两边通过同一个 PR 的评论交接。

```
你 ──一句话目标──▶ Claude（claude.ai/code 云端会话，订阅 PR）
                    │ ① 开 PR：任务合同 + 第 1 轮指令 [to-codex]
                    ▼
                GitHub PR ◀─────────────────────────────┐
                    │                                    │ ③ 推送 + 回帖 [to-claude]
                    ▼                                    │
     电脑上的 watcher（每 3 分钟看一次）─② codex exec─▶ Codex（PR 专用 worktree）
                    
     ④ 回帖唤醒 Claude → 读真实 diff 审阅 → 返修 [to-codex] / 完成 [done] / 问你 [to-human]
```

| 文件 | 给谁 | 作用 |
|---|---|---|
| [PROTOCOL.md](PROTOCOL.md) | 全部 | 交接契约：标签、评论标记、轮数、公开边界 |
| [BUILD_BRIEF.md](BUILD_BRIEF.md) | Codex | watcher 实现规格与测试清单 |
| [CODEX_ROUND_PROMPT.md](CODEX_ROUND_PROMPT.md) | watcher → Codex | 每轮执行提示词模板 |
| [`.claude/skills/agent-relay/SKILL.md`](../../.claude/skills/agent-relay/SKILL.md) | 云端 Claude | 发起、审阅、收尾的操作手册 |

## 做出来以后的效果

**你做的事只剩三件**：在 claude.ai/code 开会话说目标；手机上收到 GitHub 通知时看一眼；最后自己验收并点合并。

一次典型接力：

| 时间 | 发生什么 | 你看到什么 |
|---|---|---|
| 0 分 | 你在 claude.ai/code 说“用接力做：给 X 加 Y” | — |
| ~10 分 | Claude 读代码、写合同、开 draft PR、发第 1 轮指令 | PR 出现，带 `agent-relay` 标签 |
| ≤3 分后 | watcher 接单，指令评论出现 👀 | — |
| +10~40 分 | Codex 实现、跑测试、提交；watcher 推送并回帖，评论变 🚀 | PR 里多了提交和一条 [to-claude] |
| +几分钟 | Claude 被唤醒，读 diff 审阅；不过关就发第 2 轮返修，循环 | PR 里一来一回的指令和结果 |
| 结束 | Claude 发 [done] 并 @你，列出需要你亲自做的事（构建、装机、真人体验） | **手机收到 GitHub 通知** |

中途 Codex 卡在需要你拍板的问题上，Claude 能按合同和仓库规则回答的就直接答；涉及产品取舍、权限、真实数据的才 @你。

**它不会做的**：不合并、不 force-push、不构建安装 App、不碰真实数据和账户。最多 4 轮（1 轮执行 + 3 轮返修），超了就停下 @你。

**限制，提前知道**：

- 电脑要开机、watcher 计划任务在跑；关机期间指令会排队，开机后 3 分钟内接上。
- 延迟主要是 Codex 的执行时间，加上最多 3 分钟轮询；不是实时聊天。
- 云端 Claude 没有 Flutter，审 Dart 改动靠读 diff 和 Codex 贴出的 analyze/测试结果；Node 工具它能自己跑测试复核。
- **仓库公开**，PR 和评论任何人可见。只适合源码工作；私人数据、生活资料、令牌永远不进 PR。
- 每轮都消耗 Claude 和 Codex 的额度。
- 随时叫停：给 PR 加 `relay-paused` 标签，或直接关闭 PR。

## 安装：交给 Codex

在**本仓库目录**里启动 Codex，按顺序发下面两段。

### 第一步：实现 watcher

```text
拉取分支 claude/wonderful-carson-a26i9d，读 tools/agent_relay/BUILD_BRIEF.md、PROTOCOL.md、CODEX_ROUND_PROMPT.md 和根目录 AGENTS.md。
按 BUILD_BRIEF 在 tools/agent_relay/ 实现 watcher，零 npm 依赖，测试清单 12 项全部写成 node --test 用例。
先运行 codex exec --help、gh --version，把 codex exec 的实际参数对齐到本机版本。
完成后：node --test tools/agent_relay/ 全部通过；更新 docs/development/I_PROJECT_STATE.md 和 DEVLOG.md 顶部各一小段；提交并推送到同一分支（不 force）。
把测试结果和本机 codex / gh / node 版本告诉我。
```

### 第二步：本机配置和计划任务

```text
帮我把 Agent Relay watcher 在本机装好，不改仓库源码。

1. 确认 gh auth status 和 codex login status 都是当前用户已登录；没登录就停下告诉我怎么登。
2. 用 gh 在 Ritou-Lynx/here-i-am 建三个标签（已存在就跳过）：agent-relay、relay-paused、relay-needs-human。
3. 复制 tools/agent_relay/relay.config.example.json 为 tools/agent_relay/.state/config.json，填本机 repoPath 和仓库外的 worktreeRoot。
4. 运行 node tools/agent_relay/relay_watcher.mjs --dry-run，贴输出。
5. 用 install_relay_task.ps1 注册计划任务（当前用户、每 3 分钟），确认任务存在且上次运行结果为 0。
6. 告诉我已经可以冒烟了。
```

### 第三步：冒烟（找 Claude）

在 claude.ai/code 对本仓库开会话，说“接力冒烟”。Claude 会开一个只改 `tools/agent_relay/SMOKE.md` 的小 PR。看到 👀 → 🚀 → [to-claude] → Claude 审阅 → [done] 走通即完成。首次冒烟同时核对 Claude 评论显示的作者账号，必要时加进 `allowedAuthors`。

## 日常用法

在 claude.ai/code 对本仓库开会话：

> 用接力做：<目标>。

Claude 会按 SKILL 手册开 PR、发指令、订阅 PR。之后你可以关掉网页，等 GitHub 通知。想插话就在 PR 里直接评论，或回到那个会话说。
