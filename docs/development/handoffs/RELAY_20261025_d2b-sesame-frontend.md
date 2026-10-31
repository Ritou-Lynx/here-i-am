<!-- relay:contract v1 -->
# D2b 合同：接入 Sesame（sesame）

> 基于 v3-lab `84980161`（D2a 已合并，10-25 已部署）。

## 背景
- 催睡方案里，三星例程会拉起 Sesame（角色 Charlie），需要 Sesame 通过 i MCP 读写林埃的上下文。
- D2a 部署后，用户 10-25 在 Sesame 的 “Add custom app” 里添加 `/mcp`。诊断记录如下：`/register` 400，`callback_class: other`，`callback_count: 1`，`ua_family: python-httpx`，`callback_shapes: ['https://sesameai.app/api/oauth/external-mcp/callback']`（主机名由用户确认）。
- 回调路径没有可变段，用一个精确地址就能放行，走 D4 的精确表方式，不需要像 Gemini 那样做模式匹配。
- Sesame 由服务端代为发起 OAuth（UA 是 python-httpx）。注册时本服务固定返回 `token_endpoint_auth_method: none`，并要求 PKCE S256。Sesame 是否接受这两点，要到验收时才知道；本合同不改 OAuth 能力。验收失败时，按诊断日志另行修订。
- 接入方式照搬 D4：独立开关 `I_REMOTE_MCP_SESAME_ENABLED`（未设即开，`0` 关闭），独立凭据 `core-frontend-sesame.json`，工具集与 ChatGPT、Gemini、Antigravity 相同，缺凭据时返回 `frontend_not_paired:sesame`。
- 前端名 `sesame` 符合 Core 与读取策略的命名规则 `^[a-z][a-z0-9_]{1,31}$`。
- 生产运行的是构建器生成的六文件候选。改源码必须在 `chatgpt_candidate.mjs` 里加补丁组（mainline、legacy 两侧）。mainline 的补丁链现在是 FRONTEND → REGISTRY → GEMINI → ANTIGRAVITY → SESAME_PROBE → FOOD，新补丁组放在 SESAME_PROBE 与 FOOD 之间，反向链按相反顺序撤回。

## 完成标准

**注册表（`oauth.mjs`）**
- [ ] 新增导出常量 `SESAME_CALLBACKS = Object.freeze(['https://sesameai.app/api/oauth/external-mcp/callback'])`，并在 `FRONTEND_CALLBACKS` 里加 `sesame: SESAME_CALLBACKS`。不加模式规则，不放行其他主机（包括 `www.` 和其他子域）、端口、`http`、尾斜杠、query、fragment、大小写变体。
- [ ] 开关 `I_REMOTE_MCP_SESAME_ENABLED`：未设或 `1` 为开，`0` 为关，其他值启动时报错 `invalid_sesame_mode`。新增导出函数 `sesameEnabledFromEnv`，写法同 `antigravityEnabledFromEnv`。`OAuthServer` 构造参数加 `sesameEnabled` 并做类型校验；`isEnabledFrontend` 和它的所有调用点都要考虑这个开关。
- [ ] 开关关闭时，Sesame 的回调注册、授权、换令牌、refresh、已签令牌的使用一律拒绝。
- [ ] Sesame 回调和其他前端的回调混合注册时一律返回 400。

**路由与工具（`server.mjs`、`writeback.mjs`）**
- [ ] `writeback.mjs` 的 `FRONTENDS` 加 `sesame`：`deviceId: 'frontend:sesame'`，`displayName: 'Sesame'`，`credentialFile: 'core-frontend-sesame.json'`。
- [ ] `server.mjs` 显式分支 `sesame`，交给 Sesame 处理器，工具集与 Antigravity 相同（`i_context`、`i_recall`、`i_chat_turn`、`week_get`、`day_get`，没有 `capture_add`、`i_remember`）。缺凭据时 `i_chat_turn` 返回 `frontend_not_paired:sesame`，绝不借用其他前端的凭据。
- [ ] 启动入口读取 `sesameEnabledFromEnv()`；开关打开且写回开启时加载 `sesame` 凭据，写法同 Antigravity；并把开关传给 `createApp` 和 `OAuthServer`。
- [ ] `pair-core --frontend sesame` 可用。
- [ ] Origin：Sesame 是服务端调用，预计不带 Origin。不新增任何允许的 Origin。

**诊断（`diagnostics.mjs`）**
- [ ] `callbackClass` 遇到 Sesame 回调返回固定值 `sesame`，并加进分类白名单（第 98 行）。`callback_shapes` 仍然只在 `other` 时记录，所以 Sesame 注册不写这个字段。其他分类不变。

**候选构建器（`chatgpt_candidate.mjs`）**
- [ ] 新增补丁组 `SESAME_PATCHES`（mainline 与 legacy 两侧），按上面的顺序接进正反向链。v3-lab 新源码要逐字节通过正反向校验；候选仍是六个文件，`changed_files` 仍为 5，diagnostics 保留 CRLF。
- [ ] N1 测试 “N1 mainline food patches preserve…” 里钉的哈希，只允许更新本合同实际改动的那几个文件（预计是 oauth、server、writeback、diagnostics），并且每个都要加注释 `// D2b sesame`；仍然断言候选不含 food。

**App（`lib/ui/character/widgets/chat_message_source_label.dart`）**
- [ ] `_knownChatSources` 加 `'frontend:sesame': 'Sesame'`。

