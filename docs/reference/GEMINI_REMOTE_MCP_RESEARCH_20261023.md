# 调研：消费者版 Gemini 能否接入自定义远程 MCP（D3）

> **状态**：调研稿，未决定、未实施。核对日期 2026-10-23。对应计划表 D3。
> 本次云端会话打不开 Google 帮助中心和博客原文，以下内容来自搜索摘要、第三方指南和其他 MCP 项目的 GitHub issue/PR，没有逐页核对官方原文。
> **依据标记**：【官方】Google 帮助中心或博客（据搜索摘要）；【第三方】博客、指南；【社区】其他项目的 issue/PR 实际踩坑；【源码】本仓库代码；【推断】；【待实测】。

## 1. 结论先行

- **能接，但门槛高**：消费者版 Gemini 已支持"自定义应用（Custom apps）"，填远程 MCP 服务器的 URL 即可接入【官方】。但要求**人在美国、18 岁以上、个人 Google 账号、界面英文、开着 Keep Activity**【官方】。用户是否满足地区条件，是 D3 的第一道关。
- **订阅要求说法不一**：有说 AI Pro/Ultra 才有，有说不需要订阅、只有 Spark 要 Pro【第三方，冲突】。用户是 AI Pro，按两种说法都不会因订阅被卡。
- **可能只在 Spark 里能用**：有来源说自定义应用只在 Gemini Spark（常驻代理）的任务里调用，也有来源说普通聊天的快捷操作也能用【第三方，冲突，待实测】。
- **只能在网页端添加**，加好后手机 App 也能用【官方】。
- **我们的 MCP 现在接不上 Gemini**：Gemini 用动态客户端注册（DCR），回调地址按用户生成，不是固定值；而且一次可能报 6 个回调。本仓库的白名单只认固定地址、最多 5 个、一个不合格就整体拒绝【源码 + 社区】。要接入，需要像 D2 一样改 OAuth，并且**必须先完成 D1**（否则 Gemini 会被记成 claude_web）。
- **Gems 迁移成 Skills 与 MCP 无关**：Skills 是指令包，不是工具接入方式，不能替代 MCP。它影响的是"怎么提示 Gemini 去用 i"，不影响"能不能连上 i"。
- **建议**：先让用户花 5 分钟实测入口（见第 6 节第 1 步）。看得到 "Add a custom app" 再写 D3 relay 合同；看不到就把 D3 挂起，不做绕过地区限制的尝试。

## 2. 入口与资格

| 项 | 内容 | 依据 |
|---|---|---|
| 入口 | gemini 网页端 → Settings → Connected Apps → Custom apps → Add a custom app → 填 MCP 服务器 URL → Next → 浏览器里完成授权 | 【官方】 |
| 添加位置 | 只能在网页端添加；连上后网页端和手机 App 都能用 | 【官方】 |
| 地区 / 年龄 | 18 岁以上，人在美国 | 【官方】 |
| 账号 | 个人 Google 账号；工作或学校账号不可用 | 【官方】 |
| 语言 | 目前只支持英文 | 【第三方】 |
| 活动记录 | 必须开 Keep Activity，关掉后自定义应用不可用 | 【官方/第三方】 |
| 订阅 | 一说 AI Pro/Ultra 才支持（某厂商帮助页，2026-08-05）；一说自定义应用本身不要求订阅，Spark 要 Pro/Ultra | 【第三方，冲突】 |
| 上线时间 | 一份指南说 2026-06-29 开始推送 | 【第三方，未核对】 |
| 在哪调用 | Spark 任务里能用；聊天里是否能用说法冲突 | 【第三方，冲突】 |
| 写操作 | 自定义应用的写操作，Gemini 会先要用户手动确认 | 【第三方】 |
| 安全声明 | Google 不控制、不监控第三方 MCP 服务器，由用户自己负责 | 【官方】 |
| 传输 | 一份来源说 Gemini 侧只支持 Streamable HTTP，不支持 SSE、stdio（说的是 Gemini API，App 端推断相同） | 【第三方/推断】 |

**不要混淆**：
- **Gemini Enterprise / Business** 是另一条路：管理员在团队设置里添加 MCP 服务器，要填 client ID 和 secret，回调是 Google Cloud 的固定地址，不走 DCR【官方】。与本项目无关。
- **Gemini CLI**：2026-06-18 起不再给个人、AI Pro、Ultra 账号提供服务【第三方】，不是备选路线。
- **官方 Connected Apps**（Asana、Linear、monday.com 等）是 Google 预置的集成，不是自定义 MCP。

## 3. Gemini 的 OAuth 行为（据其他项目踩坑）

这些都来自其他 MCP 项目为兼容 Gemini 提的 issue/PR，同一现象多处出现，可信度中等【社区】：

