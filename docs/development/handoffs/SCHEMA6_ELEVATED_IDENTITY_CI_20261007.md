# schema6 提升 writer → 普通 owner 合成 CI

## 2026-10-07 第三轮启动差异已定位，保留真实 Prepare Node 失败证据

`cf9b121e` 的 Hosted 18项矩阵形成明确对照：继承桌面/仅私有桌面/私有桌面+进程线程SD三组的 cmd、Node、PowerShell 全为 `0xC0000142`（9失败）；加入 TokenDefaultDacl 的后三组全部 exit0（9成功），额外修改新 token 对象DACL未增加通过范围。故**启动差异已定位到新 token 的 DefaultDacl**，不进一步推断具体 CSRSS/DLL 内部失败机制。push 与 PR 两个 runner 的 fixed-candidate 三程序均 exit0，实际 pipeline 均已到普通 consumer：同SID、本人TokenOwner、非提升、非管理员、Medium，以及真实 `aclReceiptRead=true`；随后都报 `consumer_prepare_rejected / prepare_node_rejected`，fixedPrepare 与完整串联仍未通过。

生产 Prepare 把其 Node stderr 收敛为统一错误码。本轮不改生产源码/固定47文件/配置pins，增加夹具诊断：先用实际 pinned Node、相同OS-only清理环境调用仅只读的 `validatePreparationInputs`，保留实际argv、native argument字符串、6个允许环境变量、stdout/stderr/status；然后由 `identity_prepare_observer.ps1` 执行原始真实 Prepare 完整路径。观察器按原文件AST精确定位唯一 `Invoke-PrepareNode` 内的唯一 `child.WaitForExit`，设置本夹具自动继续断点；仅等待和读取该函数已有进程/异步输出任务，记录两个阶段序号、Code hash、argv/env/退出码/输出。它不重定义函数、不改代码/配置/guard/返回值，不重跑任何写API；finally只移除自己创建的断点，并核源hash未变。两个Node阶段仍由真实Prepare调用。诊断仅写本次 `schema6-identity-*` 根下固定报告，父pipeline完整保存consumerReport。

同轮维护59项为58通过1失败。唯一失败 `maintenance_preflight_approval` 是合成fixture最后直接 `Console.WriteLine` 绕过 ordinary dispatcher 的PowerShell成功流重定向，退出0但stdout为空；改成 `Write-Output`，保留原业务断言并新增非空输出断言。本机真实ordinary定向 **2/2通过**（69993.9ms）。新增观察器transport-only回归执行真实PS断点与两个既有Node（0/7退出），确认原合成源码仍按原行为exit2，两个阶段Code hash/stdout/stderr、源hash不变和移除断点均通过；这不冒充生产Prepare。与原4项静态契约合跑 **5/5通过**（866.8ms），受影响PS解析与diff-check通过。

本轮新增fixture观察只为获得下一次真实失败的完整原因；尚未给 `prepare_node_rejected` 指定未经证实的根因。完整现场 RegisterOnly 仍未执行，`productionRegisterOuterExecuted=false` 不变。证据在忽略目录 `build/ci/cf9b121e-schema6-identity-{pipeline,startup}.json`、`cf9b121e-identity-hosted.log`、`cf9b121e-identity-pr-hosted.log` 和维护日志；不包含现役资料或操作。

## 2026-10-07 第二轮仍失败：启动矩阵与固定权限候选

`6647d041` 的 Hosted artifact 再次得到 `consumerExit=-1073741502 / 0xC0000142`，没有 consumer identity/result。私有窗口站和桌面的安全描述符验证、父站/线程桌面恢复、对象关闭全部为 true。因此“仅桌面权限导致失败”的解释不足；实际 Apply 144/16 成功仍仅为部分证据，完整串联与 fixed Prepare 尚未通过。

