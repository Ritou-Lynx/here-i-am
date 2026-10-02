# 任务单：FlexNote 知识库 × 三端串联（2026-10-02）

## 方向决定

- **白板工作台停止开发。** 知识库、白板、视频标注和学习交给 FlexNote（终身版，已含 Flexnote AI 和 3000 点智能索引）。Here I Am 不再投入白板 UI。
- **Here I Am 只保留别人做不了的部分：** 一条消息时间线、一个记忆库、一份林埃身份，供多个聊天前端共用。
- **前端分工：** Claude 网页端负责日常文字聊天；Here I Am 手机 App 负责私密和大尺度聊天；GPT voice 随口聊，记录不迁移；ChatGPT 文字端可选接入。
- **轻量通道：** 这里的任务只有用户本人使用，不碰真实账户的生产执行。按"能跑、用着顺手"验收，不做精确 SHA 绑定，也不需要真人 Gate 签收。真实数据库、令牌和私人聊天内容一律不进 GitHub。

## 分工规则

| 标记 | 谁做 | 做什么 |
|---|---|---|
| **[Claude]** | 云端会话 | 在仓库里写代码、写测试、写指令文本，然后推送分支。云端有 Node 22，没有 Flutter，所以 Dart/App 改动交给 Codex |
| **[Codex]** | 你电脑上的 Codex | 拉取分支，在真实环境里安装、配置、跑真实数据，以及所有 Flutter/Dart 改动 |
| **[你]** | 你本人 | 做决定、处理账号和令牌、在官方客户端里点设置、试用并反馈 |

每个任务都写了交付物和验收标准。完成后在对应条目前打勾，并在 `DEVLOG.md` 顶部记一行。

---

## 任务一：FlexNote 接入 Codex，成为 AI 知识库和学习空间

目标是让 Codex（用 ChatGPT 订阅登录）通过 FlexNote MCP 检索和写入笔记，并能带你学任何主题：从知识库现出新题，同时记下薄弱点，不需要固定的闪卡。

已确认的事实（官网 releases 与 wiki，2026-10-02 读取）：
- 1.1.53 起支持 MCP，Cursor 和 Codex 可以读写笔记、列出工作区、操作当前库。服务只监听 `127.0.0.1:39125`，需要访问令牌。
- 内置 AI 有 Ask 和 Agent 两种模式，都走你自己的 key。语义索引和 OCR 消耗点数，按处理的内容量计；关键词检索不消耗点数。
- 支持 Windows、macOS、Android 和 Web，iOS 还在开发中。可以导出 Markdown（附件一起打包），可以导入思源和 Obsidian。
- 没有闪卡或间隔重复功能。这个功能我们也不需要。

| # | 谁 | 任务 | 验收 |
|---|---|---|---|
| A1 | [你] | 在 FlexNote 里**重置 MCP 访问令牌**（旧令牌出现在了聊天截图里），然后把"Codex CLI"标签页里的配置粘贴到 Codex 的配置文件 | Codex 重启后能看到 flexnote 工具 |
| A2 | [你] | 在 Codex 里问"列出 flexnote 的所有工具及参数"，把输出发给 Claude（先删掉令牌） | Claude 拿到工具清单 |
| A3 | [你] | 建一个专门的学习目录（例如 `~/study`），以后学习都在这个目录里启动 Codex | 目录存在 |
| A4 | [Claude] | 根据工具清单编写通用的"学习导师"指令（放进 A3 目录的 `AGENTS.md`），内容包括：<br>· 知识库检索策略：关键词加同义词，多轮搜索<br>· 学习模式：讲解、出题、追问、复盘<br>· 学习记录卡的格式：日期、主题、错题、薄弱点<br>· 开场先读学习记录卡<br>· 写入边界：只写学习记录卡和"学习/"下的新卡，不改原笔记 | 指令文件推送到分支，并附使用说明 |
| A5 | [你] | 挑一个主题真实学一次，记下哪里别扭 | 有一条反馈 |
| A6 | [Claude] | 根据反馈修订指令 | 第二次使用明显顺手 |
| A7 | [你]+[Claude] | 单独讨论**教资和教编的学习方案**：考试时间、资料来源、题型 | 另开任务单 |

任务一不依赖任务二，**建议最先做**，当天就能用上。

---

## 任务二：Claude 网页端 × Here I Am 手机 App ×（可选）ChatGPT 三端串联

### 目标形态

