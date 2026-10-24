# 调研：用飞书替代思源做学习笔记

> **状态**：调研稿。2026-10-24 用户本机实测后决定：学习账本迁到飞书多维表格，实施见 [F1 合同](../development/handoffs/RELAY_20261024_f1-feishu-tutor.md)。现役思源学习导师暂不改动。
>
> **核对日期**：2026-10-21。本次云端会话**访问不了 `open.feishu.cn` 和 `www.feishu.cn`**（DNS 解析失败），官方页面内容来自搜索引擎摘要和 GitHub 上的官方仓库，没能逐页打开核对。
>
> **依据标记**：
> - 【官方】飞书官方文档、帮助中心或 larksuite 官方仓库
> - 【第三方】博客、社区项目
> - 【推断】由已知事实推出，未验证
> - 【待实测】必须在用户的飞书账号上试过才能确定

## 1. 结论先行

- **方向可行。** 思源的痛点是"随处可用"这件事：手机端反应慢，工作电脑装不了，S3 同步配置麻烦。飞书在手机、网页、任意电脑上都能直接打开，同步也不用自己管，正好解决这些问题。
- **学习账本反而更合适。** 思源数据库靠 MCP 读写，写法很绕：独立行、按 keyID 逐个单元格写、MCP 不能建视图。飞书多维表格的记录、字段、视图、筛选都能通过官方 CLI 直接操作【官方】。
- **最大的不确定性是"个人版能不能接 AI"。** 官方 CLI 和 OpenAPI MCP 都要先建一个开放平台应用，再走 OAuth 授权。个人版账号能不能建应用、能开哪些权限，没查到官方的明确说法【待实测】。这是切换前第一个要验证的点。
- **接入方式应选飞书 CLI，不选 MCP。** 官方的 OpenAPI MCP 还是 Beta，而且不支持编辑云文档。个人远程 MCP 链接 7 天过期，官方文档也写着"不推荐"，并引导改用 CLI【官方】。
- **FlexNote 保留。** 视频笔记、对照 PDF 或视频画图理解，飞书画板替代不了。

## 2. 为什么想换

| 痛点（思源 3.8.6） | 飞书的情况 |
|---|---|
| 手机端不灵敏 | 飞书手机端是主力产品，打开、搜索、编辑都流畅【推断，用户日常体验】 |
| 工作电脑不方便下载、打开 | 网页版免安装；登录个人账号即可【官方】 |
| 第三方同步要配 S3/WebDAV，每次配置都麻烦 | 云端原生存储，不用配置同步【官方】 |
| MCP 只在本机，网页或手机上的 AI 要接得配 OAuth 加隧道，还得电脑开着 | 数据在云端；CLI 在任意一台装了 Node 的电脑上都能用，不依赖某台电脑开着【官方】 |

## 3. 存储容量

| 来源 | 说法 |
|---|---|
| 飞书帮助中心《查看并管理云文档存储空间》（据搜索摘要） | 基础版（免费）：**认证前 15 GB，认证后 100 GB**。容量由即时消息、邮箱、妙记、云文档共用。**个人版用户看不到剩余容量。** 删除的文档在回收站保留 30 天【官方，未能直接打开原页】 |
| 2023 年新闻 | 免费版从 200 GB 缩减到 10 GB，认证企业 50 GB【第三方，已过时】 |
| 若干教程 | 个人版 5 GB 或 10 GB【第三方，说法不一】 |

判断：
- 文字笔记和多维表格占的空间很小，几个 GB 就够用好几年【推断】。
- 真正占容量的是视频、PDF 和大图。这些放在 FlexNote 或本地，飞书里只放链接或摘录，就不用担心容量。
- 个人版"看不到剩余容量"这一条要实测确认；如果属实，就靠"不往飞书传大文件"这条约定来规避风险【待实测】。

## 4. AI 接入的三条路

