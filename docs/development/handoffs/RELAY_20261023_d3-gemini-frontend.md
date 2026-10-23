<!-- relay:contract v1 -->
# D3 合同：接入 Gemini 网页端（gemini_web）

> 已核对 v3-lab `244f420`（D1 已合并）。
> 调研依据：`docs/reference/GEMINI_REMOTE_MCP_RESEARCH_20261023.md`（PR #44）。用户 10-23 实测：个人账号网页端能看到 "Add a custom app"。

## 背景
- D1 之后，`oauth.mjs` 的 `FRONTEND_CALLBACKS` 只做**精确匹配**：frontend → 固定回调列表。Gemini 的回调按 Google 账号生成，形如 `https://<Google OAuth 中转主机>/r/user_bound_custom-mcp-<编号>-<主机>`，无法写成固定值【社区】。
- Gemini 一次注册可能带 6 个回调，分布在几台中转主机上；`MAX_REDIRECT_URIS = 5`，且 D1 要求全部回调属于同一 frontend，否则 400【社区 + 源码】。
- Gemini 可能在注册时声明 `token_endpoint_auth_method: client_secret_basic/post`，scope 带 `offline_access`【社区】。我们目前忽略该字段、一律注册为公开客户端，元数据只声明 `none`。
- `diagnostics.mjs` 只记录 Claude 两个固定回调，其他回调一律记为 `[redacted]`，`/register` 不记录回调。所以 D2 那种“先只读查日志拿回调”的办法对 Gemini **拿不到信息**，需要先加一个安全的分类字段。
- ChatGPT 的接入模式可直接照搬：独立开关 `I_REMOTE_MCP_CHATGPT_ENABLED`（默认关）、独立凭据 `core-frontend-chatgpt_web.json`、只读领域工具 + 聊天写回、无随手记和笔记、缺凭据时 `frontend_not_paired:chatgpt_web`。
- 生产跑的是构建器生成的六文件候选（server、oauth、diagnostics、mcp、writeback、i_memory_read），改源码必须同步在 `chatgpt_candidate.mjs` 加补丁组；不能新增运行时文件。现有 `PATCHES`（第 23 行）、`FRONTEND_PATCHES`（第 101 行）、`REGISTRY_PATCHES`（第 432 行），manifest `changed_files: 4`（第 615 行）。
- 部署工具 `tools/i_core/maintenance/update-mcp-source.mjs` 第 117 行只允许 MCP 配置的 `working_directory`、`source_files` 变化，**不能改环境变量**。所以 Gemini 不能靠“默认关、部署时设成 1”的开关上线（用户决定 3）。
- `mcp.mjs` 第 130–135 行 `listTools`、第 272–273 行 `createToolHandlers` 已按“非 `claude_web` 只给 `i_chat_turn`、不给笔记”处理，Gemini 直接复用，预计不用改 `mcp.mjs`。
- `frontend_registry.test.mjs` 第 10 行断言注册表恰好只有 Claude、ChatGPT 两项，第 22–30 行断言注册表名 = `FRONTENDS` 键 = App 映射表键。

## 完成标准

**注册表与回调匹配（`oauth.mjs`）**
- [ ] 开关 `I_REMOTE_MCP_GEMINI_ENABLED`（用户决定 3）：**未设或 `1` 为开**，`0` 为关，其他值启动报错 `invalid_gemini_mode`。新增导出 `geminiEnabledFromEnv`，写法同第 164 行 `chatgptEnabledFromEnv`。
- [ ] 新增导出常量 `FRONTEND_CALLBACK_PATTERNS`（`Object.freeze`），只含 `gemini_web` 一项；`FRONTEND_CALLBACKS` 保持只放精确地址。Gemini 回调模式：协议 https；主机逐字等于固定白名单（`oauth-redirect.googleusercontent.com`、`oauth-redirect-sandbox.googleusercontent.com`，部署后按诊断字段核对，不符再修订）；无端口、无 userinfo、无 query、无 fragment；路径匹配 `^/r/user_bound_custom-mcp-[A-Za-z0-9-]{1,200}$`。不得用域名后缀匹配，不得放行整个 `/r/`。
- [ ] `frontendForRedirectUri`（第 33 行）先精确查 `FRONTEND_CALLBACKS`，查不到再按 `FRONTEND_CALLBACK_PATTERNS` 匹配；一个地址最多命中一个 frontend（测试断言）。`isEnabledFrontend`（第 38 行）同时考虑 ChatGPT 和 Gemini 两个开关；`OAuthServer` 构造参数加 `geminiEnabled`，类型校验同 `chatgptEnabled`。
- [ ] `/register`（第 240 行）仅对 Gemini：回调数上限放宽到 8（`MAX_REDIRECT_URIS` 第 62 行对 Claude/ChatGPT 仍为 5）；先丢弃不合格的回调，至少保留一个 Gemini 回调才注册，注册记录只存保留下来的回调。Claude、ChatGPT 规则不变（任一不合格整体拒绝，上限 5）。混合 Gemini 与 Claude/ChatGPT 回调一律拒绝。
- [ ] `/register` 收到 `client_secret_basic`/`client_secret_post` 时不报错，仍注册为 `none`，响应里如实返回 `token_endpoint_auth_method: "none"`。`/token` 若带了 client secret 头或字段，忽略而不是拒绝（只限 Gemini client）。
- [ ] Gemini 开关关闭时：Gemini 回调注册、授权、换令牌、已签令牌使用一律拒绝（同 D1 对 ChatGPT 的处理）。

