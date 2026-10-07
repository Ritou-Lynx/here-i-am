## 2026-10-07 21:29（上海）最新结果：r02 Prepare 拒绝，已完整退回

单目录 settings 已按新授权加固成功，新只读演练零失败；六项批准外锚及实时父 SD 均未变，故按有条件预授权进入正式 r02。144项 Apply 成功后，正式 Prepare 在读取 ACL 回执时因 owner 为 Administrators 而非本人，报 `prepare_owner_rejected`。没有现场改 owner 重试。已真实恢复全144项原 owner/DACL/继承，复核原 raw 身份/字节、grant/replay、旧固定包和库存，再恢复旧任务原定义/权限，按 Core→MCP 启动并绑定完整树、schema4及三个端口。21:28:57退回签收通过。

**未完成切换，暂停待审。** 新任务不存在，候选从未启动，原库未迁移/替换，head未推进；四项真人Gate未执行。r02已消费，旧锁/回执全部保留，不得复用；下一轮须新的正式ID。单 settings 获批前置保留（f88d49ec…），生产 settings **不可清理**。完整证据和下一轮源码建议见[本轮授权及实录](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)。以下旧阶段的“r02未使用/零停机/尚未加固”均仅为当时历史，不覆盖本节。

## 2026-10-07 新授权：单目录前置及有条件 r02（优先于历史记录）

用户已授权先将单目录 settings DACL 执行入口/测试纳入 PR20、CI 全绿后，仅关闭继承并保留既有ACE；加固成功后新ID完整只读重演，包含模板逐字、PR16在线副本和结束全套复核。全套零失败且 manifest/XML/双SDDL/父SD/login 原批准hash全部不变，可直接按预授权用r02执行④–⑥；任何现场失败或偏差就停审，不进场。实际管理员/U盘/口令/关机及手机、claude.ai节点仍叫本人。此刻尚未执行加固或新演练。[本轮精确门槛和恢复判据](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)。下方“禁止改ACL/需另请进场”等为旧轮历史。

# R02 后进程映像修订与完整只读演练

## 当前结论（优先于下文阶段记录）

源码和CI完成，完整现役只读演练**未通过**。第三轮发现获批login.json父目录仍继承ACL，违反固定生产Prepare要求；不是只读helper额外限制。现有144项计划不含该目录，本轮禁止改生产ACL，故停在只读门槛，不申请正式进场。三个失败窗口及证据保留，正式r02未使用，旧Core/MCP继续Running/schema4，人为停机0。

## 范围与状态

用户要求先修进程映像校验、源码/CI全绿后固定新维护快照，在现役仅做只读演练，全部通过才申请正式进场。本轮不合并、不进正式r02、不部署；R02零停机记录已独立提交。此前精确批准的XML/双SDDL/父SD/login/candidate不因此自动变更。

## 源码与安全边界

- 普通Pin无任何系统PowerShell例外，数据/配置/发行包/密钥/状态/回执始终要求单硬链接。映像专用Pin持柄核完整实际路径/hash；系统根由GetWindowsDirectory取得，系统映像必须TrustedInstaller owner。真实PID通过同一个OpenProcess handle核创建时间及QueryFullProcessImageName；CIM仅容差9个100ns ticks。
- 维护v3配置，Execute/PreflightOnly互斥。只读ID与formalWindowId不同，独立rehearsals目录保存证据，主根共享字节不变guard仅防并发，不消费r02。
- 正式与演练共用候选/任务/进程/端口/ACL/审批/USB备份检查；演练再运行PR16在线copy，前后重核完整身份。仅合成/演练输出写入新私有目录，没有生产配置写入。
- 系统硬链接放宽仅用于映像角色；候选47文件仍全部strictPin。Core、MCP、会话启动器和release_schema6运行源码本轮零改动。

## Prepare的准确含义

