# Schema 6 口令恢复与每日自动备份 worker（2026-10-06）

## 范围与结果

源基线 `0e04e1fb1d9ca0d1a15b457bc79b66f3f8c8243d`，分支 `codex/schema6-portable-backup-20261006`。按主窗要求另纳入 CI 夹具修复 `99147eb1`（本分支等价提交 `c37df114`）；主窗只 cherry-pick 本 worker 功能提交，不重复纳入 CI 祖先。源码实现口令包装备份 key、仅口令的真实只读 inspection、每日备份、30天默认保留和可选密文镜像。

本轮仅源码与随机生成的合成数据。没有读取真实数据库、原授权、实际凭据或用户口令，没有注册计划任务、改现役服务、写外接设备/手机或创建 Windows 账号。所有临时库、口令、DPAPI key 和镜像目录均由测试生成。没有备份或迁移生产状态。

## 密钥与口令接口

新增 `portable_key_custody.mjs`：

- `wrapBackupKey({key,password,backupSetId})` / `unwrapBackupKey({envelope,password,backupSetId})`，password 必须是16–1024字节的 Uint8Array；不接受 argv、环境变量或持久化口令文件。用户应自管足够强的恢复口令；长度门槛并不等价于密码强度证明。
- scrypt 固定 N=131072、r=8、p=1、输出32字节，maxmem192MiB；salt32字节、nonce12字节、AES-256-GCM tag16字节。参数不支持降级或任意放大，解析在 KDF 前检查精确字段/长度与参数。AAD 认证绑定格式、backup purpose、backupSetId、keyId 和 KDF/随机量。
- `bindPortableArtifact({key,envelope,report})` 用备份 key HMAC 绑定密文 SHA、inventory SHA、完整数据库 fingerprint、envelope SHA、set/keyId。静态口令 envelope 在每次自动备份旁复制；每个归档有自己的绑定，不需再次输入口令。
- `restorePortableBackupForInspection({envelope,password,binding,artifactPath,outputDirectory})` 不加载 DPAPI；先解 key/核 HMAC、核密文与库存，再调用既有真实 Core inspection。恢复目标必须全新、私有，业务路由全部拒绝；不执行归档里的 launcher/config，不启用生产身份。
- 备份 key 与 Core cursor_secret 仍独立。此包**只增加 backup key 的口令包装**，没有包装独立 production recovery-custody key。跨机 inspection 不代表可重建原 production current-head HMAC、独立 trusted floor、adoption 或启动权威；这些恢复流程仍须另外保留独立 recovery key/custody 并审阅，不能拿归档 inspection floor 替代。

新 `portable_backup_schema6.ps1` 给出两套参数：Setup 用 KeyDirectory/BackupSetId/OutputDirectory；Restore 用 EnvelopePath/SHA、BindingPath/SHA、ArtifactPath/OutputDirectory。两者还需要 ReleaseDirectory 与独立 ManifestSha256。只有经过固定包全库存/Node pin 验证后，底层 wrapper 才通过 Read-Host SecureString 输入口令；Setup 要二次相同输入。密码转字符/字节在内存完成，经二进制 stdin frame 交给 Node，正常/失败路径清零可控缓冲。无口令参数。JS/.NET运行时和用户键盘输入的所有内部副本并不能由此证明被物理擦除。

## 在线副本与真实 custody 边界

`captureOnlineRuntimeBackup({specTemplate,sqliteEntryNames,key,outputDirectory})` 保留原九类 spec 契约。Core 默认一致复制，辅助 SQLite 必须明确列入 sqliteEntryNames；遇 SQLite header 却未列入时拒绝，独立 WAL/SHM/journal 也拒绝当普通配置拷贝。只读 SQLite 连接、query_only、读取事务与 SQLite backup API 固定单库视图；源库不 checkpoint、不关服务。只对新的私有目标库切 DELETE journal，并 integrity_check 与无 sidecar 检查。

`createRuntimeBackup` 的原件 sidecar/链接/角色/哈希/完整旧 release 检查没有放宽。本 worker 仅导出既有严格文件原语，在线捕获模块把私有一致副本单独作为归档输入。其他文件前后稳定身份/hash检查，旧 release 仍必须吻合固定库存/外锚。各组件开始/结束与原路径映射写入归档内部 `archive-inspection/capture-window.json`，明确 crossComponentAtomic=false。

schema5/6 在一致副本上生成 `archive-inspection/context.json`，用于验证**本次归档 inspection**。输入 spec 的原独立 recovery_custody 文件另外完整保留，内容不重写；仅移除其作为本归档 context 的标记。副本产生的 floor 不是独立来源的防回滚权威，不作为生产 clean-stop、activation、trusted head 或迁移授权。归档始终 inventory_only / production_completeness_not_attested / activation_supported=false。正常/可处理失败时只清理本次创建的明确 staging 文件；进程强杀后可能残留受 ACL 保护的未完成目录，不被当作成功备份，不递归删除未知物。

## 日常调度与镜像

