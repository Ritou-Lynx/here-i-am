# 思源笔记 MCP 接入速查

> **版本基准**：思源 3.8.6（2026-09-29 正式版）。3.8.7 仍在预览，见第 9 节。核对日期：2026-10-08。
>
> **依据标记**：
> - 【源码】读过 v3.8.6 源码
> - 【官方】发布说明或官方 issue
> - 【实测】本项目 2026-10-04 在用户电脑上跑通
> - 【约定】本项目自己的用法
> - 【未核实】还没验证
>
> 工具清单由用户在 2026-10-04 从思源导出。

## 1. 一句话

思源从 3.8.0 起在内核里自带 MCP 服务，地址就在内核端口上。客户端拿到 API Token，就能读写**整个工作空间**：

- 包括删除笔记本、文档和块；
- 读写删工作区里的任意文件；
- 安装插件、触发同步、向外发 HTTP 请求。

这些能力默认全部开放，接入时一定要用白名单收窄（第 4 节）。

## 2. 连接

| 项 | 内容 |
|---|---|
| 地址 | `http://127.0.0.1:6806/mcp`。端口就是思源内核端口，默认 6806【源码】 |
| 协议 | Streamable HTTP：POST 调用，GET、DELETE 用于会话；调用结果以 JSON 返回，不用 SSE 流式返回。请求头 `MCP-Protocol-Version` ≥ `2026-07-28` 时用无状态模式，旧协议保留会话【源码】 |
| 鉴权 | 两种：① `Authorization: Bearer <API Token>`，API Token 在 设置 → 关于；② OAuth 2.1 访问令牌（3.8.6 起，见下）【源码】 |
| 权限 | 调用方必须是管理员身份；用 API Token 鉴权即为管理员【源码】 |
| 只读运行时 | 思源内核以只读方式运行时（`util.ReadOnly`，例如只读部署），对 `/mcp` 的 POST 一律被拒。因为所有调用都走 POST，整个 MCP 实际不可用【源码】 |
| 服务名 | `SiYuan`，版本号等于思源版本【源码】 |
| 前提 | 思源（桌面端或 Docker 服务端）在运行，内核在线 |

另外，内核 HTTP API（`/api/...`，不是 MCP）的鉴权头写 `Token <API Token>` 或 `Bearer <API Token>` 都可以【源码】。

### OAuth 2.1（3.8.6 新增）

| 端点 | 用途 |
|---|---|
| `/.well-known/oauth-protected-resource`、`/.well-known/oauth-protected-resource/mcp` | 资源元数据 |
| `/.well-known/oauth-authorization-server` | 授权服务器元数据 |
| `/oauth/mcp/authorize`、`/oauth/mcp/consent` | 授权页、同意 |
| `/oauth/mcp/token`、`/oauth/mcp/revoke` | 换取令牌、吊销令牌 |
| `/api/mcp/getOAuth`、`setOAuth`、`addOAuthClient`、`removeOAuthClient` | 管理接口，需要管理员 |

- **不支持动态客户端注册（DCR）**：要先由管理员在思源里添加 OAuth 客户端（名称加回调地址），得到客户端 ID 和密钥，再填进远程客户端。远程客户端得支持手动填写客户端 ID 和密钥，例如 claude.ai 自定义 connector 的高级设置【源码】；各客户端是否都支持【未核实】。
- 授权码流程必须用 PKCE S256；`resource` 必须等于"公开地址 + `/mcp`"；scope 为 `mcp offline_access`【源码】。
- 令牌时效：访问令牌 1 小时；刷新授权最长 30 天；授权页的票据 10 分钟、授权码 2 分钟内有效【源码】。
- 修改 OAuth 设置（开关、公开地址）会清空已有授权，客户端需要重新授权【源码】。
- 用途：让部署在服务器、Docker 上，或经隧道暴露的思源，直接接入 ChatGPT 网页版、claude.ai 这类要求 OAuth 的远程客户端【官方】。
- OAuth 要在设置里开启，并填写公开地址（PublicURL），元数据里的地址都由它生成【源码】；设置界面的确切位置【未核实】。
- 对外暴露时：
  - 只放行 `/mcp`、`/.well-known/oauth-*`、`/oauth/mcp/*` 这几个路径，不要把整个内核端口暴露出去。
  - 先设访问授权码。
  - 只有电脑开着时才能用。
  - 本项目还没实测【未核实】。

