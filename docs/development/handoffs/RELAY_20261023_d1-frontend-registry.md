<!-- relay:contract v1 -->
# D1 合同：MCP 前端身份注册表（回调与前端一一对应，未知默认拒绝）

## 背景（已核对 v3-lab `3944d31`）
- `tools/i_remote_mcp/oauth.mjs` 第 28–38 行：`frontendForRedirectUri` 只要回调不是 ChatGPT，就归为 `claude_web`；`frontendForRegisteredClient`（旧令牌无 `frontend` 字段时的兜底）同样默认 `claude_web`。
- 第 145–166 行：`I_REMOTE_MCP_EXTRA_REDIRECT_URIS` 可追加任意 https 回调，这些回调签出的令牌会被记成 `claude_web`，拿到 Claude 的全部写工具，写进时间线也标成 Claude。
- `server.mjs` 第 195–198 行：路由是二选一（`=== 'chatgpt_web'` 否则走 Claude 处理器），未知 frontend 落到权限最大的一侧。
- 生产 MCP 跑的不是 v3-lab 源码，而是 `chatgpt_candidate.mjs` 由基线 `3ce7aacc` 加补丁生成的六文件候选。构建器要求“v3-lab 现行 server/oauth/mcp/writeback = 基线 + PATCHES + FRONTEND_PATCHES.mainline”逐字节一致，所以 D1 改了源码，必须同时在构建器里加一组补丁，否则候选生成直接失败，也部署不了。
- `update-mcp-source.mjs` 要求候选文件名与现役六个完全一致，所以**不能新增运行时文件**，注册表只能放进现有文件。
- 生产 MCP 配置不设 `I_REMOTE_MCP_EXTRA_REDIRECT_URIS`（`mcp-config-switch-bindings` 测试会拒绝它）。

## 完成标准

**注册表（`oauth.mjs`，单一位置）**
- [ ] 新增导出常量 `FRONTEND_CALLBACKS`（`Object.freeze`），frontend 名 → 精确回调列表：
  - `claude_web` → `CLAUDE_AI_CALLBACKS` 的两个地址
  - `chatgpt_web` → `[CHATGPT_CALLBACK_URI]`（仍受 `I_REMOTE_MCP_CHATGPT_ENABLED` 开关控制）
  - 任一回调只能属于一个 frontend（测试断言无重复）。
- [ ] `frontendForRedirectUri(uri)`：在注册表中精确查找，查不到返回 `null`，不再兜底。
- [ ] 删除 `I_REMOTE_MCP_EXTRA_REDIRECT_URIS` 与 `extraRedirectUris`（用户决定 1）。`isAllowedRedirectUri` 只认注册表中已启用的回调。
- [ ] `/register`：所有 `redirect_uris` 必须属于**同一个** frontend，否则 400 `invalid_redirect_uri`。
- [ ] `/authorize`、`/token`（authorization_code）：回调查不到 frontend 时拒绝（authorize 显示错误页不重定向；token 返回 `invalid_grant`），不签发令牌。
- [ ] 旧令牌兼容（`frontend` 字段缺失，D1b 之前签发的）：仅当该 client 的全部 `redirect_uris` 都属于 `claude_web` 时视为 `claude_web`；否则 `verifyAccessToken` 返回 `invalid_token`，refresh 返回 `invalid_grant`。
- [ ] 令牌记录里 `frontend` 不在注册表中（含被篡改的值）时，同样拒绝。

**路由（`server.mjs`）**
- [ ] 按 frontend 显式选择处理器：`claude_web` → 现有 Claude 处理器；`chatgpt_web` → ChatGPT 处理器；其他值 → 401 `invalid_token`，不进入 `handleRpcMessage`。不得再用“否则走 Claude”的写法。
- [ ] 注册表的 frontend 名集合必须等于 `writeback.mjs` 的 `FRONTENDS` 键集合（测试断言）。

**候选构建器（`chatgpt_candidate.mjs`）**
- [ ] 新增一组补丁（例如 `REGISTRY_PATCHES`，含 `mainline` 与 `legacy` 两侧），使 v3-lab 新源码仍能逐字节通过正向/反向校验；候选仍为六个文件、`changed_files` 仍为 4。
- [ ] 候选产物里不出现 `I_REMOTE_MCP_EXTRA_REDIRECT_URIS`、`extraRedirectUris`，也不出现“否则 claude_web”的兜底（测试用字符串断言）。

