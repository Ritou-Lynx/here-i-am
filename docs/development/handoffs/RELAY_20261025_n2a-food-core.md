<!-- relay:contract v1 -->
# N2a 合同：Core 运行包启用食物领域（hooks + 受控开通通道，源码与合成测试）

> 已核对 v3-lab `481cef2`（N1 已合并）。上线总方案见设计稿“N2 上线方案”：N2a Core、N2b MCP、N2c App，两次生产窗口。本合同只做 N2a 的源码，不碰生产。

## 背景
- N1 已有 `tools/i_core/food_domains.mjs`（schema、校验、`createFoodDomainHooks`、`registerFoodDomains`），但生产从未启用任何领域：
  - 生产 Core 由 `release_schema6/lifecycle/runtime_child.mjs` 第 217–218 行创建，`createICoreServer({databasePath, ...settings.options})`，`settings.options` 来自 `lifecycle/configuration.mjs` 第 60–62 行，没有 `domainHooks`。领域登记了 `requiredHooksVersion` 却没装 hooks 时，`domain_store.mjs` 第 70 行返回 `schema_not_ready`。
  - 没有生产代码调用 `registerDomain` 或 `configurePrincipal`（`domain_store.mjs` 第 52、136 行）。`domain_http.mjs` 第 140 行拒绝设备令牌，所以 MCP 和手机都需要各自的领域 principal 令牌。
- 运行包清单不能加文件：`release_schema6/package.mjs` 的 `INVENTORY` 固定 48 项，`package_switch.mjs` 只接受目标清单等于 `INVENTORY` 或历史清单，`maintenance_r1_pairing.test.mjs` 第 84–90 行钉死了清单与这两个文件的哈希。因此食物代码要并入已在清单里的 `personal_data_domains.mjs`，`food_domains.mjs` 改成转出口，N1 的 import 路径不变。
- 开通（登记领域、发令牌）必须在 Core 运行中经现有存储完成：关闭后改库会破坏 `verifyCanonicalRestart` 的托管链。先例是配对通道：`runtime_child.mjs` 第 16 行 `createPairingRequestPoller`（控制目录里的请求，用会话 `stop.key` 做 HMAC，十分钟有效，失败只写去敏回执，绝不触发关停），发起方是 `maintenance/open-pairing-window.ps1`，用法见 `maintenance/README.md` 第 124–128 行。本合同照这个模式做一个“食物开通”通道。

## 设计要点
- 固定 principal（标识不是机密，可写进源码）：
  - `food-mcp-writer`：`device_id:'i-remote-mcp'`，`installation_id:'food-mcp'`，`scopes:['food_entries:read','food_entries:create','food_entries:patch']`，`actors:['agent_inferred']`，`trusted_interactive:false`，无过期。
  - `phone-food-reader`：`device_id:'phone-main'`，`installation_id:'food-phone'`，`scopes:['food_entries:read']`，`actors:[]`，`trusted_interactive:false`，无过期。
- hooks 每次启动都装（`writerPrincipalIds:['food-mcp-writer']`）。领域没登记时 hooks 不起作用，现有行为不变。
- 领域以 `authoritative` 模式登记，`requiredHooksVersion:'food-v1'`。
- 回滚到旧包时，食物请求返回 `schema_not_ready`，其他功能不受影响。这一点要有测试证明。

## 完成标准

**1. 食物代码并入 `personal_data_domains.mjs`**
- [ ] 把 `food_domains.mjs` 的全部导出原样移到 `personal_data_domains.mjs` 末尾的“食物”一节，行为逐字节等价。`food_domains.mjs` 只剩 `export {…} from './personal_data_domains.mjs'`，导出名不变。
- [ ] 新增导出：
  - `FOOD_WRITER_PRINCIPAL_ID`、`FOOD_PHONE_PRINCIPAL_ID`、`foodPrincipalConfigs()`，配置按上节。
  - `provisionFoodDomain(domains, {rotate = []} = {})`，其中 `rotate` 是 `['writer','phone']` 的子集，否则抛 `invalid_food_provision_request`。行为：
    - 领域不存在：以 `authoritative` 登记。已存在且 mode、`requiredHooksVersion`、schema 与预期完全一致：跳过。其他情况抛 `food_domain_conflict`，不做任何修改。
    - principal 不存在或在 `rotate` 里：调用 `configurePrincipal` 发新令牌，旧令牌随之失效。已存在且不在 `rotate` 里：不动，不返回令牌。
    - 返回 `{registered:boolean, issued:{writer?:string, phone?:string}}`，全部在一个事务里完成，或保证中途失败可安全重跑。
- [ ] 不改 `domain_store.mjs`、`domain_http.mjs`、`i_core_server.mjs`、`i_core_store.mjs`、personal 四个领域的任何既有代码。

