# schema6 现场执行记录（2026-10-07，尝试后安全退回）

## 授权与当前状态

用户本轮已授权PR14普通合入v3-lab、从合并提交重建以及现场④–⑥：停用旧MCP任务、同字节MCP纳入交互式会话、注册本人批准的登录任务、关闭邮件debug，并作MCP真实请求后的真人关机→开机验收。本人输入口令、选择U盘、批准实际XML、关机开机、手机与claude.ai测试须逐步停下交本人。手机安装/配置、PR10上传器、47862退役、MCP程序更换明确排除。

本人已批准最终审阅XML及管理员权限预检，真实外SID owner恢复演练成功。10:33开始④的旧任务冻结并停止MCP，在线副本捕获因SHM摘要变化被拒绝；10:34已自动恢复旧任务和MCP。Core全程未停，仍为schema4；未Apply现役ACL、未固定Prepare/注册新任务、未迁移/替换原库，未生成生产head。10:36独立复核两旧任务的Actions/Principals/Triggers/Settings和SDDL逐项等于原定义、各一实例，47841/47860/47862恢复、MCP元数据HTTP200。本次切换暂停，详见下节；下方准备阶段描述按历史证据理解。

## 合并、候选和合成Gate

- PR14合并：`1552e251c18c4554d425a0051ea7452e4904bb40`；与审核head `aba12d60628efc89c6bd0034e1d958c6186e7800`的树diff为空，正式副本只快进。
- 合并提交的Git树重建47项，先核库存再保护新空release根、复制并重新核hash/ACL。候选目录：`D:\HereIAmRuntime\i-core\releases\schema6-20261007-1552e251`。
- manifest外锚：`6ae8f970a08ee8f21f8c78ba8846273144101cbdd8d3a2cb0530d5a3daf6b1ff`；固定Node24.14.1。
- Core固定烟测23,095ms通过，schema6真实回环、认证关闭、child/guardian exit0、Job空及锁释放均成立。
- 旧MCP同字节真实请求/开库、先停MCP再Core、独占重开及下次登录读回通过，63,675.3ms；完整关闭4,822.459ms，再次4,804.819ms，MCP有限宽限后owned Job强停3,044ms。合成Gate不替代现役或真人关机。
- PR合并前Checks全绿。合并提交1552e251本次查询6项post-merge checks全部success、0失败；PR合并前全部checks通过，二者分别记录。

## 当次只读副本预检

固定release的captureConsistentSqlite以只读事务/SQLite backup生成A，保留不改。新B仅调用公共4→5迁移，核自身路径binding、空claim、旧表DDL/全行/序号digest保全。固定preflight实际核外置与耐久exact72、逐条消息digest/event/sequence、当前android token与1 grant和无冲突reply jobs，全部通过。捕获前后原DB/WAL/SHM/journal存在性、size和hash集合相同，外置文件源与副本相同；没有业务正文/凭据输出。

B的独立闭合副本经公共validateDomainMigrationCopy核5→6、integrity、旧表/源binding/floor、12个domain表；验证scratch为backup_read_only并已清理，B/C不激活。copy floor只来自本次新建空activity谱系，不为既有5/6签生产authority。

停机前须重核现场输入，冻结后原四件或外置授权变化则本次预检不用来放行，不执行新Start。固定Start仍负责真实独占离线证明、任何SQLite前raw流式加密保全、副本迁移/immutable检查和pending短提交；不得伪造Native lease或把副本预检说成已接管。

## 私有准备及待闭合项

私有根：`D:\HereIAmRuntime\i-core\maintenance\cutover-20261007-1552e251`，新建后保护ACL；真实副本、配置、DPAPI钥匙、原始回执不入Git。

已准备独立recovery/backup两把CurrentUser DPAPI钥匙、空custody/control/备份根和未激活Core/MCP配置。尚无生产current-head。Core保持legacy_b3单上传器、reply/activity关闭、owner_managed、mail relay null；旧SMTP配置、凭据和journal保留。

