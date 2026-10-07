# Hub go-live P1：i MCP 源码审计与验证（2026-10-07）

## 范围与结论

- 审计基线：`0a24cac2b7db812f34fb845325e27b77d16139dd`，分支 `codex/hub-golive-src-20261007`，远端 `Ritou-Lynx/here-i-am`。
- 只审计 `tools/i_remote_mcp/**` 以及 W3/领域契约；未读取真实个人数据，未使用真实令牌，未请求生产 Core，未修改 schema、maintenance、生命周期或启动器库存。
- P1 的 MCP adapter 与合成契约实现已存在于该基线，本轮没有制造重复源码改动。**这不是可上线闭环**：更深 host 审计确认可信授权签发和 Core 生产装配仍缺失，详见“上线阻断”。

## 上线阻断（更深 host 审计修正）

1. **MCP 没有可信 `authorization_ref` issuer。** `domain_tools.mjs` 只要求并转发调用参数中的引用；`i_remote_mcp` 的非测试源码没有签发、持久化或核验授权记录的实现。当前合成测试由夹具用 `synthetic:<op_id>` 和注入的 verifier 代替真实入口。模型能够填写一个字符串不构成用户授权，因此 `capture_add`、Core `i_remember` 的 add/update/delete 和任何 `user_direct/user_via_agent` 操作尚不能作为生产写入入口。
2. **Core 正常 CLI 未装配业务 host policy。** `createICoreServer` 支持注入 `domainVerifyAuthorization`、`domainDedupHooks`、`domainHooks`、`domainVerifyLegacyAdoption`，但 `i_core_server.mjs` 的正常 `main()` 没有传入这些参数，也没有调用 `registerPersonalDataDomains` 或配置 scoped principals。schema6 只会创建通用 `DomainStore`：未注册域返回不可用；已注册且声明 `requiredHooksVersion` 的域在缺 hooks 时 fail-closed 为 `schema_not_ready`；user-level actor 在缺 verifier 时 fail-closed 为 `actor_not_authorized`。
3. **手机领域接线在基线缺失，本候选已另行补充。** 基线 `lib/config/dependencies.dart::_createHubRuntime` 未注入授权 callback，也没有执行领域 `hub.attach`。App 工作包已补充可选、独立领域凭据、完整 intent 签名和逐请求撤销检查，见 P1_APP 与 PHONE_AUTH 交接。它不负责生产授予或显式 route/adoption 迁移；没有有效授予和迁移证据时仍保持本地或禁用状态。
4. **凭据和模式仍只有外置注入点。** MCP `--domain-config` 能消费 owner 配置的 token/scopes，但不签发 principal，也不证明配置声明与真实 grant 一致；Core 才是最终裁决。仓库正常 host 路径尚没有已审核的个人领域注册、principal 签发、mode 切换和授权记录生命周期装配。

### 建议的最小安全闭环

- Core 增加一个 owner 装配模块，由正常 host 显式加载：安装 `createPersonalDataHooks(...)`、`personalDedupHooks()` 和可信 `domainVerifyAuthorization`；领域注册、principal 配置与 mode 切换保持本机管理动作，不能暴露成普通远程路由。启动时应检查注册域、hook version、principal policy 与配置绑定，不满足就继续 fail-closed。
- 授权记录由真实交互入口签发并持久化，至少精确绑定 `principal_id/device/generation`、`core_instance_id`、`domain`、`op_id`、`id`、`kind`、`actor`、目标字段/规范化请求摘要、签发/到期时间和 surface。引用只保存不可猜测值或其哈希；同一记录只允许相同 `op_id` 的幂等重试，不能授权另一份请求。
- Web MCP 当前拿不到独立、可信的人类点击证据。最小可诚实上线方式是两步授权：工具先返回短期 challenge/本机批准链接，用户在受信 UI 确认后由 issuer 写授权记录，随后以绑定的 opaque ref 原样重试。OAuth 登录、聊天文本、sync_id 或模型声称“用户要求记录”都不能单独签发该引用。
- MCP 在 issuer 未配置时不应把需要 user-level actor 的工具描述为可用写入口。可选择启动时拒绝 captures:create/patch/delete 配置，或保留工具但稳定返回 `authorization_not_configured`；不能让模型自造 ref 后依赖一次 403 才暴露配置缺口。
- 手机侧另由生产连接装配读取安全存储中的领域 bearer/binding，逐域 `hub.attach`，并把 quick-capture send / planning status button 接到受信 issuer；没有这些接线时继续保持现有本地或禁用状态。