```
Claude 网页（文字）  ─┐                      ┌─ 读：身份 + 最近消息（已过滤）+ 记忆检索
Here I Am 手机 App   ─┼─  i_core（电脑常驻）  ─┤
ChatGPT 文字（可选）  ─┘   时间线 + 记忆 + 身份 └─ 写：本端产生的对话轮次 + 显式记录
```

- **权威数据在电脑上的 i_core。** 手机 App 是它的客户端，已有 `CoreSyncClient`，通过 Tailscale HTTPS 同步聊天。
- **"同一套上下文"的含义：** 同一条时间线、同一个记忆库，再加每轮按需检索。它不是各家模型共享同一个上下文窗口；那在技术上做不到。
- **已有可复用的部件：**
  - `tools/i_core`：消息时间线、change feed、设备配对、`import_v3_chat.mjs` 导入器
  - `tools/i_continuity_gateway`：本机 stdio MCP，包含 `i_bootstrap`、`i_voice_turn` 等
  - `lib/data/services/sync/core_sync_client.dart`
- **还缺的部分：**
  - Memory V3 还没有进入 i_core（i_core README 写明了"不会同步 Memory V3"）
  - 没有一个公网可达的远程 MCP 端点
  - 没有私密分级
  - 没有一个从网页端写回时间线的工具

### B0　决定（先做，几分钟）

| # | 谁 | 任务 | 说明 |
|---|---|---|---|
| B0.1 | [你] | 决定 i_core 跑在哪里：**电脑常驻**，还是租一台小云主机 | 电脑关机时 Claude 网页端就读不到记忆。先用电脑起步，以后再迁移也不难 |
| B0.2 | [你] | 定私密规则：哪些角色或会话**永远不出站**（不进入任何官方前端的上下文） | 大尺度内容进入 Anthropic 的对话会增加封号风险，这一条是保护账号用的 |

### B1　数据归位：手机 → i_core

| # | 谁 | 任务 | 验收 |
|---|---|---|---|
| B1.1 | [Codex] | 在电脑上启动 i_core，确认手机 App 的同步是否还在工作；用 ADB 导出手机上的 V3 数据库副本，用现有的 `import_v3_chat.mjs` 先 dry-run，再 apply | 报告导入条数，与手机上的条数核对一致 |
| B1.2 | [Claude] | 写 `import_v3_memory.mjs`：把 Memory V3 的有效版本（memory_cards 及相关表，只取当前有效版本）**单向快照导入** i_core 的只读记忆表，可以重复导入；用 fixture 写测试 | 测试通过，推送分支 |
| B1.3 | [Claude] | i_core 加私密分级：按 `character_id` 或会话配置 `exposure = shareable / private`，默认 private 优先；所有对外读取接口只返回 shareable 的内容；补测试 | 测试覆盖私密内容"一条都不出站" |
| B1.4 | [Codex] | 在真实数据上跑 B1.2 和 B1.3，按 B0.2 填写私密配置 | 报告记忆卡数量，抽查几条私密内容确实被过滤 |

### B2　Claude 网页端：先能读

claude.ai 的自定义 connector 从 Anthropic 的服务器访问你的 MCP，所以必须是公网 HTTPS 地址。鉴权实际上需要 OAuth：它会尝试动态客户端注册（DCR），纯无鉴权的服务端有已知的接入失败问题。Pro 及以上套餐可用。

| # | 谁 | 任务 | 验收 |
|---|---|---|---|
| B2.1 | [Claude] | 新建 `tools/i_remote_mcp/`：Streamable HTTP MCP 服务，内置一个**单用户最小 OAuth**（DCR + 授权页口令），只读 i_core。工具包括：<br>· `i_context`：身份 + 当前时间 + 最近 N 条 shareable 消息<br>· `i_recall`：在记忆库和时间线里做词法检索<br>用测试覆盖鉴权、私密过滤和工具返回 | 本地测试通过，推送分支 |
| B2.2 | [Claude] | 写给 Claude 用的 Project 指令和身份说明（参考 `identity.default.json` 与连续性文档） | 文本推送到分支 |
| B2.3 | [Codex] | 在电脑上部署 B2.1，用 Tailscale Funnel 暴露公网 HTTPS，设置开机自启 | 外网能访问 `/mcp`，未授权的请求被拒绝 |
| B2.4 | [你] | 在 claude.ai 的 设置 → Connectors 里添加这个地址并完成授权；建一个"林埃" Project，贴入 B2.2 的指令；把两个工具设为"始终允许" | 在网页端问"我七月在 Here I Am 里跟你聊过什么"，它能答上来 |