**路由与工具（`server.mjs`、`writeback.mjs`、`mcp.mjs`）**
- [ ] `writeback.mjs` `FRONTENDS` 加 `gemini_web`：`deviceId: 'frontend:gemini_web'`、`displayName: 'Gemini 网页端'`、`credentialFile: 'core-frontend-gemini_web.json'`。
- [ ] `server.mjs` 显式分支 `gemini_web` → Gemini 处理器，工具集与 ChatGPT 相同（**用户决定 1**）。缺凭据时 `i_chat_turn` 返回 `frontend_not_paired:gemini_web`，绝不使用其他前端的凭据。
- [ ] `pair-core --frontend gemini_web` 可用，写入 `.state/core-frontend-gemini_web.json`。
- [ ] Origin：Gemini 预计由 Google 服务端调用、不带 Origin【推断】。不新增任何允许的 Origin（第 104 行不动）；如部署验收发现带了 Origin，另开一轮修订。
- [ ] 启动入口（第 546–582 行一带）：读 `geminiEnabledFromEnv()`，开且写回开启时加载 `gemini_web` 凭据，写法同 ChatGPT（第 571–576 行）。

**诊断（`diagnostics.mjs`）**
- [ ] 第 12 行 `CALLBACKS` 与第 51 行 `base.callback` 的现有行为不变。`/register` 与 `/authorize` 另外增加 `callback_class` 字段，取值只有 `claude`、`chatgpt`、`gemini_pattern`、`google_relay_other`、`other`、`absent`；`/register` 另记 `callback_count` 和 `gemini_kept_count`。**不记录回调原文、编号或主机名以外的任何部分。**

**候选构建器（`chatgpt_candidate.mjs`）**
- [ ] 新补丁组（如 `GEMINI_PATCHES`，含 mainline 与 legacy），v3-lab 新源码逐字节通过正反向校验；候选仍六文件。因为改了 `diagnostics.mjs`，`changed_files` 预计从 4 变为 5，`unchanged_files` 从 2 变为 1，同步改第 615 行和候选测试里对应的断言。`update-mcp-source` 只检查六个文件名和哈希，不限制改动个数（已核对第 95–97 行）。

**App（`lib/ui/character/widgets/chat_message_source_label.dart`）**
- [ ] `_knownChatSources` 加 `'frontend:gemini_web': 'Gemini'`。D1 的一致性测试会强制这一项。

**测试（合成数据）**
- [ ] 回调模式：合格样例通过；后缀伪造（`evil-oauth-redirect.googleusercontent.com`、`oauth-redirect.googleusercontent.com.evil.example`）、http、带端口、带 query/fragment、`/r/其他项目`、路径大小写变化、超长编号全部拒绝。
- [ ] 注册：6 个回调（4 合格 + 2 不合格）→ 注册成功且只存 4 个；全部不合格 → 400；Gemini + Claude 混合 → 400；开关关闭 → 400。
- [ ] 全流程：注册（带 `client_secret_basic`、`offline_access`）→ 授权 → 换令牌（带 secret 头）→ RPC 走 Gemini 处理器 → refresh；`i_chat_turn` 记为 `frontend:gemini_web`；未配对时返回 `frontend_not_paired:gemini_web`。
- [ ] Gemini 令牌拿不到 `capture_add`、`i_remember`；Claude、ChatGPT 既有测试全部不改且通过。
- [ ] 诊断：日志里不出现回调路径、编号；`callback_class` 取值正确。
- [ ] Dart：`test/ui/core/widgets/chat_message_source_label_test.dart` 加 Gemini 一项。
- [ ] 开关：未设 → 开；`0` → Gemini 注册、授权、换令牌、已签令牌全部拒绝；`2`/`true` → 启动报错 `invalid_gemini_mode`。

