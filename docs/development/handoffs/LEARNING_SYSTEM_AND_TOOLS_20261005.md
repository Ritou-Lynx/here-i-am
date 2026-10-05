# 交接：AI 学习系统与工具分工（2026-10-05）

来源会话：2026-10-03～10-05，讨论"AI 时代怎么学 + 工具怎么分工"，并落地了思源学习导师。本文给接手的新窗口用，尤其是**个人生活规划系统**的讨论：那边会碰到同一批工具，先读这里，避免推翻已定的分工或重复调研。

## 1. 已定的分工

原则：不追求 all-in-one，**每类数据只有一个家**；AI 负责在工具之间搬运。

| 职责 | 工具 | 说明 |
|---|---|---|
| 知识本体 | 思源笔记 3.8.6 | 已购"第三方同步"（S3/WebDAV，一次性），没有官方同步和订阅会员 |
| 学习账本 | 思源数据库"学习账本" | 一行一个知识点；间隔复习由 Codex 按规则排期，**不用闪卡**（用户不喜欢） |
| 可视化理解 | FlexNote（终身版） | 只导入需要画图理解的主题，不全量搬思源内容；FlexNote 里的改动不回流。教综（教师编）资料在 FlexNote"求职"空间，现有 Codex 导师线保持不变 |
| 出题、入账、出学习单 | 电脑上的 Codex | 通过思源内置 MCP 读写 |
| 语音带练 | ChatGPT dot（用户为 Pro） | 读电脑上的学习单，练完把结果写回电脑 |
| 生活数据、林埃 | Here I Am → i_core | 不变；**学习单不经过 i_core**，学习也不用 Here I Am 自制语音（体验差，用户已放弃自制前端） |

被否掉或暂缓的：
- 自制白板工作台：2026-10-02 已停，不重启。
- Obsidian：不加，避免再多一个工具。
- Here I Am 自制语音 / MiniMax 来电：用户评价"完全不可用"，不用于学习。
- 让 ChatGPT 普通语音按计划带练：快捷指令只能打开语音、不能发指令，计划塞不进去。

## 2. 学习系统现在怎么跑

```
思源（笔记 + 学习账本）
   ▲ 入账          │ 每天出学习单
 Codex（%USERPROFILE%\siyuan-study）──► today.md ──► dot 语音带练
   ▲                                                │
   └──── inbox\*.md（dot 写）或思源"学习收件箱" ◄────┘
```

- 仓库里的模板：[`tools/siyuan_tutor/`](../../../tools/siyuan_tutor/README.md)。`STUDY_AGENTS.md` 是 Codex 导师指令（在学习目录里改名为 `AGENTS.md`），`TUTOR_RULES.md` 是 dot 的语音规则，`subjects.md` 是科目表。
- 本机学习目录 `%USERPROFILE%\siyuan-study`，不在仓库里。
- 每天出学习单：设计为 Windows 计划任务跑 `codex exec`。**是否已经建好任务，本会话没有确认。**

### 进度（截至 10-04 晚）

- ✅ Codex 连上思源 MCP；日语科目初始化完成：笔记本"学习"、账本 12 个知识点（来自"日语语法"笔记本）、学习收件箱、日历视图。
- ✅ 第一份学习单（3 个新学点 + 口语任务）。
- ✅ dot：桌面应用里连上电脑（dot 资料页 → Computers → Your computer → Allow access）；Custom rules 已加（位置：设置 → Personalization → Permissions → Custom rules）；读文件、往 inbox 写文件都验证过。
- ✅ 第一次通话：除语速外顺畅。语速调慢后一两分钟内回弹；dot 通话没有逐轮转写。
- 已按反馈修订（44d84dd）：慢速规则、结果里逐条记纠正、学习单和记录里用可点的链接（思源里用块引用 `((id "标题"))`，`today.md` 里用 Markdown 链接）。
- ⏳ 待确认：新规则拷进学习目录后语速是否改善；首次入账；计划任务；Tasker 模拟来电（未写）。

## 3. 核实过的外部事实（2026-10-03～05）

