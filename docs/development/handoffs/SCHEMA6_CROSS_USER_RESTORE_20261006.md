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

## 第三轮恢复报告/清理失败后的诊断修复

- run `37426981866` / job `112148862115` 与 run `37426977466` / job `112148852517` 均在 `cross_user_restore_report` 失败，合计耗时 106183 / 109344 ms，`cleanupConfirmed=false`。管道连接已通过，child 的实际身份、标准令牌和 private workspace 前置检查因此已执行通过；没有恢复报告或成功清理证据，不能推断具体失败原因。
- 父进程 PSI 设 `RedirectStandardError=true`，Start 成功后立即 ReadToEndAsync，Job/frame 顺序不变。进程退出/清理后最多等 5 秒 drain；只解析总长 ≤8192 字符、≤16 行、每行 ≤2048 字符的输入。仅接受 `childRejected=true`、固定 child 阶段、恰好指定字段和受限异常类型/HResult/FQID，重建安全对象；任意 stderr、超限内容、额外字段均不输出。有效对象纳入最终安全 JSON 的 `childDiagnostic`，不写 stderr 原文。
- 安全报告新增 `cleanup` 各项（true=已确认，false=失败，null=本次不需要）：pipeClosed、unassignedChildStopped、jobEmpty、jobDisposed、childExited、childDisposed、stderrDrained、accountRemoved、secondaryLogonRestored、tokenOwnerRestored。`cleanupErrors` 仅用同一受限异常结构。不改变任何生产恢复或标准用户断言；清理未确认仍返回非零，不删除进程清理尚未确认的临时账号。
- 本地证据：3 个 PS parser 0 错；1 个合规安全 JSON 接受、9 个非法/超限/夹带字段样例拒绝；同 SID 子进程真实重定向 stderr、异步读取和安全 parser 取得 `child_hosted_guard`，exit2；按实际 finally 源码运行 2 个纯模拟清理分支（成功、Job.Stop 抛错）均记录正确布尔和安全错误。没有创建/切换账号、调用账号或服务操作、接触真实数据。parent GuardOnly 仍退出2；diff 检查通过。
- 本次只提交 parent/common 两个自有 PS 和本文，单次 SKIP_PROJECT_STATE 后恢复，不 push。远端不同 SID inspection 与完整清理仍未通过，等待新回执定位。

## 安全诊断白名单及 CI Job 数值错误收窄

- 复核确认旧异常类型正则和命令后缀正则允许任意 marker，已改为确切异常类型枚举；FQID 先丢弃首个逗号后的全部内容，再仅保留确定的错误前缀，其余 `redacted`。child stderr parser 只接受规范化后的精确字段和值，任意 `System.*` 类型或命令后缀都不能透传。
- 安全诊断保留 HResult，并新增始终存在的 `nativeErrorCode`（null 或 Int32）：只从最多 5 层异常链中的确切 Win32Exception 读取整数，不序列化 Message/Data/堆栈。CI 自有 Job 的 TerminateJobObject/CloseHandle 使用 SetLastError 并检查返回值，失败抛固定消息的 Win32Exception；Dispose 即使终止失败仍尝试 CloseHandle，两个都失败时保留第一个 Win32 错误。真实 Empty/Wait 回执要求不变，未修改生产 owned_job。
- 本地验证：3 个 PS parser 0 错；C# helper 编译；3 个 marker 脱敏/后缀丢弃样例通过，3 个恶意 child JSON 被拒；嵌套 Win32Exception 仅保留数值 5，HResult 原值保持；新建空合成 Job Stop/Dispose 成功，已关闭合成 Job 的 Stop 实际拒绝并报告 Win32 6。未创建账号/操作服务/运行真实 Core。parent GuardOnly 仍退出2，diff 检查通过；没有重新跑生产整包或声称远端通过。
- 仅提交 common 夹具和本文；单次 SKIP_PROJECT_STATE 后恢复，未 push。

## 第四轮 Node 恢复失败诊断透传