| | 飞书 CLI（`@larksuite/cli`） | OpenAPI MCP（`@larksuiteoapi/lark-mcp`） | 官方远程 MCP（云文档） |
|---|---|---|---|
| 状态 | 正式开源，官方维护【官方】 | **Beta**【官方】 | 官方文档标"个人调用（不推荐）"，MCP Token 链路将逐步下线，建议改用 CLI【官方，据搜索摘要】 |
| 覆盖范围 | 云文档、Markdown 文件、知识库、多维表格、云盘、画板、日历、IM、表格、幻灯片、任务、邮箱、会议、妙记等，200 多条命令，26 个 Agent Skills【官方】 | 把开放平台 API 包成工具，按预设工具集启用【官方】 | 只有云文档：搜索、创建、查看、更新、列出、评论【官方，页面 2026-01-13 更新】 |
| 能否编辑云文档 | 能：`docs +create` 直接写 Markdown，也能读、更新、搜索；Drive 里的 `.md` 文件支持局部 patch 和整体覆盖【官方】 | **不能**，只能导入和读取【官方】 | 能更新，细节未核实 |
| 多维表格 | 表、字段、记录、视图、仪表盘、自动化、表单、聚合分析【官方】 | 有部分工具（如 `bitable.v1.appTableRecord.search`），预设集名称在不同版本间不一致【官方/第三方】 | 无 |
| 认证 | `lark-cli config init` 配置应用凭据，`auth login --recommend` 走 OAuth；凭据存在系统钥匙串；默认以用户身份调用【官方】 | 建自建应用，用 `--oauth` 加 `--token-mode user_access_token`，否则可能回退到应用身份，读不到个人数据【官方】 | 在 MCP 配置平台生成个人链接，**7 天有效**，权限等于用户本人的文档权限【官方，据搜索摘要】 |
| 怎么接 Codex / Claude | Agent 在终端里调用 CLI，配套 Skills（`npx skills add larksuite/cli -y -g`）【官方】 | 标准 MCP 配置 | 标准远程 MCP |

结论：**用 CLI。** 它是唯一同时具备"能写云文档"和"多维表格全功能"的正式方案；Codex 本来就在终端里干活，不需要 MCP 这一层。

### 个人版能不能用（关键未知）

- 开放平台的官方流程默认在"企业"下创建自建应用；第三方对接文档提到需要"所在飞书企业的开放平台开发权限"【官方/第三方】。
- 个人版在飞书里也算一种"企业版本类型"（个人版/团队版）【第三方】。所以个人账号也许就是自己这个租户的管理员，能建应用，但没有确证【推断】。
- 第三方工具 larkdown 的 `config init` 声称"通过设备码授权自动创建一个个人应用"【第三方】，这说明个人账号走得通的可能性不小【推断】。
- **验证办法**：用个人账号登录飞书开放平台的开发者后台，看有没有"创建企业自建应用"的入口；再跑一遍 `lark-cli config init` 和 `auth login`，看能不能读写自己的一篇文档、一张多维表格【待实测】。

## 5. 现有学习导师怎么映射

现役方案见 [`tools/siyuan_tutor/`](../../tools/siyuan_tutor/README.md)。

| 现在（思源） | 换成飞书 | 难度 |
|---|---|---|
| 笔记本"学习" | 知识库空间，或"我的空间"下的文件夹 | 低 |
| 资料定位：`search` 全文检索 + `sql` 按结构查 | 云文档搜索，加读文档大纲。**没有 SQL**，按标题层级批量查会更笨【推断】 | 中 |
| 读正文：`block get_kramdown` | `docs` 读取，CLI 输出 Markdown【官方】 | 低 |
| 学习账本：思源数据库，独立行、按 keyID 逐格写 | **多维表格**：字段沿用现有 10 个（知识点、科目、来源、掌握度、最近结果、连对、错次、上次练习、下次复习、备注）；可以直接建"今日待复习"视图【官方】 | 更简单 |
| 来源链接：`siyuan://blocks/<块ID>` | 飞书文档链接；能否精确到段落的锚点【待实测】 | 中 |
| 学习单：思源文档 `学习单/日期` + 本机 `today.md` | 飞书文档；`today.md` 保留给 dot 读 | 低 |
| 学习收件箱 | 飞书文档，或多维表格里加一张"收件"表；`inbox/*.md` 保留 | 低 |
| 排期规则（连对 → 3/7/14/30 天） | 不变，仍由 Codex 计算后写回 | 无 |
| Windows 计划任务 `codex exec` 每天出学习单 | 不变；CLI 凭据在钥匙串里，计划任务能否非交互读取【待实测】 | 中 |
| 删除禁令（不用 remove/delete） | 照搬到指令里；另外授权时只申请需要的 scope | 低 |