MCP六文件快照保留原字节与import布局，server仍`adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6`；原OAuth/frontend/phone token、writeback和logs .state原位使用。跨项目.i根有非白名单权限而未修改，新受保护I_HOME只放同字节identity.json。身份投影固定于复制时，原投影未来更新不自动传播，须显式核hash刷新；不称动态身份源。

只读核验发现原Core state/文件及i_memory DB/policy未满足固定ACL门禁。切换准备须先保全精确旧ACL，再收紧受影响state/文件及未来新文件继承，核回退可恢复；不放宽生产检查、不改跨项目.i。

当次九类备份、口令包/认证绑定及NTFS镜像已完成，详见下节。历史52项真实恢复只作历史证据，不代替本次raw保全；历史手机schema62副本按现有认证密文提取，无须重新ADB。恢复新用户现役Core仍是已记录的下一轮缺口。

本人已明确选择T:，核Samsung PSSD T9 / USB / NTFS / Healthy，目标T:\HereIAmRecovery-20261007-1552e251；未格式化或改已有资料。本人第四次完成固定SecureString两遍输入，最低16 UTF-8 bytes检查未降低，口令不进聊天/日志。最终审阅XML已获本人批准；仍须固定PrepareOnly成功且输出逐字相同后才可注册，本次未到该阶段。

## 当次USB备份与真实恢复（10:02–10:03上海）

固定公共API先只读捕获现役schema4 baseline，归档和恢复指纹统一绑定该冻结副本。其他组件各自一致，跨组件不是共同原子快照。活跃原文件前后观察变化，不据此认定本驱动写入，也不将本档案当停机raw保全；切换前重核预检与冻结原件，固定Start仍执行任何SQLite前真实离线raw加密。

输入114项，API追加归档context/capture-window后116项。九类逐项：database1、旧release10、configuration81、task2、credentials8、domain_policy3、transcript_grants1、replay_approvals1、recovery_custody9。包含MCP OAuth/frontend/phone token与writeback账本、i_memory policy/库/快照、完整grant与72项replay、隧道/Serve查询导出、原ACL、认证旧档案提取的手机schema62副本、新固定候选/MCP配置/源码及独立两把DPAPI钥匙。Tailscale机器私钥按本人决定不备份；此时没有生产current-head，不能虚构已保全。

密文SHA256：d2411fd63d839460c784d64de792dd7ab1d51278814e9845bcad45c1ec9a6ef5。口令envelope SHA256：57d928297fc89b5dde963d2b0b76e9f3c1972f5fa4ea183643eb8d49d7401521。backupSet/keyId绑定通过，T盘predeploy的密文/envelope/portable-binding/认证receipt逐文件核对。本机/USB日常备份另用daily根、30天保留；切换档案单独长期保留，不由日常prune删除。

从T盘真实提取并启动Core inspection_read_only：health200、schema4、node前缀9d634309、设备7；8表数量/指纹与baseline相同，chat_messages/change_events各7015、reply jobs/shadow各0；5条业务探针403。库字节/文件身份不变、无sidecars。总44,098ms，指纹9ac9645ec096ac2f3c5a41e7513c3a7c154399984ff1eb29c93978d10c07c732。

本次USB恢复用本机DPAPI解锁key，不是本次跨用户口令-only还原；portable绑定当次核验、已审核跨用户CI分别记录。详细回执/路径/hash/临时驱动仅在私有根，不入Git；手机副本未重新ADB。

## 权限与本人Gate