- PR run `37428320391` / job `112153073744` 实际失败在 `child_restore_inspection`，总计 118905 ms；全部需要的清理分项为 true，`cleanupConfirmed=true`。这证明 child 已通过复制及全部文件 owner 检查，尚不证明 inspection 成功；RuntimeException/redacted 本身不足以确定 Node 内部根因。
- Invoke-CrossUserNode 每次入口清空仅用于诊断的 script 变量。非成功返回时，仅从 stderr 中接受 `fixtureRejected` 为布尔 true、固定 phase 枚举、64 位小写十六进制 errorCodeSha256、恰好这三个字段的 JSON，重建为 phase/hash 两字段；总长/行数/单行长度限制与 child parser 相同。不再依赖任意 Exception.Message 或 FQID 来携带该信息。
- child 失败 JSON 新增始终存在的 `nodeDiagnostic`（null 或 phase/hash 两字段）。父 parser 只在 `child_restore_inspection` 上接受非 null 值，并再次验证精确字段、字符串类型、固定 phase 及完整 64hex；布尔 false/字符串伪 true、未知 phase、坏 hash、额外字段和超限内容都不透传。没有改变成功证据或生产检查。
- 本地验证：3 个 PS parser 0 错；6 个恶意/错误 Node 诊断拒绝，错误 child 上下文拒绝；实际运行本 Node 夹具仅 8 字节合成 stdin，使其在 `input` 阶段按既有断言失败（不读取 productionRoot/workspace、不写文件），真实 Invoke/helper 捕获并经父 parser 往返保留 ERR_ASSERTION 的 SHA256 `bc3401c7b6b4bd7355ea1bbf002ec5b8db3166a4b55d7e9ed6aa6ed1bcc5187d`。未创建账号、操作服务或改生产模块；下一次真实 CI 的 phase/hash 才用于定位恢复错误。
- 仅提交 common/child 两个自有 PS 与本文，单次 SKIP_PROJECT_STATE 后恢复，不 push。

## 第五轮认证失败及 stdin 二进制协议修复

- 第五轮两次真实 Node 诊断均为 `restore`，错误码 SHA256 `4881737c9b27e65fe2e8a2650af307d42887a48b93b5802358fffa11af0bb9fd`，已对应固定码 `portable_authentication_failed`。这确认了认证失败；跨 SID 恢复通过仍待修复后新回执，不提前宣称完成。一次 SecondaryLogon 清理另报 1052，另一轮完整清理通过，本补丁不猜测或修改服务逻辑。
- Windows PowerShell 5.1 实际反射确认没有 ProcessStartInfo.StandardInputEncoding；pwsh7.6 有该属性，不能据此替代 PS5.1 行为。未修复的实际进程测试中，48 字节载荷在 Console UTF-8 BOM 下变成 51、UTF-16 BOM 下变成 50，摘要均改变；无 BOM UTF-8 下为 48 且摘要相同。原因是 .NET Framework 在 Start 构造 redirected stdin StreamWriter，AutoFlush 会先写编码 preamble，之后 BaseStream.Write 并不能撤回。
- CI helper 仅在 `$p.Start()` 期间临时设置 UTF8Encoding(false)，finally 立即恢复原 Console.InputEncoding，再执行原 Job.Add、原始字节写入及原清理流程。设置或启动失败仍经过既有未入 Job 持柄清理；不长期更改父进程编码或把口令转成字符串。
- MJS stdin 从至少 32 字节收紧为恰好 48 字节且流累计不超过48；与 parent 随机口令和 BinaryReader frame 一致。factory/restore 成功安全报告新增 `inputByteCount=48`、`binaryInputExact=true`，父进程对两份报告检查整数类型、值48及确切布尔true，不能以字符串代替。生产 portable/inspection API 无改动。
- 本地实际 PS5.1 调用修改后的 Invoke-CrossUserNode 和纯内存 Node byte receiver：原 UTF8 BOM / UTF16 BOM 两种编码均收到48、载荷 SHA256 相同、函数退出前原编码恢复；不存在的合成 exe 启动失败路径同样恢复。真实 MJS 输入 47/49/50/51 字节均在 input 阶段以 ERR_ASSERTION 拒绝，未访问 productionRoot/workspace。3 个 PS parser 0 错、Node --check 与 diff 检查通过。没有本机账号/服务/真实库操作，没有重新运行生产整包。
- 仅提交 common/mjs/parent 三个自有 CI 夹具与本文，单次 SKIP_PROJECT_STATE 后恢复，不 push。
