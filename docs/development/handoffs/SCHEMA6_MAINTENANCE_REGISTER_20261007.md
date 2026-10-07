# Schema 6 维护注册与固定准备入口

## 独立 Prepare 串行门控补强

独立 JS CLI 普通调用现在固定委托同目录 `prepare-production-login.ps1 -ConfigPath ... -ExpectedConfigSha256 ...`，外层固定 PowerShell bootstrap 在同一不可写/不可删句柄下复核配置及脚本 hash 并保持至执行返回；没有 SkipGuard、Internal 或可注入 callback 参数。新的 PS 入口先固定配置及完整维护闭包，要求冻结阶段的 `active-window.guard` 已存在并取得同一个独占锁，持有候选库存、批准/冻结/ACL/配置文件和活体数据的不可写/不可删读句柄；随后在固定 Node 的固定 literal API 调用前后各做一次实时冻结复核。Node API 仅生成批准 XML 并返回证据，**不自行发布准备成功回执**；PS 第二次复核通过后才以 CreateNew 发布。

`prepare_live_guard.ps1` 的 `Assert-PrepareLiveFrozen(Config,Frozen,Service,Leases)` 为 import-safe 共享函数，检查 taskPath 文件夹 + name、完整冻结 XML hash、SDDL、禁用/零触发/零重试/零实例、端口、四件存在性/hash/size/file_id 及外部文件。文件身份使用与冻结回执一致的 volume/index 十六进制编码。没有注册、启停或写入原任务的能力。遇失败只写 stdout；不得将错误回执写入错配的 journal 或其他原始路径。

`maintenance_outputs.mjs` 必须在输入验证时通过，且属于维护闭包 pin；三个输出必须直属 `maintenanceRoot/windows/windowId`，互异并与 raw/external/ACL inventory/批准输入无碰撞。WindowId 统一 8–80 位、字母数字首字符、其余字母数字/下划线/连字符。

Register 的 `--validate-registration` 子调用仍为只读，不重取父进程持有的 guard。维护闭包新增 `prepare-production-login.ps1`、`prepare_live_guard.ps1`、`maintenance_outputs.mjs`；旧配置缺任一项即拒绝。

验证：`maintenance_prepare.test.mjs` 2/2 通过。真实双进程合成检查覆盖默认 JS CLI 在既有独占 guard 下拒绝，释放后新的独立 PS CLI 能到达下一个明确锚校验门；保留 guard 旧字节、无回执、零任务创建。输出误配测试覆盖 journal、输出互撞、批准 XML 和窗外路径，journal 字节保持不变。此测试没有伪造成功生产准备，也没有使用任何生产配置。PowerShell 三文件解析与 Node 语法检查通过。

基线：`codex/schema6-online-shm-preflight-20261007` / `d4b71a92`。仅迁入参数化源码和合成验证；未运行生产准备、生产注册、旧任务操作、数据库访问或部署。

## 入口与外锚

- `tools/i_core/maintenance/register-approved-login.ps1 -ConfigurationPath <private.json> -ExpectedConfigurationSha256 <sha256> -RegisterOnly`。
- `tools/i_core/maintenance/prepare-production-login.mjs --config <private.json> --config-sha256 <sha256>`；`--validate-registration` 只复核既有固定准备回执。
- 私有配置 `format=schema6-maintenance-login-config-v1`：`maintenanceRoot`、`windowId`、`candidateSourceCommit`（40 位 Git commit）、`candidateManifestSha256`、`releaseDirectory`、`ownerSid`、`taskName`、`approvedSddl`、`nodeSha256`。
- 所有文件均由私有配置传入：`ownerApprovalPath/Sha256`、`frozenReceiptPath/Sha256`、`aclReceiptPath/Sha256`、`approvedXmlPath/Sha256`、`loginConfigurationPath/Sha256`、`outputXmlPath`、`preparedReceiptPath`、`registrationReceiptPath`。
- `maintenanceFiles:[{path,sha256}]` 至少覆盖注册入口、`register_task_primitives.ps1`、`maintenance_window.ps1`、准备入口、`acl_receipt.mjs` 和维护副本使用的 `release_schema6/package.mjs`。PowerShell 在加载帮助模块前验证并持有只读、不共享写/删除的句柄；核对最终路径及单链接身份。
- `frozenTaskNames`、`frozenPorts`、`rawPaths`（完整四件）、`externalFiles`（每个 external key 的原件及副本路径数组）明确限定实时复核范围。`aclExpected` 使用 ACL worker 的完整清单/时间/外锚接口，`freezeSha256` 必须等于 `frozenReceiptSha256`。
- owner approval 仍使用 `schema6-owner-gates-approved-v1` 格式，新增固定绑定 `windowId`、`candidateSourceCommit`、`candidateManifestSha256`、`owner_sid`、`approved_sddl`、`login_sha256`，保留 `task_name`、`xml_review_sha256`、`require_fixed_prepare_identical=true`。