1. **用 DCR（RFC 7591）自注册**，不需要手填 client ID。服务器不支持 DCR 时，Gemini 会退回去在 Advanced 里要求填 client ID/secret【社区/第三方】。
2. **回调地址按用户生成**：主机是 Google 的 OAuth 中转 `oauth-redirect.googleusercontent.com`（另见 `oauth-redirect-sandbox.googleusercontent.com` 等中转主机），路径形如 `/r/user_bound_custom-mcp-<编号>-<主机>`。每个 Google 账号不同，无法预先登记一个固定值。
3. **一次注册可能带 6 个回调**，分布在几台中转主机上；有服务器因为其中几个不合格而整体返回 400，注册失败。
4. **可能声明 `client_secret_basic` 或 `client_secret_post`**，scope 里带 `offline_access`；有服务器对这两点直接报 400，修法是接受请求、仍按公开客户端注册。
5. **白名单的安全写法**：主机精确匹配（只认那几台中转主机，https，逐字比较），再加路径前缀 `/r/user_bound_custom-mcp-`。不要按 `googleusercontent.com` 后缀放行（这个域也托管用户上传内容），也不要放行整个 `/r/`（那是 Google 通用账号关联入口）。前缀里的下划线是 Cloud 项目 ID 不允许的字符，所以别的项目抢不到这个前缀。
6. **已知故障**：Google 开发者论坛有帖子报告 Spark 的自定义 MCP 授权在 302 回调后停住、从不请求 `/token`【社区，未知是否已修】。

## 4. 本仓库现状与差距

对照 `tools/i_remote_mcp/oauth.mjs`【源码】：

| 现状 | 对 Gemini 的影响 | 要改什么（D3 合同用） |
|---|---|---|
| `isAllowedRedirectUri` 只认 Claude 两个固定回调、ChatGPT 一个固定回调和环境变量里的精确地址 | Gemini 的按用户回调全部被拒 | 新增"Gemini 模式"：精确中转主机 + 路径前缀匹配；像 ChatGPT 一样做成显式开关，默认关 |
| `MAX_REDIRECT_URIS = 5` | 6 个回调直接 400 | 放宽到能容纳 Gemini 的数量，或只保留合格回调后再判断 |
| 注册时任何一个回调不合格就整体拒绝 | Gemini 混入不合格回调时注册失败 | 只对 Gemini 请求采用"过滤后保留合格的"，Claude/ChatGPT 维持现行严格规则 |
| 元数据只声明 `token_endpoint_auth_methods_supported: ['none']`，注册时忽略请求里的认证方式 | Gemini 若坚持用 secret，换令牌可能失败【待实测】 | 先实测；必要时接受该字段但仍注册为公开客户端 |
| `offline_access` 已在 `scopes_supported` 里 | 应该没问题 | 实测确认 |
| `frontendForRedirectUri` 非 ChatGPT 回调一律归为 `claude_web` | Gemini 的写回会被记成 Claude 来源 | **先做 D1**（前端身份注册表），再加 `gemini_web` 身份，App 显示名同步加映射 |

其他约束（来自 D1 草稿，见项目记忆）：生产 MCP 是由构建器在基线上打补丁生成的六文件候选，改 `oauth.mjs`/服务端必须同时在构建器里加补丁组，部署走 C1 的 `update-mcp-source` 流程，不能新增运行时文件。

## 5. Gems → Skills 的影响

- **时间**：个人账号的 Gems 从 2026-11-17 开始自动迁移成 Skills；Workspace 账号更晚（一说 2027-03-01 前不停用）【官方/第三方】。迁移后的 Skill 可能以草稿状态出现，需要手动启用【第三方，未核对】。
- **Skills 是什么**：在普通聊天里用 `/名字` 调用的指令包，可叠加多个，采用开放的 SKILL.md 格式；不需要付费订阅，但要开 Keep Activity【官方/第三方】。Canvas、Deep Research、Guided Learning 等暂不能在 Skills 里用【第三方】。Spark 也会运行 Skills【第三方】。
- **与 MCP 的关系**：搜索没有找到"Skills 取代自定义应用/MCP"的说法，两者是独立功能【第三方】。Skill 能否点名调用某个自定义应用，没有资料【待实测】。
- **对本项目的意义**：
  1. 如果 D3 接通，可以写一个 Skill（例如 `/林埃`），把 claude.ai 那边 MCP 服务器说明里的规则（每轮 `i_chat_turn` start/end、"帮我记一下"用 `i_remember`、查不到不编造）写进去，相当于 Gemini 侧的"服务器说明"。Gemini 是否读取 MCP 服务器自带的 instructions 未知【待实测】，所以这个 Skill 可能是必需品。
  2. 不要新建 Gem；已有的 Gem 若带资料文件，迁移前先下载备份【官方建议】。
  3. Skills 本身**不能**替代 MCP：它不能读写 i_core，只能改变提示词。

