# MCP 配置链禁用登录登记候选（2026-10-09）

本工作包只新增维护入口，不改变 Core release、48 文件 inventory、manifest、Core configuration 路径/hash、运行时源码或旧换包入口。`deploymentReady=false`。源码和合成验证不构成生产登记、启用或恢复授权。

## 入口与输入

`tools/i_core/maintenance/register-mcp-config-switch-login.ps1 -ConfigurationPath <approved.json> -ExpectedConfigurationSha256 <sha256> -RegisterOnly`

输入 format 为 `schema6-mcp-config-switch-registration-v1`，精确字段由 `MCP_REGISTRATION_FIELDS` 导出：

- `approved=true`、`registerOnly=true`、`registerDisabled=true`、`registrationDerivation=fixed_prepare_settings_enabled_false_only`。
- `releaseDirectory`、`manifestSha256`、`ownerSid`、`taskName`：原 Core 与新任务名；任务名必须与 proposal.newTaskName 完全一致。
- `proposal:{path,sha256}`：`schema6-mcp-config-switch-v1`，由独立 bindings 模块完整核对 Core 不变、新旧配置链、六文件候选与 backup 覆盖。
- `humanApproval:{path,sha256}`：format=`schema6-mcp-config-switch-registration-human-approval-v1`、action=`create_new_disabled_login_task_only`、authorized=true；精确包含登记输入除 `format`/`humanApproval` 外的全部字段。包括 proposal、新旧 task、双 SDDL、父 SD hash、继承披露、所有源码 pin、输出位置及候选 manifest 的间接精确 pin。新增、缺少或变化字段拒绝。
- `closedMarker`、`currentHead`、`originalCloseInput`、`originalCloseReceipt`、`mcpStart`、`fixedPrepareReceipt`、`preparedXml`、`approvedXml`、`registrationXml`：均为 `{path,sha256}`。
- `oldTask:{name,xml:{path,sha256},sddl,sddlSha256}`：真实已禁用且零实例原任务的 XML/SD 快照；不得以测试任务代替现场证据。
- `registrationSddl`、`expectedRegisteredSddl`、`parentSddlSha256`、`taskSecurityPolicyVersion=windows-file-oi-v1`、`inheritedReadOnlyPrincipals`。
- `maintenanceFiles:[{path,sha256}]`：当前维护 checkout 的精确闭包，47 个固定包源码（48 inventory 去除 Node）和 8 个维护文件，集合由 `MCP_REGISTRATION_SOURCES` 导出。固定 Node 另由 release inventory 持柄 pin。
- `registrationReceiptPath`：新的独立私有输出路径，不在 Core state、custody 或 release 内；只允许 CreateNew。

不接收 `offline`、`switchEvent`、`targetFloor`、`switchPlan` 等换包字段。没有离线操作、custody package-switch 事件或虚构的 NativeLease。

## 必须真实取得的证据

原关闭 input/receipt 必须来自受审批的 `close-schema6-session.ps1`；检查原 login 配置、原 release、维护源码 hash、session/control 路径和原输出路径。实际 launcher 的 launch/ready 由 close input hash 锚定；child、guardian、supervisor、session-close、session-exit、closed marker 六终态由 close receipt 锚定。只接受当前 48 文件 Core 的在线 `mode=start`、确实打开 store 后的正常关闭；拒绝离线操作、超时、强制 Core、缺失/非零退出或尚有 handles/job。

原 MCP 的 `mcp-start.json` 单独经 human approval pin，`mcp-stop.json` 使用关闭回执已有的 mcpStop hash；匹配 PID、start ticks、Core token/ready PID、数据库与 owned-job scope。不存在即阻断，不补造终态。

`fixedPrepareReceipt` 原样保存固定 release 的 `prepare_login_schema6.ps1 -PrepareOnly` 输出：`prepared:true,registered:false,started:false,manifest_sha256,login_configuration_sha256`。原脚本没有 format，不人工另造成功字段。

