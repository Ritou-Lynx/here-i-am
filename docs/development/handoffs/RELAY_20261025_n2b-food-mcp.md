<!-- relay:contract v1 -->
# N2b 合同：生产 MCP 候选加入食物工具（凭据文件 + legacy 补丁组）

> 基于 N2a 分支 `claude/n2a-food-core`（PR #62）。本合同依赖 N2a 的 `provisionFoodDomain` 做测试，**#62 必须先合并**。上线总方案见设计稿“N2 上线方案”。本合同只做源码与合成测试，不碰生产。

## 背景
- 生产 MCP 是 `tools/i_remote_mcp/chatgpt_candidate.mjs` 从固定 legacy 基线（`tools/i_core/test_fixtures/release_schema6/mcp_reader/legacy/`）加补丁组生成的六文件候选。legacy 侧没有任何领域工具：`server.mjs` 里只有补丁带进来的空 `domainTools` 引用。N1 的 `FOOD_PATCHES` 只作用于 mainline，legacy 为空（`chatgpt_candidate.mjs` 第 1057 行起）。
- 候选只能有这六个文件，构建器还禁止候选里出现 `domain_tools|personal_data_domains|coreRemember|domain-config`（同文件 `constructCandidateSources` 末尾）。所以食物工具要以自包含代码内联进 legacy `server.mjs`，新文件和对 mainline 模块的 import 都不行。
- 生产部署用的是 `update-mcp-source`（维护 README“只替换 MCP 六文件源码（合同 C1）”）。它能换六个文件的源码，但改不了启动参数和环境变量。因此食物凭据不走配置，改为照 `pair-core` 的先例存进 MCP 的 `stateDir`：legacy `writeback.mjs` 第 249 行 `loadFrontendCredential` 读 `core-frontend.json`；`server.mjs` 第 451 行的 `pair-core` 从 stdin 读一次性秘密。这样窗口 2 只需要 `update-mcp-source`，加上一次凭据写入和一次会话重启，不需要 `mcp-config-switch`。
- N2a 的 `provision-food-domain.ps1` 从 stdout 输出一行 JSON，里面有 `writer_token`（以及 `phone_token`）。本合同新增的子命令从 stdin 接收这行 JSON。
- `core_instance_id` 取自 Core 的 `GET /v1/core/health` 返回的 `node_id`（无需认证），在写入凭据时绑定。

## 完成标准

**1. legacy 补丁组（`chatgpt_candidate.mjs` 的 `FOOD_PATCHES.legacy.server`）**
- [ ] 新增子命令 `set-food-credential`，参数为 `--state-dir`、`--core-url`，与 `pair-core` 写法相同：
  - 从 stdin 读一行 JSON（≤8KB），取出 `writer_token`，校验格式为 `^[A-Za-z0-9_-]{43}$`，忽略其他字段（包括 `phone_token`）。
  - 没有 `writer_token` 时报 `food_writer_token_missing`。错误提示里要说明用 `-Rotate writer` 重新发。
  - 请求 `GET {coreUrl}/v1/core/health` 拿到 `node_id`，失败时报 `food_core_unreachable`。
  - 用 `saveJsonPrivate` 写入 `stateDir/core-food.json`，内容为 `{format:'core-food-v1', principal_id:'food-mcp-writer', token, core_instance_id, time_zone:'Asia/Shanghai'}`。
  - stdout 和 stderr 只输出不含令牌的确认，例如 `已保存食物写入凭据`。令牌不进参数、环境变量或日志。
- [ ] `serve` 启动时，如果 `stateDir/core-food.json` 存在就严格校验：键集合精确、format 正确、token 和 core_instance_id 合法。校验失败要拒绝启动，并输出不含秘密的错误码 `invalid_food_credential`，不能静默忽略。文件不存在时行为与现在逐字节相同。
- [ ] 内联一份自包含的食物工具实现（领域 HTTP 客户端、`food_log`、`food_day`），行为与 mainline `domain_tools.mjs` 的 `createFoodTools` 和 `FOOD_TOOLS` 等价：
  - 工具名、中文 description、inputSchema 都相同。
  - 本地 04:00 日界、`local_date` 与 `totals` 由 MCP 计算、禁止字段时报 `food_field_not_allowed`、actor 固定 `agent_inferred`、`void` 只 patch `voided:true`、按 `op_id` 指纹去重、`food_day` 全量翻快照并隐藏 `voided`。
  - 返回形状一致。
  - 代码里不得出现上面列出的禁用词，不 import 新模块（只允许 `node:` 内置模块）。
- [ ] 工具暴露：凭据存在时，`claude_web`（默认 handlers）、`chatgpt_web`、`antigravity` 三套 handlers 和 tools 都加上 `food_log`（requiredScope `i.write`）和 `food_day`（`i.read`）；`gemini_web` 不加。凭据不存在时，四个前端的工具清单与现在逐字节一致。
- [ ] 新补丁组只改 legacy `server.mjs`。其余五个文件的候选输出不变，哈希仍是 oauth `7c82a07d`、diagnostics `2b461c32`、mcp `0ae610bf`、writeback `783e8fd0`、i_memory_read `cee18518`。仍是 `changed_files: 5`。正向和反向补丁都要能精确还原。
- [ ] mainline 的 `server.mjs`、`domain_tools.mjs` 不改（mainline 继续用 N1 的 `food` 配置块）。