## 审计矩阵

| 要求 | 源码证据 | 本轮验证 | 结论 |
|---|---|---|---|
| `i_remember` 写 Core `captures` | `domain_tools.mjs` 的 `createCoreRemember` 将 add/update/delete 映射为 create/patch/permanent delete，固定 `actor=user_via_agent` 与 `source=claude_web`；`server.mjs` 的 Core 模式以该 adapter 替代旧 notes handler | `i_remember Core CRUD clears online bodies`、`Core mode never falls back to legacy notes`、OAuth Web Core 测试通过 | adapter 已具备；可信授权 issuer 与生产 host 装配未具备 |
| `capture_add/list/ack` 按 scope 暴露 | `createDomainTools` 先按配置 scope 过滤目录，执行时再次检查 action scope；Core HTTP 使用同一真实 bearer 再做最终授权 | owner/scope/strict-field 拒绝、planner 处理者绑定、旧 OAuth 只读 token 拒绝写入均通过 | 已具备；配置是目录上限，真实 grant 仍由 Core 决定 |
| 规划工具按 scope 暴露 | `plan_list/upsert/set_status`、`week_get/set`、`day_get/set` 都由 action scope 选择；Web surface 只允许 `capture_add/week_get/day_get` | 本机 MCP 无聊天工具、scope ceiling、Web 禁止 planner 写工具、day title 独立凭据测试通过 | 已具备 |
| 本机 Codex 入口无聊天权限 | `planner_server.mjs` 仅装配领域 handlers，绑定 `127.0.0.1`，拒绝浏览器 Origin/Fetch，限制 scope ceiling | 真实本机 HTTP MCP 测试通过；`i_context` 与 `capture_add`（无相应 scope）均不能越权调用 | 已具备 |
| 网页 captures 与计划读取凭据隔离 | `createWebDomainOptions` 限 captures scopes；`plan_reads` 必须使用不同 token，且只能是三类 plan `:read` | Web 组合凭据测试、实际 MCP 的 `day_get` 标题测试通过 | 已具备 |
| `i_chat_turn/i_context/i_recall` 兼容 | 既有 handlers 未改变；Core notes 只替换记事 adapter，聊天 writeback 继续走既有 B3 路径 | B1×B2 集成、协议、OAuth、B3 三轮聊天与补交/去重回归全部通过 | 已具备 |
| 失败保持可重试且不虚报成功 | Core client 将传输不确定返回 `transport_unknown`，要求相同 `op_id` 原样重试；冲突保留结构化结果 | 丢失 Core 响应后单一 durable receipt、结构化 conflict 测试通过 | 已具备 |

## 本轮验证

命令在仓库根目录执行，Node 为 `D:\Nodejs\node.exe` v24.14.1；测试文件由 `rg --files tools/i_remote_mcp` 明确发现后逐个传给 Node，未把目录当测试模块。

```powershell
$tests = @(rg --files tools/i_remote_mcp | Where-Object { $_ -match '\.test\.mjs$' })
& 'D:\Nodejs\node.exe' --test @tests
```

结果：`100` tests，`12` suites，`100` pass，`0` fail，耗时约 `4.0 s`。其中领域专项使用随机本机端口上的合成 schema6 Core HTTP；其余覆盖 OAuth、MCP 会话、B1/B2 只读、B3 聊天写回、旧账本升级、诊断脱敏与设备分享边界。

## 限制与主窗口事项

- 这是组件源码与合成 HTTP 验证，不等于可上线闭环。生产 scoped principal、网页授权 issuer、业务 hooks/注册、真实 owner 配置及迁移均未闭环；手机候选接线的最新结果另见 P1_APP。
- 本轮未启用 `--domain-config`、未签发或轮换凭据、未停用 47862。真实切换仍按 README 的部署前置执行，并确保只启用一个记事消费者。
- 新的本机 `planner_server.mjs` 入口可能影响启动器/库存；按任务边界，本轮不改启动器，由主窗口决定是否纳入现场清单。
- `tools/i_core/import_personal_notes*` 由主窗口拥有，本轮只复核 MCP 侧合成 adoption 覆盖，没有修改迁移脚本。