第三轮仅改夹具。`identity_startup_diagnostics.ps1` 在同一必跑 job 先做 **6 个变量组合 × cmd/node/PowerShell =18 次**即时退出启动：继承桌面基线、仅私有桌面、私有桌面+进程/线程 SD、私有桌面+TokenDefaultDacl、固定候选（私有桌面+两者）、最后额外改变新 restricted token 内核对象 DACL。最后一个变量仅操作 `CreateRestrictedToken` 新返回的 `limited` 句柄；不修改父 token 或任何原有宿主对象。每个诊断子进程限15秒，超时只按自己创建的准确句柄终止并等退出；清理不确定立即停止矩阵。即时退出程序不创建任务、访问应用状态或派生子树。

矩阵与正式候选均用 `CREATE_SUSPENDED`，在 `ResumeThread` 前读取真实子 token，严格要求同 SID、本人 TokenOwner、Elevation=0、非管理员和 Medium。验身份或读取安全描述符失败时，finally 终止尚未恢复执行的确切子进程并确认退出。记录父/原限制/修改后的 TokenDefaultDacl、限制 token 自身与实际子 token 的内核 SD、实际进程/线程 owner+DACL+label、启用/deny-only groups、restricted SIDs 和失败阶段。TokenDefaultDacl 与 token 对象 SD 明确分开。

正式 `RunLimited` 固定采用“私有桌面+明确进程/线程 SD+子 token 私有 DefaultDacl”，**不读取矩阵结果、不动态挑选、不修改 token 对象 SD**。本人/SYSTEM/Administrators 三主体、protected DACL、owner 均原生回读；进程/线程 label 按实际 Windows 语义接受无 label 的 implicit Medium 或精确 Medium NW，显式 High/Low 等均拒绝。原生产 ordinary guard 和固定47文件无改动。此候选针对默认对象权限的假设仍待真实 Hosted 证实，不把本机成功当根因已定。