**思源 3.8.6**（2026-09-29）
- 内置 MCP：`http://127.0.0.1:6806/mcp`，鉴权 `Authorization: Bearer <API Token>`；3.8.6 起也支持 OAuth 2.1（DCR + PKCE），可以经隧道接 claude.ai / ChatGPT 网页。依据源码 `kernel/mcp/server.go`、`kernel/model/mcp_oauth.go`。
- 工具清单由用户导出，见 `tools/siyuan_tutor/README.md` 的 Codex 白名单；`database` 工具能建表、加行、改单元格，但**不能建视图**。
- 内置 AI Agent，工作空间 `data/ai/AGENTS.md`，电脑和手机都能用；Agent 本身也能连外部 MCP。
- 免费：插件、挂件、数据库、闪卡、API、ECharts 图表块。插件 API 有 `addTab`、`addDock`（含手机）、`openTab`、`onLayoutReady`。`data/plugins` 和 `data/widgets` 会随同步到手机（源码 `kernel/model/repository.go`）。

**ChatGPT**
- dots：Pro 和 Business Premium 才有（Plus 没有）。
  - 只用官方插件，不能接自定义 MCP。
  - 通话只能由用户在 dot 对话里点电话按钮发起；用户看到官方规划里有"主动来电"，过渡期打算用 Tasker 模拟来电。
- 自定义 MCP（开发者模式）：公开资料显示只在网页端可用，Plus/Pro 能否写入说法不一。
- 定时任务：Plus 最多 5 个活跃任务，网页和手机都可用，可推送；Pulse 已停。

**FlexNote 1.1.56**
- MCP 只在本机 `127.0.0.1:39125`，只能操作当前打开的空间。
- 有自定义 CSS 和 Mermaid；没有插件系统、自定义首页、闪卡；iOS 还在开发。
- 能从思源增量重新导入。

**Heptabase**：AI Tutor 2026-03-31 上线，8 月有手机版。本会话只拿它作参照，没有采用。

## 4. 和"生活规划系统"相关的已有线索

- **看板（未开工，只是提议）**：做成思源插件当首页。
  - 数据：i_core 的生活数据加思源学习账本，每天投影成 JSON。
  - 交互：点击跳回原笔记或原记录；就地提问交给思源 Agent，并把 i_remote_mcp 接进 Agent。接入前要把思源的 OAuth 回调 `/api/ai/mcp/oauth/callback/...` 加进 i_remote_mcp 的回调白名单。
  - 原任务单 B5 打算在 FlexNote 里用 Mermaid 出看板，因 FlexNote 没有首页和插件，建议改到思源。
  - 呼应 `docs/design/whiteboard-requirements.md`"首页 = 模块化 dashboard，图表打底、林埃的观察叠在上面"。
- **Here I Am 已有的生活数据**：Memory V3 卡片类型含 `expense_entry`、`income_entry`、`shopping_order`、`sleep_record`、`task`、`schedule`、`plan`；手机端还有 Ledger、Schedule 设计（见 `docs/design/春雨昼眠主题*.md`）。COROS 手表数据有 MCP 可用。
- **提醒和推送**：用户不爱点通知，通知容易堆积。更有效的是"像来电一样"的强提醒，加固定时间的语音互动。生活规划系统若需要提醒，应沿用这个结论。
- **数据边界**（AGENTS.md）：Project Memory 和生活事实、关系记忆隔离；普通聊天不自动成为 User-truth；私密会话不出站。学习账本放在思源，不进 Memory V3。

## 5. 给新窗口的建议

- 先读本文、[项目状态](../I_PROJECT_STATE.md)、[任务单](../PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md)。涉及学习部分再读 `tools/siyuan_tutor/`。
- 生活规划沿用同一个分工原则：先定"每类数据的家"（规划和待办放思源数据库还是 Here I Am Schedule），再定 AI 怎么搬。
- 学习系统的后续修订（语速、Tasker、计划任务）留在学习那条线，生活规划窗口不要改 `tools/siyuan_tutor/`；需要联动时只改接口约定，比如看板读哪些字段。