加固前固定PrepareOnly会因实际state/i_memory ACL尚未Apply而拒绝，这是保留的生产门槛。只读演练从manifest-pinned固定源码抽取独立审阅hash钉住的纯XML模板，核全部声明配置和精确待Apply库存，用本机COM NewTask内存对象核兼容，并逐字比对批准XML。没有注册或执行真实任务。

演练报告明确productionPrepareInvoked=false、productionPrepareStillRequiresAclApply=true、prepareTemplateBytesEqual=true；它不生成或冒用冻结、ACL Apply、正式Prepare成功回执。正式现场仍要实际Apply后执行受守卫Prepare。

## 演练检查清单

| 检查 | 拒绝条件 |
|---|---|
| 候选47项 | 库存/hash/size/来源不符；任何普通文件多硬链接或链接路径 |
| USB/备份 | 非NTFS（usb_ntfs_required_do_not_format，绝不格式化）、卷UUID/USB serial/model不符、密文两端hash不符、九类缺项、只有hash而无真实restore证据 |
| 两旧任务/完整树/端口 | XML四段/SDDL/Enabled/单实例/EnginePID、全部PID创建时间/实际路径/hash、端口所有者不符 |
| ACL | 精确144路径集合、owner/DACL/继承与基线不符；16外owner不符；任何文件多硬链接 |
| XML/SDDL | exact hash、父SD、继承推导、外主体rights披露、COM内存roundtrip不符 |
| 在线副本 | DB/WAL字节/大小/身份变化、journal出现、SHM存在性/大小变化；仅在线忽略SHM内容，离线四件不放宽 |
| 结束复核 | task/完整tree/DB FileId/ACL/父SD/pins变化；失败不产生通过回执 |

## 自动验证

映像专项：本机Windows真实conhost hardlink_count=2只读通过；30个断言，包括路径/hash/owner/别名/reparse/租约/CIM时间/PID复用/退出拒绝。只读分支测试实际执行源AST，在正常/失败两条路径后设置mutation trap，均零调用；data/config双硬链接拒绝。USB身份/九类/实际restore门槛反例通过。审批专项用合成144项、真实COM内存对象、纯模板逐字XML和流式密文hash；Windows CI自动发现maintenance_*.test.mjs。

本机维护+在线copy整组55项：53通过、0失败、2项opt-in未执行（foreign-owner提升与真实COM注册留Hosted Windows一次性VM）。新增维护专项全部执行，映像30断言、合成ACL144/模板与备份、只读dispatch和三个真实fixed-release在线copy适配场景通过；合成writer仍存活，DB/WAL不变、SHM读标记offset104变化，72审批/1grant对齐。CI、新维护快照与现役演练结果在完成后追加；此时不声明已演练通过。

## 现场与授权

正式入口仍为未使用cutover-retry-20261007-r02。沿用获批候选须逐47库存与源码对照，沿用XML/双SDDL须重核原hash；任何变化必须说明并重新审批。task-approval…\settings属于生产配置、不可清理。演练全过不等于进场授权；本轮完成后暂停交审核。

## 第一轮真实只读演练：安全拒绝并修正

源码27069c31的15项CI全绿（push37607610743/PR37607614065/policy37607611585），维护52/52、Windows整包283/283均0未执行。固定24项维护快照manifest452a7244…后执行独立readonly-20261007-e7907e724752。候选/映像/完整旧任务树已绑定，在演练文件初始化处报new_empty_directory_required：窗口已含entry.lock/phase-receipts，不得交给只接受空目录的固定保护函数。没有进入ACL审核、模板输出或在线SQL副本阶段，不能记作全套演练通过。

失败回执rollback.attempted=false、noMigrationOrReplacementPerformed=true；只读回查两旧任务仍Running、Core仍schema4，正式r02目录不存在。保留旧演练锁/回执/输入/维护快照，不删不复用。修订只在窗口内新建空copy-validation和prepare-template子目录并分别保护，窗口原ACL及现役144项不变；用真实Open-MaintenanceWindow及固定Protect-NewDirectory补回归，验证非空父目录拒绝、两个新子目录保护正确、父ACL/旧证据不变、重复子目录拒绝。修正提交CI全绿后新ID重试，正式进场仍不在本轮范围。

