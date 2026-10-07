# Schema6 r03 现场执行记录（2026-10-08）

> **最新状态（2026-10-08约00:32，北京时间）：自动备份出现已证实的ACL阻断，暂停真人Gate，切换未完成。** 新schema6/Core与同会话MCP继续健康运行，head已推进，后续只向前修。受审备份配置文件未满足固定key-custody的protected/仅本人+SYSTEM要求；只读纯断言复现`custody_acl_invalid`。拟议仅该文件DACL调整属于原144项之外的新ACL变更，**尚未执行，等待本人另行批准**；不把排查或拟议方案记为修复。四项真人Gate全待，10/09晚完整T9备份及真实还原仍待。
## 当前签收状态

**切换未完成。** r03 已完成真实旧任务冻结、先停旧 MCP、在线副本预检、再停旧 Core及连续观察；随后144项 ACL Apply通过，回执owner为本人；真实普通身份Prepare实际调用固定Prepare并成功，输出XML与批准字节一致。第二次UAC后，受审生产RegisterOnly完成CREATE与严格回读；主窗于00:24:22.739实际启动精确注册任务；固定恢复流程已完成schema4副本接管，独立head推进，pending清除；00:25:22确认原址schema6 ready及同会话MCP启动。**当前已跨原件替换/head提交边界，只能向前修；四项真人Gate仍待，不宣布切换完成**。不把CI、Prepare成功或文件出现当作部署完成。

窗口：`cutover-retry-20261007-r03`；维护源码：`a85dcf756aff406bc1c66c537353e76b13958ef1`。主窗确认本人于 **2026-10-08 00:10（北京时间）** 明确在电脑前继续。r02 已消费并完整退回的历史另见[前轮实录](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)，r03不复用其锁/回执。

用户截止仍为 **北京时间2026-10-09 18:00**：四项真人 Gate 全部完成才算切换完成；否则停止本轮推进，回上海再继续。截止不是强制降库许可。`commitStarted`、原库替换、head推进或新写入任一出现/无法排除，只能向前修；即使未替换，pending造成144项精确库存漂移也不得盲退 ACL 或启动旧v4。详见[完整现场链边界](SCHEMA6_POST_PREPARE_GATES_20261007.md)。

本记录worker只读取指定维护结构化回执、合成CI工件与主窗忽略日志，仅写本文。没有运行维护入口、SQL、任务/服务/手机动作；没有读取数据库正文、配置凭据或真实聊天。后续阶段按主窗新增证据更新，不预填成功。

## 精确源码 CI：八项完整成功，非生产验收

完整手动 CI [37642935026](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37642935026)绑定 `a85dcf756aff406bc1c66c537353e76b13958ef1`，主窗保存的结构化回执 `a85-complete-source-ci-20261008.json` 显示runConclusion=success、8个实际job全部completed/success，核验时间2026-10-08 00:06:48北京时间。

| ci.yml实际job | 结果 |
|---|---|
| Schema6 Windows lifecycle and backup | success；实际292/292，0失败/取消/跳过，1536788.8784ms |
| Schema6 Windows maintenance acceptance | success；实际61/61，0失败/取消/跳过，53114.9772ms |
| Schema6 elevated writer to ordinary owner pipeline | success；真实高完整性writer→同SID非提升consumer，Apply144/16、固定Prepare和安全合成COM往返，详见下段 |
| Schema6 password-only restore under another Windows user | success；另一Windows SID、password-only、dpapiUsed=false、inspectionOnly=true、activationSupported=false、cleanupConfirmed=true；不是另一实体电脑部署 |
| Flutter whiteboard + workbench (Linux) | success |
| Bridge Node tests (Linux) | success |
| Flutter full suite (Linux) | success |
| Windows build + whiteboard integration | success |

identity流水线结构化artifact实际 `passed=true`、`aclCount=144`、`foreignOwnerCount=16`、`fixedPrepare=true`、`registrationValidation=true`、`syntheticRegistered=true`、`comReadback=true`、`deleted=true`、`frozenTaskDeleted=true`、`consumerExit=0`；writer为高完整性/提升token，consumer为同SID中完整性/非管理员token。主窗已复核fixedPrepare两阶段退出0。**`syntheticOnly=true`、`productionRegisterOuterExecuted=false`**：成功的是Hosted合成流水线，不是本机生产注册入口或真实任务。该CI合成candidate manifest为`8029958e…02d36`，不可与生产批准`3b7e210b…147fa0`混称同一manifest。