`preparedXml`、`approvedXml`、proposal 的目标 task XML 必须逐字相同。`registrationXml` 必须经 Scheduler `NewTask(0)` 载入该 XML，唯一修改 `Settings.Enabled=false` 后得到的确切 COM XML；登记时重新派生并逐字对照。不能手改 trigger/action/principal 或替换入口。

## 实际登记门控

1. 在任何外部代码执行前，持柄校验配置、human approval、proposal、维护依赖闭包、原 Core 48 项和双方 MCP 精确六项。from 使用 `tools/i_remote_mcp/...`/`tools/i_memory/...`；to 使用去掉 `tools/` 的候选 runtime 布局。
2. 保留原 runtime lock 和 custody lock 的 OS 独占句柄。closed marker/current-head 持只读共享句柄；不写入、不推进 generation、不读取独立恢复密钥或 credential 文件。
3. 闭态目录仅做原始字节哈希：非 DB 文件持柄 pin；原有 `closedStateSnapshot` 重算完整 state tree/hash 与 marker 一致，再将 DB 以独占只读句柄重新哈希核对。不开 SQLite，不解析业务内容，不输出内容或文件清单。每个目录先拒绝 reparse 再递归；sidecar 拒绝。所有句柄保持到登记结束。
4. 目标 backup config 要求受保护 ACL，只有当前 owner 与 SYSTEM 两主体的 FullControl。其余持柄 pin 使用既有 owner/ACL/单硬链接/final-path 校验。
5. 原 task 必须真实存在、禁用且零实例，XML/SD 与审批完全一致。新任务必须不存在；复用原 Task Security policy 验证双 SDDL、父 SD hash 和继承的只读主体。
6. 只调用原 `New-ApprovedTask` 的 `TASK_CREATE=2`，创建时即禁用；回读完整 definition、SD、禁用/零实例状态，重查原任务与父 SD。没有 Run、Enable、修改旧任务或删除任务的路径。
7. 失败只尝试禁用本次确实创建并持有的任务对象，不修改碰巧同名的已有任务。回执只记录门控结果和审批 hash，不声称已启动。

## 验证及界限

专项 53/53 通过，零失败、零跳过（显式 `SCHEMA6_SYNTHETIC_TASK_TEST=1`）：成功证据组合、41 项关键篡改反例、5 个缺失终态、全部审批字段变化、闭包与脚本语法、真实前缀 profile、闭态 ledger/DB 原始字节漂移。

真实 COM 合成 fixture 用本次唯一 nonce 名创建两个禁用任务，验证 CREATE-only 同名拒绝、完整 SD/definition 回读及动作篡改拒绝；两任务随后清理，未启动 action。fixture 使用显式 Owner principal/action context，不能将这种局部验证当作完整生产 wrapper 或真实会话闭环通过。

另有完整 wrapper 合成 E2E：当前维护源码闭包复制到独立私有 nonce 根，48 文件合成 release 使用固定真实 Node，动作脚本均为 inert exit 0；真实调用 generator/finalize 与原样登记 wrapper，合成 raw DB/ledger 只做哈希，合成 marker/head/六终态/Prepare 回执由测试明确构造。成功创建的新任务禁用且零实例，回执双 SDDL/父 SD 校验通过，marker/head/DB 字节不变；缺 guardian、闭态 ledger 漂移、human approval 漂移和旧 nonce 实际启用均在新任务 CREATE 前拒绝，最后清理两 nonce。测试严格要求 SCHEMA6_SYNTHETIC_TASK_TEST=1；若任务清理未确认则保留合成根。此项证明完整登记门控在合成材料上贯通，不证明真实 Native 关闭或现场恢复。

当前没有执行完整生产登记，也没有将合成终态写成真实现场回执。原会话缺少终态、最新关闭证据不齐时，这个入口保持拒绝；必须先由独立获批恢复/正常关闭流程取得真实证据。无需也不允许为了准备候选而伪造 close receipt、触碰原库/密钥、推进 custody 或恢复现场。