ACL快照144项：Core state60、i_memory state84；其中16个Core项owner为旧账户。普通token没有SeRestore/SeTakeOwnership；单向取owner会留下不能还原旧owner的风险。已生成限定两state、只改owner/DACL/继承、不改组/SACL/内容、含回退的管理员脚本；语法/辅助声明编译通过；8项合成对象的加固/恢复继承/部分失败回退已通过，hash/身份/大小/最后写入/Group均不变。真实外SID恢复及提升已由本人批准并在独立临时文件验证成功；passed、SeRestore启用、foreign owner往返及最终readback均成立，未触及现役。管理员创建的预检回执默认owner为Administrators，后仅将此新回执归还本人且hash不变；不代表现役144项ACL已Apply。

daily/login配置哈希匹配但未启用；daily用于未来schema6，必需current-head尚不存在，不能现在运行。固定PrepareOnly依赖原state与memory叶ACL通过。已用固定构造及Windows PS5.1准备仅审阅XML，SHA256 7de2a122a782c509cad3a89304bce5ba88e03c607583eb62a17d9b57ee183a05，任务名HereIAm-CoreSchema6-Session；已交本人审批。以后仅当固定PrepareOnly成功且同字节才可注册，审阅产物本身不可注册。daily输入118项，额外包含未来新登录配置/备份配置/任务XML；当前head与正式XML两项尚不存在，不运行。准备时0停机；随后本次MCP短暂停止并已恢复，Core未停、原库仍schema4，手机未操作。


## 10:33现场尝试与安全退回（本次停止点）

本人批准XML SHA256 7de2a122a782c509cad3a89304bce5ba88e03c607583eb62a17d9b57ee183a05及管理员预检。管理员预检只在新合成文件实际启用SeRestorePrivilege并完成当前owner→旧SID→原owner/DACL的真实往返，原文件hash与最终readback通过，生产路径未触及。

先前两次均在任何现役mutation前拒绝：第一次private_owner（新管理员预检回执owner默认Administrators，已限定该回执归还用户且字节未变）；第二次PowerShell5.1单个COM任务实例被管道解包，StrictMode访问Count失败。仅修三处Instances调用为数组，PS5.1解析、0/1/2实例合成及全部只读预检通过，独审精确逆向diff核对；失败锁和阶段回执均保留，没有盲清锁。最终冻结helper SHA256 b0530b590b4e824a68e3680b45490cc5488670cc981ddd059d2e007c600c986c，生产固定包字节未改。

本次唯一实际停机尝试：

| 上海时间 | 实际操作与判据 |
|---|---|
| 10:33:22–10:33:24 | 旧两任务禁用，移除触发/失败重试，保留Action/Principal/SDDL；原Core进程仍运行。 |
| 10:33:29–10:33:38 | 精确任务实例、PID/创建时间/镜像/父子树绑定后停止旧MCP，确认树/实例/47860和47862退出。 |
| 10:33:38–10:33:43 | 只读一致副本捕获前后raw集合比较失败，错误raw_input_changed_during_capture；没有进入隔离4→5验证、停止Core或后续阶段。 |
| 10:33:43–10:34:01 | 按用户“任何一步不满足完成判据就退回”分支恢复原两任务定义/启用状态，Core旧进程继续运行；重新拉起旧MCP并核树/端口。 |
| 10:36:42 | 主窗独立复核原任务四组XML语义及SDDL完全相同、各一实例；Core schema4/原PID未变，MCP元数据HTTP200，三端口正确绑定；无新任务、frozen ready或current-head。 |

整次执行52.423秒。MCP停止意图至旧任务/端口恢复确认窗口31.753秒；没有连续HTTP采样，不能等同精确MCP不可用时长。Core未停，本次不属于30秒新会话关机Gate，也不构成旧v4 clean_closed证明。

文件差异仅SHM的SHA256变化：DB存在/10,596,352字节/hash不变；WAL存在/4,144,752字节/hash不变；SHM存在/32,768字节、hash改变；journal前后均不存在。SHM前3b0d6a9a6750a650e6f2c9ff374768bb180bd17d2c81dd97a0005b2e0ef118e5，后9647c038bf426f02423f5557d9bd0bca433f6eac868166e4bd511888b355e7d7。缺少before字节，不能认定是锁页、read mark或某个写入者；不据DB/WAL稳定就放行或忽略SHM。