主窗报告PR后台仍显示旧34582提交、push queued，为外部同步故障；独立 `pull_request_target` PRPolicy shadow 属informational，不在ci.yml八job之内。初版本地生成器误把它列为第九项，已按实际工作流纠正为八项；exactHead及全部实际job成功门禁保留，旧结果未伪造成新结果。生产检查与固定47运行文件未因此修改。PR同步未解决不抹去本次精确源码手动CI证据，也不能把CI扩大为本机四项真人验收。

## 新完整只读演练与批准外锚

新ID `readonly-20261007-001d00b21dd4`，正式目标r03；实际 **37460ms**、passed=true。日志 `build/ci/a85-readonly-001d00b21dd4.log` 中结构化结果由worker读取确认：

- ACL audit：精确144项、owner/DACL一致、16外owner，未Apply、未取得maintenance guard、未读取目标正文。
- XML/注册输入SDDL/继承预期SDDL/父SD批准绑定通过，本机COM内存往返通过；registered=false、started=false。
- 固定Prepare模板字节与批准XML完全一致；`productionPrepareInvoked=false`、`productionPrepareStillRequiresAclApply=true`，不能写成真实Prepare成功。
- NTFS/USB及卷身份、九类备份和既有真实还原核验通过；116项清单。内层archive验证为1对/2文件/932138708字节，本轮newBackupCreated=false、newRestorePerformed=false。
- PR16在线副本预检通过，validation receipt SHA256 `8a9d985e0eba9219fecb74ef851be67ccd0836fd2e98c4f7830f2f98c8e14836`。在线策略仍严格DB/WAL字节和身份、journal存在性、SHM存在性/大小；不是原址迁移。
- tasksUnchanged=true、processTreesBound=true、liveMutationPerformed=false、productionConfigurationWritten=false、formalEntryConsumed=false、deployed=false。

主窗通知于00:10再次实际计算六外锚，全部仍等于原批准值；该次六锚重算由主窗签收，本worker没有另读真实配置正文。

| 批准工件 | 固定SHA256 |
|---|---|
| candidate manifest | 3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0 |
| 最终XML | 4bc643571073b726fad4cc781785129a27a6c9b4a669ef9df1a621c5cebb397e |
| 注册输入SDDL文件 | 50398e9fe2ff2b2cbf62ee4ed31b703ddc21aff6339a0595963e2cb859915feb |
| 继承预期SDDL文件 | 9d1a0c172a55d1ac6ee5a8a831793abde4cd6b7252258329688283f3bc593580 |
| 父SD文件 | 330eb3abb433de72e6efae43075cd7440976dae310f7d55da2717626b38b880d |
| login.json | 28c5b700b98815b57b57e4cc9430f16ee8ef5ba8bdc3a1a08f854873965e1e00 |

维护快照相对维护根为 `staging/maintenance-source-a85dcf75-001d00b21dd4`，本轮输入为 `rehearsal-inputs-a85dcf75-001d00b21dd4`；仅定位已固定维护工件，不改固定运行包的source_commit标签。生产候选仍来自c9662439、固定47项，维护源码a85与其分开绑定。

## r03 真实冻结：已通过

主窗日志阶段严格顺序：read-only-approval-checks → disable-old-tasks → stop-mcp → validate-copy → stop-core → frozen-file-check → observe-65s → frozen-ready。日志末累计114139ms；这不是已确认的全外部请求不可用时长。

冻结回执：`windows/cutover-retry-20261007-r03/frozen-legacy-runtime-ready.json`（维护根相对路径），**SHA256 `845d1e24dcec44089ae7a1c274be873893d0debba664f1bc3dcb9cdf98c3526a`**。worker直接重算一致，读取白名单字段确认：

