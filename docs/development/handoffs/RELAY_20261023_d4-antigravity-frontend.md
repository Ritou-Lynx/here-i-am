<!-- relay:contract v1 -->
# D4 合同：接入 Antigravity（antigravity）

> 已核对 v3-lab `084be21`（D1、D3 及 #49 已合并并部署）。

## 背景
- Antigravity 通过本机 MCP 代理（客户端名 `MCP CLI Proxy`）连远端 MCP：动态注册公开客户端（`token_endpoint_auth_method: none`，PKCE S256），`grant_types` 为 `authorization_code`、`refresh_token`，scope `i.read i.write offline_access`。回调固定为两个本机回环地址（端口由 MCP URL 哈希得出，用户提供，不随启动变化）：
  - `http://127.0.0.1:32014/oauth/callback`
  - `http://localhost:32014/oauth/callback`
- D1 之后 `oauth.mjs` 第 29–32 行 `FRONTEND_CALLBACKS` 只做精确匹配，`/register`（第 268 行起）要求全部回调属于同一个已启用前端。两个回环地址都放进同一个前端的精确表，现有注册逻辑即可接受，不需要像 Gemini 那样做模式匹配或过滤式注册。
- 精确表本身不限制 `http:`；第 280、286 行错误文字写的是 “https callback”，只是文案。
- 安全边界：回环回调意味着拿到口令的人能在任意机器上换到令牌。但现在拿到口令的人已经能在自己的 claude.ai 账号里添加这个 MCP，所以口令本来就是唯一闸门，失败锁定不变；本合同不放宽口令规则。
- 接入方式照搬 Gemini（D3）：独立开关、独立凭据 `core-frontend-antigravity.json`、工具集同 ChatGPT/Gemini、缺凭据时 `frontend_not_paired:antigravity`。`mcp.mjs` 第 130–135 行、第 272–273 行已按“非 `claude_web` 只给 `i_chat_turn`、不给笔记”处理，预计不用改。
- 前端名须满足 Core `^frontend:[a-z][a-z0-9_]{1,31}$`（`i_core_store.mjs` 第 38 行）与读取策略 `auto_share_origins` 的同样规则，`antigravity` 符合。
- 生产跑构建器生成的六文件候选，改源码必须在 `chatgpt_candidate.mjs` 加补丁组（mainline、legacy 两侧）；不能新增运行时文件。`update-mcp-source` 不能改环境变量，所以开关只能“未设即开”。

## 完成标准

**注册表（`oauth.mjs`）**
- [ ] 新增导出常量 `ANTIGRAVITY_CALLBACKS`（`Object.freeze`），恰好是上面两个地址；`FRONTEND_CALLBACKS` 加 `antigravity: ANTIGRAVITY_CALLBACKS`。不新增模式规则，不放行其他端口、路径、`::1`、`https`、带 query/fragment 的变体。
- [ ] 开关 `I_REMOTE_MCP_ANTIGRAVITY_ENABLED`：未设或 `1` 为开，`0` 为关，其他值启动报错 `invalid_antigravity_mode`。新增导出 `antigravityEnabledFromEnv`，写法同 `geminiEnabledFromEnv`（第 190 行）。`OAuthServer` 构造参数加 `antigravityEnabled`，类型校验同 `geminiEnabled`；`isEnabledFrontend` 及其所有调用点一并考虑该开关。
- [ ] 开关关闭时：Antigravity 回调注册、授权、换令牌、refresh、已签令牌使用一律拒绝（同 Gemini）。
- [ ] Antigravity 回调与 Claude/ChatGPT/Gemini 回调混合注册一律 400；单独一个回环地址注册也可以。
- [ ] 第 280、286 行错误描述改为不含 “https” 的中性文案（如 `redirect_uris must be an allowed callback`）；错误码 `invalid_redirect_uri` 不变。

**路由与工具（`server.mjs`、`writeback.mjs`）**
- [ ] `writeback.mjs` `FRONTENDS` 加 `antigravity`：`deviceId: 'frontend:antigravity'`、`displayName: 'Antigravity'`、`credentialFile: 'core-frontend-antigravity.json'`。
- [ ] `server.mjs` 显式分支 `antigravity` → Antigravity 处理器，工具集与 Gemini 相同（`i_context`、`i_recall`、`i_chat_turn`、`week_get`、`day_get`；无 `capture_add`、`i_remember`）。缺凭据时 `i_chat_turn` 返回 `frontend_not_paired:antigravity`，绝不使用其他前端的凭据。
- [ ] 启动入口：读 `antigravityEnabledFromEnv()`，开且写回开启时加载 `antigravity` 凭据，写法同 Gemini（第 600–607 行）；并把开关传给 `createApp`/`OAuthServer`。
- [ ] `pair-core --frontend antigravity` 可用（`frontendDefinition` 已按 `FRONTENDS` 查找，预计无需改）。
- [ ] Origin：本机代理预计不带 Origin。不新增任何允许的 Origin（第 52–53、115 行不动）；验收若发现带了 Origin 另行修订。