独立复核又发现正式后续ACL Apply要求windowDirectory自身是protected DACL。Open-MaintenanceWindow现在只在刚创建且仍为空时初始化该新窗口的owner/三主体protected DACL，再写entry.lock/phase-receipts；已有根、旧窗口、旧锁和回执不改。追加合成测试抽取实际ACL Apply的Assert-PrivateDirectory验证新窗口可承接正式流程，并证明现有根/旧证据ACL不变、非空窗口不可重新保护。这不改生产144项ACL或任何固定运行字节；新维护快照纳入该模块修订。

## 最终源码与CI证据

维护源码62104abd7893cb03f6c719771fa5daa15f9b0a65，草稿[PR20](https://github.com/Ritou-Lynx/here-i-am/pull/20)。15项检查均completed/success，attempt=1：

- [Push CI 37612656051](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37612656051)
- [PR CI 37612661999](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37612661999)
- [Policy 37612659417](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37612659417)

两端维护52/52、Windows整包283/283，均0失败、0跳过。本机最终维护整组52项：50通过、0失败、2特权opt-in未执行，Hosted已实际补齐。新增窗口/正式ACL消费者专项4/4通过。PR20不合并。

固定维护24项source manifest SHA256：4bdfdfc87e5bc626086c674aadc1845c2029158727d7489db39fea04c4b5aef0。
CI回执SHA256：29883ae981efec2631564a799b4cd468c0ae9d4de19793b9f3379f610915f656。
两次621快照源字节及manifest相同，各自新目录/新输入；未复用锁和回执。

## 第二、三轮现役只读演练

| 独立窗口ID | 拒绝 | 耗时 | 失败回执SHA256 |
|---|---|---:|---|
| readonly-20261007-49b3cf9b5514 | task_policy_disclosure_changed | 29.761秒 | d4d571a8253c506cde065a7441cf77064fc1ad4adba8ceee8cd184b20c8fd295 |
| readonly-20261007-133c99c0837b | preflight_protected_owner_or_root_rejected | 58.801秒 | b84dc1707ba0e03c034bc31ba5033253144d3ad0dda7f88bd027f1bb8950a4a1 |

第二轮是本机输入生成器问题：历史零外SID显示文件仅2字节空白，包装ReadJson的null得到含null的一项数组，严格策略按预期拒绝。改为用固定快照内纯策略从获批expected SDDL推导数组，严格要求零外主体，并用ConvertTo-Json -InputObject验证空数组往返。显示文件、SDDL/XML/login及维护源码均未改，相同绿源码的新ID重试；未放宽生产数组/逐项比对。

第三轮已执行候选47项核验、旧任务/端口/完整树绑定（Core 3、MCP 4进程，含系统子进程）、ACL144/16外owner、审批/COM内存比对、USB/九类备份及已有真实还原证据核验；随后Prepare父目录权限拒绝。**未生成模板成功回执，未执行在线SQLite复制/副本迁移，未完成结束全套复核**。58.801秒不是关机/关闭性能指标。

三个失败均rollback.attempted=false、noMigrationOrReplacementPerformed=true，无preflight-only通过回执。失败后两旧任务仍Enabled/Running，Core health schema4，正式windows/cutover-retry-20261007-r02不存在。没有停/启/冻任务进程、现役ACL Apply、生产配置写入、注册、原库升级/替换、head推进或手机/隧道操作。只写新私有快照/演练输入/证据目录。

## 真实阻断：生产配置父目录不满足固定Prepare要求

精确目录：

D:\HereIAmRuntime\i-core\maintenance\cutover-20261007-1552e251\task-approval-c9662439-3fb4b5c51a0f467cbd1ec3c1c18aee73\settings

只读metadata：当前用户owner；外主体Allow规则0；AreAccessRulesProtected=false；仅3份配置；不在原state/i_memory两根的144项快照内。其余要求protected的control-root、backup-key、release、MCP source/identity/state及原settings根均符合。

固定login_schema6.ps1:93–94对login父目录调用Assert-ProtectedPath -Root；固定protected_paths.ps1:14拒绝继承；prepare_login_schema6.ps1:89的ValidateOnly先经过该检查。因此正式Prepare同样失败。只读helper preflight_approval_checks.ps1:164复用同一要求；ACL Apply仅处理原快照行，不能自动补此目录。独立复核确认：保持批准路径/144计划/guards时，没有源码-only合法修法；改路径会改获批XML。不得悄悄计入144、假定已Apply或放宽Root要求。

## 待另行授权的最小处理（未执行）

建议保持路径、文件字节、owner和本人/SYSTEM/Administrators三主体FullControl，**仅给上述单个settings目录关闭继承，保留既有ACE为显式规则**。它仍是生产配置、不可清理/移动/改名。这是额外生产ACL变更，超出本轮“只读、不改ACL”授权，必须另审另批；原144项ACL加固、停服、注册和切换不随此放行。

精确未执行方案保存在第三轮rehearsal-inputs目录的production-settings-acl-proposal.json，含目录/3文件原ACL、文件hash与拟议目录DACL。真实SID仅本机私有证据，不入仓库：

- 方案SHA256：11374854974b5994adc18e1afa35cf95eea56d57f074350db9f95c8017bf250d
- 当前目录SDDL SHA256：5533f773840e001c189ee3a054eaee09ec6d301fe3f8eb757b3cd582a2bd5de4
- 拟议目录SDDL SHA256：f88d49ec29c276b95fcc0040af2fa319251d10f063a79c0699d54c9f667a6e25

只在内存调用SetAccessRuleProtection(true,true)生成方案，**未调用Set-Acl**；读回确认现场DACL未变。实施前须将实际变更入口纳入受审源码/测试，核owner/原DACL/3文件单链接与hash并保存原ACL。成功判据：目录protected，owner/三主体权限保持，3配置字节相同，子文件无权限扩大。失败则恢复保存的原目录DACL，核3文件/子权限；不触原库/任务，无需启停服务。若字节或路径改变，不能沿用原XML批准。

| 配置文件 | 字节数 | 只读SHA256 |
|---|---:|---|
| core.json | 1455 | cc5f8a42f31a18b72d8dba28559d1a4a01300ea875e117d61e9928deb9f4722c |
| daily-backup-config.json | 68662 | d33106d26cf4c6e7c7f54e007e84bda869c0ce9c7b75a1377d98b321e4387cb5 |
| login.json | 1465 | 28c5b700b98815b57b57e4cc9430f16ee8ef5ba8bdc3a1a08f854873965e1e00 |

补齐该现场前置后，须再用新只读ID完整跑模板逐字、PR16在线副本和结束复核，才能申请正式进场；当前没有放行结论。

## 批准工件与B线

固定47运行文件零改动，沿用manifest 3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0，不重建或改source_commit标签。获批XML4bc64357…、双SDDL50398e9f…/9d1a0c17…、父SD330eb3ab…及login完整hash保持。Core/MCP/启动器字节不变；原144项及额外目录均未Apply。

B[PR19](https://github.com/Ritou-Lynx/here-i-am/pull/19)最终源码cf2f6d57d58626a7cbf03904625c809e0f034842已推并暂停，主窗独立核实Push37611138795/PR37611145743/Policy37611141576均completed/success。16个Core运行文件及固定包/新入口依赖评估属于未来上线，不进入本轮47候选/维护快照；MCP换包、手机安装、上传器和47862仍须另审。B源码绿不等于主窗完成上线验收。