| 字段 | 实际值/边界 |
|---|---|
| format / passed | schema6-frozen-legacy-runtime-ready-v2 / true |
| ready时间 | 2026-10-07T16:13:05.0313322Z，即北京时间10-08 00:13:05.031 |
| expires时间 | 2026-10-07T16:43:05.0313322Z，即北京时间10-08 00:43:05.031；不可越期借用 |
| observationMs | 70530；连续观察超过65秒 |
| tasks / portsFree | 两旧任务；47841、47860、47862均空闲 |
| candidateSourceCommit | c96624397e52dfc569f8da263ff0644e0fca24f4 |
| candidateManifestSha256 | 3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0 |
| 本次冻结内在线副本验证SHA256 | 5b212047af0bbf8ccd8b4fef14a7aa0a8399651807b224b5f3aa7e900ca8429b；与之前readonly演练回执分开 |
| aclApplied | false，属于冻结生成时状态，不替代之后Apply回执 |
| databaseReplaced / schemaMigrationPerformed | false / false，冻结阶段未迁移替换原件 |
| legacyCleanCloseProven / nativeLeaseProven | false / false；冻结退出不伪称旧v4 clean-close或新native lease成功 |

截至该签收点，旧MCP先停、旧Core后停且未迁移替换。不能拿回执过期前“曾冻结”替代每个后续入口自己的实时冻结门禁。

## 真实 Apply144：已通过

本人已点第一次UAC“是”。主窗确认受审owner wrapper PID18516实际退出；该进程退出由主窗签收，本worker未操作进程。实际Apply于北京时间 **00:14:46.725–00:14:57.850**执行。

worker直接读取`windows/cutover-retry-20261007-r03/acl-apply.json`，重算SHA256 **`69ae4c49b25c5b439a50141ded96927ecb11aa61dbaeb18ceaef3d1011795861`**，并只读核owner等于当前本人SID（不输出SID）。回执`mode=Apply`、passed=true、verified_count=144、expected_count=144、expected_foreign_owner_count=16；432项分别为baseline_comparison/apply_owner_dacl/apply_readback各144，verified全true、code均为空字符串，rollback_attempted=false。inventory_verified/metadata_unchanged/freeze_verified全true，绑定冻结SHA845d…3526a及生产manifest3b7e…147fa0。

`target_contents_read=false`、`services_changed=false`、`tasks_changed=false`、`sacl_restored=false`。回执`raw_external_verified=false`须如实保留：Apply本身不是后续原件/外锚再次全检证明，不能从144权限通过推导所有后续门禁已闭合；真实Prepare仍执行自己的冻结/原件校验。

主窗已完成BindAclLogin，新绑定SHA256 `7a0bf7f7c1f1b2e1cf60aa8bd173cc380e75051ee5101f64dc74e09ba21a66ce`；此为主窗提供的绑定证据，本worker未读取其真实配置正文。r02回执owner不符的历史没有通过改旧owner重试来遮掩；r03生成新本人owner回执后才进入下一步。

## 真实普通 Prepare：已通过

主窗于北京时间 **00:17:54**签收实际普通身份Prepare进程exit0；不是test observer、不是只提取模板。这是主窗确认进程结果的时间，不将它误作文件创建时间。`login-prepare.json`文件元数据约00:16:58、prepared XML约00:16:55。

worker直接读取新窗口`login-prepare.json`与重算prepared XML摘要：

| 项目 | 实际证据 |
|---|---|
| 准备回执SHA256 | 4ea09cc55fa519e119c23c6a4bf4bf116ed96c797beb26701dc8f1f438de29f3 |
| format | schema6-production-login-prepare-v3 |
| passed / fixed_prepare_validated / identical_to_approved_xml | true / true / true |
| registered / started | false / false；Prepare不等于注册或启动 |
| 本次Apply绑定 | 69ae4c49b25c5b439a50141ded96927ecb11aa61dbaeb18ceaef3d1011795861 |
| 冻结绑定 | 845d1e24dcec44089ae7a1c274be873893d0debba664f1bc3dcb9cdf98c3526a |
| prepared XML实际SHA | 4bc643571073b726fad4cc781785129a27a6c9b4a669ef9df1a621c5cebb397e；逐字锚与批准XML一致 |
| login配置/两SDDL/父SD/manifest | 回执字段逐项等于上表原批准六锚 |
| 权限算法/其他只读主体 | windows-file-oi-v1 / inheritedReadOnlyPrincipals=[] |