本次未修改现役ACL/线上配置、未固定Prepare/注册登录任务、未开启新Core、未原库迁移/替换、未产生生产custody head；Cloudflare/Tailscale、手机、PR10和47862桥配置均未变。旧MCP程序字节未更换。原程序恢复，不需要本人现在关机。原始拒绝及安全退回回执只留私有维护根，不入Git；安全退回回执名cutover-safely-reverted.json。

此前曾提出“先停Core再文件复制”的候选设想，尚未实现或执行；用户随后明确要求先合成证实SHM原因。本轮已证实读连接可改变SHM，按获准范围修正在线比较，不采用该停机复制设想。原现场逐字节证据不足，仍不能反推当次具体SHM字节变化。

待部署辅助RegisterOnly脚本仅新建于私有维护根，纯mock/XML检查通过但仍待独审及真实COM核验，未执行、未注册。权限维护窗口同样未运行。保留这两份草稿不代表现场通过。

## 真人Gate与失败边界

以下均未做，四项全过才算切换完成：

1. 新会话MCP真实i_recall/i_chat_turn后本人正常关机，核MCP退出、Core clean_closed及共同30秒回执。
2. 本人开机登录，获批任务自动新control/RunId启动Core→MCP，再实际MCP请求。
3. 手机正常同步，原sync_id/op_id去重、单上传器，47862单消费者保留。
4. claude.ai真实公网写入获耐久接受，pending完成。

替换前判据不满足按清单恢复旧v4/MCP；一旦commitStarted、替换原库/推进head或新Core写入，保全并向前修，不降旧库、不删pending。


## 现场退回后的源码修复（本轮不再进入现场）

新分支 codex/schema6-online-shm-preflight-20261007 从 v3-lab@1552e251 开出，只写源码、合成测试和文档，推草稿PR后暂停审核。不查询/操作现役Core、MCP、隧道、原库、任务或手机；固定47项runtime字节不改，私有现场执行器也不更新。本节取代此前“下一轮先评估停机复制”的方向。

### 合成原因证据

[完整复现报告](SCHEMA6_SHM_REPRODUCTION_20261007.md)使用既定Node24.14.1/SQLite3.51.2和原固定release真实captureConsistentSqlite。独立writer提交后封住SQL入口，只用IPC保活，无后台写入；三次全新根均只改SHM offset104，aReadMark[1]由2到3，DB/WAL存在、大小、SHA256和dev/ino全不变。独立readOnly连接仅执行一次SELECT的三次对照相同。没有其他进程的两组对照（writer正常退出、强杀后保留WAL）也各三次，分别观察到新建sidecars和SHM重建头部/读标记，详细区别不混称“仅锁页变化”。