## 允许修改的路径
- `tools/i_remote_mcp/oauth.mjs`、`server.mjs`、`writeback.mjs`、`mcp.mjs`（仅工具清单需要时）、`diagnostics.mjs`
- `tools/i_remote_mcp/chatgpt_candidate.mjs` 及其测试
- `tools/i_remote_mcp/*.test.mjs`（只追加；新建 `gemini_frontend.test.mjs`）。允许改动的既有断言只有：`frontend_registry.test.mjs` 第 10 行（改为断言精确表仍只有 Claude、ChatGPT，模式表只有 Gemini）、第 22–23 行（注册表名改为两张表的并集）；`chatgpt_candidate.test.mjs` 中 `changed_files`/`unchanged_files` 的数值。
- `lib/ui/character/widgets/chat_message_source_label.dart`、`test/ui/core/widgets/chat_message_source_label_test.dart`
- `tools/i_remote_mcp/README.md`
- `docs/development/handoffs/RELAY_20261023_d3-gemini-frontend.md`（只由 Claude 改）

## 不做 / 边界
- 不改 Core、`i_memory_read.mjs`、`tools/i_core/maintenance/`（含 `update-mcp-source.mjs`）。
- 不新增运行时文件；不加 Sesame。
- 不生成生产候选、不部署、不碰生产和真实数据。
- 止损：同一测试名或错误码连续两个提交失败即 blocked，最多 3 轮。

## 验证命令
- `node --test tools/i_remote_mcp/*.test.mjs tools/i_memory/*.test.mjs`
- `flutter test test/ui/core/widgets/chat_message_source_label_test.dart test/ui/character/widgets/persona_chat_source_label_test.dart test/ui/desktop/desktop_chat_source_label_test.dart`
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/d3-candidate`（成功，六文件；输出不提交）
- CI 全绿。

## 为什么不先做只读探针（与 D2 不同）
现有诊断把非 Claude 回调一律记成 `[redacted]`，`/register` 也不记回调，所以让 Gemini 先连一次被拒，日志里拿不到回调形状。改为：按社区资料实现模式匹配，同时加上 `callback_class`/`gemini_kept_count` 诊断字段，由部署后的真人验收检验；若验收时 `gemini_kept_count = 0`，按诊断结果修订主机白名单。

## 部署（合并后另行确认，手动执行）
1. 生成六文件候选，经 `tools-3baf72d` 的 `update-mcp-source.mjs --dry-run`（Windows PowerShell 5.1）。
2. 环境变量不动（未设即开，用户决定 3）；按 update-mcp-source 注册新任务（停用），停服切换、启动。
3. `pair-core --frontend gemini_web`。
4. 真人验收：Gemini 网页端添加 → 授权 → 普通聊天里调一次 `i_context`；Spark 里再试一次；写一轮 `i_chat_turn`（Gemini 会弹确认）；App 显示“Gemini”。Claude、ChatGPT 各写一轮确认不受影响。
5. 写一个 `/林埃` Skill，只放调用规则（每轮 `i_chat_turn` start/end、查不到不编造）。

## 用户决定（10-23，均按建议）
1. **Gemini 能用哪些工具**：同 ChatGPT：读取、聊天写回、只读周/日计划；不给随手记（`capture_add`）和笔记（`i_remember`）。
2. **数据边界**：Gemini 要求开 Keep Activity，对话会存在 Google 的活动记录里，林埃的上下文也会进去。用户已接受。
3. **开关默认值**（待用户确认，按建议起草）：未设即开、设 `0` 关闭。理由：部署工具不能改环境变量；授权本身要口令且有失败锁定，未配对时不能写回。备选是默认关并在本 PR 改部署工具，范围更大。

## 需要真人的部分
- 合并由用户进行，收到 `relay:done` 前不要合并。
- 部署每一步单独同意。