至Prepare签收点，真实高权限Apply生成的新本人owner回执已经被生产普通Prepare消费并成功，registered/started仍为false。随后生产RegisterOnly的实际结果见下一节，不能将两个阶段回执混用。
## 生产 RegisterOnly：实际 CREATE 与严格回读通过

本人处理第二次UAC后，主窗确认该次子进程PID584实际退出。`windows/cutover-retry-20261007-r03/login-registration.json`已生成，文件写入时间北京时间 **00:22:05.921**；这是回执文件时间，不推定为整个任务链已启动的时间。

worker直接重算SHA256 **`4c78e3e251d23c69e8d5cd2f849ce47eaf4d2b989b4e309b7bcfc2c4ec57f179`**，只读核owner等于当前本人SID，读取白名单结构化结果：

| 项目 | 实际值 |
|---|---|
| format / passed | schema6-approved-login-registration-v3 / true |
| registered / started | **true / false** |
| old_tasks_changed / database_changed | false / false；仅指RegisterOnly此步骤 |
| actions / principals / triggers / settings / sddl_verified | 全true |
| frozen_rechecked / instances_zero | true / true |
| manifest / 两SDDL / 父SD | 原批准摘要全部一致 |
| inheritedReadOnlyPrincipals / count | [] / 0 |

主窗另外在普通身份通过真实COM复核：新任务 `enabled=true`、`state=3`（Ready）、`instances=0`，InteractiveToken=3、LeastPrivilege=0、Unified=true。此项实时COM复核由主窗执行，本记录worker没有操作任务COM。主窗确认六批准锚不变；worker本步只复核注册回执包含的manifest/双SDDL/父SD，XML/login沿用已核Prepare及主窗六锚复核。

这次属于**本机生产新任务实际注册通过**，不再只是Hosted安全合成COM证据；该注册回执仍是registered=true/started=false。之后显式启动的实际结果另见下一节，不能把RegisterOnly回执改写成已启动。旧任务继续冻结。
## 精确任务实际启动：00:24:50阶段记录

主窗报告北京时间 **00:24:22.739** 对精确获批任务执行一次`.Run(null)`成功，InstanceGuid=`{D40C22E0-2F28-4699-B8B2-23A24CDD1AE4}`、state=4（Running）。这是本轮获准的显式任务启动，**不是开机登录自动触发Gate**；本worker未调用任务API。

主窗只读确认本代 `session-c6034acb52324b2d93592a74a222f2ec` / `control-9264cfeeea12438e877b84b4f23b5f41`；`session-window.json`记录窗口PID20200、hook_ready=true、manifest为原批准值。固定supervisor38372、runtime Node46896、guardian38876当时运行。PID只用于这次回执关联，不是未来操作授权或长期存活证明。

**00:24:50** 发现`s6-recovery-pending.json`及`s6-copy-7400cf33-9a19-4d38-87fd-d5803a5684eb`，说明原址固定Start已经进入恢复/副本阶段，不能继续沿用“fixedStart尚未触原库”的早期描述。这些路径的出现本身不证明raw密文完整、复制/迁移已通过、原库已替换或head已提交。

该00:24:50阶段由主窗实时只读签收，当时本worker未读pending，未确认commitStarted或提交终态；主窗继续观察，不回退、不重复启动。pending/副本新增已经使早期“无新增项、144精确库存可直接恢复”的前提不能默认成立。随后的迁移/head/ready独立结构化复核见下一节；不删除pending、不盲恢复旧ACL或开启旧v4的边界保持。
## 原址schema6接管及同会话MCP：已ready，跨提交边界

主窗于北京时间 **00:25:22**直接读取新ready及原址health：schema6、预期node身份、runtime PID46896；47841由该Core监听，47860/47862由会话MCP PID1944监听。主窗确认pending已不存在、独立head于00:25:01推进。端口/health/pending缺席是主窗实时检查，本worker没有访问业务库或扩大state枚举。

