<!-- relay:contract v1 -->
# A1 合同：App 内聊天接 i MCP 只读工具

> 基于 v3-lab `08ab47d`（N2 notes 已上线，现役任务 n2-notes，server 候选 `4b1014e0`）。

## 目标
让手机 App 文字聊天里的林埃能查 i MCP 上的只读数据：飞书日记（notes_recent / notes_search / notes_read）、日摘要（life_digest）、学习（study_today / study_source / study_progress）、心率历史（heart_rate）、饮食（food_day）、记账（expense_day）。做法：i MCP 新增一个只读前端 `here_i_am_app`，App 用已有的 MCP 客户端和 OAuth 代码连上它，再给林埃加一个网关工具 `i_query`。GPT-Live 通话接工具不在本合同（另做）。

## 背景
- App 聊天走本地 CompanionAgent（工具表在 `lib/agent/skills/character_tools_factory.dart` 的 `buildCompanionTools`），不连 i MCP。App 已有 `lib/agent/mcp/`（McpClient、McpOAuth），目前只给 COROS 用（`lib/data/services/coros_mcp_service.dart`、`lib/ui/settings/widgets/coros_connect_page.dart`，WebView 里拦截 localhost 回调）。
- i MCP 加前端的先例是 D2b Sesame（`docs/development/handoffs/RELAY_20261025_d2b-sesame-frontend.md`）：精确回调表、独立开关、`chatgpt_candidate.mjs` 加 mainline/legacy 两侧补丁组。生产跑的是构建器生成的候选，改源码必须同时加补丁组。
- 与 Sesame 不同：App 前端**只读**，不开放 `i_chat_turn`，所以**不需要 Core 凭据、不需要 pair-core、不改读取策略**。App 自己就是聊天时间线，不能再经 MCP 写回，否则消息重复。

## 完成标准

### 第一部分：服务端（第 1 轮）

**注册表（`oauth.mjs`）**
- [ ] 新增导出常量 `APP_CALLBACKS = Object.freeze(['http://127.0.0.1:47859/hereiam/i-mcp/callback'])`，`FRONTEND_CALLBACKS` 加 `here_i_am_app: APP_CALLBACKS`。只精确匹配：`localhost`、其他端口、`https`、尾斜杠、query、fragment、大小写变体、userinfo 全部不认。
- [ ] 开关 `I_REMOTE_MCP_APP_ENABLED`：未设或 `1` 开，`0` 关，其他值启动报 `invalid_app_mode`。新增 `appEnabledFromEnv`，写法同 `sesameEnabledFromEnv`；`OAuthServer` 加 `appEnabled` 参数和类型校验；`isEnabledFrontend` 及全部调用点考虑此开关。关闭时注册、授权、换令牌、refresh、已签令牌一律拒绝。
- [ ] App 回调与其他前端回调混合注册返回 400。
- [ ] 发给 `here_i_am_app` 的令牌 scope 只能是 `i.read`：即使请求 `i.write` 也只签 `i.read`（授权码和 refresh 两条路径都要）。

**路由与工具（`server.mjs`；`mcp.mjs` 仅在确实需要时）**
- [ ] `server.mjs` 显式分支 `here_i_am_app`，用独立的处理器和工具表。工具表**只有**以下 10 个（模块未启用时对应工具自然缺席）：`notes_recent`、`notes_search`、`notes_read`、`life_digest`、`study_today`、`study_source`、`study_progress`、`heart_rate`、`food_day`、`expense_day`。
- [ ] 明确**不出现**：`i_context`、`i_recall`、`i_chat_turn`、`i_remember`、`capture_add`、`week_get`、`day_get`、`food_log`、`expense_log`、`life_todo`、`study_result`。处理器表里也不能有这些（调用返回未知工具错误，而不是执行）。
- [ ] `writeback.mjs` 不加这个前端；不加载任何凭据文件。
- [ ] 不新增允许的 Origin（App 不带 Origin）。

**诊断（`diagnostics.mjs`）**
- [ ] `callbackClass` 对 App 回调返回 `here_i_am_app`，加进分类白名单；不记录 `callback_shapes`。