## 3. 对外暴露哪些工具

- **暴露策略**（`ai.mcp.exposurePolicy`）：
  - 默认 `allow`，所有内置工具都对外暴露。
  - 可以按"能力 ID"单独设为 `deny`。能力 ID 的格式是 `native/backend/<工具名>`，例如 `native/backend/file`【源码】。
  - 设置入口在思源的 AI 设置里，菜单名以界面为准。
- **不会对外暴露的**：只供思源内置 Agent 使用的能力（AgentOnly），以及从外部 MCP 服务接进来的工具【源码】。
- **没有只读注解**：内置工具都没有标 `readOnlyHint`，客户端会把它们一律当成"可能写入"【源码】。读和写又经常在同一个工具里（例如 `block` 既能 get 也能 delete），所以客户端按工具授权时，分不开读和写。

## 4. 工具清单（3.8.6，共 30 个）

"只读""写入""删除或高风险"三列按动作的含义划分。其中 database、asset、image、search、skill、bazaar、sql、http_request 这 8 个工具的读写和外发属性，源码里有明确声明【源码】；其余按动作名划分。

| 工具 | 用途 | 只读 | 写入 | 删除或高风险 | 备注 |
|---|---|---|---|---|---|
| system | 系统信息 | version, current_time, workspace | — | — | |
| workspace | 工作空间 | list, info | — | — | |
| notebook | 笔记本 | list | open, close, create, rename, set_icon, random_icon | remove | |
| document | 文档 | get, list, search_docs, info | create, rename, move, duplicate | delete | create 用 `markdown` 写正文 |
| block | 内容块 | get, get_kramdown, get_children, tree_stat, dom, breadcrumb, batch_get, batch_kramdown | insert, append, prepend, update, move | delete | 见第 6 节 |
| dailynote | 日记 | — | create, append, prepend | — | `notebook` 必填 |
| search | 搜索 | fulltext, asset, getasset | — | semantic（数据外发、外部计费） | semantic 要先配嵌入模型 |
| sql | 只读 SQL | query | — | — | `stmt` 必填 |
| outline | 文档大纲 | get | — | — | |
| ref | 引用与反链 | backlinks, mentions | refresh | — | refresh 的具体效果【未核实】 |
| attr | 块属性 | get, batch-get | set | — | |
| tag | 标签 | list | — | rename, remove | 影响所有用到该标签的块 |
| bookmark | 书签 | list, labels | rename | remove | |
| database | 数据库（属性视图） | search, get, render, keys, unused | create, key_add, key_update, key_set_template, item_add, item_update | key_remove, item_remove, clean | 见第 6 节 |
| template | 模板 | search, get, render | save_as, create | remove | |
| asset | 附件 | unused, stat | upload, create_html | clean | clean 删除没有被引用的附件 |
| image | 图片 | list | — | analyze（外发、计费）、generate（写入、外发、计费） | `documentID` 必填 |
| export | 导出 | — | md, html, preview, docx, sy, md-zip, data | — | 在本机生成导出内容或文件 |
| import | 导入 | — | md, sy | data | 批量写入；data 导入整份数据 |
| history | 文档历史 | list, search, get | rollback | clear | |
| repo | 数据快照 | list, search, diff, file_get | create, tag, untag, file_rollback, file_open, file_export | checkout, purge | checkout 会把工作空间恢复到某个快照 |
| sync | 同步 | status | — | perform, upload, download | 改动云端或本地数据 |
| inbox | 云收集箱 | list, get | convert | — | 需要官方订阅；`remove_after` 会在转换后删除云端条目 |
| file | 工作区文件 | list, read, grep, find, stat | write, rename, copy | delete | 官方说明只用于调试和读日志，不要用来改工作区数据【源码】 |
| unzip | 解压 | — | 解压到 `destPath` | — | |
| http_request | HTTP 请求 | — | — | get, post, put, delete, patch | 从思源内核向任意地址发请求，可能把数据发出去【源码：外部作用】 |
| web_fetch | 读取网页 | — | — | 读取任意网址 | 外部访问 |
| web_search | 联网搜索 | — | — | 搜索 | 外部访问 |
| skill | 思源技能 | load, list | save, install, rename | remove | |
| bazaar | 集市包管理 | list, installed, updates, readme | enable, disable | install, update, update_all, install_local, uninstall | 会安装第三方代码 |