**诊断（`diagnostics.mjs`）**
- [ ] `callbackClass`（第 16 行起）对 Antigravity 回调返回固定值 `antigravity`；其他分类不变。不记录回调原文。

**候选构建器（`chatgpt_candidate.mjs`）**
- [ ] 新补丁组（如 `ANTIGRAVITY_PATCHES`，mainline 与 legacy），v3-lab 新源码逐字节通过正反向校验；候选仍六文件、`changed_files` 仍为 5（diagnostics 保留 CRLF）。

**App（`lib/ui/character/widgets/chat_message_source_label.dart`）**
- [ ] `_knownChatSources` 加 `'frontend:antigravity': 'Antigravity'`。

**测试（合成数据）**
- [ ] 新建 `tools/i_remote_mcp/antigravity_frontend.test.mjs`：
  - 两个回调精确命中 `antigravity`；`http://127.0.0.1:32015/oauth/callback`、`http://[::1]:32014/oauth/callback`、`https://127.0.0.1:32014/oauth/callback`、`http://127.0.0.1:32014/oauth/callback/`、`http://127.0.0.1:32014/oauth/callback?x=1`、`http://LOCALHOST:32014/oauth/callback`、`http://127.0.0.1:32014/other` 全部为 `null`。
  - 全流程：注册（两个回调、`client_name: MCP CLI Proxy`、scope 含 `offline_access`）→ 授权 → 换令牌 → RPC 走 Antigravity 处理器 → refresh；`tools/list` 无 `capture_add`、`i_remember`；`i_chat_turn` 记为 `frontend:antigravity`；未配对时返回 `frontend_not_paired:antigravity`。
  - 混合注册（Antigravity + Claude、Antigravity + Gemini）→ 400。
  - 开关：未设 → 开；`0` → 注册、授权、换令牌、已签令牌、refresh 全部拒绝；`2`/`true` → 启动报错 `invalid_antigravity_mode`。
  - 诊断：`callback_class` 为 `antigravity`，日志不含回调原文。
- [ ] `test/ui/core/widgets/chat_message_source_label_test.dart` 加 Antigravity 一项。
- [ ] Claude、ChatGPT、Gemini 既有测试除下面列出的断言外不改且通过。

## 允许修改的路径
- `tools/i_remote_mcp/oauth.mjs`、`server.mjs`、`writeback.mjs`、`diagnostics.mjs`、`mcp.mjs`（仅工具清单确需时）
- `tools/i_remote_mcp/chatgpt_candidate.mjs`、`chatgpt_candidate.test.mjs`
- `tools/i_remote_mcp/*.test.mjs`：只追加；新建 `antigravity_frontend.test.mjs`。允许改动的既有断言只有：`frontend_registry.test.mjs` 第 10 行（精确表加 `antigravity: ANTIGRAVITY_CALLBACKS`）。
- `lib/ui/character/widgets/chat_message_source_label.dart`、`test/ui/core/widgets/chat_message_source_label_test.dart`
- `tools/i_remote_mcp/README.md`（加 Antigravity 一节）
- `docs/development/handoffs/RELAY_20261023_d4-antigravity-frontend.md`（只由 Claude 改）

## 不做 / 边界
- 不改 Core、`i_memory_read.mjs`、`tools/i_core/maintenance/`、`tools/i_continuity_gateway/`。
- 不新增运行时文件；不改口令规则、锁定策略、令牌有效期。
- 不生成生产候选、不部署、不碰生产和真实数据。
- 止损：同一测试名或错误码连续两个提交失败即 blocked，最多 3 轮。

## 验证命令
- `node --test tools/i_remote_mcp/*.test.mjs tools/i_memory/*.test.mjs`
- （CI 执行，本机无 Flutter 时可跳过）`flutter test test/ui/core/widgets/chat_message_source_label_test.dart`
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/d4-candidate`（成功，六文件、`changed_files: 5`；输出不提交）
- CI 全绿。

## 部署（合并后另行确认，手动执行）
1. 从工具副本 `tools-dddff0f1` 生成新候选，`update-mcp-source` 从现役 d3fix 任务登记新任务（停用），切换（不加 NoRollback）。
2. 读取策略 `auto_share_origins` 加 `antigravity`（先备份），`pair-core --frontend antigravity`，重启。
3. 真人验收：Antigravity 添加远端 MCP → 弹窗输口令授权 → 调一次 `i_context` → 写一轮 `i_chat_turn` → 手机 App 能看到（显示 “Antigravity” 需 App 重建）。Claude、ChatGPT 各写一轮确认不受影响。

## 用户决定（10-23，均按建议）
1. **工具集**：同 ChatGPT/Gemini，不给随手记和笔记。
2. **开关**：`I_REMOTE_MCP_ANTIGRAVITY_ENABLED` 未设即开、`0` 关闭。理由同 D3：部署工具不能改环境变量。
3. **安全**：接受“本机回环回调 + 口令”作为闸门；口令仍是唯一凭据，与现状等价。

## 需要真人的部分
- 合并由用户进行，收到 `relay:done` 前不要合并。
- 部署每一步单独同意。

## 审核记录