本worker随后仅从主窗白名单读取本代`session-window.json`、`ready.json`、`mcp-start.json`、`recovery-custody/current-head.json`及指定recovery/floor回执，重算hash并提取结构化状态与相互绑定布尔值，不读stop.key、不输出token/认证值：

| 工件/结果 | 独立只读复核 |
|---|---|
| session-window.json | SHA256 `3cf37bad95b07ec1f6be3e8cc055232f21f76fd7f263bb95d3ff0d22ce04d133`；pid20200、hook_ready=true |
| ready.json | SHA256 `eb1f7b84cea465fad4b8e30fd85f82e078af81bcb3b78252303cfaddad6371a4`；schema_version=6、pid46896、127.0.0.1:47841 |
| 运行策略 | companion_upload_mode=legacy_b3、companion_reply_jobs=false、activity_enabled=false、domain_policy=owner_managed、commandline_secret_free=true |
| mcp-start.json | SHA256 `014202b297bcd3266e0558fb782a04d9dae41c7f60a2dde240454903edfbf2ba`；pid1944、core_pid46896、core_ready_bound=true、listen_port47860；core_token与ready token相同（只记布尔，不输出值） |
| manifest相互绑定 | window/ready/MCP/recovery event全部等于原批准3b7e…147fa0 |
| current-head.json | SHA256 `afe8d0842d57d1790df0dafbf81422327da5816ff9e6ec28b9ed0266e1d9bb35`；generation=1、previousHeadSha256=null、custodySha256=下列floor摘要 |
| recovery event | SHA256 `d5d3a95f4a256b8a61a9c1e1d120bd6178474a7d7015afaf160c1435c14e5250`；kind=schema4_copy_adoption，事件内部recoveredAtMs对应00:24:58.629，不误作后续head落盘/ready时间 |
| floor | SHA256 `8871b93121a9b87dddf4b01832cafda785fe2ec684918e1bfea4146a2f7d0a69`；schemaVersion=6、origin=schema4_copy_adoption、recoveryEventSha256等于上列event摘要 |
| head/event/floor身份与canonical路径 | 三者一致；head/event/floor receipt身份与本代ready token一致。只记比较布尔，不公开路径/身份值 |
| raw保全绑定 | recovery event引用rawManifestSha256=`966f42faddeebff613f91ad05b96b0ca07b30704f519160ff9c4d004c3df7ee8` |
| 提交时DB摘要 | floor记载`404462aad4e915b16cfad4830e4f53803dff9b6d85b25474a8568e171e392d61`；是该次提交证据，不能当作接受新写入后的在线当前DB摘要 |

这证明真实固定接管已越过副本准备并形成schema6 floor/current-head与ready链；worker仅核结构/hash/相互绑定，未持认证密钥重新计算MAC，也没有独立解密raw归档或读取业务库，不能把此次只读复核称为另做一次全数据恢复验证。原包/MCP字节及六批准锚仍按已批准范围保持。

**从此只向前修复。** 不因后续真人Gate失败、网络不可达或截止到来而恢复旧ACL后启动schema4，不还原旧DB/head，不删latch/marker。正常关机前仍须一次已授权真实MCP请求证明read model确实开库；本轮显式Run和health200不替代本人关机→开机登录、手机同步及claude.ai端到端写入。备份调度尚须单独回执，MCP启动不等于备份已成功。
## 自动备份ACL阻断：暂停Gate，单文件前修待批

### 真实失败证据与证据限度

本代`backup-status-fb0f3a63304744fc8a5db5c228f39260.json`实际记录`status=backup_worker_failed`、`success=false`。本worker直接重算SHA256 **`eb8b59d0b56fba4e80194bf0b14074d72ddd24ff6f8778d1a7cdb05cea3195a4`**；文件时间2026-10-07T16:25:09.8638172Z，即北京时间10-08 00:25:09.864；`next_attempt_utc=2026-10-08T16:25:09.8563164Z`，即北京时间 **10-09 00:25:09.856**。这是调度回执记载的下一次尝试时间，不代表已经重试或下次保证成功。