**测试（合成数据）**
- [ ] 新建 `tools/i_remote_mcp/sesame_frontend.test.mjs`：
  - 回调精确命中 `sesame`。以下变体全部返回 `null`：`https://www.sesameai.app/...`、`https://evil.sesameai.app/...`、`http://sesameai.app/...`、`https://sesameai.app:8443/...`、加尾斜杠、`?x=1`、`#f`、`https://SESAMEAI.app/...`、`/api/oauth/external-mcp/callback2`、带 userinfo 的地址。
  - 全流程：注册（单个回调，`client_name` 任意）→ 授权 → 换令牌 → RPC 走 Sesame 处理器 → refresh。`tools/list` 里没有 `capture_add`、`i_remember`；`i_chat_turn` 记为 `frontend:sesame`；未配对时返回 `frontend_not_paired:sesame`。
  - 混合注册：Sesame 加 Claude、Sesame 加 Antigravity，都返回 400。
  - 开关：未设时为开；设 `0` 时注册、授权、换令牌、已签令牌、refresh 全部拒绝；设 `2` 或 `true` 时启动报错 `invalid_sesame_mode`。
  - 诊断：`callback_class` 为 `sesame`，没有 `callback_shapes` 字段，日志里不含回调原文。
- [ ] `test/ui/core/widgets/chat_message_source_label_test.dart` 加 Sesame 一项。
- [ ] 其他既有测试不改并且通过，例外只有：`frontend_registry.test.mjs` 第 10 行（精确表加 `sesame: SESAME_CALLBACKS`，以及对应的 import），和上面说的 N1 哈希。

## 允许修改的路径
- `tools/i_remote_mcp/oauth.mjs`、`server.mjs`、`writeback.mjs`、`diagnostics.mjs`、`mcp.mjs`（仅在工具清单确实需要时）
- `tools/i_remote_mcp/chatgpt_candidate.mjs`、`chatgpt_candidate.test.mjs`
- `tools/i_remote_mcp/*.test.mjs`：只能追加；新建 `sesame_frontend.test.mjs`；既有断言只能按上面两处例外修改
- `lib/ui/character/widgets/chat_message_source_label.dart`、`test/ui/core/widgets/chat_message_source_label_test.dart`
- `tools/i_remote_mcp/README.md`（加 Sesame 一节）
- `docs/development/handoffs/RELAY_20261025_d2b-sesame-frontend.md`（只由 Claude 改）

## 不做 / 边界
- 不改 Core、`i_memory_read.mjs`、`tools/i_core/`、`tools/i_continuity_gateway/`、食物相关文件。
- 不新增运行时文件；不改口令规则、锁定策略、令牌有效期、`token_endpoint_auth_method`。
- 不生成生产候选，不部署，不碰生产和真实数据。
- 止损：同一个测试名或错误码连续两个提交失败，就回 blocked；最多 3 轮。

## 验证命令
- `node --test tools/i_remote_mcp/*.test.mjs tools/i_memory/*.test.mjs`
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/d2b-candidate`：要成功，六个文件，`changed_files: 5`；输出不提交。
- Flutter 测试以 CI 为准。CI 要全绿。

## 部署（合并后另行确认，手动执行）
1. 用 `tools-dddff0f1` 生成新候选。候选根目录和其下每个子目录都要设成受保护 ACL。然后用 `update-mcp-source` 从现役 d2a 任务登记新任务（先停用），再切换（不加 NoRollback）。
2. 读取策略 `auto_share_origins` 加 `sesame`（先备份），执行 `pair-core --frontend sesame`，重启。
3. 真人验收：在 Sesame 里添加 `/mcp`，弹窗输入口令授权，调一次 `i_context`，写一轮 `i_chat_turn`，手机 App 里能看到这条记录（显示 “Sesame” 需要重建 App）。Claude、ChatGPT 各写一轮，确认不受影响。

## 需要真人的部分
- 合并由用户进行；收到 `relay:done` 之前不要合并。
- 部署的每一步都要用户单独同意。

## 审核记录

### 第 1 轮（10-25）：通过（Claude 修了测试夹具）
- Codex 提交 `d16b5ed`，只改了允许的 11 个路径，报 blocked：`callback_shape.test.mjs`、`frontend_registry.test.mjs`、`oauth_identity.test.mjs` 3 项旧测试把 `sesame` 当作“未知前端”夹具，sesame 变成已知前端后这 3 项失败。
- Claude 处理：callback_shape 测试的分类表加 `sesame: 'sesame'`，另外两处夹具名改为 `unknown_frontend`。这几处属于同类夹具调整，不改变断言的意图。
- 核对 diff：`SESAME_CALLBACKS` 只有一个精确地址，没有模式规则；开关贯穿注册、授权、换令牌、refresh、令牌校验；server 有显式的 `sesame` 分支，工具集与 Antigravity 相同，未配对时返回 `frontend_not_paired:sesame`；diagnostics 分类为 `sesame`，不写 `callback_shapes`；N1 测试只更新了 4 个改动文件的哈希，并标注 `// D2b sesame`；Dart 测试的“未知前端”改用 `frontend:synthetic_unknown`。
- 云端复跑 263/263。候选 6 个文件，`changed_files: 5`；哈希前 8 位为 server `12fc40a9`、oauth `e2c88aca`、diagnostics `5303ef6d`、mcp `0ae610bf`、writeback `a7a6f95d`、i_memory_read `cee18518`。Flutter 以 CI 为准。