依据：[CreateProcessAsUserW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessasuserw) 说明未提供进程/线程 SD 时由 token 推导，创建成功可随后 DLL 初始化失败；[Mandatory Integrity Control](https://learn.microsoft.com/en-us/windows/win32/secauthz/mandatory-integrity-control) 说明没有 integrity SID 的对象按 Medium 处理。

本机已实际通过：Windows PowerShell5.1 C# 编译；普通父 token、继承本机桌面下 **15/15** 原生启动（3程序×5种kernel/defaultDacl/tokenObject组合）全部 exit0，全部预恢复真实身份断言通过，明确私有 DACL 的各组合读回通过。另一个只睡眠的合成 PowerShell 在 **15158ms** 超时；独审要求统一异常清理后再次实测为 **15110ms**，`timedOut=true`、`terminatedAfterTimeout=true`、`childExitConfirmed=true`，正常 cmd 退出也核 `childExitConfirmed=true`。该清理保证仅针对准确句柄对应的直接子进程，不声称通用子孙树终止。本机回执为忽略目录 `build/ci/identity-startup-local.json`；`privateDesktopTested=false`、`elevatedWriterTested=false`。未发起 UAC。静态契约 **4/4**、三份受影响 PowerShell 解析及 diff-check 通过。

新 artifact 增 `build/ci/schema6-identity-startup.json`；其 `diagnosticOnly=true`、`pipelinePassed=false`，completed 只表示观测完成，非启动/串联通过。矩阵普通启动失败是观测并继续；清理不确定会失败并阻止后续真实 pipeline，artifact 上传仍执行。正常观测完成后真实 pipeline 使用固定候选，自己的失败使 job 失败。正式 pipeline 即使 native launcher 抛错也保存 `consumerLaunch` 和 privateDesktop 证据；旧 ordinary fixtures 出错时打印同份启动证据。安全派生 COM 仍不能称完整生产 RegisterOnly，`productionRegisterOuterExecuted=false` 保持不变。

## 2026-10-07 Hosted 首轮失败与桌面隔离修订

首轮候选 `befcad08` 的真实 artifact `11487836939` 已证明 writer Elevated/Admin/默认 owner BA/High 四项成立；实际 Apply **144 项、16 项原 foreign owner** 通过，ACL 回执 owner 断言通过，原合成 frozen task 已绑定删除。`fixedPrepare=false`，完整串联未通过。旧两项普通身份夹具的子进程均在约0.57秒退出，状态 `3221225794 / 0xC0000142`，无 stdout/stderr；原 identity 串联只报缺少 consumer 回执。

本次仅修测试环境：每次限制子 token 启动前用 `CWF_CREATE_ONLY` 新建随机窗口站及其私有桌面，创建时提供同 SID/SYSTEM/Administrators 明确 DACL 和 Medium mandatory label。通过原生安全描述符读回逐项核 owner、三个允许主体/完整权限、protected DACL、单个 Medium NW label；`STARTUPINFO.lpDesktop` 显式指定该对象。创建后在 finally 恢复夹具进程原窗口站；读取原 thread desktop，只有实际变化时调用 `SetThreadDesktop(original)` 恢复，并验证两项恢复。没有 `SwitchDesktop`、输入操作或原桌面/窗口站 ACL 修改。子进程退出后检查 `CloseDesktop`/`CloseWindowStation` 成功，consumer 实际读出的窗口站/桌面名必须等于父端创建名。

桌面访问导致 DLL 初始化失败目前仍是待新 Hosted 验证的推断；[Microsoft CreateProcessAsUserW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessasuserw) 明确说明空 lpDesktop 会继承父对象，目标用户须有窗口站和桌面的完整访问，进程创建成功也可能随后 DLL 初始化失败。本次不降低 token 身份要求；并先记录 `consumerExit` 与 `consumerResultExists`，缺少结果时用带退出码的固定错误，避免掩盖原失败。

本机修订验证：C# 编译、当前普通 token 及当前桌面只读查询成功；静态契约 **3/3**、相关 PowerShell 解析与 diff-check 通过。获准的普通身份私有对象微测在创建命名窗口站时得到 **Access is denied**，父窗口站恢复验证成立，没有创建可报告为成功的私有对象、没有执行子进程、没有请求 UAC。因此私有对象创建/读回/关闭和完整高低 token 链仍待新 Hosted 真正执行。下面的56项结果及装配结果为首版本机历史证据，不代替新 Hosted 通过。

同时将真实 online preflight 三用例通过 `online_preflight_ordinary.ps1` 进入同一普通身份派发器：外层只保留三项 hosted proof 环境供授权范围断言，真正 Node/production adapter 继续 OS-only clean environment；Git core 路径仍经原装配器严格验证。初次本机普通身份 **direct / missing-grant / cli 全部通过**：原库 schema4、合成迁移 schema5、DB/WAL稳定、ready后SQL调用0；missing-grant明确拒绝 nonempty_grants_required。派发器成功JSON和stderr分开捕获，避免 Node 诊断污染JSON。没有降低生产普通身份 guard。

## 范围与当前证据

本工作包仅修改测试、合成夹具和 `.github/workflows/ci.yml`。未改固定 runtime 47 项，未访问现役库、凭据、服务、手机或现役任务，未发起本机 UAC。生产 `owned_artifacts.ps1` 及各 writer 修复由独立工作包负责。

新增必跑 job：`schema6-identity-pipeline`，显示名 **Schema6 elevated writer to ordinary owner pipeline**；沿原 workflow 的 push、pull_request、workflow_dispatch 触发规则执行，无 opt-in 环境变量和失败忽略。独立 runner 使用既有 hosted module scope，**不调用**旧 `run_windows_tests.ps1`，不继承其修改 TokenOwner 的 workaround。旧 suite 的 workaround 保留。

首版交接时 Hosted 新 job 尚未运行；后续实际失败及修订状态见上节。本机当前普通 token 无法代替管理员 writer → 普通 consumer 证据，C# 编译成功也不代表实际跨 token 启动通过。

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