**2. 测试**
- [ ] `chatgpt_candidate.test.mjs`：
  - N1 那条测试（约第 228–246 行）允许改两处，测试名可以同步改，其他既有断言一律不许动：
    - `i_remote_mcp/server.mjs` 的固定哈希更新为新值，其余五个不变。
    - 第 242 行“不得出现 `food_log|food_day|food_entries|createFoodTools`”的断言限定到其余五个文件，另给 server 追加正向断言：包含 `food_log`、`food_day`，并且不含 `createFoodTools` 这个 mainline 函数名（内联实现用别的名字）。
  - 追加测试：候选 `server.mjs` 不含禁用词；只 import `node:` 模块和原有的相对模块。
- [ ] 新文件 `tools/i_remote_mcp/food_candidate.test.mjs`，端到端执行：
  - 构建候选到临时 `build/` 子目录。
  - 用 `createICoreServer` 加 N2a 的 food hooks 起一个合成 Core，再用 `provisionFoodDomain` 拿到令牌。
  - 把 provision 风格的一行 JSON 经 stdin 交给候选的 `set-food-credential`，检查 `core-food.json` 内容和权限，检查 stdout/stderr 不含令牌。
  - 用候选的 `serve`（或其导出的 createServer）配合 OAuth 测试令牌，对三个前端分别验证工具清单。
  - 走 `food_log` 的 add、update、void 流程，再用 `food_day` 读回，确认写进了合成 Core，`local_date` 与 totals 和 mainline `createFoodTools` 的结果完全一致（同一组输入在两边逐字段对比）。
  - gemini 前端看不到食物工具。
  - 反例：缺 `writer_token`、令牌格式错、Core 不通、凭据文件多键或缺键（`serve` 必须拒绝启动）、凭据不存在（工具清单不变）。
- [ ] 既有测试除上面那一处，只能追加。

**3. 文档**
- [ ] `tools/i_remote_mcp/README.md` 的“食物记录”一节补一段“生产候选”：说明凭据文件，说明 `provision-food-domain.ps1 | node server.mjs set-food-credential` 的管道用法，提醒写入后要重启会话。
- [ ] `tools/i_core/maintenance/README.md` 的“食物领域开通”一节补一句，说明 stdout 的消费者就是 `set-food-credential`。

## 允许修改的路径
- 修改：`tools/i_remote_mcp/chatgpt_candidate.mjs`（改 `FOOD_PATCHES.legacy.server` 及其注释；并在 `constructCandidateSources` 的 legacy 链上接入 `FOOD_PATCHES.legacy`：正向放在 `ANTIGRAVITY_PATCHES.legacy` 之后，反向还原校验最先撤销它，写法与 mainline 链一致；其他逻辑不改）、`tools/i_remote_mcp/chatgpt_candidate.test.mjs`（见上）、`tools/i_remote_mcp/README.md`、`tools/i_core/maintenance/README.md`
- 新建：`tools/i_remote_mcp/food_candidate.test.mjs`
- `docs/development/handoffs/RELAY_20261025_n2b-food-mcp.md` 只由 Claude 改。
- 若发现必须改 legacy 基线 fixture、mainline 源码、`update-mcp-source.mjs` 或其他文件，停下并发 blocked 说明原因。

## 不做 / 边界
- 不碰生产：不登记任务，不运行 `update-mcp-source`，不在本机写真实凭据。
- 不改 N2a 的 Core 代码。不做 App（N2c）。手机令牌本合同不处理：N2c 会用 `-Rotate phone` 重新发。
- 不新增依赖，不放宽任何校验。
- 止损：同一测试名或错误码连续两个提交失败就发 blocked。最多 3 轮。

## 验证命令
- `node --test tools/i_remote_mcp/*.test.mjs tools/i_core/food_domains.test.mjs tools/i_core/release_schema6/maintenance_n2a_food.test.mjs`：列出基线上就失败的用例。
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/n2b-candidate-<轮次>`：用新目录，不要覆盖旧目录。贴出六个文件的哈希，输出不提交。
- CI 全绿，“MCP ChatGPT compatibility (Windows)”要实际执行。

## 之后（不在本合同）
- 窗口 1：用户同意后换 Core 包（含 N2a），运行 `provision-food-domain.ps1 | node <候选>/server.mjs set-food-credential --state-dir <MCP state>`，凭据随即落盘。
- 窗口 2：用 `update-mcp-source` 换成本合同的候选，然后重启会话，在 Claude、ChatGPT、Antigravity 三端各记一餐做验收。
- N2c：App 加“饮食同步”，用 `-Rotate phone` 取手机令牌。

## 需要真人的部分
- 合并由用户进行，收到 `relay:done` 前不要合并。#62 要先合并。
- 生产步骤每一步都需要用户单独同意。

## 审核记录

### 第 1 轮（10-25）：blocked，合同修订
- Codex 发现 `constructCandidateSources` 的 legacy 正向生成和反向校验（约第 1160–1162 行）没有接入 `FOOD_PATCHES.legacy`，只改补丁组无法改变候选，因此停下，未改动任何文件。判断正确。
- 裁决：扩大允许范围，允许在 legacy 链上接入 `FOOD_PATCHES.legacy`，正向在 Antigravity 之后，反向最先撤销。其他逻辑不改。
- 本机 `food_domains.test.mjs:218` 的 EPERM 失败与 N2a 第 1 轮相同，是沙箱的 realpath 限制。云端复跑通过，不影响结论。

### 第 2 轮（10-25）：blocked，合同修订
- Codex 发现 `chatgpt_candidate.test.mjs:242` 断言六个候选文件都不得出现食物工具名，这和本合同直接冲突。Codex 停下，未改动任何文件。判断正确。
- 裁决：该断言限定为其余五个文件，server 改为正向断言（见第 2 节）。前两轮都是合同缺口，不计入止损轮数，止损从第 3 轮起算。