`scheduler_once_schema6.ps1` 由主窗的登录会话监督器按需调用，参数为 ReleaseDirectory、ManifestSha256、KeyDirectory、ConfigPath、ConfigSha256。它不创建任务或常驻循环；主窗决定登录时、到期时和重试时机。日常不用恢复口令，仅用已有 DPAPI backup key。ConfigPath 必须当前用户+SYSTEM的受保护 ACL，并且字节 SHA 受外锚约束。

config 顶层精确字段为 `policy,specTemplate,sqliteEntryNames,envelopePath,envelopeSha256`。policy 为：

```json
{"format":"i-core-automatic-backup-v1","outputRoot":"<existing private canonical directory>","backupSetId":"<64 hex>","retentionDays":30}
```

可选 mirrorRoot 是由用户以后配置的独立目的地；省略即不复制外部。此实现要求目标路径通过严格普通本地路径与新目录 ACL 检查；Windows 镜像文件系统需要支持受保护 ACL。不自动选择盘、云端或手机。自动 API 的 specTemplate 非 release 文件 hash 在稳定捕获后重新生成；模板限定来源与逻辑角色，而不要求活跃 OAuth/policy/数据库永远停在旧 hash。

- 距最近成功本机归档24小时才重新捕获；时钟倒退明确拒绝。默认 retentionDays=30，可显式1–3650天。
- 每个成功本机目录保存密文、portable-key、portable-binding和备份 key 签名的 receipt。成功本机与镜像状态分开：目的地不可用仍保留本机成功，返回 mirror_pending；重接后遍历仍保留的本机归档补复制、逐项哈希确认，不重复抓数据库。半途镜像失败留下的专属未完成目录不覆盖、不作为成功或自动清理对象。
- 只有验证签名和全部哈希、且目录仅有预期文件的归档可按天数删除。未知目录、额外用户文件、旧 key 无法验证的归档都不被清理；镜像未补齐时暂停过期清理，避免删掉唯一副本。
- 新 key 必须重新明确 SetupPortable，更新受保护 config 的 envelope 外锚；旧归档保留各自 envelope/binding。调度器不会静默轮换 key/口令。旧 key 的归档不会被新 key 自动清理。
- 固定 Automatic PowerShell wrapper 在 outputRoot 持有 FileStream(OpenOrCreate, ReadWrite, FileShare.None) OS锁，并检查无链接、单链接和私有ACL；锁文件保留，所有权以活句柄为准，异常退出自动释放。不会把残留文件误认为永远有 writer。JS raw API 只作同进程 Set 互斥；生产跨进程必须通过固定 wrapper。
- 主窗负责将整个 scheduler PS/Node 后代树放入通用 Windows Job：正常停止先等待，超时强杀整树并核退出回执，不能只杀 PowerShell 留下 Node。此 worker 不把单独的锁进程终止测试夸称为完整 Job 停机验收；备份失败不关闭 Core。

## 验证与限制

- 前一轮组合：原备份23项、原inspection8项、新核心13项，44/44，0失败/0跳；包括旧固定包 Create/Verify/RestoreInspection 与环境隔离回归。
- 新固定包专项实际执行 SetupPortable→Automatic(DPAPI)→移走原 DPAPI key目录→RestorePortable，真实 Core readonly health、5条业务路由403、完整数据库 fingerprint 和字节不变均通过。SecureString 的 UI 输入用测试进程 Read-Host 替身，口令随机、仅stdin；生产转换/传输/包装/解包代码均实跑，不声称真人终端交互已验。
- 最终新专项包含14项：口令错误/篡改/KDF成本与弱参数拒绝、跨进程password-only inspection、schema6在线WAL副本、辅助SQLite遗漏拒绝、hardlink拒绝、due/retention/clock、镜像离线重接、OS锁争抢/强制终止持锁PS后残留路径重入。最后一次整组13项核心通过、原生1项在OS锁ACL重写处失败；脱敏phase定位后，对已保护锁改为只验证ACL，新锁才设置。原生同一专项返修后1/1通过（约30秒）；没有删除锁路径来伪造恢复。主窗仍须跑最终整合候选验证。
- 当前测试 token 非管理员，未创建或借用其他 Windows 用户。独立 Node 进程未得到原备份 key，只收到口令/envelope/binding/密文并成功 inspection；这证明无 DPAPI 依赖，不等价于已经完成真实跨 Windows 用户/跨机器测试。
- 未运行 Linux；核心算法/SQLite测试跨平台保留，只有 Windows 原生 PowerShell/DPAPI专项平台跳。新夹具使用 syntheticRoot / syntheticFixedNode 规避 Windows TEMP 8.3别名，不放宽生产路径保护。
- 无口令、数据库、身份秘密或真实配置进入 Git。仅提交自有源码、测试、此 handoff 和主窗后续明确授权的四项 package库存；一次性 SKIP_PROJECT_STATE=1 后恢复，无 push。DEVLOG/I_PROJECT_STATE、全局 closeout、最终固定候选/CI与生产接受由主窗负责。