### 参数取值

| 参数 | 可选值或结构 |
|---|---|
| `dataType` | `markdown`（默认）、`dom` |
| `database.layout` | `table`、`list`、`calendar`、`gallery`、`kanban` |
| `database.type` | `text`、`number`、`date`、`select`、`mSelect`、`url`、`email`、`phone`、`mAsset`、`template`、`created`、`updated`、`checkbox`、`relation`、`rollup`、`lineNumber` |
| `database.keys[]` | `{name, type, icon?}`，其中 `name`、`type` 必填 |
| `image.detail` | `auto`、`low`、`high` |
| `image.outputFormat` | `png`、`jpeg`、`webp` |
| `web_fetch.format` | `markdown`（默认）、`text` |
| `bazaar.pkgType` | `plugins`、`widgets`、`themes`、`icons`、`templates` |
| `bazaar.frontend` | `desktop`、`desktop-window`、`mobile`、`browser-desktop`、`browser-mobile` |
| `bazaar.packages[]` | `{pkgType, packageName, repoHash}`，三项都必填 |

## 5. 推荐的接入范围

**本项目 Codex 的白名单**（学习导师、规划助手共用）【约定】【实测】：

```
system, workspace, notebook, document, block, dailynote, search, sql, outline, ref, attr, tag, database, template
```

- 白名单里仍有删除类动作：notebook remove、document delete、block delete、tag rename/remove、database item_remove/key_remove/clean、template remove。这些靠导师指令禁止。
- `search` 的 semantic 会把查询发给嵌入模型的服务商。

**建议在思源暴露策略里直接关掉的**：file、repo、sync、bazaar、skill、unzip、import、http_request。用不到的话，再加上 web_fetch、web_search、inbox、export。

这是第二道保险：就算某个客户端没配白名单，也调不到这些工具。

## 6. 关键语义与易错点

### 数据库（属性视图）

| 动作 | 要点 |
|---|---|
| create | `parentID` 必填（文档或块的 ID）；`layout` 默认 table；可以用 `keys` 一次建好字段【源码】 |
| item_add | 非独立行必须给 `blockID`，会把已有块绑进数据库；`detached: true` 建独立行，用 `content` 写主键文字【源码】 |
| item_update | 参数为 `(id, keyID, itemID, value)`，`value` 是单元格对象，原样交给内核【源码】。写法见下表 |
| 模板（公式）字段 | 用 `key_set_template` 设置，不要用 `item_update` 写计算列【源码说明】 |
| render | `query` 是关键词筛选；分页参数 `page`、`pageSize`，默认每页 50。没有按日期筛选，需要读全部行后在客户端筛【源码】【约定】 |
| clean | 只删除 `unused()` 列出、没有被引用的数据库【源码】 |
| 视图 | 工具里没有视图相关动作，`create` 只能指定初始布局。日历、看板等视图要在界面里添加【源码】 |

本项目使用的单元格写法【约定】。初始化时已经实际写入成功【实测】，但没有逐项核对结构，拿不准时先改一个单元格，再用 `render` 核对：

| 字段类型 | 写法 |
|---|---|
| 文本 | `{"text": {"content": "…"}}` |
| 数字 | `{"number": {"content": 2, "isNotEmpty": true}}` |
| 日期 | `{"date": {"content": <毫秒时间戳>, "isNotEmpty": true}}` |
| 单选 | `{"mSelect": [{"content": "模糊"}]}` |
| 链接 | `{"url": {"content": "siyuan://blocks/…"}}` |