**候选构建器（`chatgpt_candidate.mjs`）**
- [ ] 新增补丁组 `APP_PATCHES`（mainline、legacy 两侧），接在 `NOTES_PATCHES` 之后，正反向链都要接上。legacy 侧要把 notes、life_digest、study、heart_rate、food_day、expense_day 的只读处理器挂到 App 处理器上（参照 NOTES/EXPENSE 补丁里对 antigravity 的挂法；expense/study 若按前端分表，App 只取只读那部分）。
- [ ] v3-lab 新源码逐字节通过正反向校验；候选仍是六个文件。钉哈希的既有测试只允许更新本合同实际改动的文件，每处加注释 `// A1 app frontend`。

**部署脚本（只写不跑）**
- [ ] 新建 `tools/relay_scripts/app_mcp/a1-deploy.ps1` 与 `a1-deploy.mjs`，照抄 `tools/relay_scripts/notes/n2-deploy.*` 的结构：ps1 为 PS5.1、UTF-8 带 BOM、**CRLF**，首行设输出编码，核对 mjs 的 SHA256（原字节或 CRLF→LF 后任一一致），用现役 release 的 node.exe 启动。mjs 预检锁定现役任务 `HereIAm-iCoreSchema6-n2-notes-20261108`（server `4b1014e0`），建并复制新候选（根目录和每个子目录受保护 ACL，写法照 n2），update-mcp-source 先 dry-run 再从 n2-notes 任务登记新任务 `HereIAm-iCoreSchema6-app-mcp-20261110`（先 disabled），切换（失败自动退回 n2-notes），最后核对心率监听 47866。**不写 notes.json（已存在），不改策略，不 pair-core。**输出每行一个 JSON，不含令牌、域名、本机路径、SID、正文。

**测试（合成数据）**
- [ ] 新建 `tools/i_remote_mcp/app_frontend.test.mjs`：回调精确命中及全部变体返回 null；全流程（注册→授权→换令牌→`tools/list`→调用一个只读工具→refresh）；`tools/list` 恰好是允许集合（在启用了 notes/study/heart_rate/food/expense/life_digest 的夹具下）；禁止工具调用被拒；请求 `i.write` 只拿到 `i.read`；混合注册 400；开关未设开、`0` 全拒、`2` 报 `invalid_app_mode`；诊断 `callback_class` 为 `here_i_am_app`、日志无回调原文。
- [ ] 候选测试里加一条：生成的候选中 App 前端工具集同上，其他前端工具集不变。
- [ ] 其他既有测试不改并且通过，例外：`frontend_registry.test.mjs` 精确表加 `here_i_am_app`，以及上面的钉哈希。

### 第二部分：App（第 2 轮）

**连接服务**
- [ ] 新建 `lib/data/services/i_mcp_service.dart`，结构仿 `CorosMcpService`：单例、`ensureConnected`、`callTool`、`isConnected`、`lastError`。服务地址和令牌存安全存储（复用 `mcp_token_storage.dart` 的方式，用独立的 key 前缀 `i_mcp`），过期用 refresh token 续期，续期失败提示重新连接。仓库里不写任何服务地址。
- [ ] 新建 `lib/ui/settings/widgets/i_mcp_connect_page.dart`，仿 `CorosConnectPage`：用户粘贴一次 i MCP 地址（`https://…/mcp`）→ 发现元数据 → 动态注册（redirect 固定为上面的 `APP_CALLBACKS[0]`，`client_name` 为 `Here I Am App`，scope `i.read`）→ PKCE S256 → WebView 打开授权页（用户输口令）→ 拦截回调换令牌。显示已连接/断开按钮。回调常量与服务端一致（写在一处，测试里断言字符串相等）。如 `McpOAuth` 需要加可选 `resource`/`scope` 参数，向后兼容地加，COROS 路径行为不变。
- [ ] 在 `personal_center_screen.dart` 和 `settings_page.dart` 里 COROS 入口旁边加“林埃数据（i MCP）”入口。