ChatGPT dot 的语音带练链路（读 `today.md`、写 `inbox/`）完全不受影响。

## 6. 隐私与边界

- **只用个人账号。** 工作电脑上如果登录的是公司的飞书租户，学习笔记绝不能放进公司空间：企业管理员对租户内的内容有管理权限，离职时账号也会被回收【推断，基于企业版的常规管理能力】。
- 飞书内容存在字节跳动的服务器上，不是端到端加密。工作、学习、生活方面的思维库可以放；**情感交流、关系记忆、林埃相关内容不放**，这和项目的数据边界一致：生活事实、关系记忆以 i_core 为准，Project Memory 隔离【约定】。
- CLI 以用户本人身份操作，官方提醒注意幻觉、提示注入和数据泄露，**不要把机器人拉进群聊**；CLI 默认会随请求附带系统类型和硬件型号（风控），可以用 `lark-cli config risk-control` 关掉【官方】。
- 凭据照旧不进仓库、文件和聊天；CLI 默认存在系统钥匙串里【官方】。

## 7. 白板与视频

- 飞书画板：画思维导图、流程图够用；CLI 有 `lark-whiteboard`，能按 DSL 渲染图表【官方】。
- FlexNote 的视频笔记、对照 PDF 或视频画布理解、Mermaid，飞书都替代不了，**保留**。
- 分工建议：**飞书 = 文字思维库 + 学习账本；FlexNote = 视频、PDF、画图理解。** 同一份内容只在一处维护，不两边同步（沿用 [参考库](README.md) 的原则）。
- FlexNote 现在可以从思源增量导入；飞书没有这条路。换成飞书之后，需要画图的主题要么手动导入 FlexNote，要么先导出成 Markdown 再导入【推断】。

## 8. 切换成本与风险

| 项 | 说明 |
|---|---|
| 已有思源内容迁移 | 日语笔记本和 12 行账本，量很小。飞书有 Markdown 导入；账本可以重建或导出 CSV 再导入【推断】 |
| 思源"第三方同步"已买断 | 沉没成本，不影响决策 |
| 离线 | 飞书离线编辑能力有限，没网时体验不如本地的思源【待实测】 |
| 锁定 | 云端专有格式；CLI 能读成 Markdown，可以定期导出备份【官方/推断】 |
| 免费政策变动 | 飞书免费版额度改过多次（200 GB → 10 GB → 现在的 15/100 GB）【第三方/官方】 |
| 和 i_core 的关系 | 不变：学习单不经过 i_core，学习账本不进 Memory V3 |

## 9. 讨论前要实测的清单

按顺序做，前一项不过就不用往下了：

1. 个人账号在开放平台能不能建自建应用；`lark-cli config init` 加 `auth login` 能不能走通。
2. CLI 能否读写自己的一篇云文档（Markdown 进、Markdown 出），以及一张多维表格（加记录、改单元格、按日期筛选）。
3. 个人版的真实容量，以及能不能看到剩余空间。
4. 文档链接能否精确到段落（决定账本"来源"字段的写法）。
5. Windows 计划任务里的 `codex exec` 能否非交互调用 CLI（钥匙串凭据、OAuth 刷新）。
6. 工作电脑上用网页版登录个人账号，和公司租户能否干净隔离。
7. 手机端编辑学习笔记的手感（L4 真人主观项）。

都通过后，再写 `tools/feishu_tutor/`：照 `siyuan_tutor` 的结构改写 `STUDY_AGENTS.md`，账本换成多维表格，并在本目录补一份 `FEISHU_CLI.md` 速查。