**B2 做完就能用了：Claude 网页端已经"认识你、记得手机里的事"。**

### B3　Claude 网页端：再能写回

| # | 谁 | 任务 | 验收 |
|---|---|---|---|
| B3.1 | [Claude] | 在远程 MCP 里增加两个工具：<br>· `i_chat_turn`：一次提交"上次调用之后的所有轮次"，返回最新上下文。按内容哈希去重，漏调的轮次在下一次调用时自动补上；写入时间线，来源标记为 `claude_web`<br>· `i_remember`：用户说"帮我记一下"时写入一条显式记录，可以编辑和删除，不自动升级为 User-truth | 测试覆盖去重和漏轮补齐 |
| B3.2 | [Claude] | 更新 Project 指令：每轮先调用 `i_chat_turn`，再回答 | 推送分支 |
| B3.3 | [Codex] | 手机 App 能显示来源为 `claude_web` 的消息，并标注来源（Flutter 改动加本机测试） | 网页端聊过的话出现在手机 App 里 |
| B3.4 | [你] | 正常用一周，记下漏记和不顺手的地方 | 一份简短反馈 |
| B3.5 | [Claude]（可选） | 如果漏记明显：写一个只读自己 claude.ai 页面的浏览器扩展，确定性回写；或者写一个官方数据导出的导入器，定期补齐 | 按 B3.4 的反馈决定做不做 |

### B4　ChatGPT（可选，B3 稳定后再做）

| # | 谁 | 任务 | 说明 |
|---|---|---|---|
| B4.1 | [你] | 在 ChatGPT 的 设置 → Connectors → Advanced 里看能不能开启 Developer mode，能不能添加 B2 的地址 | 公开资料对 Plus/Pro 是否支持**写入**说法不一，必须实测 |
| B4.2 | [Claude] | 如果能接：复用同一个远程 MCP，按需调整鉴权和工具描述；如果只能读，就只开放 `i_context` 和 `i_recall` | — |
| B4.3 | — | GPT voice：实时语音调不了工具，记录不迁移。真想留下来的事，回到文字端说一句"帮我记一下" | 不做开发 |

### B5　FlexNote 生活数据看板（依赖 A2 和 B1）

| # | 谁 | 任务 | 验收 |
|---|---|---|---|
| B5.1 | [Claude] | 写数据投影脚本：从 i_core 生成每日摘要和结构化生活记录（消费、饮食、运动、心情等）JSON；写一份给 `codex exec` 用的"写入 FlexNote"指令，内容包括日记摘要、按标签和属性建记录卡、每周重新生成 Mermaid 图表 | 推送分支 |
| B5.2 | [Codex] | 在电脑上设置每日计划任务：运行投影脚本，再用 `codex exec` 写入 FlexNote | FlexNote 里每天出现一条摘要，"我的生活"白板上图表在更新 |
| B5.3 | [你]（可选） | 运动数据直接取 COROS（手表），不用口述 | — |

边界：FlexNote 只用来展示，数据单向从 i_core 流过去。在 FlexNote 里的修改**不会回流**成生活事实，要改事实，在聊天里说或者在记忆库里改。

---

## 建议顺序

1. **今天**：A1 → A2 → A3（Claude 收到工具清单后接着做 A4）。同时完成 B0.1 和 B0.2 两个决定。
2. **第一个里程碑**：B1 → B2，在 Claude 网页端能聊到手机里的记忆。
3. **第二个里程碑**：B3，网页端聊的内容能回到 Here I Am。
4. **之后按需**：B5 生活看板、B4 ChatGPT、B3.5 补齐手段。

每一步都能单独用上。哪一步做完发现"已经够用"，就可以停在那里。

## 参考

- FlexNote 发布记录：https://myflexnote.com/releases
- FlexNote AI 文档：https://wiki.myflexnote.com/zh/ai
- Claude 自定义 connector：https://support.claude.com/en/articles/11503834
- 现有连续性架构：[LIN_AI_CROSS_TOOL_CONTINUITY.md](../companion-first/LIN_AI_CROSS_TOOL_CONTINUITY.md)
- i core：[tools/i_core/README.md](../../tools/i_core/README.md)；i gateway：[tools/i_continuity_gateway/README.md](../../tools/i_continuity_gateway/README.md)
