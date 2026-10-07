# 林埃的项目状态

## 开发协作：Agent Relay 经 GitHub PR 自动接力（2026-10-07）

用户只能用 Claude 网页端，要求 Claude 负责指令与规划、Codex 负责执行。方案不自建工作台、不复活 dev_agent_bridge，以 GitHub PR 为交接通道：claude.ai/code 会话写合同、开 draft PR、发 `relay:to-codex` 评论并订阅 PR；用户电脑上的 watcher 每 3 分钟查一次，在 PR 专用 worktree 运行 `codex exec`，推送（不 force）后回帖 `relay:to-claude` 唤醒 Claude 审阅。最多 4 轮，不合并、不构建安装、不碰真实数据；仓库公开，PR 内容不含私人资料。

已交付文档：`tools/agent_relay/`（PROTOCOL、BUILD_BRIEF、CODEX_ROUND_PROMPT、README）与 `.claude/skills/agent-relay/SKILL.md`。watcher 源码、标签、本机计划任务与真实冒烟待 Codex 执行；纯文档，未构建。

## 学习系统：思源为知识库与学习账本，dot 语音带练（2026-10-04）

用户认定不追求 all-in-one：思源（3.8.6，已购第三方同步）作知识本体和学习账本；FlexNote 只用于需要可视化理解的主题，不全量搬入思源内容，教综线保持现状；ChatGPT dot（用户为 Pro）作语音带练前端，用户期待官方后续支持 dot 主动来电，过渡期用 Tasker 模拟来电。Here I Am 自制语音不用于学习；学习单不经 i_core。

已交付 `tools/siyuan_tutor/`（f76da90）：按用户提供的思源 3.8.6 MCP 工具清单编写 Codex 导师指令（账本为思源数据库独立行 + 来源块链接、间隔复习、入账、每天出学习单写入思源与 `today.md`、不删除边界）、dot/GPT voice 语音规则与结果格式、日语科目表和设置说明（Codex 工具白名单、定时 `codex exec`）。思源内置 MCP 的地址与 Bearer API Token 鉴权已在源码核对。纯文档，未构建；账本单元格写法、dot 读写本机文件与语音守规矩程度待用户本机实测。看板改做思源插件（点击跳转原笔记、就地经思源 Agent 提问）尚为提议，未开工。

10-04 已完成日语初始化（账本 12 点）、dot 连电脑与首次通话；按反馈修订语速、纠正记录与链接格式（44d84dd）。全量交接见 [handoffs/LEARNING_SYSTEM_AND_TOOLS_20261005.md](handoffs/LEARNING_SYSTEM_AND_TOOLS_20261005.md)，供生活规划系统等新窗口接手。

## 方向调整：白板停止开发，转向三端串联（2026-10-02）

用户决定白板工作台停止开发：知识库、白板、视频标注与学习改用 FlexNote（终身版，1.1.53 起提供 MCP），由 Codex 接入。Here I Am 收敛为 i_core 上的一条时间线、一个记忆库与一份林埃身份，供 Claude 网页端、手机 App 与可选 ChatGPT 文字端共用；GPT voice 记录不迁移，私密会话不出站。任务与分工见[任务单](PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md)；本条只改文档，未改产品源码。

