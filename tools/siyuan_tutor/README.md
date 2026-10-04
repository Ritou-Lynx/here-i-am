# 思源学习导师

笔记和学习账本都放在思源笔记里。电脑上的 Codex 通过思源内置 MCP 出题、入账、每天出学习单；语音练习交给 ChatGPT dot（或 GPT voice 项目），按学习单带练，结果再由 Codex 入账。工具用法基于思源 3.8.6 的 MCP 工具清单。

```
思源（笔记 + 学习账本）
   ▲ 入账          │ 每天出学习单
   │               ▼
 Codex（电脑，本目录）──► today.md ──► dot / GPT voice 语音带练
   ▲                                     │
   └──── inbox/*.md 或思源"学习收件箱" ◄──┘ 学习结果
```

| 文件 | 给谁 | 作用 |
|---|---|---|
| `STUDY_AGENTS.md` | Codex | 导师指令：检索、出题、账本、排期、入账、出学习单。复制到学习目录后改名为 `AGENTS.md` |
| `TUTOR_RULES.md` | dot 或 GPT voice | 语音带练规则和结果格式 |
| `subjects.md` | Codex | 科目表，先建了日语 |

## 一次性设置

### 1. 思源

1. 升级到 3.8.6 以上，学习时保持开着（MCP 跑在思源内核里，地址 `http://127.0.0.1:6806/mcp`）。
2. 设置 → 关于，复制 **API Token**。不要贴进聊天或截图。
3. 在 AI 设置里的 MCP 对外能力中，能关的先关掉：工作区文件、数据快照、同步、集市、技能、解压、导入、HTTP 请求。下面 Codex 的白名单也会挡住它们，这里是第二道保险。
4. 建议先在思源里手动建一个数据快照，作为回退点。

### 2. Codex

PowerShell 里执行，然后**完全重启** Codex：

```powershell
setx SIYUAN_API_TOKEN "粘贴令牌"
```

在 `%USERPROFILE%\.codex\config.toml` 加入：

```toml
[mcp_servers.siyuan]
url = "http://127.0.0.1:6806/mcp"
bearer_token_env_var = "SIYUAN_API_TOKEN"
startup_timeout_sec = 20
tool_timeout_sec = 120
enabled_tools = ["system", "workspace", "notebook", "document", "block", "dailynote", "search", "sql", "outline", "ref", "attr", "tag", "database", "template"]
```

白名单之外的工具（file、repo、sync、bazaar、skill、unzip、import、export、http_request、web_fetch、web_search、inbox、asset、image、history、bookmark）Codex 看不到。白名单里的 notebook、document、block、database、tag 仍带删除类动作，靠导师指令禁止；要更严，可以给这几个工具加 `tools.<工具名>.approval_mode = "prompt"`，代价是每次读写都要你点确认。

### 3. 学习目录

在电脑上建 `%USERPROFILE%\siyuan-study`（不要放进本仓库，也不要和 FlexNote 导师的 `~/study` 混用），复制进去：

- `STUDY_AGENTS.md`，改名为 `AGENTS.md`
- `TUTOR_RULES.md`
- `subjects.md`

再建一个空的 `inbox` 文件夹。

### 4. 初始化

在学习目录里启动 Codex，说"初始化日语"。它会先列出要建的文档、数据库和第一批知识点，你确认后再建。建好后在思源里给"学习账本"加一个日历视图（按"下次复习"），并把 `subjects.md` 的状态改为"已初始化"。

### 5. 每天自动出学习单

先在学习目录里手动说一次"出今天的学习单"，确认流程顺畅、不会卡在确认上。然后在 Windows 任务计划程序里新建一个每天早上（例如 06:30）的任务：

```powershell
codex exec --cd "$env:USERPROFILE\siyuan-study" --full-auto "出今天的学习单"
```

任务运行时电脑要开着、思源要开着。没开的那天就没有新学习单，语音导师会说"今天的学习单还没生成"。

## 语音练习

### dot（首选）

1. 在 dot 的资料页连接你的电脑（ChatGPT 桌面应用要开着，电脑在线）。
2. 给 dot 的指令，原样发过去：

   > 你是我的日语语音导师。每次我找你学习，先读我电脑上的 `%USERPROFILE%\siyuan-study\TUTOR_RULES.md` 并严格照做，再读同目录的 `today.md`。除了按规则往 `inbox` 文件夹新建结果文件，不要修改电脑上的任何文件，不要替我给任何人发消息。

3. 在 Custom Rules 里再写一遍硬边界：只能在 `siyuan-study\inbox` 新建文件；不得修改或删除其他文件；不得对外发送任何内容。
4. 学习时在 dot 对话里点电话按钮。

### GPT voice 项目（备选）

把 `TUTOR_RULES.md` 的内容贴进一个 ChatGPT 项目的指令。学习单需要作为第一条消息进入对话，目前只能手动贴，或等 Tasker 方案（见下）。结果由你分享到思源"学习收件箱"。

### Tasker"来电"（过渡方案）

在 dot 能主动来电之前，用 Tasker 模拟来电，解决通知堆着不点开的问题：

- 每天固定时间：全屏场景 + 铃声，按钮"接听""30 分钟后"。
- 接听：打开 ChatGPT，进入 dot 对话（或项目），再点电话 / 语音按钮（需要 AutoInput，ChatGPT 改版后可能要重新录制点击位置）。
- 不接：30 分钟后再响，最多两次。

具体配置步骤待你确认用 dot 之后再补。

## 已知限制

- 思源和 Codex 都在电脑上，出学习单和入账需要电脑开着；语音带练本身不需要（dot 读 `today.md` 时需要电脑在线）。
- 账本的单元格写法（`STUDY_AGENTS.md`"写账本"一节）按思源数据库通用格式编写，初始化时 Codex 会先改一个单元格核对；如有出入，以思源返回为准并反馈修订。
- dot 只认官方插件，不能直接调思源 MCP，所以它通过本机文件和 Codex 交接。
