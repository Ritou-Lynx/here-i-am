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