### 块与文档

- `block update` 只替换一个块，不追加；`append`、`prepend` 会新建一个子块并返回它的 ID【源码说明】。
- `batch_get`、`batch_kramdown` 的 `ids` 用英文逗号分隔【源码说明】。
- 读内容优先用 `get_kramdown`，多个块用 `batch_kramdown` 一次读完【约定】。
- `sql` 只读，适合按结构查 `blocks` 表，例如：`SELECT id, content, hpath FROM blocks WHERE box='<笔记本ID>' AND type='h'`【约定】。

### 链接

- 块链接：`siyuan://blocks/<块ID>`。
- 文档里引用别的块：`((<块ID> "锚文本"))`，显示为标题，鼠标悬停可以预览。
- 写进思源文档用块引用；写进本机文件和回复里用 Markdown 链接。不要贴裸链接【约定】。

## 7. 客户端配置

**Codex**【实测】：

```toml
[mcp_servers.siyuan]
url = "http://127.0.0.1:6806/mcp"
bearer_token_env_var = "SIYUAN_API_TOKEN"
startup_timeout_sec = 20
tool_timeout_sec = 120
enabled_tools = ["system", "workspace", "notebook", "document", "block", "dailynote", "search", "sql", "outline", "ref", "attr", "tag", "database", "template"]
```