## 强门控

准备入口验证维护闭包、固定 Node/release、私有 ACL、v2 冻结窗口及完整 ACL Apply 逐项回执，实际调用固定 release 的 `prepare_login_schema6.ps1 -PrepareOnly`。只有输出声明未注册/未启动且生成 XML 与批准 XML **逐字节一致**才写新准备回执。

注册入口必须持有维护 guard；只允许 `TASK_CREATE=2`。包含隐藏任务的枚举若已有同名即拒绝；竞争性创建由 COM 原子 CREATE 拒绝，不使用更新。注册前后复核旧任务禁用、零触发、零重试、零实例、端口及四件/外部文件精确指纹。注册后通过真实 COM 逐项比较 Actions、Principals、Triggers、Settings、路径、零实例及 SDDL。

COM 规范化方式：把已注册 XML 再送入 `NewTask.XmlText`，由同一个 Scheduler 物化缺省值，再比较带命名空间的完整四节和 COM 属性。Actions 顺序不排序；持续时间按 tick 归一，UserId 按 SID 归一。**不允许 UnifiedSchedulingEngine=false 变成 true**。SDDL 保留 owner/group/protected 标志，拒绝 deny/object/callback ACE，只合并同 SID/flags 的 allow 权限位；Scheduler 追加的 owner FR 在已有 FA 时不会扩大权限。生产不容忍 protected 标志丢失。

生产注册失败时，不删除任务：仅对本次 CREATE 已返回的对象尝试禁用并记录结果；未返回对象则明确记录 outcome unconfirmed，不按名字触碰竞争者。没有任务 Run/RunEx、原任务写入或数据库写入入口。

## 真实 COM 合成证据与修正

本机只创建 **1 个**随机 `HereIAm-Synthetic-` 任务：禁用、无触发、动作为系统 cmd 的 `/d /c exit 0`，从未运行。

第一次读回揭示两个真实 Scheduler 行为：省略的 `UseUnifiedSchedulingEngine` 从 NewTask 的 false 变为注册后的 true；SDDL `D:P` 保护位消失并追加同 owner 的冗余 FR ACE。严格比较正确拒绝；早期 finally 复用了失败断言，导致该合成任务暂留。

随后没有再次 CREATE。只读确认本次随机 Source nonce、路径、禁用、零触发和零实例；将合成期望明确设为 Unified=true、非 protected DACL 后，对同一对象完成四节/SDDL回读、同名拒绝和 action XML 差异拒绝，再删除并枚举确认缺席。最终回执：`created_once=true,recovery_readback=true,existing_rejected=true,xml_difference_rejected=true,deleted=true,disabled=true,triggers=0,instances=0`。这不是生产 XML 获得规范化豁免。

最终夹具显式固定 Unified=true 和非 protected DACL。清理只绑定本次 CREATE 对象、随机 Source、路径、owner、禁用/零实例/零触发和安全 action，不再复用待测的全量设置断言；从而设置回读失败也可安全清理自己的合成任务。

## 测试与剩余边界

- `node --test tools/i_core/release_schema6/maintenance_register.test.mjs`：5 passed，1 个真实 COM 测试按默认 opt-in 跳过。本机真实 COM 生命周期已单独闭合，不重复创建。
- 纯验证测试覆盖过期/错误窗口/错误候选、冻结清单缺项、观察期不足、prepared 各锚/字节差异，以及完整 ACL 输入通过、缺逐项 readback/旧候选拒绝。
- Windows CI 设置 `SCHEMA6_SYNTHETIC_TASK_TEST=1`，每个 ephemeral runner 实际执行一次。可设置 `SCHEMA6_SYNTHETIC_TASK_REPORT`，夹具使用 CreateNew 写不含 SID/真实路径的计数与判据回执。
- PowerShell 解析通过。最终 CI 结果由主控整合记录。本包未执行真实生产 PrepareOnly，未证明已有批准 XML在当前 Scheduler 上可注册通过；如果实际系统改变显式或默认 false，必须停下重新审阅。
