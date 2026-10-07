# PR14 大数据防回退与耗时验收（2026-10-06）

本轮只继续 codex/core-deploy-readiness-20261006 与同一草稿 [PR14](https://github.com/Ritou-Lynx/here-i-am/pull/14)，不合并、不部署。现役 Core/MCP/隧道、原库、实际任务、手机均未读取或操作；测试使用独立合成库、临时固定包和随机端口。前轮自动运行、口令备份和跨用户只读还原已获用户通过，本页只登记本轮新证据。

## 修复与能证明的范围

原 domainRecordWitness 把每条领域行存入外置 floor，超过16,384条主动拒绝；floor还有4MiB上限，安全关闭与随后恢复都会被同一条上限阻断。现在 progress witness升为v2，记录部分只保存固定字段 format/count/maxRevision/sha256。十六进制摘要固定64字符，计数和版本使用受限整数；记录/消息增长不会增加一条条外置见证。4MiB总格式防护保留，未放宽plainPath、ACL、原生离线租约或配置绑定。

摘要覆盖排序后的 namespace/domain/id 身份、revision和完整物化行HMAC。恢复不是单看最大版本：先认证真实receipt、op metadata及其完整结果承诺，再在旧domain_ops cutoff重建旧记录集合，要求其摘要等于外部封存值；随后重建最新承诺，与当前全部物化行双向逐项匹配。删除的recoverable状态、purge后的null正文、revision前进均须匹配认证操作结果。principal用于操作认证，记录身份不按principal拆开，因此另一principal的旧版本不能掩盖同记录回退。

以下情形拒绝：

- 已封存行缺失、revision下降、同revision正文/删除标志被改写；
- 有真实新receipt但把新行换回旧正文；
- 只抬revision、追加未认证accepted metadata，或同revision有相互冲突的认证承诺；
- 不可变消息/变更/op/receipt旧前缀被修改、删短，之后再追加更大MAX；
- 原库、旧marker和旧floor一起还原，却与库外current-head不符。

合法编辑→删除→retention purge持续前进，设备合法重新配对仍允许。旧prefix的cut/count/hash在同一次扫描中核对，同时生成当前prefix；所有历史行仍参与验证。safe close的原两次inspect/capture合为一次immutable inspect并复用已验证witness；DB字节SHA改流式计算。同一次实际close目录读取同时产生DB回执与原格式state-tree摘要，seal最终全库SHA仍核该DB不变；后续启动仍全目录重算，不能掩盖封存间隙的非DB文件改动。独立floor在全部SQLite读者关闭后持久化，最后完整SHA覆盖读取到floor写完这段，再提交head；SHA失败允许留下未接入head的内容寻址floor，但head不前进。ActivityProgress已经认证的manifest在同次immutable读取中复用，不重复深检。普通schema6 crash recovery不再计算只用于旧v4迁移的legacyDigest；旧v4迁移的legacy全量核对仍保留。

大库的四个只读 Worker 分别完整读取 change_events、chat_messages、领域 op/receipt/物化行及 activity 的完整 schema/floor 深审计；主线程同时执行完整 integrity_check 和身份/配置验证。完整全库 foreign_key_check 由 activity 深审计执行；小库顺序路径仍保留主线程同一检查。只有实际私有 Worker 成功才复用结果，真实孤儿 FK 损坏拒绝为 database_integrity_failed；若DDL与FK同时损坏，可能先报告DDL拒绝，不宣称所有复合损坏的首个错误码完全相同。Worker 使用 immutable/readOnly/query_only，全部关闭后才发布私有响应；取消或截止后不得接受成功，最后仍核全库字节 SHA 与提交前 SHA。这里并行计算全量证明，没有用过期摘要或随机抽查代替旧历史检测。小库继续顺序校验。原生离线检查改为单个常驻 PowerShell helper 与同一固定 Node 的私有线程管道：每个 phase 仍有独立 challenge/sequence/MAC、真实进程句柄/Job/锁/DB 文件检查；transport线程实际await退出，helper与Core退出、Job空才允许clean。readonly计算线程在成功消息之前已关闭SQLite，随后请求terminate，不把它称为独立await退出证明。

管道竞争复现与修复：给每次返回后重建管道加入50ms合成间隙，旧快速线程客户端会在下一管道存在前连接并拒绝。逐序号不可变签名ready文件确保当轮管道已建立后才连接，无连接失败重试/成功缓存；完整plainPath、peerPID=Core ChildPid、MAC和原15秒预算均保留。覆盖序号/认证错误和相同间隙的红→绿；Windows PowerShell 5的File.Replace空参数与替换时路径检查竞争通过不覆盖ready文件消除。未加诊断的真实20/20包close→restart→close通过，1.682/1.507秒，helper退出、Job空、合成目录清理。协议/旧witness/close-snapshot专项23/23，含floor写后改DB时最终SHA拒绝且head逐字不前进。

普通adapter初始化异常在Worker私有try内加载，失败有限消息主动唤醒；postMessage自身失败设失败signal，不能成功。入口文件/其静态依赖加载失败、native/OOM等无JS回执场景仍可能等内部300秒deadline；主线程自身onerror并不能在Atomics.wait期间立即执行。外部supervisor收到stop后原有60秒关闭超时与guardian父进程丢失清理保持不变，隐藏Windows会话关机钩子另有30秒总预算，不能混为一个超时。本轮未提高任一预算。

旧v1逐行数组先核原revision/hash，再要求最新行具备认证操作的完整承诺，成功后封为v2；没有认证证据的旧行以 old_domain_witness_unverifiable 或相应拒绝码停下，不自动相信现状。更旧的无progress witness floor继续要求完整数据库字节完全一致，不扩大兼容授权。

边界：独立head/密钥和受保护运行时仍是信任根；它不是抵抗宿主管理员或所有密钥同时失陷的方案。最后seal之后没有独立外置见证的每条ACK不能逐条证明未丢失，仍需按原sync_id/op_id对账。设备/principal/域配置等独立维度仍有各自字段与总体格式约束，本页只消除记录和消息条数造成的线性floor增长；算法运行时间与内存并非恒定。activity关闭，本轮不声明裁剪其已签历史后仍能恢复。

## 合成正确性验收

新增容量用例默认参加CI，没有新增skip。200,000条领域记录各有真实schema的receipt/op/payload/change，认证由DomainStore生产方法产生；消息/变更各100。另以真实DomainStore执行create→patch→delete→retention revision4。最终c15a源码容量用例344.3502563秒完成（其中seed36.328秒），关闭及合法恢复全部通过；floor从空基线2,213字节增至2,674字节。200,000条seed记录之外，真实DomainStore测试记录由revision1依次patch→delete→retention至4；count200,001、maxRevision和64位十六进制摘要均有实际断言。六种真实损坏全部拒绝，新增孤儿FK在实际并行seal与recover路径均拒绝，外置head逐字不前进。采样测试进程RSS895,574,016字节，不声明恒定内存或Core峰值。最初v2五种攻击版310.132秒是早期通过记录，不能代替本次复验。

| 真实篡改 | 拒绝结果 |
|---|---|
| 已删除行换成旧记录 | domain_record_rollback_rejected |
| 伪增revision | domain_record_envelope_invalid |
| 同revision篡改正文 | domain_record_rollback_rejected |
| 删除物化行 | domain_record_materialization_mismatch |
| 改写旧change_events前缀 | recovery_history_diverged |
| 删除消息引用的device，造成真实孤儿FK | database_integrity_failed；seal与recover均拒绝，独立head逐字不前进 |

原始文件保全和副本验证实际执行；只在便携correctness夹具中替换OS lease，生产入口不接受此能力。344.350秒是多轮合法恢复与六种攻击的完整容量测试时间，不是单次关闭耗时。

## 关闭、恢复与每日备份耗时

优化前完整 native 基线：10倍关闭14.496秒、异常恢复48.864秒；50倍关闭35.512秒、异常恢复103.637秒、真正每日备份48.820秒。两次关闭均不合格，未用降低数据量或增加关机预算规避。10倍早期8.505秒只测归档创建，不是完整每日备份，因此不填正式每日备份列；50倍每日备份另有1.635秒一次性口令包/配置准备，不计入每日操作。原基线 adapter SHA256 为6d7ded60d92b83f1cef1010686f60c6592e551e6c5a064ae731db0ad11cf6417，50倍库体积为1,066,053,632字节（采样，非连续峰值）。

中间优化版 f972：10倍关闭3.232秒/恢复27.085秒/每日备份24.906秒；50倍关闭11.062秒（失败）/恢复73.366秒/每日备份52.188秒。第四activity线程版183e6ca：10倍关闭3.141秒/恢复26.166秒/每日备份25.968秒；50倍关闭10.515秒（失败）/恢复74.887秒/每日备份50.358秒。失败回执与实验日志均保留，没有把接近门槛当通过。最终版 c15a1f1 为完整SQLite检查使用64MiB临时页缓存并避免重复完整FK；缓存不是持久证明。同一份1,066,184,704字节合成库的完整integrity_check，默认2,000KiB缓存5.101秒、65,536KiB缓存3.030秒，前后数据库SHA一致。生产仍全量校验，不存历史摘要缓存、不增加关机时限。以下为同一最终源码的正式native结果。两档串行，根窗不同时运行整组测试。消息正文为512字符合成内容；“70,000/350,000消息/变更”取较保守含义：chat_messages与change_events各有该数量，而非相加后该数量。

| 档位 | chat_messages | change_events | domain_records / ops / receipts | 完整安全关闭 | 强杀后下次启动到ready | 备份创建及认证验证 | floor字节 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 10倍 | 70,000 | 70,000 | 各20,000 | 3.118秒 | 25.729秒 | 11.865秒 | 2,569 |
| 50倍 | 350,000 | 350,000 | 各100,000 | 9.014秒 | 70.049秒 | 51.587秒 | 2,581 |

两档均为 adapter SHA256 c15a1f1faa629e2eb06bd1d770efb7e925b8a0c86b2534e67852d83851c19518，实际固定包文件与输入逐字匹配。10倍库213,045,248字节、seed WAL214,013,432字节；归档305,376,718字节，SHA256 288ce3336208f0ba07993d2d926e174e5df997c0b5146a1ce6c2a16b3fd990ea；manifest373a2005c962efb2243fb498792bc92fdec98e2d7faf6d838e9bd9751236236a。50倍库1,066,024,960字节、seed WAL1,071,991,072字节；归档1,158,356,443字节，SHA256 78131c5a4bd647444dc7a652d58632429d72e70ea1f4c8d9c424ef9224af298f；manifest f5f28d078f496c77bb69b4ad468e88fadc8f43e75dcbcdafc0c04bb24c243e3f。合成包source属于一次性测试仓库，不能当正式分支commit；最终正式固定包另在主窗交付节绑定。

一次性seed/环境准备不计入三项耗时：10倍seed4.531秒、lab32.146秒、口令包/配置1.137秒；50倍seed27.933秒、lab56.376秒、口令包/配置1.624秒。原始日志为忽略的build/ci/pr14-scale-cache-native.ten.log与.fifty.log，最终退出回执、真实Job空、合成环境清理均通过；较早超标日志与合成环境保留，不覆盖失败证据。每天操作不含U盘复制、OS调度等待或真实九类资料的另一种负载。数字为本机各一次完整合成测量；没有把近似数据量、多次revision的容量验收或局部profile时间填成native耗时。

关闭阶段回执（秒）：10倍request ACK0.664、floor2.355、child2.792、guardian2.845、supervisor2.992，总3.118；50倍ACK0.646、floor7.687、child8.688、guardian8.740、supervisor8.898，总9.014。floor或ACK不是终点。采样harness RSS为10倍159,907,840/峰值353,374,208字节，50倍326,320,128/峰值412,680,192字节；这不是Core峰值内存，未作该声明。

正式native测量从生产prepareRelease生成固定包，运行真实Windows supervisor/guardian/Job/认证管道/离线锁，关闭计时从请求stop到完整退出与clean-close回执，包含sealClosedRecovery。异常恢复从下一次固定启动到schema6 ready，包含预打开DB/WAL/SHM/journal加密保全、真实副本回放、integrity/独立head/配置绑定与新control启动；不把adapter局部时间冒充总时间。每日备份含完整固定包（含Node）、合成库、独立head/floor及全部角色占位输入的加密创建与verifyRuntimeBackup；不含OS调度器等待，不宣称覆盖真实九类52文件的相同负载。

最终50倍9.014秒通过10秒门槛，关机钩子总预算30秒没有增加。超标版14.496/35.512、11.062、10.515秒均按失败保留；没有降低条数、缩短正文、增加超时或省去历史改写检测。全量并行校验和固定大小缓存已达标，因此没有引入只能核新增行的持久摘要缓存。

## 现场与下一轮

[本人操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)与[④–⑥现场清单](SCHEMA6_CUTOVER_FIELD_CHECKLIST_20261006.md)已按用户定案同步。先另获合并授权→合并PR14到v3-lab→从合并提交重建固定候选，再另获切换授权。U盘只接受现场确认NTFS；FAT32/exFAT停止告知，格式化决定交本人，i不格式化。邮件debug关闭、47862桥保留、legacy_b3唯一上传器；立即真人关机→开机→登录，清停回执/自动启动/手机同步/claude.ai写入四项全部通过才切换完成。

Windows更新后需有用户交互式登录会话；ARSO可能在手工解锁前自动建立会话并触发任务，本机尚不确定，官方机制依据和未来获准验证方法在现场清单。换机后的口令备份仍只能inspection-only还原；新用户DPAPI、新独立恢复key/current-head和配置路径绑定以建立新现役Core是下一轮已知缺口，本轮不实现。

## 主窗最终交付

主窗整组650 tests /649 pass /0 fail /0 cancelled /1既有skip，885,951.5865ms；skip精确为case-distinct live paths，当前测试卷不能表达两个大小写不同文件身份。本轮没有新增skip，200k容量用例默认参加本机与CI。相邻专项95/95通过，包含activity none/progress/exact真实孤儿FK、错误绑定、伪floor认证、worker取消/私有发布失败和最终SHA/head保护。固定库存46项，28个Node文件语法、16个Windows PowerShell5.1脚本语法均通过；45库存文本为Git LF字节，Node仍固定24.14.1与既有SHA。

整组spec SHA256 5ea47d657752ef4000148c63c74bdc56a00d0971ac63597150ff59f84dfd90ab；TAP SHA256 b0794551c450671635b3235a829586e7e34435b969309fe9933eff15c2d22371。日志位于忽略的build/ci/pr14-scaled-main.spec.log/.tap；只有合成诊断，未加入真实资料。

正式固定源aa42e93a74830e6b928bd63d822537235de064e7；manifest a04432cf038e4d30fea3ff1bd4029ef4af3b47bc27a37fb86dff9d7cda571842；库存46项，45源文本与本机已测字节逐字相同，Node仍为58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f。受保护候选在本机隔离真实Core启动、loopback健康、认证停止、child/guardian exit0、Job空和锁释放烟测通过23,526ms，库存未改。候选路径为C:\\Users\\Lynx-DB\\AppData\\Local\\Temp\\schema6-pr14-final-vo61QT\\candidate，仅供本轮复核，未来合并后必须重新构建。首次只保护父目录的准备尝试被protected_root_required在启动前拒绝；未打开原库，未改门控。按原有流程先保护新空候选根，再逐字复制核验库存，复测通过；非空目录初始化也按原门控拒绝，未绕过。

随后只有文档回执变动，最终远端head的库存仍需逐字核对本固定包；新13项CI实际回执登记在同PR的精确Checks与正文，旧a608绿色不能作为本轮新提交证据。完成后只推同一PR并暂停，不合并、不部署；真实关机与客户端Gate仍未执行。
