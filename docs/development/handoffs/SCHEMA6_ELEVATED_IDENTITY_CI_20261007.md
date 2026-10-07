# schema6 提升 writer → 普通 owner 合成 CI

## 范围与当前证据

本工作包仅修改测试、合成夹具和 `.github/workflows/ci.yml`。未改固定 runtime 47 项，未访问现役库、凭据、服务、手机或现役任务，未发起本机 UAC。生产 `owned_artifacts.ps1` 及各 writer 修复由独立工作包负责。

新增必跑 job：`schema6-identity-pipeline`，显示名 **Schema6 elevated writer to ordinary owner pipeline**；沿原 workflow 的 push、pull_request、workflow_dispatch 触发规则执行，无 opt-in 环境变量和失败忽略。独立 runner 使用既有 hosted module scope，**不调用**旧 `run_windows_tests.ps1`，不继承其修改 TokenOwner 的 workaround。旧 suite 的 workaround 保留。

截至本交接，Hosted 新 job **尚未运行**。本机当前普通 token 无法代替管理员 writer → 普通 consumer 证据，C# 编译成功也不代表实际跨 token 启动通过。

## 串联与身份断言

1. Writer 实际查询当前 Windows token，要求 `TokenElevation=true`、`IsInRole(Administrator)=true`、默认 `TokenOwner=Administrators`、High integrity。任一不符失败，不能跳过或用环境标签代替。
2. 用真实 `prepareRelease` 从当前 Git commit 装配完整 47 文件候选；维护源码单独复制并逐项 pin。复制后断言维护库存一致且包括 ACL、owner helper、Prepare、注册 primitives。Git 从已安装 `git --exec-path` 定位 core executable，再由原装配器执行 canonical/单链接校验；本机硬链接 launcher 被正确拒绝。
3. 新合成根内建立精确 144 项，含 16 项 Administrators owner。创建随机禁用、零触发的合成 frozen task，实际观察至少 65 秒并复核其 COM 状态。冻结证据仅描述该合成任务、临时空 state 和临时端口。
4. 保持真实提升 token 和 BA 默认 owner，调用受审 `Invoke-AclMaintenance -Mode Apply -ConfirmFrozen`，传入真实 helper 外锚。全部144项必须通过；后续直接读取其真实 `acl-apply.json`，不手造成功 Apply 回执，不在 writer 后修补其 owner。
5. `CreateRestrictedToken(DISABLE_MAX_PRIVILEGE | LUA_TOKEN)` 明确禁用 BA SID，给子 token 设置 Medium integrity 和同 SID 的 TokenOwner；`CreateProcessAsUserW` 启动普通 consumer。父端核 token；子端再次查询并断言同 SID、非提升、非管理员、Medium integrity。生产普通身份 guard 还会核其 TokenOwner。
6. 普通 consumer 验证实际 ACL 回执，执行真正的 maintenance Prepare 入口，后者执行固定包的 `prepare_login_schema6.ps1`。已审纯模板源片段由既有独立 hash 锚固定；最终 Prepare XML 必须与先前 approved XML 字节相等。随后在同普通 token 运行 `--validate-registration`，实际核生产注册使用的 source/config/freeze/ACL/approval/output/parent-policy 输入和 prepared proof；保留各步 false registered/started 断言。
7. 从固定 Prepare 输出显式派生安全合成 XML，仅删触发、置 Enabled=false、将动作改为 `cmd /d /c exit 0`、加随机 Source nonce。恢复这些明确差异后，Actions、Principals、Triggers、Settings 四段必须与固定 Prepare 一致。实际注册通过生产 `New-ApprovedTask`，再以 `Assert-RegisteredTask` 真实 COM 核定义、安全描述符与零实例。
8. SDDL expected 在 CREATE 前由独立 FILE 继承 oracle 从 registration+parent 计算，与生产 policy 推导交叉核对；绝不从注册结果回填 expected。删除只接受本次 confirmed-created、随机 name/nonce/SID/path/disabled/zero-trigger/zero-instance/inert-action 绑定对象，随后真实验证消失。两只合成任务均走此绑定清理。