## 10. 实测结论（2026-10-23/24，用户本机，lark-cli 1.0.98）

| 项 | 结果 |
|---|---|
| 个人账号建自建应用 | 能建，但授权被平台拦截：`config init` 校验报 21001 "scope blocked by data security policy"，`auth login` 报 "restricted by your organization's security policy"。与 larksuite/cli issue #2815、#2818 一致（约 10-13 起，豆包或个人账号下的自建应用都受影响）【实测】 |
| 绕过 | 自建一个免费团队（企业）租户，切到这个团队后运行 `config init --new`（扫码自动建应用）和 `auth login --domain "docs,base"`，user 和 bot 两种身份都 ready【实测】 |
| 云文档 | `docs +create --doc-format markdown` 写入后用 `docs +fetch` 读回，逐字一致；`docs +update --command str_replace` 只改目标行【实测】 |
| 多维表格 | 建表、加字段、批量加和改记录、`--filter-json` 筛选、`+view-create` 加 `+view-set-filter` 建视图都能做。"≤ 今天"要写成 `["下次复习","<","Tomorrow"]`，这是动态值，不会过期【实测】 |
| 计划任务 | Interactive（只在登录时运行）的计划任务里，codex exec 能调用 lark-cli，但必须用 `-s danger-full-access`：workspace-write 会断网，放开网络后 DPoP 密钥（Windows KSP）在 restricted token 下报 20140。"不管是否登录"模式没有测【实测】 |
| 续期 | access token 过期后能用 refresh token 静默刷新；refresh token 有效期 7 天，过期后能否续期待复测【实测/待实测】 |
| risk-control | 只附带系统类型和设备型号，用来识别 token 被盗；官方建议保持默认，本项目定为不修改【官方】 |

Windows 注意（PowerShell 5.1）：
- npm 全局目录要加进 PATH。
- 逗号分隔的参数要加引号，否则会被拆成数组。
- 传 JSON 和多行文本一律用 `@file`。
- 先设 `[Console]::OutputEncoding=UTF8`。
- 多行脚本不要用 here-string 管道，也不要用无 BOM 的 `-File`（前者会静默丢掉脚本，后者会把中文读乱），改用 `-EncodedCommand`。

## 来源

- 飞书 CLI 官方仓库：[larksuite/cli README.zh](https://github.com/larksuite/cli/blob/main/README.zh.md)；[飞书 CLI 官网页](https://www.feishu.cn/feishu-cli)
- OpenAPI MCP 官方仓库：[larksuite/lark-openapi-mcp](https://github.com/larksuite/lark-openapi-mcp)；[npm @larksuiteoapi/lark-mcp](https://www.npmjs.com/package/@larksuiteoapi/lark-mcp)
- 远程 MCP（未能直接打开，内容据搜索摘要）：[个人调用远程 MCP 服务（不推荐）](https://open.feishu.cn/document/mcp_open_tools/end-user-call-remote-mcp-server?lang=zh-CN)、[远程 MCP 支持的工具列表](https://open.feishu.cn/document/mcp_open_tools/supported-tools?lang=zh-CN)、[MCP 概述](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/mcp_integration/mcp_introduction?lang=zh-CN)
- 存储容量：[飞书帮助中心：查看并管理云文档存储空间](https://www.feishu.cn/hc/zh-CN/articles/988314140482)（未能直接打开）；[蓝点网 2023 年报道](https://www.landiannews.com/archives/97474.html)
- 开放平台应用创建：[飞书开放平台：创建应用](https://open.feishu.cn/document/develop-gadgets-(not-recommended)/develop-a-gadget-in-5-minutes/create-an-app?lang=zh-CN)；[阿里云：配置飞书企业自建应用](https://help.aliyun.com/zh/document_detail/3006030.html)
- 第三方：[larkdown](https://github.com/amzyang/larkdown)、[AlexAnys/feishu-mcp](https://github.com/AlexAnys/feishu-mcp)
