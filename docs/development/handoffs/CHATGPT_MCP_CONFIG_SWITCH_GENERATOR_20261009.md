# ChatGPT MCP-only 配置候选生成器（2026-10-09）

范围：独立维护工作树；仅新增候选生成器、绑定校验器、专项测试。不修改固定 Core 48 项、manifest、生命周期、旧换包入口；不注册/启动/恢复，不打开数据库或独立凭据。本交接不构成生产批准。

## 接口

`validateMcpConfigSwitch(proposal)` 位于 `tools/i_core/maintenance/mcp-config-switch-bindings.mjs`。proposal 的精确字段：

- `format: schema6-mcp-config-switch-v1`
- `core: {releaseDirectory, manifestSha256, configurationPath, configurationSha256}`
- `fromArtifacts`、`toArtifacts`：各且仅四个 `{role,path,sha256}`，role 为 login/mcp/backup/task。
- `candidate: {manifestPath,manifestSha256,runtimeDirectory}`
- `oldTaskName`、`newTaskName`，大小写不敏感地不同。

成功返回 `validated:true`、无业务正文的 owner/path/hash 绑定；始终 `approved:false,deploymentReady:false,registered:false,started:false`。失败仅固定 `mcp_switch_*` 错误，不回显输入值。

所有 Core 引用共用唯一 core 对象，login 两端精确绑定其路径和 hash。现有48项 release verifier 检查完整字节。MCP Node/path/hash、数据路径、端口、参数、旧环境保持；只允许独立 runtime、entrypoint 去 tools/ 前缀、精确六项 source_files、新增 ChatGPT flag=1。候选源集合恰六项，三变三不变，旧包每项匹配 base SHA，新包匹配 result SHA/bytes，拒绝额外文件和链接。

## 生成与固定 Prepare

输入 JSON 精确字段为 `format: schema6-mcp-config-switch-generation-v1`、上述 core/fromArtifacts/candidate/oldTaskName/newTaskName，及 `outputDirectory`。输出目录必须全新，并独立于原配置、包、候选源、状态、密钥、备份等根。

```text
node tools/i_core/maintenance/generate-mcp-config-switch.mjs --input INPUT --input-sha256 SHA256
```

输出三份配置、纯模板 `login-task.review.xml`、`static-inputs.json`、safe diff。新 core.json 不创建；`login-task.prepared.xml` 不生成，保持给原固定包 PrepareOnly 的新路径。返回 loginPath/loginSha256/outputXmlPath/staticInputsPath/staticInputsSha256。

随后仅在授权的准备范围内，用原固定包 `prepare_login_schema6.ps1 -PrepareOnly` 和上述 login/path/hash 输出 actual prepared XML；不运行服务。读取其真实回执，不能把纯模板输出标为 fixed Prepare。

```text
node tools/i_core/maintenance/generate-mcp-config-switch.mjs --finalize STATIC_INPUTS --input-sha256 SHA256
```

finalize 对实际 prepared XML 做绑定检查，全新写 `proposal.json`。返回 proposalPath/proposalSha256，并保持 `fixedPrepareReceiptRequired:true`。该阶段不认证 Prepare 回执；由专用 RegisterOnly evidence validator 绑定真实回执、本人批准 XML、双 SDDL 和父 SD。

## 备份约束

旧 backup 除精确附件重绑外保持全字段。活跃 Core release inventory 保持48项加manifest。精确重绑旧MCP六源、login/mcp/backup/task；另外在 `preserved/mcp-config-switch-source/` 新增明确命名的十项旧原件，拒绝 namespace 碰撞、缺附件、未知增删或策略变化。MCP与源码使用新实际SHA；login/backup/task 的循环模板hash保持旧合法值，由在线捕获替换，不能声称为最终备份字节摘要。所有非配置源只验证声明，不打开数据库/密钥文件。

## 生产与回退门槛

同Core配置切换不制造 custody package-switch event。生产需独立新 RegisterOnly wrapper，持柄固定维护闭包和审批，确认真实当前 clean-close、两锁与无实例，原任务安全态、CREATE-only禁用注册、COM精确回读以及父SD前后重核。缺少clean终态独立阻塞生产；候选生成不伪造 marker/head/close。

回退保留当前OAuth状态、B3账本、业务数据；不能恢复旧state快照。关闭flag或恢复旧MCP不等于吊销已有token，回退计划须如实披露。任何额外撤权单独审批。

## 验证

专项：`node --test tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs`，仅合成源/配置/临时根。正向过程用缺失的数据库与独立key路径证明不访问它们；覆盖Core/Node/环境/数据路径/端口/库存/链接/备份缩水/输出重叠等拒绝场景。本工作包完整专项 22/22 通过、零跳过（69.059 秒）；随后将候选 source_commit 固定为 f90058f21049f514f8ab2af407227aee02e2f259，新增来源替换负例与正向复验 2/2 通过（7.094 秒）。最终测试文件共 23 项（含父项），主窗可统一重跑；不继承旧候选/CI/真人结果。

依赖闭包：bindings 直接 import 固定 `package.mjs`、`lifecycle/configuration.mjs`、`backup_bundle.mjs` 及 Node 内置模块；不 import 旧 package-switch bindings。这三项的递归静态依赖位于现有48项库存。generator 另 import 新 bindings；用于正式执行的维护快照须完整 pin 后再加载。


## 新备份配置文件 ACL 修订

生成器创建新 backup JSON 后，以固定 Windows PowerShell 5.1 脚本对该新文件持柄设置 FileSecurity：当前 owner 与 SYSTEM 两条显式 FullControl，关闭继承并去除继承 ACE；立即回读 owner/protected/精确ACE集合及类型/继承标志。路径仅通过 JSON stdin 传递，不插入 PowerShell 源码。子进程使用清理后的系统环境及固定系统模块目录。非 Windows 显式 0600 并检查 mode。

finalize 再次只读检查同一权限契约，任何漂移拒绝发布 proposal；这不替代生产 RegisterOnly 的再次检查。没有修改旧文件或旧 runtime 门槛。

实跑窄测 3/3 通过、零跳过（14.206 秒）：完整生成/finalize正向、真实 Windows 文件 owner+SYSTEM/protected/显式两ACE断言、添加 Administrators ACE 后 hash 不变仍拒绝 finalization，且 proposal.json 不产生。合成漂移仅修改该用例自行创建的新文件，已清理。
