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

## 设置：交给 Codex 做

能让 Codex 做的都写成了提示词，按顺序发给它。前提是思源开着，并且 Codex 已经能连上思源 MCP（地址 `http://127.0.0.1:6806/mcp`，鉴权为 `Authorization: Bearer <API Token>`）；还没连上的话，先把这个前提告诉 Codex，让它一并配好，令牌只走环境变量 `SIYUAN_API_TOKEN`，不写进文件和聊天。

### 第一步：检查配置、建学习目录

在**本仓库目录**里启动 Codex（要从仓库拷文件），发：

```text
帮我把思源学习导师装好，不碰思源里的任何笔记。

1. 检查 %USERPROFILE%\.codex\config.toml 里的 [mcp_servers.siyuan]：
   - 令牌必须走环境变量（bearer_token_env_var），文件里出现明文令牌就停下告诉我。
   - 没有 enabled_tools 白名单时，先备份再加上：
     enabled_tools = ["system", "workspace", "notebook", "document", "block", "dailynote", "search", "sql", "outline", "ref", "attr", "tag", "database", "template"]
     改完提醒我重启 Codex 才生效。
2. 用思源 MCP 的 system version 确认版本不低于 3.8.6。
3. 新建 %USERPROFILE%\siyuan-study，以及其中的 inbox 和 inbox\done 文件夹。
4. 从本仓库 tools/siyuan_tutor/ 复制：STUDY_AGENTS.md 改名为 AGENTS.md，TUTOR_RULES.md、subjects.md 原名。
   目标已存在且内容不同，先给我看差异，不要覆盖。
5. 最后告诉我：在 siyuan-study 目录里新开一个 Codex，说"初始化日语"。
```

### 第二步：初始化

在 `%USERPROFILE%\siyuan-study` 里新开 Codex（`AGENTS.md` 只在这个目录里生效），说"初始化日语"。它会先列出要建的文档、数据库和第一批知识点，你确认后再建，并先改一个单元格核对账本写法。

### 第三步：试跑并设成每天自动

还在学习目录里，说"出今天的学习单"，看结果没问题后，发：

```text
把"每天出学习单"设成 Windows 计划任务：
1. 在 siyuan-study 里写一个 run-daily.cmd：用 codex 可执行文件的完整路径运行
   codex exec --cd "%USERPROFILE%\siyuan-study" --full-auto "出今天的学习单"
   输出追加到 siyuan-study\logs\daily-日期.log。
2. 先手动运行一次 run-daily.cmd，确认它不会卡在任何确认上、today.md 已更新。
3. 用 schtasks 建一个每天 06:30、以我当前用户身份运行的任务（时间先问我）。
4. 把任务名和怎么删除它告诉我。
```

任务运行时电脑和思源都要开着。没开的那天就没有新学习单，语音导师会说"今天的学习单还没生成"。

### 只能你自己做的

- **思源**：给"学习账本"加一个日历视图（按"下次复习"）。MCP 不能建视图，只能在界面里点。
- **思源（可选）**：AI 设置里把 MCP 对外能力中用不到的关掉（文件、快照、同步、集市、技能、解压、导入、HTTP 请求）；初始化前手动建一个数据快照当回退点。Codex 的白名单已经挡住这些工具，这里是第二道保险。
- **dot 和 Tasker**：在 ChatGPT 和手机上设置，见下文。

白名单里的 notebook、document、block、database、tag 仍带删除类动作，靠导师指令禁止；要更严，可以在 config.toml 里给这几个工具设 `approval_mode = "prompt"`，代价是每次读写都要你点确认。

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
