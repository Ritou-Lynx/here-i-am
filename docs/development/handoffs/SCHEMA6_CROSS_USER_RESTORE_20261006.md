# 跨 Windows 用户口令恢复 CI 夹具

范围仅新增 `tools/i_core/test_fixtures/release_schema6/cross_user_restore*` 与本文。没有修改生产模块、workflow、账号、现役数据/服务/任务/手机；未 push。主窗负责独立 hosted Windows job 与最终实际跨 SID 验收。

## 调用与输出

在 checkout 根、Windows PowerShell 5.1、官方 Node v24.14.1 下运行：

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools/i_core/test_fixtures/release_schema6/cross_user_restore.ps1 -ProductionRoot $PWD -NodePath (Get-Command node.exe).Source -OutputReport build/ci/schema6-cross-user.json
```

必须为 GitHub Actions 的 `RUNNER_ENVIRONMENT=github-hosted`、Windows，且当前真实身份是管理员 runneradmin。本机 `-GuardOnly` 也拒绝；不能用本夹具在笔记本创建或切换账号。预估远端 2–5 分钟，建议 job 15 分钟上限。最终只上传指定安全 JSON；不要上传整个临时目录、恢复目录、profile 或子进程输出。

输出含不同 SID 的 SHA256、纯口令/未使用 DPAPI、真实 Core inspection、5 条拒绝、DB 字节不变、schema/node/device/全部表数量与摘要、耗时、账号创建及清理布尔值。只读 Core 的生产检查实际包含 5 条被拒业务路由（其中一条 GET），不把该数字虚称 5 次 SQL 写操作。JSON 不含口令、原始 SID、正文、绝对路径或原始错误。退出 0 才表示恢复和清理均成功；cleanup 失败返回非零。跨另一机器未做，报告明确 `crossMachineTested=false`。

## 实际流程与边界

- 原账号用生产 `createRuntimeBackup`、`wrapBackupKey`、`bindPortableArtifact` API 制作纯合成 schema4/九角色归档。覆盖 bigint/blob/null/重复行、设备与全部表指纹；它不是完整 production schema4 store，目标是生产备份/inspection 数据保真。生产固定库存及 pinned Node 原字节复制，传输 manifest 带文件 hash。
- 随机恢复口令仅在内存、子进程 stdin 和身份受限 NamedPipe 中；新标准用户账号密码只在 SecureString/PSCredential，不进入 argv/env/文件/log。仅创建唯一 `s6cu_` 随机账号、普通 Users 成员。若需要，只在该受门控 CI 进程启动 SecondaryLogon。
- 新用户仅能读传输子树；原 source/archive 保持原账号隔离。新用户在明确委托的空 CI sandbox 内自行创建 private 目录并持有 owner/保护 ACL，复制并检查工具与密文 hash，然后仅凭口令调用生产 `restorePortableBackupForInspection`。该 API 实际启动/关闭只读 Core 并执行路由拒绝和字节不变检查，没有复制或访问原 DPAPI key directory。
- NamedPipe ACL 只允许原用户与临时 SID，双方检查真实管道进程 PID。父进程只在成功 Assign Job 后发送恢复口令；子进程收到 frame 前不创建编译器/Node 后代。未入 Job 的失败分支按 retained process handle 终止并等待，已入 Job 的树按 kill-on-close Job 收口。
- hosted 管理员默认 TokenOwner 可能是 Administrators；父进程在 CI guard 后临时设置当前 SID 作为创建默认 owner，finally 恢复。标准用户复制后的全部目录/文件 owner 必须是其真实 SID。未修改生产 ACL 校验。
- 清理仅承诺持有的进程树、精确 name+SID 临时账号、仅由本次启动的 SecondaryLogon 和父进程 TokenOwner。进程树退出不明确时不删除账号并报失败。profile、合成文件留给一次性 hosted runner 销毁，不递归删除其他 profile/路径。

## 本地证据与未完成项

- 三个 PowerShell 文件 parser：0 错；Node `--check` 通过；通用 C# Job/Pipe/TokenOwner helper 在本机编译通过。
- Windows PowerShell5.1 执行 `-GuardOnly` 返回 2，固定 `hosted_runner_required`，在任何账号/服务/新目录动作前拒绝。未创建或切换本机账号。
- 同一 Windows SID 的合成 factory → 纯口令 restore 已用主窗最新生产模块实际通过：`factoryVerified=true`、`restored=true`、`realCoreVerified=true`、5 条拒绝、`databaseBytesUnchanged=true`。该次数据库指纹 SHA256 为 `c62c631efdb4e34368075327d083c31e2c94cfcbc92c441bb2a0093e658293eb`（合成随机密钥导致下次不同）。首次沙箱运行在 NTFS 原子发布遇到 EPERM；在已授权的私有 TEMP 合成范围执行通过，未改生产 API。
- **真实不同 SID 的恢复尚未在本机运行；必须以新远端 CI job 的 JSON/退出码确认。** 本地通过不冒称跨用户通过。最终主窗整体 Core/Windows 602 pass 等证据不替代本新增 job。
- 独立 worker 只提交自有四夹具和本文，使用一次 `SKIP_PROJECT_STATE=1` 并 finally 恢复；主窗统一集成状态。

## 首轮远端失败后的窄修复

- 远端 run `37425475844` 的 job `112144024474`、另一个 job `112144041393` 均实际失败：`temporary_account`、`accountCreated=true`、`cleanupConfirmed=true`，耗时分别 58802 / 58673 ms。尚未得到不同 SID 恢复通过证据；两次失败不跳过，也不归因于已经证实的网络问题。
- 账号创建后分开记录 Users 组加入、root/factory/source/archive/transfer ACL、空 child 目录及委托、SecondaryLogon 查询/启动、pipe、进程启动/Job 分配、身份、口令 frame、恢复报告、退出和断言阶段。失败安全 JSON 增加 `failureDiagnostic`，只含受限异常类型、数值 HResult、固定允许的 FQErrorId；其他 FQErrorId 一律 `redacted`。不输出 Exception.Message、TargetObject、堆栈、账号或口令。PowerShell 会把任意 throw 正文作为 FQErrorId，因此此处使用明确允许的错误 token 集合。
- `Add-LocalGroupMember` 直接接收刚创建的 LocalUser / LocalPrincipal，避免 SecurityIdentifier 转换后再次解析目标。移除宿主 Administrators 全组枚举，改由 child 检查自身真实 WindowsIdentity.Groups 不含 Administrators SID（包括 deny-only 成员），且 WindowsPrincipal 非管理员；成功报告增加 `standardUserToken=true`，父进程必须核验。该断言没有放宽标准用户要求。
- 原实现的对象转换、宿主组成员名称解析是源码可见的潜在失败点，目前只是待验证假设。ACL 或 SecondaryLogon 也仍可能失败；本补丁保留失败和清理语义，不通过更改宿主组/服务启动类型绕过失败。
- 本地窄验证：3 个 PowerShell 文件 parser 0 错；合成含账号/口令/路径的 ErrorRecord 未泄漏，已知固定错误 token/HResult 保留；Windows PowerShell 5.1 `-GuardOnly` 仍返回 2，在任何账号或服务操作前拒绝；`git diff --check` 通过。没有在本机创建/切换账号、启动服务或重新跑生产整组。下一次 hosted Windows 实跑才能确认跨 SID 与本轮修复效果。
- 本次只提交 3 个自有 PS 夹具和本文，使用单次 `SKIP_PROJECT_STATE=1` 并 finally 恢复；未 push，Node/生产模块/workflow 没有改动。

## 第二轮子进程提前退出后的诊断修复

- 第二轮两个 hosted job 已越过账号创建/组/ACL/SecondaryLogon，child 立即输出旧固定拒绝，父进程之后在 `cross_user_pipe_connect` 等待 60 秒失败；`cleanupConfirmed=true`。141/150 秒是包含 factory 的总时长，不能当成 restore 时长。第一轮 58 秒同样包含 factory，并非已证实的网络或 pipe timeout。
- 主窗独立纯内存验证已证实：旧 SecurityIdentifier 转 LocalPrincipal[] 发生 PSInvalidCastException，LocalUser 可转换；上一轮改传 `$created` 有此补充证据。第二轮 child 失败的具体原因仍未证实，可能为 credential 环境标记或 pre-pipe 身份/目录检查，不能混同两个阶段。
- child catch 现在输出受限 JSON：固定 `failurePhase`、`childRejected=true` 与已有安全异常诊断。阶段覆盖 hosted guard、身份、标准令牌、workspace 创建/owner/ACL、pipe、口令 frame、native helper、server PID、transport、copy、inspection、report；不输出原始异常文本/账号/口令。
- credential 启动改用 .NET ProcessStartInfo：SecureString Password、UserName/Domain、LoadUserProfile、UseShellExecute=false、CreateNoWindow 与 Hidden。EnvironmentVariables 先清空，仅显式加入 OS/GITHUB_ACTIONS/RUNNER_ENVIRONMENT/RUNNER_OS/SystemRoot/WINDIR/TEMP/TMP；没有继承 token 或其余环境。TEMP/TMP 初始指向新账号被委托的空父目录，child 创建并验证 private 后再切换。显式环境块与 UseShellExecute=false 的契约参见 [Microsoft .NET 文档](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.environmentvariables?view=netframework-4.8.1)。这消除对 credential 默认环境的依赖，但不声称已确定旧失败根因。
- Job.Add 成功后才能发恢复口令，未分配 Job 的实际已启动子进程仍按持柄终止；新增 childStarted 区分 Process 对象已构造与进程真正启动，Start 失败不等待不存在的进程。失败不跳过；生产模块与测试断言未放宽。
- 本地：3 个 PS parser 0 错；parent GuardOnly 和 child 实际 guard 均退出 2，child 安全 JSON 明确 `child_hosted_guard`，未发生目录/账号/服务动作；按源码实际构造 ProcessStartInfo 验证仅 8 个允许环境键、SecureString 保留、hidden/profile/UseShellExecute 标记正确，未调用 Start；`git diff --check` 通过。真实不同 SID 恢复仍待远端新回执。
- 本次只提交 2 个自有 PS 及本文，单次 SKIP_PROJECT_STATE 例外后恢复；不 push。
