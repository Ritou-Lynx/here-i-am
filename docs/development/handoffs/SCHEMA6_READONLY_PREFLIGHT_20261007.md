# R02 后进程映像修订与完整只读演练

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
