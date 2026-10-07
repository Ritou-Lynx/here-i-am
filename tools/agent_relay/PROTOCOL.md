# Agent Relay 交接协议 v1

云端 Claude（规划、审阅）和本机 Codex（执行）经同一个 GitHub PR 接力。本文是双方和本机监听脚本（watcher）共同遵守的契约；改动本文须同步修改 watcher 的解析与测试。

## 角色

| 角色 | 在哪 | 做什么 | 不做什么 |
|---|---|---|---|
| Claude | claude.ai/code 云端会话，订阅该 PR | 写任务合同、开 PR、发每轮指令、读真实 diff 审阅、判定完成或升级给用户 | 合并 PR、在一轮执行中途推送代码 |
| watcher | 用户电脑，计划任务每 3 分钟跑一次 | 发现新指令 → 在 PR 专用 worktree 调 `codex exec` → 推送 → 回帖 | 判断代码对错、改写指令、force-push、合并 |
| Codex | 用户电脑，由 watcher 启动 | 按本轮指令实现、跑指定验证、提交 | 扩大范围、构建安装 App、碰真实数据和账户 |
| 用户 | GitHub 手机 App 通知 | 只处理 `to-human` 和 `done`；随时可加 `relay-paused` 叫停 | 复制粘贴 |

## 标签

| 标签 | 含义 |
|---|---|
| `agent-relay` | 开启接力。没有它 watcher 不看这个 PR |
| `relay-paused` | 用户叫停。watcher 跳过，Claude 不再发指令 |
| `relay-needs-human` | 超轮数或需要用户决定。watcher 跳过，直到用户移除 |

## PR 条件（watcher 逐条检查，任一不满足就跳过）

- 仓库为 `Ritou-Lynx/here-i-am`，PR 为 open，base 为 `v3-lab`。
- head 分支在本仓库（不是 fork），前缀为 `claude/` 或 `codex/`。
- 有 `agent-relay`，没有 `relay-paused` 和 `relay-needs-human`。

## PR 描述：任务合同

Claude 开 PR 时在描述里写合同，以 `<!-- relay:contract v1 -->` 开头：

```markdown
<!-- relay:contract v1 -->
## 目标
一句话结果。
## 完成标准
- [ ] 每条都能用命令或 diff 验证。
## 允许修改的路径
- tools/xxx/
## 不做 / 边界
- 不构建、不安装、不碰真实数据库与令牌。
## 验证命令
- node --test tools/xxx/
## 需要真人的部分
- 无 / 具体说明。
```

合同同时写进分支上的 `docs/development/handoffs/RELAY_<YYYYMMDD>_<slug>.md`，作为 PR 的第一个提交和留档。

## 评论标记

机器只认评论**第一行**的 HTML 注释，人看下面的正文。

| 第一行 | 谁发 | 意思 |
|---|---|---|
| `<!-- relay:to-codex round=N -->` | Claude | 第 N 轮指令。N 从 1 开始连续递增 |
| `<!-- relay:to-claude round=N status=S sha=X -->` | watcher | 第 N 轮结果。S 为 `done`、`blocked`、`dirty`、`failed`；X 为推送后的 head 短 SHA，失败时为 `none` |
| `<!-- relay:to-human -->` | Claude 或 watcher | 需要用户决定，正文 @Ritou-Lynx 并写清楚问题和选项 |
| `<!-- relay:done -->` | Claude | 审阅通过，正文 @Ritou-Lynx，列出需要真人做的事 |

`to-codex` 正文格式：

```markdown
<!-- relay:to-codex round=2 -->
**[to-codex] 第 2 轮：返修**

1. 问题：……（文件:行号）
   要求：……
   验收：……
2. ……

本轮验证：`node --test tools/xxx/`
```

## 一轮的生命周期

1. Claude 发 `to-codex round=N`。
2. watcher 发现后先给评论加 👀 反应（表示已接单），再在 PR 专用 worktree 里快进到 PR head，启动 Codex。
3. Codex 实现、验证、提交；最后一条消息按 [CODEX_ROUND_PROMPT.md](CODEX_ROUND_PROMPT.md) 的格式写结果。
4. watcher 推送（只快进，不 force），发 `to-claude round=N`，给指令评论加 🚀（成功）或 😕（失败）。
5. Claude 被唤醒，审阅后发下一轮 `to-codex`、`done` 或 `to-human`。

## 轮数与停止

- 最多 4 轮：第 1 轮执行，第 2–4 轮返修。watcher 拒绝 `round > 4`，并给 PR 加 `relay-needs-human`、发 `to-human`。
- Codex 回 `blocked`（需要决定）时：Claude 能依合同和仓库规则回答就发下一轮；涉及产品语义、权限、外部影响或用户偏好的，发 `to-human`。
- 一轮执行中（`to-codex` 已发、`to-claude` 未到）Claude 不推送代码，避免冲突。

## 公开边界

本仓库公开，PR 和评论任何人可见。合同、指令、结果里不写令牌、真实数据、私人聊天、生活资料和本机绝对路径；需要引用时写相对路径或“本机某配置”。watcher 回帖前做密钥模式扫描，命中则只贴占位说明，全文留本机日志。

## 永不

合并 PR、force-push、rebase 他人提交、删除分支、构建或安装 App、碰真实账户或生产执行、处理非白名单作者的评论。
