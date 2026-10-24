<!-- relay:contract v1 -->
# D2a 合同：探测 Sesame 的 OAuth 回调（诊断加回调形状）

> 已核对 v3-lab `0a3b903`（D1、D3、#49、D4 已合并并部署）。

## 背景
- D2（接入 Sesame）的第一步。用户 10-24 在 Sesame 的 “Add custom app” 里添加 `/mcp`，现役 MCP 诊断日志显示：`POST /mcp` 401 → 两个 `.well-known` 200 → `POST /register` 400，`callback_class: other`、`callback_count: 1`、`ua_family: python-httpx`。也就是说，Sesame 走的是标准 DCR，只是回调不在 `FRONTEND_CALLBACKS` 白名单里。
- Sesame 没有公开回调地址；`diagnostics.mjs` 第 15 行起的规则是“不输出未识别回调的任何部分”，所以现在拿不到。
- 本合同只在 `/register` 遇到 `other` 类回调时，多记一份**脱敏后的回调形状**：协议、主机、端口，以及路径每一段的形状（看起来是固定单词的段保留原文，其他段只记长度）。这样足够写出白名单规则（精确地址或 Gemini 那种“主机 + 路径前缀”），又不会把可能带用户 ID 或密钥的段写进日志。用户 10-24 同意这项诊断口径的放宽。
- 注册逻辑、白名单、OAuth 行为一律不变；Sesame 依旧会被拒。正式接入（D2b：回调白名单、`sesame` 身份、来源标签）等拿到形状后另出合同。
- 生产跑构建器生成的六文件候选，改 `diagnostics.mjs` 必须在 `chatgpt_candidate.mjs` 加补丁组（mainline、legacy 两侧）。

## 完成标准

**诊断（`diagnostics.mjs`）**
- [ ] 新增导出函数 `callbackShape(value)`，输入不可信字符串，返回字符串或 `null`：
  - 解析失败、非 `http:`/`https:`、带用户名或密码时返回 `null`。
  - 结果格式：`<protocol>//<hostname>[:<port>]<path>`，`hostname` 用 `URL` 解析后的小写值，超过 253 字符返回 `null`；默认端口不写。
  - 路径按 `/` 分段：满足 `^[a-z][a-z_-]{0,31}$` 的段保留原文，其他非空段替换为 `{n}`（n 为该段的字符数，如 `{36}`）；空段保留（保持结尾斜杠）。路径整体超过 20 段返回 `null`。
  - 有 query 时末尾追加 `?{q}`，有 fragment 时追加 `#{f}`，不记录其内容。
- [ ] `registration(values, kept)`：当 `callback_class` 为 `other` 时，额外写字段 `callback_shapes`，值为所有 `other` 类回调的 `callbackShape` 结果数组（去掉 `null`，最多 8 项，去重并保持顺序）；其他分类的请求不写这个字段。
- [ ] `callbackClass`、`callback_count`、`gemini_kept_count` 等既有字段与分类不变；`GET /authorize` 的 `callback` 字段仍走原来的 `endpoint()` 脱敏，不改。
- [ ] 文件第 15 行注释改成说明新口径：未识别回调只记录上述形状，不记录原文。

**候选构建器（`chatgpt_candidate.mjs`）**
- [ ] 新补丁组（如 `SESAME_PROBE_PATCHES`，mainline 与 legacy），v3-lab 新源码逐字节通过正反向校验；候选仍六文件、`changed_files` 仍为 5（diagnostics 保留 CRLF）。

**README**
- [ ] `tools/i_remote_mcp/README.md` “脱敏运行诊断”一节补一句 `callback_shapes` 的含义与脱敏规则。

**测试（合成数据）**
- [ ] 新建 `tools/i_remote_mcp/callback_shape.test.mjs`：
  - `https://app.example.com/oauth/callback` → 原样；`https://App.Example.com:8443/oauth/callback/` → `https://app.example.com:8443/oauth/callback/`；
  - `https://x.example.com/r/user_bound_custom-mcp-AbC123` → `https://x.example.com/r/{25}`；`https://x.example.com/cb/550e8400-e29b-41d4-a716-446655440000` → `https://x.example.com/cb/{36}`；
  - `https://x.example.com/cb?state=secret#frag` → `https://x.example.com/cb?{q}#{f}`，结果不含 `secret`、`frag`；
  - `https://user:pw@x.example.com/cb`、`ftp://x.example.com/cb`、`not a url`、空串、超长主机、超过 20 段 → `null`；
  - `http://127.0.0.1:9000/callback` → 原样。
  - 全流程：`/register` 只带一个合成的未知回调（如 `https://sesame-test.example/oauth/callback/abcdef0123456789`）→ 仍 400；诊断记录 `callback_class: other`、`callback_shapes: ['https://sesame-test.example/oauth/callback/{16}']`，整条记录 JSON 不含 `abcdef0123456789`。
  - Claude、ChatGPT、Gemini、Antigravity 回调注册的诊断记录没有 `callback_shapes` 字段。
- [ ] 既有测试不改且通过（`chatgpt_candidate.test.mjs` 只追加候选相关断言）。

## 允许修改的路径
- `tools/i_remote_mcp/diagnostics.mjs`
- `tools/i_remote_mcp/chatgpt_candidate.mjs`、`chatgpt_candidate.test.mjs`（只追加）
- 新建 `tools/i_remote_mcp/callback_shape.test.mjs`
- `tools/i_remote_mcp/README.md`
- `docs/development/handoffs/RELAY_20261024_d2a-sesame-callback-probe.md`（只由 Claude 改）

## 不做 / 边界
- 不改 `oauth.mjs`、`server.mjs`、`writeback.mjs`、`mcp.mjs`、Core、`tools/i_core/maintenance/`、App。
- 不放宽任何回调、不新增前端或开关；不新增运行时文件。
- 不生成生产候选、不部署、不碰生产和真实数据。
- 止损：同一测试名或错误码连续两个提交失败即 blocked，最多 3 轮。

## 验证命令
- `node --test tools/i_remote_mcp/*.test.mjs tools/i_memory/*.test.mjs`
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/d2a-candidate`（成功，六文件、`changed_files: 5`；输出不提交）
- CI 全绿。

## 部署（合并后另行确认，手动执行）
1. 按 D4 段 6 的流程，从现役任务 `HereIAm-iCoreSchema6-d4-mcp-20261023-48bd91ed` 用 `update-mcp-source` 登记新任务并切换（不加 NoRollback）；不改读取策略、不配对。
2. 用户在 Sesame 里再添加一次 `/mcp`，然后只读取出当次 `/register` 记录的 `callback_shapes`，贴回给 Claude 写 D2b。