**App 显示名一致性（用户决定 2）**
- [ ] 新测试读取 `lib/ui/character/widgets/chat_message_source_label.dart` 中 `_knownChatSources` 的键，断言等于注册表每个 frontend 的 `frontend:<name>`。以后加 Sesame 漏改 App 映射表时 CI 会红。不改 Dart 文件。

**测试（合成数据）**
- [ ] `oauth.test.mjs` / `oauth_identity.test.mjs` 追加：未知 https 回调注册被拒；混合 Claude+ChatGPT 回调注册被拒；ChatGPT 关闭时 ChatGPT 回调被拒；旧令牌（删掉 `frontend`）在纯 Claude client 上仍为 `claude_web`、在含非 Claude 回调的 client 上被拒；`frontend` 改成 `sesame`/`""`/`Claude_web` 的令牌被拒且不进 RPC。
- [ ] `oauth.test.mjs` 第 200–201 行依赖 extra 参数的两条断言，改为断言 extra 机制已移除（这是唯一允许改动的既有断言）。
- [ ] 新建 `tools/i_remote_mcp/frontend_registry.test.mjs`：注册表无重复回调、与 `FRONTENDS` 键一致、与 App 映射表一致、`server.mjs` 未知 frontend 返回 401。
- [ ] `chatgpt_candidate.test.mjs`：候选生成成功、六文件、四个改动、正反向补丁可还原，以及上面的字符串断言。

## 允许修改的路径
- `tools/i_remote_mcp/oauth.mjs`、`tools/i_remote_mcp/server.mjs`
- `tools/i_remote_mcp/chatgpt_candidate.mjs`、`tools/i_remote_mcp/chatgpt_candidate.test.mjs`
- `tools/i_remote_mcp/oauth.test.mjs`、`tools/i_remote_mcp/oauth_identity.test.mjs`（只追加；第 200–201 行例外）
- `tools/i_remote_mcp/frontend_registry.test.mjs`（新建）
- `tools/i_remote_mcp/README.md`（删除 extra 回调说明，写明“新增前端 = 注册表加一项 + 配对 + App 映射表加一行”）
- `docs/development/handoffs/RELAY_20261023_d1-frontend-registry.md`（只由 Claude 改）

## 不做 / 边界
- 不改 `mcp.mjs`、`writeback.mjs`、`diagnostics.mjs`、`i_memory_read.mjs`、Core、App、`tools/i_core/maintenance/`。
- 不新增运行时文件；不加 Sesame/Gemini（D2/D3 做）。
- 不生成生产候选、不运行 update-mcp-source、不碰生产和真实数据。
- 止损：同一测试名或同一错误码在连续两个提交上失败，即判为 blocked。最多 3 轮。

## 验证命令
- `node --test tools/i_remote_mcp/*.test.mjs tools/i_memory/*.test.mjs`
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/d1-candidate`（成功，manifest 六文件、`changed_files: 4`；输出目录不提交）
- `git status --short`（只出现允许修改的路径）
- CI：Linux 全量与 `MCP ChatGPT compatibility (Windows)` 全绿。

## 用户决定（10-23，均按建议）
1. **`I_REMOTE_MCP_EXTRA_REDIRECT_URIS`**：删除。生产没用它；保留就意味着任意回调都能签出令牌，与“未知默认拒绝”矛盾。以后接 Sesame 走代码改动（注册表加一项）。
2. **App 显示名是否改读 Core 设备显示名**（C1 遗留）：**不改**，保留 App 映射表，另加上面的一致性测试。理由：Core 目前没有给 App 的设备列表接口，改读要动 Core API、同步协议和 App 三处；而且 Core 登记名是“claude.ai 网页端”“ChatGPT 网页端”，不是 C1 定的“Claude”“ChatGPT”。
3. **旧令牌兼容**：按上面“纯 Claude client 才认”处理。现役 Claude 连接不受影响；如果有异常的旧 client，最坏是被要求重新授权一次。

## 部署（合并后另行确认，手动粘贴）
1. 在用户电脑用 v3-lab 生成六文件候选，复制到受保护私有目录。
2. 从工具副本 `tools-3baf72d` 用 `update-mcp-source.mjs --dry-run` 生成新配置（Windows PowerShell 5.1），再正式生成并注册新任务（停用状态）。
3. 停服切换、启动，真人验收：Claude 和 ChatGPT 各写一轮，App 标签不变；用一个未知回调注册应被拒。

## 需要真人的部分
- 合并由用户进行。Codex 回帖并收到 `relay:done` 前不要合并。
- 部署每一步单独同意。

## 审核记录
（待填）