SQLite官方[WAL文件格式](https://www.sqlite.org/walformat.html#the_wal_index_or_shm_file)说明SHM是WAL索引和协调状态，不存持久数据库数据，可从WAL重建；[锁与read-mark](https://www.sqlite.org/walformat.html#how_the_various_locks_are_used)说明读者会在取得读锁时更新read-mark。普通可写wal-index场景中，即使数据库连接readOnly，读者仍可写SHM；这不表示所有SQLite只读场景必然改SHM。另见[共享内存临时文件](https://www.sqlite.org/tempfiles.html#shared_memory_files)。本次实测支持修改在线比较前提，不证明原现场恰好改变了同一字节；原现场before字节没有留存。

### 唯一放宽点：在线副本输入比较

原拒绝比较只存在于私有现场驱动，不属于固定runtime。本分支将这一段副本预检形成可复核源码 tools/i_core/maintenance/precutover_validate_copy.mjs，实际调用同目录 online_preflight_input_guard.mjs；仍先验证固定release，再加载其未改的capture/迁移/preflight。没有默认真实路径，输出须新空、与源/授权/release隔离且通过固定私有ACL断言。

| 输入 | 在线复制前后判据 |
|---|---|
| DB、WAL | 路径、存在、大小、文件身份、SHA256全相同；读取哈希期间文件变化也拒绝。 |
| SHM | 存在性和大小相同；不比较内容及读标记。 |
| journal | 存在性相同；新出现或消失均拒绝。 |

四件诊断SHA和身份仍记录在私有回执；SHM/journal hash只是诊断，不参与在线判定。rawStable:true表示上述online comparison_policy通过，绝不表示四件全字节相等。拒绝回执保留before/after诊断。数据/release的plainPath/hardlink/ACL检查未变；系统PowerShell入口沿用固定lifecycle的SystemRoot绝对入口，不使用PATH查找。

冻结之后的原件证明仍核四件完整字节，原始流式加密仍原样保存存在的SHM内容；strictClosedPath、NativeLease、恢复custody、迁移和幂等门禁均未改。在线回执不能替代离线证明，也不能因rawStable=true跳过冻结原件/独占检查。

### 本机验证及交付

固定release四组各三次（12场景）全部通过，合成结果JSON及hash见复现报告。新比较器17项覆盖SHM同大小改内容放行；DB/WAL同大小改一字节、大小变化、同内容换身份拒绝；journal出现/消失拒绝；SHM大小/存在变化、WAL出现/消失、四件hardlink及畸形观察拒绝。固定release真实副本适配器3/3通过（直接调用、缺grant拒绝、真实CLI）；合成原件schema4不变，副本4→5、exact72及1 grant通过。随后使用Git HEAD新建固定包的相同3场景亦通过，不依赖本机release路径。主窗新比较器、默认四场景复现、Git新包适配器和相邻portable_automatic/release汇总67/67通过，0失败/跳过，103,953.7846ms；全部新代码以同一工作树字节验证。本机合成日志仅在忽略的build/ci/online-shm-preflight-local.log。没有运行App构建或现场命令；远端精确提交全项CI由草稿PR Checks及正文最终回执登记，不借用PR14旧绿。

首轮汇总67项中64过、3个新适配器在复制前因系统PowerShell nlink=2被数据plainPath误拒绝；OS文件canonical不变且非symlink。新适配器改为与固定configuration/offline_lease一致的SystemRoot入口，未修改plainPath函数或数据/sidecar/release调用。失败记录保留，不跳过或屏蔽测试。

下次现场仍须另建一次性私有维护入口/配置，按已审核源码固定hash并验证调用关系、回执路径与冻结helper的依赖锚。新CLI为 --config 私有JSON（releaseDirectory、manifestSha256、databasePath、approvalsPath、grantsPath、outputDirectory），不是旧驱动参数的直接替代；本轮没有重写私有helper或重用旧锁。新source PR审核通过不等于现场入口已经闭合，更不授权重进现场。

### ACL未做项

[现场清单](SCHEMA6_CUTOVER_FIELD_CHECKLIST_20261006.md)及[ACL复核](SCHEMA6_ACL_SEQUENCE_REVIEW_20261007.md)列明：在线预检通过 → 停Core/完整树与端口释放/65秒无respawn → 重核144项快照及文件内容 → 同SID管理员且SeRestore可用 → parent到child加固全部144项（含16旧owner）→ 全项权限、身份、大小、mtime和hash复核 → 固定PrepareOnly及批准XML逐字匹配 → 仅CREATE注册 → 固定Start。

Apply失败或替换前退回必须恢复全部144项owner/DACL/继承，不能只恢复已写项；再全项readback，最后先旧Core再旧MCP。若固定Start已生成pending等新文件，旧144项精确inventory回退会拒绝，须保持停写并补受审恢复方案，不删pending、不改常量绕过。出现commitStarted、原库替换、head推进或新写入则向前修。当前ACL未Apply；以上是下次窗口顺序，不声称新的全流程自动回退入口已经实现。