## 6. 建议的 D3 推进步骤

1. **用户实测入口（5 分钟，零风险）**：用个人账号登录 Gemini 网页端，界面设成英文，打开 Settings → Connected Apps，看有没有 Custom apps / Add a custom app。截图里不要带账号信息。
   - 没有：D3 挂起，在计划表记"地区/资格不满足"，等 Google 扩大范围。不尝试用代理等方式绕过地区限制（违反服务条款，也会让账号风险进入生产链路）。
   - 有：继续第 2 步。
2. **等 D1 合并**：Gemini 身份必须走前端注册表。
3. **只读摸底**（同 D2 第一步）：Codex 只读查 MCP 日志，拿到 Gemini 注册时实际发来的 `redirect_uris`、`token_endpoint_auth_method`、`scope`，核对第 3 节的社区说法。这一步需要用户在 Gemini 里点一次"添加"，预期会被拒。
4. **relay 合同**：按第 4 节表格改 OAuth（Gemini 开关默认关、主机精确 + 前缀匹配、过滤式注册、`gemini_web` 身份、构建器补丁组、测试）。
5. **生产（手动，需用户同意）**：部署、打开开关、配对、真人验收；先在 Spark 和普通聊天各试一次只读调用，再试写回（Gemini 会弹确认）。
6. **Skill**：验收通过后写 `/林埃` Skill，内容只放调用规则，不放关系记忆。

## 7. 风险与边界

- **数据边界**：接入后 Gemini 能读到 i_core 的上下文。Google 声明不对第三方 MCP 负责；Gemini 的活动记录（Keep Activity 必须开）会保存对话。是否接受林埃相关内容进入 Google 的活动记录，需要用户决定。
- **范围控制**：Gemini 开关必须默认关闭，和 ChatGPT 一样显式启用；白名单不能放宽成域名后缀。
- **资料可信度**：本稿多数细节来自第三方和社区，Google 这类功能变化很快，第 6 节第 1、3 步的实测结果优先于本稿。

## 来源

官方（据搜索摘要）：
- [Connect & manage custom apps for Gemini Apps（Gemini 帮助中心）](https://support.google.com/gemini/answer/17209137?hl=en&co=GENIE.Platform%3DDesktop)
- [Set up your custom MCP server connection（Gemini Enterprise 帮助）](https://support.google.com/g/answer/17106276?hl=en)
- [Introducing skills in the Gemini app and Workspace（Workspace Updates）](https://workspaceupdates.googleblog.com/2026/09/skills-gemini-app-workspace.html)
- [About the transition from Gems to skills（Workspace 帮助）](https://knowledge.workspace.google.com/admin/generative-ai/gemini-app/about-the-transition-to-skills)

第三方：
- [Gemini MCP: How to Add a Custom Server in 2026（Carly）](https://www.usecarly.com/blog/gemini-mcp/)
- [How to Add a Remote MCP Server to the Gemini App（Tempreon）](https://tempreon.com/guides/add-mcp-server-to-gemini)
- [Google Gemini MCP Support（Tactiq）](https://tactiq.io/learn/google-gemini-mcp-support)
- [How to connect to Gemini via MCP（MarginEdge 帮助）](https://help.marginedge.com/hc/en-us/articles/54127138423443-How-to-connect-me-to-Gemini-via-MCP)
- [Gemini Spark Availability（Flowith）](https://flowith.io/blog/gemini-spark-global-access-countries-plans-guide/)
- [Gemini app replacing Gems with skills in November（9to5Google）](https://9to5google.com/2026/09/27/gemini-gems-skills/)
- [Google Is Replacing Gemini Gems With Skills Nov 17（TechRepublic）](https://www.techrepublic.com/article/news-gemini-gems-skills-migration/)

社区（其他项目的兼容修复）：
- [homerun PR #128：Gemini 作为自定义应用连接](https://github.com/orochibraru/homerun/pull/128)
- [memory-cloud issue #2232：按合格回调注册 DCR 客户端](https://github.com/kagura-ai/memory-cloud/issues/2232)
- [mml-tools PR #136：兼容 Gemini Custom MCP 的 DCR](https://github.com/a91453/mml-tools/pull/136)
- [trail-tools PR #104 / #106：只放行 Google 中转主机上的 Gemini 回调](https://github.com/johanbrandhorst/trail-tools/pull/106)
- [COROS-MCP issue #17：为 Gemini 网页端放行回调](https://github.com/coroslab/COROS-MCP/issues/17)
- [Google AI 开发者论坛：Spark 自定义 MCP 授权在 302 后停住](https://discuss.ai.google.dev/t/gemini-spark-custom-mcp-oauth-stops-after-302-callback-and-never-calls-token/177327)