主窗在约00:32只读确认`daily-backups`为空、没有`.automatic.lock`，没有得到本次成功自动备份。该检查是明确时间点状态，不推断后来永不生成文件，也不把不存在lock称作备份完成。

已证实阻断来自两项相互独立证据：

1. 固定`key_custody.ps1:35–39`的`Assert-BackupPrivateAcl`强制目标ACL为protected，允许主体仅本人/SYSTEM。
2. 真实`daily-backup-config.json`的`AreAccessRulesProtected=false`，三条继承Allow ACE为本人/SYSTEM/Administrators；这个实际ACL必然被该断言拒绝。主窗用真实普通PS5只加载Library并调用纯Assert，实际复现`custody_acl_invalid`，`keyLoaded=false`、`workerInvoked=false`、`mutation=false`；独立审计得到相同结论。

这证明当前配置ACL与固定备份入口不兼容。**没有保存这次真实backup attempt的原始stderr，不能断言历史失败唯一根因已经被完整还原，也不能排除修复此ACL后还有其他拒绝条件。** 此次只读复现没有加载密钥、启动备份worker或改变配置，不算一次真实备份重试。

### 最小待批前修范围

仅拟调整**该单个daily-backup-config.json文件的DACL**为protected且仅本人/SYSTEM。这是原144项state/i_memory ACL清单之外的新生产权限变更；按用户“偏差停审”要求，必须本人明确另批。**当前未执行**，不自行继承原Apply授权，也不放宽固定`Assert-BackupPrivateAcl`或改47项runtime。

| 工件/拟议变更 | 精确绑定 |
|---|---|
| 配置内容SHA256（保持不变） | d33106d26cf4c6e7c7f54e007e84bda869c0ce9c7b75a1377d98b321e4387cb5 |
| 原DACL SHA256 | 0d36b0b74b4eae218cbdf0681514d2363bb721e548918d5742a1da525f71a841 |
| 拟议DACL SHA256 | 6b61fec3e35b247c9b5a067721dee36b5851847d0ddd4ca5353d0e7b2394dd72 |
| 拟议终态 | 文件protected，Allow仅本人/SYSTEM；不是settings目录整体ACL调整 |
| 执行状态 | 未执行；待本人另批。当前候选/配置内容hash不变不能自动授权DACL改变 |

完整SID/SDDL只在受保护本机审阅材料，不写入本文。`settings`仍是不可清理的生产配置目录；本次拟议单文件DACL不许可移动目录、重写XML/login内容、改手机、重签凭据或退回旧Core。

### 同时补记的真实只读证据

- 主窗真实raw manifest摘要仍为`966f42faddeebff613f91ad05b96b0ca07b30704f519160ff9c4d004c3df7ee8`；四件中3件present：DB **10,596,352B**、WAL **4,144,752B**、SHM **32,768B**，journal absent。这是本次原址接管的raw清单证据，不等于之后新的完整T9备份/真实还原，也不代表已再次解密全量原始文件。
- 主窗使用正确协议的debug-mail探针返回 **503 / shortcut_mail_disabled**，符合本候选关闭调试邮件的要求；MCP无鉴权探针返回 **401**。这些是对应协议边界证据，不是手机同步、真实MCP读库请求或claude.ai写入成功。
- 新schema6/Core和MCP保持健康运行，当前不关机、不重复启动、不恢复旧任务；因已替换/head推进，只能向前修。**暂停四项真人Gate**，不让备份阻断被健康接口通过掩盖。
- **10/09晚完整T9备份及真实还原仍待执行/签收**；不能以历史九类备份、CI跨用户还原、本次raw保全或失败调度回执代替。该未完成项与四真人Gate各自保留，不改写截止规则或提前标完成。
## 后续待签收，不预填成功

