# 生产 settings 单目录 ACL 前置与有条件切换（2026-10-07）

## 本轮授权与当前状态

用户已明确授权额外的单目录 DACL 加固，先把真实执行入口和合成测试纳入 PR20、精确源码 CI 全绿，才可执行。此页初始状态为源码准备，尚未加固、重演或正式进场；后续真实结果追加，不用测试代替现场证据。

唯一现役目标：

D:\HereIAmRuntime\i-core\maintenance\cutover-20261007-1552e251\task-approval-c9662439-3fb4b5c51a0f467cbd1ec3c1c18aee73\settings

这是生产配置目录，**不可清理、移动、改名**。本次仅关闭继承并保留所有既有 ACE 为显式规则，不改 owner/group/SACL、三份配置字节和子权限，不触原库、任务、服务。它不属于原 state/i_memory 的144项，不能悄悄扩大该清单。

| 外锚 | SHA256 |
|---|---|
| 原私有方案 | 11374854974b5994adc18e1afa35cf95eea56d57f074350db9f95c8017bf250d |
| 原目录 SDDL | 5533f773840e001c189ee3a054eaee09ec6d301fe3f8eb757b3cd582a2bd5de4 |
| 拟议目录 SDDL | f88d49ec29c276b95fcc0040af2fa319251d10f063a79c0699d54c9f667a6e25 |
| core.json | cc5f8a42f31a18b72d8dba28559d1a4a01300ea875e117d61e9928deb9f4722c |
| daily-backup-config.json | d33106d26cf4c6e7c7f54e007e84bda869c0ce9c7b75a1377d98b321e4387cb5 |
| login.json | 28c5b700b98815b57b57e4cc9430f16ee8ef5ba8bdc3a1a08f854873965e1e00 |

真实 SID、完整 SDDL 和配置内容只保留在私有方案及受保护回执，不入仓库。

## 执行及成功/恢复判据

执行入口为 `tools/i_core/maintenance/protect-approved-settings.ps1`。源码必须先经合成测试、独立复核及 PR20 CI，再从精确提交固定新的维护快照；不执行可变 checkout。参数给出原方案路径及其批准 SHA、全新回执目录与显式 Execute。不得复用旧锁、旧成功回执或原三个失败演练 ID。

执行前核方案、当前 owner、原完整 SDDL、恰好三份直接文件、plain 路径和实际句柄身份、单硬链接及各自 hash；从当前 ACL 在内存重算 SetAccessRuleProtection(true,true)，必须逐字等于原拟议 SDDL。先将原 ACL 和四项身份持久保存至新的受保护回执，再写目标目录的 DACL。仅请求 READ_CONTROL/WRITE_DAC，不请求 WRITE_OWNER，也不启用恢复权限或自行提权。

入口使用已有 Windows 文件系统 API SetFileSecurityW，只设置 DACL/保护位；微软明确说明目录安全变更不会传播给子项。该 API 已标记 obsolete，仍列有 Windows 支持；在本次严格“单目录、不写 child ACL”的窄维护场景保留它，以实际 Native 合成往返和子 SDDL 逐字核验约束。路径调用期间持目标及全部祖先 no-delete 句柄，前后核同一原句柄身份。没有使用不适用于文件系统的 SetKernelObjectSecurity，也不采用普通 SetSecurityInfo 的默认继承传播。[微软 SetFileSecurityW](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-setfilesecurityw)、[SetSecurityInfo](https://learn.microsoft.com/en-us/windows/win32/api/aclapi/nf-aclapi-setsecurityinfo)。

成功须目录 protected、owner/group 和既有权限不变、实际 SDDL 等于原拟议、三个文件 ACL/身份/hash 不变，原 DACL 及终态回执已耐久落盘。失败如已开始 DACL 写入，就恢复原目录 DACL并核四项原 ACL/身份及三文件 hash；恢复不能闭合则明确失败，不能记录成功。此入口没有启停服务、注册任务或 SQLite 动作；如实际需要管理员权限，由主窗叫本人。

## 新只读演练与正式 r02 门槛

加固成功后，使用新的只读 ID 完整执行 v3 PreflightOnly：候选47项、USB/九类备份与已有真实还原、旧任务/完整进程树/端口、144项 ACL/16旧 owner、XML/双 SDDL/父 SD 和 COM 内存兼容、固定 Prepare 纯模板逐字输出、PR16 在线副本及隔离校验、结束全套复核。在线仅忽略 SHM 内容；DB/WAL 字节/大小/身份、journal 存在性、SHM 存在性/大小仍严格，离线 raw/strictClosedPath/NativeLease 不变。

用户已给**有条件预授权**：全套演练零失败且下列批准外锚全部不变，才可直接用未消费的 cutover-retry-20261007-r02 执行已批准④–⑥。旧文档“另请授权”保留为历史，不覆盖本次明确预授权。出现任何现场失败、偏差或需要修改批准内容，停下交审核，不进入正式现场。

| 必须不变的批准工件 | SHA256 |
|---|---|
| 候选 manifest | 3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0 |
| 最终 XML | 4bc643571073b726fad4cc781785129a27a6c9b4a669ef9df1a621c5cebb397e |
| 注册输入 SDDL 文件 | 50398e9fe2ff2b2cbf62ee4ed31b703ddc21aff6339a0595963e2cb859915feb |
| 继承预期 SDDL 文件 | 9d1a0c172a55d1ac6ee5a8a831793abde4cd6b7252258329688283f3bc593580 |
| 父 SD 文件 | 330eb3abb433de72e6efae43075cd7440976dae310f7d55da2717626b38b880d |
| login.json | 28c5b700b98815b57b57e4cc9430f16ee8ef5ba8bdc3a1a08f854873965e1e00 |

本轮新增维护入口在固定47运行文件之外；Core/MCP/会话启动器及候选库存没有因此改字节，不重新标记 manifest 的来源提交。口令、U盘确认、实际管理员操作、关机→开机及手机/claude.ai 真人步骤继续叫本人。正式前段失败按既定退回；原库替换、head推进或新写入开始后只向前修。

手机安装/改配置、PR10启用、47862退役、MCP程序更换均不在授权内。B线PR19已独立完成源码并暂停，不进入本轮固定包。

## 源码复核及本机验证（尚未现场）

两项独立复核问题已修：不适用的 kernel-object API 换为上述文件 API；失败时未证实的 owner/child ACL/字节状态记 null，完整最终或恢复复核通过才记不变。原 original.json 耐久写入后立即保持只读、拒写/删句柄并重核 SHA，到 finally 才释放。合成专测2/2、37断言通过：成功、拒绝条件、真实 rollback、rollback API失败、child ACL漂移、原恢复材料写失败零mutation、成功回执写失败实际rollback、根rename拒绝、硬链接拒绝或检测、恢复材料写拒绝。主窗整组与CI在完成后追加。

同 owner 的 ACL 并发变更不可能由数据共享句柄完全排他，采用漂移检测/恢复/停审；不宣称绝对阻止 hardlink 创建。现场签收必须同时满足进程退出0、最终返回 passed、完整 result.json 逐字段一致、没有 failure.json，及独立 owner/SDDL/三配置 hash/ACL复核。写回执失败可能留下不完整 result 文件，单看它不能放行。旧方案/原DACL/所有失败证据保留。

主窗维护整组54项：52通过、0失败、2特权opt-in未执行，41.733秒；新入口2项和37原生断言均实际执行。两项opt-in由既有Hosted Windows门禁强制执行，CI未全绿前不加固。