**网关工具**
- [ ] 新建 `lib/agent/built_in_tools/i_mcp_query_tool.dart`，工具名 `i_query`，参数 `tool`（enum：上面 10 个名字）和 `arguments`（object，可选）。客户端也做白名单校验；未连接时返回“还没连接 i MCP，请到设置里连接”；服务端报错原样转成工具结果文本，不抛异常打断回复。结果超过 20000 字截断并注明。
- [ ] 在 `buildCompanionTools` 里加入 `i_query`（仿 `buildCorosMcpTool` 的位置）。
- [ ] `companion_agent_skill.dart` 加一小节（≤12 行）：用户提到日记/写过的东西/工作文档 → `notes_search` 或 `notes_recent` 再 `notes_read`；今天过得怎样/日摘要 → `life_digest`；学习 → `study_*`；吃了什么 → `food_day`；ChatGPT 里记的账 → `expense_day`；昨晚心率/睡眠 → `heart_rate`。查不到就说没有，不编造；不要每轮都查。

**测试**
- [ ] `test/` 下加单测：`i_query` 白名单拒绝非法工具名；参数原样转发给假服务；未连接文案；截断；回调常量等于 `http://127.0.0.1:47859/hereiam/i-mcp/callback`。
- [ ] `flutter analyze` 无新增问题；既有测试不改。

## 允许修改的路径
- `tools/i_remote_mcp/oauth.mjs`、`server.mjs`、`diagnostics.mjs`、`mcp.mjs`（仅确需时）、`chatgpt_candidate.mjs`、`README.md`
- `tools/i_remote_mcp/*.test.mjs`：只追加；新建 `app_frontend.test.mjs`；既有断言只按上面例外修改
- `tools/relay_scripts/app_mcp/`
- `lib/data/services/i_mcp_service.dart`、`lib/ui/settings/widgets/i_mcp_connect_page.dart`、`lib/agent/built_in_tools/i_mcp_query_tool.dart`
- `lib/agent/mcp/mcp_oauth.dart`（仅向后兼容的可选参数）
- `lib/agent/skills/character_tools_factory.dart`、`lib/agent/skills/companion_agent/companion_agent_skill.dart`
- `lib/ui/settings/widgets/personal_center_screen.dart`、`lib/ui/settings/widgets/settings_page.dart`
- `lib/l10n/*.arb` 及生成的 `app_localizations*.dart`（仅新增入口文案时）
- `test/` 下新建的测试文件
- `docs/development/handoffs/RELAY_20261110_app-i-mcp-tools.md`（只由 Claude 改）

## 不做 / 边界
- 不改 Core、`writeback.mjs`、`tools/i_core/`、各工具模块本身（notes_tools、study_tools、heart_rate、life_digest、expense_tools、domain_tools）。
- 不改口令规则、锁定策略、令牌有效期、`token_endpoint_auth_method`。
- App 不经 MCP 写任何东西；不改 GPT-Live 通话；不改 COROS 现有行为。
- 代码轮不生成生产候选、不部署、不碰生产和真实数据；部署只走脚本轮。
- 仓库公开：不写服务地址、口令、令牌、本机路径。
- 止损：同一测试名或错误码连续两个提交失败就回 blocked。

## 验证命令
- `node --test tools/i_remote_mcp/*.test.mjs tools/i_memory/*.test.mjs`
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/a1-candidate`：成功、六个文件；输出不提交。
- 第 2 轮：`flutter analyze` 与新增测试文件的 `flutter test`；全量以 CI 为准，CI 要全绿。

## 部署（脚本轮，第 1 轮审过后）
1. `tools/relay_scripts/app_mcp/a1-deploy.ps1`（mode=write）：从 n2-notes 切到 app-mcp 新任务，停服约 1 分钟，失败自动退回。
2. 云端用 Claude 的 i 连接器调一次 `notes_recent`，确认现有前端不受影响。

## 需要真人的部分
- 在部署脚本轮评论上点 👍。
- 第 2 轮合格后从本分支装 App，设置里粘贴一次 i MCP 地址、输一次口令；然后在聊天里问一句日记里的事验收。
- 收到 `relay:done` 之前不要合并。