| 阶段 | 当前证据状态 | 放行所需证据 |
|---|---|---|
| 本人UAC / Apply144及16旧owner | 已通过，见上节新回执69ae…5861 | 该次权限结果不替代后续入口实时冻结/原件门禁 |
| 非提升正式Prepare→fixedPrepare | 已通过；实际普通进程exit0，新回执4ea0…29f3，XML原批准同字节 | registered=false、started=false；生产注册须另签收 |
| CREATE-only注册→严格回读 | 已通过；回执4c78…f179，registered=true/started=false；普通COM再次核零实例/Ready | 不等于启动或登录Gate；原任务继续冻结，后续需主窗启动精确获批任务 |
| 获批交互式任务→固定Start | 主窗已签收实际任务启动、hook_ready及固定三进程；本代session/control见上节 | 本次显式Run不是登录自动触发Gate；终态与恢复结果另验 |
| raw保全→副本4→5→6→提交/head→schema6 ready | 已实际schema4_copy_adoption、head generation1推进、schema6 ready；pending缺席由主窗签收 | 本worker仅白名单结构/hash绑定复核，未重复解密/SQL；已跨提交边界，只向前修 |
| 会话MCP与备份调度 | MCP健康；自动备份实际失败，配置ACL阻断已证实，单文件DACL前修待另批 | 不放宽固定检查；取得批准并修复后仍须真实备份结果，不能以MCP健康代替 |
| Gate 1 正常关机clean-close | 因备份阻断暂停，未执行/未签收 | 先一次真实MCP请求开read model，再本人关机；同30秒总预算MCP→备份→Core，Core child/guardian exit0、Job空、无Core force、clean_closed与锁释放齐全 |
| Gate 2 开机登录自动启动 | 因备份阻断暂停，未执行/未签收 | 本人登录后真实任务自动新RunId/control、schema6单实例、备份/MCP恢复并再次成功真实请求；手工启动不能替代 |
| Gate 3 手机同步 | 因备份阻断暂停，未执行/未签收 | 正常链路accepted、原sync_id/op_id去重与outbox保留/补交、单上传器/单消费者 |
| Gate 4 claude.ai公网写入 | 因备份阻断暂停，未执行/未签收 | 真实公网调用和Core耐久接受，pending完成；metadata/ready或waiting_for_retry不能替代 |

生产 `task-approval-…/settings` 是配置目录，**不可清理、移动或重命名**。原包与全部旧新证据保留；`legacy_b3`唯一上传器、PR10关闭、reply jobs/activity关闭、47862桥及单消费者保留、MCP原程序字节保持。手机安装/改配置、凭据重签、47862退役、重发邮件均无新增授权。

## 无正文证据索引

| 证据 | SHA256/定位 |
|---|---|
| r03冻结回执 | 845d1e24dcec44089ae7a1c274be873893d0debba664f1bc3dcb9cdf98c3526a |
| Hosted identity pipeline | 60697a179c3bdb9d56db195e73eed342305a8e57722509ef168e99630f34ecf6；忽略目录a85-hosted-schema6-identity-pipeline.json |
| Hosted identity startup | 6c16f5e47c3cbc6abf366696f34152db8265f8ec5e0005b25b28f423db32c956；忽略目录a85-hosted-schema6-identity-startup.json |
| 八job完整CI检查 | build/ci/a85-complete-source-ci-20261008.json；run37642935026，exactHead=a85dcf75 |
| maintenance61 / lifecycle292 | build/ci/a85-hosted-11492039749-schema6-windows.tap / a85-hosted-11494857510-schema6-windows.tap |
| 新只读演练/冻结阶段日志 | build/ci/a85-readonly-001d00b21dd4.log / a85-formal-r03-freeze.log |

真实SID、完整SDDL、私有配置内容、凭据及聊天正文不写入本文。以上最新状态为schema6/MCP健康运行、自动备份ACL阻断已证实、单文件前修待本人另批；真人Gate暂停，切换未完成，完整T9备份/真还原仍待。后续只按新的授权及回执增补。
## B线当前进度（独立、不进入本次运行包）

主窗于本轮读取独立窗口最新完成回执，并只读核对[PR19](https://github.com/Ritou-Lynx/here-i-am/pull/19)：精确head `cf2f6d57d58626a7cbf03904625c809e0f034842`，草稿open，14个当前check全部completed/success。B窗口报告P1四个缺口已在源码层面闭合，16个Core运行文件的改动清单待主窗评估；本轮没有把B源码带入47项固定候选，也没有换MCP包、装手机、切47862或开启PR10。B已暂停等审核；不能把源码CI当成上线或真人Gate结果。
