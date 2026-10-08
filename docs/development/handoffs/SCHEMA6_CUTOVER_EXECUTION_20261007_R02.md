## 2026-10-07 21:29（上海）最新结果：r02 Prepare 拒绝，已完整退回

单目录 settings 已按新授权加固成功，新只读演练零失败；六项批准外锚及实时父 SD 均未变，故按有条件预授权进入正式 r02。144项 Apply 成功后，正式 Prepare 在读取 ACL 回执时因 owner 为 Administrators 而非本人，报 `prepare_owner_rejected`。没有现场改 owner 重试。已真实恢复全144项原 owner/DACL/继承，复核原 raw 身份/字节、grant/replay、旧固定包和库存，再恢复旧任务原定义/权限，按 Core→MCP 启动并绑定完整树、schema4及三个端口。21:28:57退回签收通过。

**未完成切换，暂停待审。** 新任务不存在，候选从未启动，原库未迁移/替换，head未推进；四项真人Gate未执行。r02已消费，旧锁/回执全部保留，不得复用；下一轮须新的正式ID。单 settings 获批前置保留（f88d49ec…），生产 settings **不可清理**。完整证据和下一轮源码建议见[本轮授权及实录](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)。以下旧阶段的“r02未使用/零停机/尚未加固”均仅为当时历史，不覆盖本节。

# r02 再次进场前签收：系统映像 Pin 拒绝，未进入窗口

本轮用户已精确批准 FINAL_TASK_APPROVAL.md 的 XML、双 SDDL、父 SD、零外 SID、候选 manifest 与 login 配置，并授权合并 PR18 后按原④–⑥切换。以下是本轮实际执行结果，不代替旧历史记录。

## 已完成

- PR18 精确 head `09cba7e6e56bd60bed745868770c7ed07031820e` 的15项检查再次全绿核验后，普通合并到 `v3-lab@ea388345cf3da72a719e306fb88da5b2944b797b`。GitHub集成转ready返回403，本机既有GitHub身份完成已授权转ready/合并；没有输出凭据。
- 用户批准的 XML SHA256 `4bc643571073b726fad4cc781785129a27a6c9b4a669ef9df1a621c5cebb397e`；注册输入 SDDL `50398e9fe2ff2b2cbf62ee4ed31b703ddc21aff6339a0595963e2cb859915feb`；继承后预期 SDDL `9d1a0c172a55d1ac6ee5a8a831793abde4cd6b7252258329688283f3bc593580`；父 SD `330eb3abb433de72e6efae43075cd7440976dae310f7d55da2717626b38b880d` 全部只读复核一致，零外 SID。
- manifest `3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0`；login配置 `28c5b700b98815b57b57e4cc9430f16ee8ef5ba8bdc3a1a08f854873965e1e00` 一致。合并提交46份源码与固定Node共47项及维护快照22项逐字一致，沿用精确获批候选，不为改source_commit标签重写包。
- T盘为NTFS、Healthy、USB Samsung PSSD T9；用户已确认保持连接。卷UUID与镜像根的完整绑定尚未执行，不能视为本轮备份已完成。没有格式化、转换文件系统或新增明文镜像。
- 当前ACL原快照144项与现役实际库存/owner/DACL/继承全部相同，无新增/缺失/变化；外owner16项。两旧任务均Enabled/Running、各1实例，Actions/Principals/Triggers/Settings及SDDL与基线一致，47841/47860/47862由预期Core/MCP监听。

## 冻结前阻断（不是已执行入口失败）

目标旧任务完整树包含 `C:\Windows\system32\conhost.exe`。只读 `fsutil hardlink list` 显示System32和WinSxS两个系统硬链接。受审 `freeze-legacy-runtime.ps1`（SHA256 `e68b9a6dec604c96ad3b2489a2d13ddc3e125cf996bcaac4b0e9825ea38ed730`）的普通Pin会对除精确系统PowerShell外的文件调用 `FreezeIdentity.FileId`，其 `i.links!=1` 拒绝conhost。

主窗用PowerShell AST只提取同一受审源码的原始Add-Type及Fail/Hash/Plain/Pin定义，执行只读Pin并释放全部句柄，实际结果 `file_identity_rejected`；未执行顶层入口、未调用Open-MaintenanceWindow。独立源码复核确认没有合法配置可避开：加入conhost在Pin拒绝；省略它在完整树PIdentity拒绝；WinSxS别名/复制件不匹配真实进程映像路径。

调用链：freeze L345–346 processImagePins → RequiredPin L239 → Pin L50–56 → FileId L67。省略时L360 → GetBound L107–108 → PIdentity L83。Open-MaintenanceWindow位于L296，故不得用正式入口试错而消耗r02。

## 按失败规则停止

- 未进入 `cutover-retry-20261007-r02`，没有创建其entry.lock/窗口回执，旧锁与回执保留。
- 没有冻结/停用任务、停止或重启Core/MCP/隧道、ACL Apply、生产Prepare或Register、原库SQLite读取/迁移/替换、head推进、新Core写入、手机操作。
- 服务无需退回操作，继续旧运行链；本轮人为停机0。四项真人Gate均未执行。
- 没有绕过plainPath、NativeLease、strictClosedPath、数据/release单链接或完整进程树检查，也没有临场修受审维护字节。

## 后续最小修订建议（未实现、未放行）

只在维护helper增加固定Windows系统映像专用pin，允许精确系统PowerShell/conhost由Windows servicing形成多硬链接；仍核无reparse、规范实际路径、已批准hash、文件身份及持柄禁止写删。普通Pin和数据、release、配置、四件、外置授权的单链接检查保持。完整树枚举和每个映像白名单/hash保持，禁止可配置任意放行开关。

补合成回归：合法系统映像通过；非系统双链接、别名、错误hash、reparse、遗漏后代全部拒绝。须源码审阅/CI/新维护闭包后再进场，不能以本轮XML批准自动批准未审代码。固定候选Core/MCP/启动器和XML/双SDDL无需因此改变；若实作改变这些字节，另明确说明。

## 生产配置不可清理

`D:\HereIAmRuntime\i-core\maintenance\cutover-20261007-1552e251\task-approval-c9662439-3fb4b5c51a0f467cbd1ec3c1c18aee73\settings`

**这是生产配置目录，不是临时审阅缓存：不可清理。** 内含获批login.json及其绑定core/daily配置；XML的绝对参数路径和配置摘要与它绑定。当前不得改名、移动、清理或用新审阅目录覆盖。以后换包时再迁入正式生产配置目录，迁移须重新绑定路径/hash、重新生成并批准XML，保留必要恢复资料。上层task-approval名称不能成为清理依据。

B线独立PR19继续其源码/CI/审核；本轮冻结前停止不取消B，也不宣称B已上线。