任务 A4 已交付 `tools/flexnote_tutor/`：基于 FlexNote 1.1.56 MCP 工具清单的 Codex 学习导师模板与科目表（教师编·中学语文，求职空间）；需在本机复制到仓库外学习目录使用。B0.1 定为 i_core 先跑在电脑上。 B1/B2 并行开发按[接口约定](CONTINUITY_B1_B2_CONTRACT.md)进行：`tools/i_memory/`（记忆快照+出站策略+只读接口）与 `tools/i_remote_mcp/`（claude.ai 远程 MCP+单用户 OAuth）。 `tools/i_memory/` 已交付：V3 记忆快照导入、出站策略（缺失即 fail closed）与 `openReadModel` 只读接口，合成 fixture 测试通过；真实导出与导入（B1.4）待 Codex 本机执行。 B2.1/B2.2 已交付 `tools/i_remote_mcp/`（远程只读 MCP、单用户 OAuth、`i_context`/`i_recall`、Project 指令，fake readModel 测试通过）；两者已合入主任务分支：补消息级私密关键词、OAuth 回调默认仅限 claude.ai，B1×B2 集成测试通过（共 60 项）；真实导入、私密配置、Funnel 部署与 claude.ai 接入待 Codex 本机执行。claude.ai 已经 https://i.ilynx.date/mcp（Cloudflare 固定隧道）接入并通过两问真人验收；B3 写回见[简报](B3_WRITEBACK_BRIEF.md)与[设计](B3_WRITEBACK_DESIGN.md)，源码已在 claude/b3-writeback 交付。B2.3 实测：claude.ai 经 Funnel `:10000` 无法连接，经 Cloudflare 隧道可完成注册并到达口令页，长期入口改用 Cloudflare 固定隧道 + 自有域名。A 线已由 Codex 本机跑通（教综拆解导入、初始化、5 题冒烟），模板已按反馈修订。

## B3 写回源码交付（2026-10-03，claude/b3-writeback）

按[设计](B3_WRITEBACK_DESIGN.md)交付：`tools/i_remote_mcp` 新增 `i_chat_turn`（每轮写回网页端双方原文到 i_core 时间线，内容对齐去重、漏轮补交、i_core 不可达时本机账本暂存）与 `i_remember`（显式记录只存本机账本，可改可真删；手机经只监听本机的拉取通道 `:47862` 取走，按用户决定无需确认直接进 Record 流程成卡）。OAuth 新增 `i.write`，启用写回后签发 `i.read i.write`，旧令牌需重新授权；Project 指令改为每轮先 `i_chat_turn`。

i_core 新增受限 `external-frontend` 设备身份 `frontend:claude_web`：可提交 user/companion、不能读 feed/ack、不能请求核心回复，不改 schema，不需要 worker 密钥。读取层新增 `messages.auto_share_origins`：列出的前端来源只跳过 ID/哈希放行清单，私密类型、关键词和私密 ID 仍优先；省略时保持旧行为。

合成验证：i_remote_mcp 67/67（含真实 i_core 服务与存储 + 真实读取层 + MCP + OAuth 端到端）、i_memory 35/35 通过；i_core 新增 2 项通过，全量仍有 54 项 activity fixture 合同失败，与改动前基线一致。未部署、未接真实数据。待 Codex 本机：合入、policy 开关、i_core 配对窗口 + `pair-core`、手机令牌与 Tailscale Serve、重启、`revoke-all` 与 claude.ai 重新连接、Project 指令、Flutter 来源显示与记录入卡、真人验收。

## B2.3 固定隧道与运行诊断（2026-10-03）

正式入口已从 Funnel 切换到 Cloudflare 固定隧道和自有域名。隧道注册为 Windows 开机自启服务（Auto、LocalSystem），配置和凭据放仓库外；服务运行并建立 4 条边缘连接。remote MCP 保留既有登录自启，public-url 已更新，旧令牌已撤销，现有口令不变。QUIC 可用，未修改代理或 TUN。尚未执行整机重启验收。

本机配置检查：/mcp 返回 401 且挑战头使用新域名，两份 OAuth 元数据返回 200 且 resource/issuer 一致；这不是公网可达性验收。用户确认 Bot Fight Mode/Under Attack 关闭、自定义规则为空、Access 停留首次设置页。公网复测由 Claude 从 tailnet 外完成，当前尚待报告。

tools/i_remote_mcp 新增脱敏 HTTP/RPC JSONL：每行 UTC 时间、固定 UA 家族、已知 callback/resource/Origin 和工具结果摘要；不记录口令、token、原始 UA、body、工具内容或原始异常。协议及 JSON/SSE 行为未变。本分支合成回归 66 项通过；只部署受控 server/diagnostics 文件后，既有运行副本回归 74 项通过，其私密读取层与真实 policy 的文件哈希保持不变。真实配置、凭据、策略、数据库和日志不在提交中。

B2.4 尚未完成：等待公网复测通过，再做正式 connector i 的口令授权、工具允许设置、林埃 Project 与两题真人验收；届时记录 POST authorize/token 和 tools/call 以及仅 JSON 的实用结果。Funnel :10000 仍保留，正式接入成功后再询问用户是否关闭；其他映射未变。