安全派生任务注册 **不等于完整现场 RegisterOnly**。回执显式 `productionRegisterOuterExecuted=false`；没有调用 `register-approved-login.ps1` 的最外层 RegisterOnly 配置租约/guard/登记回执 writer。完整真实 XML 注册仍属于未来获批现场步骤，不能把本 CI 的安全派生注册说成完整生产注册成功。

## 文件与回执

- `identity_token.cs`：原生 token 查询、限制子 token、无 UAC 的普通子进程启动。
- `identity_assemble.mjs`：实际候选和维护依赖装配。
- `identity_pipeline.ps1`、`identity_consumer.ps1`、`identity_task_oracle.ps1`：上述串联、安全派生、独立 expected 与绑定清理。
- `run_identity_pipeline.ps1`：独立 hosted module scope 入口。
- `ordinary_fixture.ps1`：旧 Prepare guard/preflight approval 合成测试遇 hosted elevated token 时，使用同原生普通子进程运行原测试；不把新普通身份 guard 关闭或 mock 掉。
- `maintenance_identity_pipeline.test.mjs`：必跑 CI/真实入口/身份核查/安全边界的静态契约。
- artifact `schema6-identity-pipeline-results`：`build/ci/schema6-identity-pipeline.json` 与 module-scope 报告。串联回执包含实际双方 token、candidate/source/maintenance/ACL/XML hash、计数及真实注册/回读/清理状态；只涉及 disposable VM 的合成身份与资料。

## 本机验证（待 Hosted 补齐）

- 首次沙箱内专项发现多项 ACL/进程查询权限限制；未把这些失败归因于业务逻辑或模型。之后通过已批准的脱沙箱普通进程执行，未提权、未触发 UAC。
- 当时的维护整组 **56 项：53 通过、1 失败、2 跳过**。唯一失败是 settings 测试 AST 导入丢失生产 `$PSScriptRoot`，导致新增 helper pin 无法定位；已改为保留 `Invoke-SettingsProtection` 原文件 ScriptBlock AST，不修改生产验证。
- 修后 settings 定向 **2/2 通过，37 项原生断言通过**。其余上述53项未发生针对性变更；不把组合结果伪称另一次完整整组实跑。
- 两个未执行项是本机无管理员 token 的 foreign-owner privilege roundtrip、原 opt-in COM 生命周期。新完整双 token job 本机未执行；由 Hosted 实际补证。
- 新静态契约 **2/2 通过**；新5个 PowerShell 文件解析通过；token C# 本机编译与实际普通 token 查询通过；`git diff --check` 通过。
- 本机只装配阶段实际成功：基线 `ffbb0e89cddc6c910b95d528d5575ac153dcc9b8`、47 个 runtime 文件、21 个维护源码文件；manifest `08315e4a5992a1e1ed0a97915fe3596217bbed1e0e43031c39f02abf6d7fe1b8`。后续新提交须重新装配和绑定，不能沿用此 manifest 当作新候选验收。
- 独立 writer 工作包随后新增 `maintenance_owned_artifacts` 原生回归及20断言，本工作包未把其自报结果算入上述56项；主窗需对最终合并 diff 统一复验。

本包没有提交或 push。下一步由主窗复核、统一提交、等待每个当前 HEAD 的 Hosted 必跑检查，并针对真实返回继续修复；只有实际通过的 artifact 才能证明跨 token 链通过。

## 主窗最终整组复验（22:07）

最终合并维护源码/夹具专项实际执行57项：55通过、0失败、2本机特权条件未执行，79490.9895ms。两未执行仍是foreign-owner与原COM opt-in；新Hosted独立job不采用此跳过机制，尚待实际执行。新增owner helper 20项原生断言在该整组中再次通过。回执在忽略目录build/ci/last-attempt-maintenance-local.tap，不能当成管理员writer→普通consumer证据。固定47运行文件无diff；六批准hash21:59实核不变。