**2. 运行时（`release_schema6/lifecycle/runtime_child.mjs`）**
- [ ] 第 218、237 行两处 `createICoreServer` 都传 `domainHooks: createFoodDomainHooks({writerPrincipalIds:[FOOD_WRITER_PRINCIPAL_ID]})`。函数从 `config.release` 下的 `personal_data_domains.mjs` 动态导入，与第 217 行导入 `i_core_server.mjs` 的写法一致。
- [ ] 新增导出 `createFoodProvisionPoller({control, token, manifestSha256, core, writeReceipt, now})`，在现有 25ms 轮询里调用，写法与配对通道相同，与配对和关停互不影响：
  - 输入：控制目录中的 `food.request`，≤1024 字节，普通文件。内容为 JSON，键集合精确：`{request_id(UUID), rotate(数组), expires_at_ms, hmac}`。HMAC 用 `stop.key` 计算，消息是 `token|manifest|food|request_id|rotate按字母序逗号连接|expires_at_ms`，有效期不超过 10 分钟。
  - 处理前先删请求文件。同一 `request_id` 不得重放。过期、HMAC 错误、JSON 坏、键不对、超长、非普通文件，都只写回执 `food-receipt-<n>.json`，`status` 为 `rejected_*`，不发令牌，Core 继续运行。
  - 合法请求：调用 `provisionFoodDomain(core.store.domains, {rotate})`。
    - 回执写 `{status:'provisioned', request_id, registered, issued:['writer',…], hooks_version:'food-v1', at_ms}`，不含令牌。
    - 若发了令牌，另写 `food-tokens-<request_id>.json`，内容为 `{format:'food-tokens-v1', request_id, writer_token?, phone_token?}`。
    - `food_domain_conflict` 与其他异常只写去敏回执。
  - 回执写失败、任何异常都不得进入关停处理（同 `pair` 测试第 133 行）。
- [ ] 不改 `ready.json`、`child.json`、`launch.json` 的形状，不改配置格式（`configuration.mjs`）、`package.mjs`、`package_switch.mjs`、`INVENTORY`。

**3. 发起脚本（新 `tools/i_core/maintenance/provision-food-domain.ps1`）**
- [ ] 参数为 `-TaskName <name> [-Rotate writer,phone]`，只限 Windows PowerShell 5.1。定位唯一的活动会话与控制目录，照抄 `open-pairing-window.ps1` 的检查（单一活动会话、manifest 一致、进程存活、受保护路径）。请求用独占预留加原子改名发布。最多等 60 秒拿到对应 `request_id` 的回执。
- [ ] 读取令牌文件，然后立即删除。stdout 只输出一行 JSON：
  - 成功：`{"status":"provisioned","registered":…,"issued":[…],"writer_token":…,"phone_token":…}`，只含本次发出的令牌。
  - 失败：`{"status":"rejected_*"}` 加非零退出码。
  - 令牌不得写进参数、环境、日志或其他文件。
- [ ] 已有未处理的 `food.request` 时拒绝，错误码 `food_unhandled_request_exists`。
- [ ] 不登记、不启动、不停止任何计划任务。

**4. 测试（新 `tools/i_core/release_schema6/maintenance_n2a_food.test.mjs`，追加 `tools/i_core/personal_data_domains.test.mjs`、`food_domains.test.mjs`）**
- [ ] `provisionFoodDomain` 用真实 `DomainStore`：
  - 首次运行：登记领域并发出两张令牌。第二次运行：`registered:false`，不发令牌。
  - `rotate:['writer']`：旧写入令牌被 `authenticate` 拒绝，新令牌可用，手机令牌不变。
  - 已有同名领域但 mode 不同或 schema 不同：抛 `food_domain_conflict`，且数据库无变化。
  - 非法 `rotate` 被拒绝。
- [ ] 端到端（`createICoreServer` 加 food hooks，走 HTTP `/v1/core/domains/food_entries`）：
  - 写入令牌以 `agent_inferred` 能 create、patch、置 `voided`。
  - 手机令牌能读 snapshot 和 changes，create 返回 `scope_forbidden`。
  - 设备令牌返回 `scope_forbidden`。
- [ ] 回滚兼容：先在装了 hooks 的情况下登记并写入一条，再以不带 hooks 的方式重开同一数据库（相当于旧包）。启动和健康检查正常，食物请求返回 `schema_not_ready`。现有备份包或只读检查路径能处理含食物行的数据库（用现有测试夹具，至少一条）。
- [ ] 轮询器单元测试，照抄 `maintenance_r1_pairing.test.mjs` 的场景：合法请求、HMAC 错误、过期、重放、超长、坏 JSON、多余键、非法 `rotate`、冲突、回执写失败。每种情况都不触发关停，令牌只出现在令牌文件里，不出现在回执里。另加一个 Linux 真 Core 用例。
- [ ] Windows CI 合成用例：`provision-food-domain.ps1` 对合成会话执行。stdout 恰好一行 JSON，令牌文件已删除，再次执行不发令牌，`-Rotate phone` 只换手机令牌，有未处理请求时拒绝。没有 Windows 环境时以 CI 为准。
- [ ] 断言 `INVENTORY` 仍为 48 项，`package.mjs` 和 `package_switch.mjs` 的哈希不变（复用 R1 测试中的常量，不改其断言）。