- 令牌只放在环境变量里：Windows 上执行 `setx SIYUAN_API_TOKEN "…"`，然后完全重启 Codex。
- 还可以给单个工具设 `approval_mode`（可选值 `auto`、`prompt`、`writes`、`approve`），见 [Codex MCP 文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。因为思源工具都没有只读注解，按"写入"来判断确认的设置可能对读操作也生效【未核实】。

**Claude Code（本机）**【未核实】：

```
claude mcp add --transport http siyuan http://127.0.0.1:6806/mcp --header "Authorization: Bearer <令牌>"
```

**远程客户端**（claude.ai、ChatGPT 网页版的开发者模式）：需要公网 HTTPS 加 OAuth 2.1，按第 2 节的办法暴露。ChatGPT 的自定义 MCP 目前只能在网页端用【未核实】。

**ChatGPT dot**：只能用官方插件，接不了自定义 MCP。要用思源内容，只能通过"连接电脑"读本机文件【官方】。

## 8. 思源内置 Agent 作为 MCP 客户端

思源 Agent 本身也能连外部 MCP 服务。

| 项 | 内容 |
|---|---|
| 配置位置 | `ai.mcp.servers[]`【源码】 |
| 字段 | `name`、`enabled`、`type`；本机命令类用 `command`、`args`、`env`、`inheritEnv`；远程类用 `url`、`headers`；另有 `timeout`、`disableStandaloneSSE`、`trustToolAnnotations`【源码】 |
| 启动 | 思源启动时自动连接已启用的服务【源码】 |
| 转发 | 接进来的外部工具不会再经思源的 MCP 对外暴露【源码】 |
| OAuth 回调 | `/api/ai/mcp/oauth/callback/<flowID>`【源码】。如果要接本项目的 i_remote_mcp，需要把这个回调地址加进它的回调白名单【约定】 |
| 能力策略 | `ai.agent.capabilityPolicy`：按能力 ID 设 `allow` 或 `deny`【源码】 |
| 审批策略 | `ai.agent.approvalPolicy`：默认 `risk`（按风险决定是否确认），可选 `allow`、`confirm`、`risk`，能细到动作【源码】 |
| 工作空间指令 | `data/ai/AGENTS.md`：会随同步走，最多 32 KiB，在 设置 → AI → Agent 里编辑，电脑和手机都能用【官方】 |

## 9. 版本动态

| 版本 | MCP 相关变化 |
|---|---|
| 3.8.0 | 内置 MCP 服务和 AI Agent、语义搜索【官方】 |
| 3.8.6（2026-09-29） | MCP 支持 OAuth 2.1；Agent 和 MCP 能管理集市包；支持工作空间 `AGENTS.md`；新增思维导图块；数据库日历视图增强【官方】 |
| 3.8.7 预览版（2026-10-04 至 10-07） | Agent 支持用 ChatGPT 账号登录；修复连接 2026-07-28 协议的外部 MCP 服务时，对方没有工具列表通知就连不上的问题【官方】 |

## 10. 其他扩展方式（不经 MCP）

- **内核 HTTP API**：`http://127.0.0.1:6806/api/...`，例如 `/api/filetree/createDocWithMd`。规划助手的手机快捷录入就用这个【约定】。思源手机端的内核能不能接受其他 App 的请求、被系统清掉后还能不能连上【未核实】。
- **插件 API**：`addTab`、`addDock`（手机端也能用）、`addTopBar`、`openTab`、`onLayoutReady`、`openMobileFileById`【源码】。
- **挂件**：放在 `data/widgets/`。挂件和插件目录都会随同步到其他设备【源码】。
- **费用**：插件、挂件、数据库、闪卡、API、AI（用自己的 key）都免费；第三方同步（S3/WebDAV）需要一次性买断 PRO；官方同步需要订阅【官方】。

## 11. 在本项目里的角色

以 [个人数据中枢 ADR](../development/PERSONAL_DATA_HUB_ADR_20261005.md) 为准：

- 思源只管**成篇的文字**，不和 i_core 双向同步。
- 学习账本和招聘日历**暂时**放在思源数据库里，W7 之后再评估。
- 看板先由 Codex 用只读令牌**单向生成**思源文档。

使用方：
- [`tools/siyuan_tutor/`](../../tools/siyuan_tutor/README.md)：学习导师。
- [`tools/life_planner/`](../../tools/life_planner/README.md)：规划助手。

凭据：令牌只放在环境变量 `SIYUAN_API_TOKEN` 里，不写进文件、仓库或聊天。

## 12. 未核实、待补

- MCP 暴露策略和 OAuth 设置在界面里的确切菜单名。
- `item_update` 各字段类型的值结构（目前能写入，但没有逐项核对）。
- `ref refresh` 的具体效果。
- 经隧道把思源 MCP 接到 claude.ai、ChatGPT 网页版：没实测。
- Docker 服务端版思源加第三方同步的组合：没实测。
- 手机端思源内核能否被其他 App 调用。

## 来源

- 源码（v3.8.6）：
  - [kernel/mcp/server.go](https://github.com/siyuan-note/siyuan/blob/v3.8.6/kernel/mcp/server.go)
  - [kernel/mcp/tools/](https://github.com/siyuan-note/siyuan/tree/v3.8.6/kernel/mcp/tools)
  - [kernel/mcp/tools/types.go](https://github.com/siyuan-note/siyuan/blob/v3.8.6/kernel/mcp/tools/types.go)
  - [kernel/mcp/tools/capability.go](https://github.com/siyuan-note/siyuan/blob/v3.8.6/kernel/mcp/tools/capability.go)
  - [kernel/conf/ai.go](https://github.com/siyuan-note/siyuan/blob/v3.8.6/kernel/conf/ai.go)
  - [kernel/api/router.go](https://github.com/siyuan-note/siyuan/blob/master/kernel/api/router.go)
  - [kernel/model/mcp_oauth.go](https://github.com/siyuan-note/siyuan/blob/master/kernel/model/mcp_oauth.go)
  - [kernel/model/session.go](https://github.com/siyuan-note/siyuan/blob/master/kernel/model/session.go)
- 官方：
  - [Releases](https://github.com/siyuan-note/siyuan/releases)
  - [#19867 MCP OAuth 2.1](https://github.com/siyuan-note/siyuan/issues/19867)
  - [#19876 工作空间 AGENTS.md](https://github.com/siyuan-note/siyuan/issues/19876)
  - [定价](https://b3log.org/siyuan/en/pricing.html)
- 插件 API：[petal/siyuan.d.ts](https://github.com/siyuan-note/petal/blob/main/siyuan.d.ts)