## B1 审核读取层源码交付（2026-10-03）

codex/continuity-b1-local-policy 从 2a27f7d7 同步既有本机通用读取改动：messages.private_message_ids 按 sync_id 排除；消息/卡片正向 ID 清单只允许审核条目；内容 SHA-256 映射拒绝未审核修订。所有允许条件与角色、类型、关键词及私密 ID 等原有限制取交集，不能覆盖私密排除。显式空清单/映射拒绝全部，省略字段兼容旧策略；更新策略须重新打开读取模型。接口与哈希字段顺序见 CONTINUITY_B1_B2_CONTRACT.md 和 tools/i_memory/README.md。

本分支 i_memory / remote MCP 合成回归 74/74 通过：涵盖合法/非法策略、大 ID 清单、未审核新增和内容变更、所有本地读取出口及远程文本/结构化返回。集成测试注入合成身份，避免读取用户身份投影。该验证不代替手机同步、公网访问或 claude.ai 真人验收。

真实 policy、私密关键词、审核 ID/哈希清单、数据库、审批和日志仍只保存在本机；筛查脚本不包含在交付。运行副本与当前工作分支未改动。本分支以读取层同步为范围，不实现 B3 写回；诊断日志在独立 codex/continuity-cloudflare-diagnostics 分支，协作方按所需合并或 cherry-pick。

## GitHub 同步完成（2026-10-01）

原仓库 `Ritou-Lynx/here-i-am` 的默认分支 `v3-lab` 已合入[整合 PR #1](https://github.com/Ritou-Lynx/here-i-am/pull/1)，整合提交为 `4520590a4f1eaa75ee514be3ea2ab320645ae617`。GitHub PR Policy Preflight 通过；其高风险分类来自本次大范围历史文件整合，已有人工范围复核与独立凭据审计，没有拒绝项。

已从 GitHub 完整新 clone 演练其他设备接入：分支和整合 SHA 一致，完整 fsck 通过，130 个受控源码哈希及13个公开保留文件 blob一致，提交检查可安装，未公开的本地/私人检查点对象不存在。正式开发副本的 v3-lab 跟踪 origin/v3-lab，正常 push 地址已恢复；本机具体路径见原交接，各设备使用自己的目录。

其他远端历史分支与旧本地检查点保留；日常集成集中 v3-lab。新设备按[多设备协作说明](MULTI_DEVICE_GITHUB_WORKFLOW.md)重新 clone，旧私人谱系目录继续留档。源码协作恢复不迁移真实账户数据，也不启用生产执行。


## 单一 GitHub 协作谱系

2026-10-01：用户授权恢复单一 GitHub 仓库、多设备源码协作。唯一仓库为 `Ritou-Lynx/here-i-am`，默认集成分支为 `v3-lab`；从公开净化基线 `3856fc7f` 重新整理待公开文件层，不推送未净化的本地检查点。

公开准备已复核凭据、私人资料与素材边界：历史文档只保留技术证据摘要，消息索引、真人健康值与生活引语留本机；13 个原公开保留文件的 Git blob 不变。130 个已验源码保持 SHA-256。旧 Memex globalEarly/cnEarly 定时发布工作流移除；没有建立新的安装包发布入口。

其他设备按[多设备协作说明](MULTI_DEVICE_GITHUB_WORKFLOW.md)完整 clone 并安装提交检查。原私人主树、未公开检查点和 T7 恢复点保留；真实数据库、账户、签名、原始设备回执与迁移审计不进入 GitHub。

## 验证与执行边界

既有源码专项和独立 Windows 构建/启动结果见[本地开发交接](LOCAL_DEVELOPMENT_20261001.md)。原本机构建绑定源码检查点 `339b6bc7`；重新整理公开提交只改文档、忽略规则和旧自动发布入口，没有改变产品源码。

生产长任务仍拒绝执行，活动诊断默认关闭；真实账户迁移、真人验收、减弹窗与生产准备未由源码同步完成。同步是否完成以 GitHub 默认分支和本机复核回执为准。