**5. 文档**
- [ ] `maintenance/README.md` 新增“食物领域开通”一节：说明用途；说明 stdout 只交给下一步经 stdin 消费（N2b 会定义 MCP 配置写入）；说明令牌不进 transcript；说明 `-Rotate` 的用法；说明回滚时的影响。

## 允许修改的路径
- 修改：`tools/i_core/personal_data_domains.mjs`（只追加食物一节）、`tools/i_core/food_domains.mjs`（改为转出口）、`tools/i_core/release_schema6/lifecycle/runtime_child.mjs`、`tools/i_core/maintenance/README.md`
- 追加：`tools/i_core/personal_data_domains.test.mjs`、`tools/i_core/food_domains.test.mjs`
- 新建：`tools/i_core/maintenance/provision-food-domain.ps1`、`tools/i_core/release_schema6/maintenance_n2a_food.test.mjs`，以及 `tools/i_core/test_fixtures/release_schema6/` 下本合同专用的新夹具。
- 既有测试只能追加，不能改已有断言。若确需改，例如某处钉了 `runtime_child.mjs` 或 `personal_data_domains.mjs` 的哈希，就停下，发 blocked 说明具体位置。
- `docs/development/handoffs/RELAY_20261025_n2a-food-core.md` 只由 Claude 改。

## 不做 / 边界
- 不碰生产：不生成部署候选，不换包，不登记任务，不在本机运行开通脚本，不碰真实数据库或令牌。
- 不改 MCP（N2b）和 App（N2c）。不顺带改 shortcut-mail checkpoint 等其他换包遗留。
- 不新增依赖。不放宽任何现有校验。
- 止损：同一测试名或错误码连续两个提交失败，就发 blocked。最多 3 轮。

## 验证命令
- `node --test tools/i_core/*.test.mjs tools/i_core/release_schema6/*.test.mjs tools/i_remote_mcp/*.test.mjs`。基线上已失败的 PowerShell/SMTP/计时类用例请列出名字，不必修。
- `node --test tools/i_core/food_domains.test.mjs tools/i_core/personal_data_domains.test.mjs tools/i_core/release_schema6/maintenance_n2a_food.test.mjs tools/i_core/release_schema6/maintenance_r1_pairing.test.mjs tools/i_remote_mcp/food_tools.test.mjs`：全部通过。
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/n2a-candidate`：六个文件的哈希仍与 `48bd91e` 候选相同（本合同不应影响 MCP）。
- CI 全绿，Windows 用例要实际执行，不能是跳过。

## 之后（不在本合同）
- N2b：六文件候选的 legacy 侧加入食物工具，MCP 启动配置读取写入令牌（经 `mcp-config-switch`）。
- N2c：App 加“饮食同步”设置，接收手机令牌并打开 core 路由。
- 窗口 1：换 Core 包（带本合同），然后运行开通脚本，令牌经 stdin 交给 N2b 的配置步骤。窗口 2：切换 MCP 配置，三端验收，然后接入手机。每一步都要用户单独同意。

## 需要真人的部分
- 合并由用户进行，收到 `relay:done` 前不要合并。
- 生产换包和开通由用户另行同意。

## 审核记录

### 第 1 轮（10-25）：Codex 报 blocked，Claude 云端复核后小修
- Codex 提交 `9b59af4`，只改了允许的路径。Codex 报告的两个失败都是本机沙箱造成的：只读检查在 realpath 上报 EPERM，全量测试运行期间源码被改动。
- 云端复跑结果：
  - 专项测试 81 项，73 过、0 败、8 跳。
  - 全量 `tools/i_core`、`release_schema6`、`i_remote_mcp` 共 1046 项，943 过、11 败、92 跳。这 11 项与 `v3-lab` 基线失败的用例逐名一致，没有新增失败。
  - INVENTORY 48 项和两份固定哈希不变。MCP 候选六文件哈希不变。
- 代码审核：
  - 食物代码已原样迁移，并改成转出口。
  - `provisionFoodDomain` 在单事务内完成，冲突时不做修改。
  - 轮询器先删请求再解析，校验 HMAC、有效期和重放；回执不含令牌；任何异常都不进入关停。
  - 两处 `createICoreServer` 都已装上 hooks。
- Windows CI 只有 1 项失败：Windows 合成脚本用例中 `-Rotate phone` 实际发出 `[]`。原因是夹具 dot-source 维护脚本时，维护脚本的 param 块把 `$Rotate` 重置成了空。Claude 直接修了三处：
  - 夹具在 dot-source 之前保存参数。
  - 维护脚本按逗号拆分 `-Rotate`，因为 `-File` 调用时 `writer,phone` 会作为一个字符串传入；测试补了一项。
  - README 去掉了末尾空行。
