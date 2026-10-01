# P6 R7 本机 AppId matrix runtime 候选

## 当前实测：v5 八项事件矩阵与完整回收通过

2026-09-12。冻结 source/snapshot `tmp/p6-r7-review/native-appid-matrix-runtime-05.cs` SHA `A6744DA33DEBCED897F8A8671D7EE181FF1728E680D6115FC4D1FEE49E1C44C6`；exe `tmp/p6-r7-helper/windows_text_gate_appid_matrix_runtime.v5.exe` SHA `E112067A868814BF2353DC8B9350B88A028DC77DF971290F70EF8D3FD913508E`。主控最终专项19/19、自测233、真实文件等待22断言通过，候选未再修改。依赖仍为冻结 events01/sockets03/runtime-adapters01/contract01/v15及v10/v11c；下面修复说明是本候选的实现依据。

固定采集脚本 `tmp/p6-r7-review/run-matrix-capture-05.ps1` SHA `06C1C011821D7EC872E45D2E5D8430CDDF46B6AC44E3409424E99D2D5B5D8064`，先持久化实际stdout和退出码再解析。actual05 attempt `5019bbd0-3999-4b6a-9346-cd85f040d51b`，native与runner实际exit0。报告 `tmp/p6-r7-review/native-appid-matrix-runtime-actual-05.json` SHA `BF9DD260E9A215977FBEF70054D3618871B7CF0D4A7DE15A90A77B1480B32402`；采集回执 `tmp/p6-r7-review/native-appid-matrix-runtime-capture-05.json` SHA `CF298F5F63406014E605CCB45FD65CA91A4C532462FF398FA2BAE57EEDF43060`，stdout_preserved/parsed_expected_report/candidate_post_pin=true。独立审计重新核对这些指纹及报告字段通过。

八项host正控、精确父时间窗、零接收及对应own-filter丢弃事件均成立（八角色各matched_count=1），owned-peer admit、wrong-peer reject、marker往返成立。child正常exit0/held close、JobActive0、stdio EOF、drain、post-pin、安装与清理helper actual exit0/精确回执、rules_postabsence及所有受跟踪句柄关闭均true，`matrix_passed=true`、`event_matrix_passed=true`、`cleanup_pending=false`。原合同 `all_negative_roles_blocked=false` 保留：四TCP10035未完成，四UDP发送成功，不改称同步拒绝；本次通过依据为额外的精确系统事件与整条回收证据。

历史162de/70ea分别只读确认四对象全无；28e6由固定退役恢复器实际删除三规则及一分层并确认缺席，均pendingfalse，不与5019实例拼接。当前结论仅为本机固定v5的有界八项WFP矩阵，不证明真实CLI持续隔离、容器等效文件隔离、生产/App或真人Gate。R7真实上游/模型请求仍0，生产profile仍拒绝；P6/Goal1未通过。

## v5 候选：公开字段完整性与 ready/ack 写入竞态窄修

2026-09-12。主控报告 v4 `native-appid-matrix-runtime-actual-04.json` 已保存 `mode=rejected` / `failure_stage=99`，capture04 保存实际 exit 2。worker 只核查源代码和执行本地测试；未重跑 v4/v5 actual，不把私有 cleanup stage1 诊断当成已确定的系统错误原因。

冻结 v4 源码 `tmp/p6-r7-review/native-appid-matrix-runtime-04.cs` SHA `333CC344F6DEB478CC37FCEAB2C20E1D18F07CF09DCFBA39E6EEB6DCC5C79828` 的独立字段抽取证明：实际 Base / StartReport / Coordinator 共写 **36** 个顶层字段，PublicReportKeys 只有 **35** 个，唯一缺项为原有 `all_negative_roles_blocked`。v5 只把该字段纳入白名单；Coordinator 整个方法与 v4 原文完全一致，清理、身份和 event Gate 未调整。保留启动 `failure_stage=0` / `rows=null`、最终报告专用 depth 6 / 16 KB serializer；内部 MatrixRecords journal/parser 未修改。

回归从实际 Base 初始化与 StartReport / Coordinator 全部字面字段写入收集并集，与白名单和最终序列化结果分别比对；发现动态字段写法或不能识别的 report 索引时拒绝测试，不能靠 synthetic 与白名单同时遗漏而通过。每层字段集还独立取自实际 HelperDiagnostic、EventDiagnostic、MatrixSocketFixtures.Rows、MatrixNetEvents.SafeSummary：合成 rows 修正为真实 **13** 字段，event/helper 外壳直接调用实际纯投影函数。完整成功和 fixture 前失败均能输出；`all_negative_roles_blocked=false` 与 `event_matrix_passed=true` 的合成组合可同时保留。fixture 前未调用 helper 的诊断保持 null/未调用语义。

另修复一个可复现的读取竞态：writer 使用 CreateNew / FileShare.None，原 Wait 仅见文件存在就立即返回，此时 Read 可能早于 writer 关闭。新增 WaitRead，在原 **30 秒**总预算内等待文件出现；只对严格 Read 抛出的 HRESULT `0x80070020` / `0x80070021`（共享/锁冲突）等待重试，其他异常立即拒绝，超时返回 null。ready / ack 直接验证这次完整读取的字符串，不再 Wait 后另开一次 Read。普通 Read / ReadPinned、protected ACL、held pins、lease 与 token 核验不变；不启动第二 helper、不扩大等待或重试范围。28e6 的 ready/ack 文件与 cleanup stage1 失败形态与该竞态相符，但未保存该次原始 errno，因此本修复不能证明它就是那次失败的原因。

专项 `node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_runtime.test.mjs` **19/19**、0 skip；联合 C# x64 warnings-as-errors 两入口编译通过，托管 self-test **233**。新增临时文件/本地线程测试 **22** 断言：真实独占 writer 已创建且 Flush 后仍不许返回 ready；writer 关闭后必须读全；仍独占时到期返回 null；32/33 可重试；2/3/5/80/87、权限/编码异常不重试。全套仅测试临时目录、plan/self-test、托管投影/策略与本地文件等待，没有 UAC、BFE、Job、probe、socket、CLI 或模型请求。所有冻结源/依赖 pins 测试前后不变，旧 v3/v4 snapshot/exe 保留。

| 本次交付（停止修改，主控负责最终冻结与实际验收） | SHA-256 |
| --- | --- |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_runtime.cs` | `A6744DA33DEBCED897F8A8671D7EE181FF1728E680D6115FC4D1FEE49E1C44C6` |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_runtime.test.mjs` | `F80E4CC7337E294E1FC5F15E15FE85E3B9C5F6CB7ABB461984BFD5111EA8A66D` |

## v3 实际采集事故与公开投影修复

2026-09-12。固定 attempt `70ea3573-f6cf-4c5c-b680-8a21288ea5fb` 的外层采集脚本已在 `ConvertFrom-Json` 后因 schema/mode 校验失败而 throw，落盘前没有保存 stdout；因此不存在可供重建的原始 runtime 报告，原 native exit 也未知。事故单 [capture incident](../../../tmp/p6-r7-review/native-appid-matrix-runtime-capture-incident-03.json) SHA `DDFA2C3155D6CE1448B53D4776BC955D265E03B5E20F956E71F982A6E85EC99C` 仅记录采集缺失，不是原报告或实际通过证据。

代码级纯合成复现已表明，旧 `MatrixRecords.Json` 的 `RecursionLimit=5` 无法序列化完整公开链 `report → event_diagnostic → capture_summary → roles[8]`。当 coordinator 在 finally 后投影该结构时，最外层 Main 会捕获序列化异常并输出小型 `mode="rejected"` fallback；这与“JSON 能解析、随后 schema/mode 被拒绝”的现场相符，但仍是基于源码与事故形态的推断，不能倒推原 stdout 或退出码。

当前 runtime 只为最终公开报告新增独立 `JavaScriptSerializer`，`MaxJsonLength` 仍为 16384、`RecursionLimit=6`，恰好覆盖固定公开 schema；它先拒绝任何未列出的顶层字段，再校验 UTF-8 字节上限。真实 coordinator 与纯回归共用 `StartReport`：启动即写 `failure_stage=0`、`rows=null`，随后只有 catch 覆盖 stage、只有 fixture 建成才覆盖 rows；未知 rows 不会被写成通过。`MatrixRecords` 的默认 serializer、journal/parser、私有 record 上限和 fail-closed 规则均未放宽。专项纯合成回归构造完整最终 report：旧 serializer 必须失败，新投影必须成功，顶层字段恰为固定 schema，capture summary 含八个角色且不含敏感占位；另验证 fixture 前失败路径仍可投影 `rows=null` 和 `fixture_ready=false`。该纯重建不构成对 70ea 实际矩阵的补证；不得因本修复重跑、覆盖或伪造旧 actual。

## 历史 v3 准备：仅 helper 启动诊断增量

当前固定162de实例只读回查已实际执行：普通 Medium 的 READONLY transaction 返回5（access denied），四对象尚未查询，`cleanup_pending=true`。管理员模式的固定只读检查 v2 与启动脚本已冻结、测试及独立复核通过，但未实际执行；等待用户处理新一次 Windows 确认，当前没有运行中的 helper 或确认等待。详见 [固定实例检查](P6_R7_WINDOWS_APPID_MATRIX_INSPECT_HANDOFF.md)。

主控已复核无执行策略变化，专项15/15与冻结self230实际exit0；source/快照 `tmp/p6-r7-review/native-appid-matrix-runtime-03.cs` SHA `5CEE2B12AD226E38C92E4C1792106DD19517EB0C37CCEAD31E1DC364A84D1FB9`，联合exe `tmp/p6-r7-helper/windows_text_gate_appid_matrix_runtime.v3.exe` SHA `07FA499C4922B80D531C09FA23F053C7982AD28718F9BA6089297ECBA34B77F3`。其它依赖与v2相同。当前只运行pure self，没有运行v3 actual，也没有新增系统确认；等待固定162de实例规则回查和用户确认窗口反馈。

2026-09-12。v3 只增加公开 `install_diagnostic` / `cleanup_diagnostic`，固定 schema `matrix_helper_diagnostic_v1`，沿用总报告 v2 schema。每项有 invoked、launch_attempted/launch_returned/launched、launch_error、process_handle_observed、ready_wait_attempted/ready_observed、live_bound、exit_wait_attempted/exit_wait_result、actual_exited/actual_exit、receipt_read_attempted/receipt、handles_close_attempted/handles_closed。只输出布尔、null 或原生数字，无路径、身份、原始异常。ShellExecuteEx 返回后立即保存 GetLastWin32Error，仅调用失败时输出该数值；不把成功调用遗留的 last-error 当成错误。

未 Invoke 时 invoked=false、其余观测字段 null。进入 Invoke 但未调用 launch 时 launch_attempted=false、launched=null；ready 等待正常超时且无文件时 ready_observed=false，未等待或等待异常为 null。actual_exited 只在原 held helper 退出/身份/exit-code 查询验证成功时为 true，其余 null，不从缺 ready/回执制造退出或仍在运行结论。receipt=false 仅表示尝试读取后尚未验证成功，未尝试为 null。每个诊断字段只记录实际到达步骤，均不参与 Accepted、cleanup 或 event 门。没有新增 native 调用、等待、自动 retry、UAC verb 或权限变化。下面的 v2 actual02 原报告保留，本包不执行固定实例回查或实际重试。

专项 `node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_runtime.test.mjs` 实际 exit0，**15/15**、0 skip；托管 self-test **230**（新增 24 个投影断言，覆盖无调用、launch 失败、ready 超时、exit 未知、回执缺失和诊断不改变接受条件）。测试仍仅联合编译、plan/self-test/纯反射，未执行实际入口。source SHA `5CEE2B12AD226E38C92E4C1792106DD19517EB0C37CCEAD31E1DC364A84D1FB9`、test SHA `9C0656ED11AC028FCE9C8BC6CCF58F5F7E11D65954391D3D91F352164071EFD1` 已停止修改，主控负责新 v3 snapshot/exe 与复核。旧 v2 工件保留，不覆盖、不实跑。

## 历史 v2 事件证据接线（已联合冻结）

主控最终冻结：runtime02 SHA `9B6FFA005D45F9737AEAC00A341DDD51D82445EE2AB4505BD1B1EC9F9A82743C`；events01 SHA `C6AAC8A35CE163CB0D4D3760C069220A95628579434B9CE18D6D8F282854E2C8`；sockets03 SHA `3F0C2DABDA9ECDD1A7F6D56A1CAD81C8B99AD4548FB4E4EA477F08128E4052D2`；native使用runtime-adapters01 SHA `F2D3B35A1E6D1763930BA7F9A82AB8DBB595E02D5D720216A0161DBCE8A0D0AB`。最终联合exe `tmp/p6-r7-helper/windows_text_gate_appid_matrix_runtime.v2.exe` SHA `EB039CB1778F0B56E322CA97FEEEEA6D7675EFECC7A8A9DE3B4EB377E0F3462A`，冻结self206与plan均exit0。主控组合28/28通过后，events仅补2条字节序反例与说明注释，专项再次4/4、264纯断言、SDK36个编译期ABI断言通过；两次独立复核已关闭P2并绑定最终逻辑。host03本机实测metadata/时间窗通过。旧v1工件保留。

v2首次实际02已结束：attempt `162de9b7-046f-45dc-b15e-a6ced3d785e2`，coordinator exit2、failure_stage3，未创建probe；八项host fixture ready成立，但未获得安装helper实际结束/回执及规则postabsence。`cleanup_pending=true`、matrix/event/production/human=false。报告 [actual02](../../../tmp/p6-r7-review/native-appid-matrix-runtime-actual-02.json) SHA `767E40D8646CB432BA10C555C6884BA13364A9636C34455E6C1616FC1435E031`，前后候选pins不变。只读现场只有copied image与prepared（SHA `74FE88F74597E31EBD2AF6DCA727AE8AB458A5363977B514A48023B790BD803D`），无ready/ack/receipt或spawning/bound；原exe与该probe当前均无活动进程。没有记录具体ShellExecute错误，不能把它断言为1223或自动审批拒绝。该实例正在准备固定scope只读规则检查；原报告保留，不能因无child就推定规则缺席。

2026-09-12。本轮只改 current runtime、其专项测试及本文，native adapter 与所有 v1 快照/exe 保持不动；events 与 sockets 由其它明确拥有者修改。v2 报告 schema 为 `p6_r7_appid_matrix_runtime_v2`，不把 v1 的同步错误码门槛改写为通过。

v1 实际报告 `tmp/p6-r7-review/native-appid-matrix-runtime-actual-01.json`，SHA `C648AAD15E7CAF83D1687198CA6EBFA8CFD603232E4435BA32C024236028F336`，attempt `7eaeb3df-d560-499d-864f-c7ed2a2b3e89`，coordinator exit 2。该次真实 probe exit0、held child close、Job Active0、stdio EOF、helper actual close、规则 postabsence、受跟踪句柄关闭及 broker 正反控/marker 成功；`cleanup_pending=false`。四项 TCP 为 10035/incomplete，四项 UDP send 成功/合同 not_blocked，八项监听零接收，`matrix_passed=false`。这是原候选的有界失败证据，不证明 UDP 数据穿透，也不提升生产隔离。

v2 保留全部原关闭、身份、Job、规则回执及 peer 证明。stdio 改为恰好八次 `row`→`row_outcome`，固定角色顺序、index/nonce/marker 对应，一帧在途且写入上限仍 4096 字节。父进程在每次发送前/接收后读取与 probe 相同的 precise FILETIME API，独立验证 operation 时间窗及 tuple 对应；任一无效/缺失窗口使事件门为 false，不从 child 自报窗口直接接受证据。

仅新增三个 own-attempt 私有文件：`event-binding.json`、`event-probes.json`、`event-receipt.json`。安装 helper 在原规则安装之后可选读取精确 filter/layer IDs；binding 外壳绑定实际安装 helper PID/creation、attempt、nonce。父进程只在该 helper actual exit0 和原安装回执通过后接受并持 read pin。仅完整八项父窗口有效才写 probes；probes 只来自 socket 模块的严格固定投影。清理 helper 在移除规则之前可选读取/pin/re-read 这些文件并采集 own-filter drop；事件结果外壳绑定实际清理 helper，写在原规则清理回执之后。父进程只在该 helper actual exit0、原规则清理回执和原 binding/probes 都匹配时接受结果。文件拒绝、事件读取失败、采集关闭/未知或事件回执失败都使 event gate 为 false，原规则清理仍继续；不为采集去更改全局日志开关或网络策略。

原 `all_negative_roles_blocked` 继续输出原合同结果。新 `all_own_filter_drops_matched` 需要严格 event schema/hash/八角色匹配及实际清理 helper 绑定；新 `event_matrix_passed` 与 v2 `matrix_passed` 还同时要求本机正控、最终排空和零接收、全部父窗口、正常 probe exit0、peer/marker、post-pin 和完整规则/资源回收。公开诊断只投影固定布尔、枚举/计数和角色，不公开 tuple、地址、AppId、filter ID、身份或原始错误。`production_isolation_passed` 与 `human_gate_passed` 始终 false。

`event_diagnostic` 为 diagnostic-only 固定外壳：binding_verified、probes_available、capture_present、capture_validated，及 integration_stage（0=已验证，1=安装绑定缺失，2=探针元数据缺失，3=清理 helper 未被实际回执链接受，4=事件回执缺失，5=事件内容无效）。只有实际清理 helper 与规则回执通过才可输出 `capture_summary`；summary 由 events 模块纯校验后重建，只含 collection_enabled、enumeration_complete、resources_closed、固定 error_stage、原生 API DWORD/nullable 的 api_status，以及固定八角色 matched/count。合法但未通过的 capture 可诊断，不能放行；无合法 capture 时 summary 为 null。

本轮另窄修 `Accept()`：新 accepted socket 设置 timeout 失败时立即关闭；关闭失败保留 socket 所有权并进入粘滞失败，不能在返回 caller 前丢失句柄。

本节描述候选实现，不是新 actual 结果。最终 source/test/联合依赖 hash 与冻结 exe 由主控复核绑定；worker 不执行 UAC/WFP/Job/socket/CLI，也不访问账户或凭据。

v2 worker 专项已执行 `node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_runtime.test.mjs`，实际 exit 0，**14/14**、0 skip。测试联合编译当前八个源，且只执行 read-only plan、managed self-test、固定 invalid 参数及纯 policy 反射；self-test **206** 项（原 166、全部 32 个 event 门组合、8 个绑定外壳正反例），反射另验 128 个 cleanup、80 个 helper/exit、32 个 event 组合。未执行原生入口。source `9B6FFA005D45F9737AEAC00A341DDD51D82445EE2AB4505BD1B1EC9F9A82743C`、test `A55279E71E20FE638015EE1676EB2B415E70C75B83D1A71975D7C9E9D2CF450A` 已交主控审阅，worker 暂停修改。该轮联合测试所见 events `A272D36CCE43CEF781387F6FB7B9EE71BDA8CD62A5D3A154A354A1AA22E6F38E`、sockets `3F0C2DABDA9ECDD1A7F6D56A1CAD81C8B99AD4548FB4E4EA477F08128E4052D2`；其它拥有者仍可能在最终审计前更新它们，因此这些仅为当轮依赖观察，不是最终联合 exe pin。正式 snapshot/exe 由主控串行生成，禁止覆盖 v1 工件。

## 历史 v1 实现与冻结证据

2026-09-12。基线 `v3-lab@bbb8025d99fc0acaa846d58b4e5a94cef90f8756`。本包新增 runtime 源码/专项测试/本文；只为接线最小修改当前 native adapter 及其测试，保留冻结 adapters-02/v2，不改合同、旧 coordinator/core、全局状态或 Git 索引。socket 模块由主控拥有。

本包实现普通 Medium coordinator、DETACHED own probe、UAC own-rule helper 三角色，可供主控审计后执行显式 `--apply-local-appid-matrix`。默认/`--plan`/`--self-test` 不进入原生路径。worker 只执行编译、托管 self-test、公开纯 policy 和 Node 静态检查；没有执行实际 probe、Job、socket、UAC、WFP、CLI，没有读凭据、改网络配置、连接公网或请求模型。

## 运行链路

1. coordinator 必须为普通 Medium。所有源祖先 held canonical/no-reparse；只在合同 `D:\HereIAm-P6-R7-AppId-Matrix` 的 fresh UUID 目录写固定文件名。新 root/attempt 使用 protected ACL：当前 user、SYSTEM、Administrators 三个 FullControl 项；已有 root 必须 exact owner/ACL，只校验而不修改。复制执行文件用 CreateNew，source/image held pin、final path、single link 和 SHA-256 校验。不是针对恶意同权进程或管理员的防护。
2. 先创建本机 broker 和八个 fixture，fresh inventory/独占 bind/host marker 正控/排空必须 Ready，才请求 UAC。fixture 不足是 incomplete；若未请求规则/创建 child，资源精确关闭后可无系统 pending，公开 Job/child/EOF 等未发生证明为 null。
3. prepared journal 绑定 UUID/scope/nonce/owner PID+creation+token digest、source/image hash、port。coordinator 持 own Job，readback flags `0x2008`/ActiveLimit1/初始 0/0。UAC helper 先写 ready lease 并等待 ack；coordinator 持 ShellExecuteEx process handle，在 helper 存活时核 PID/creation/image/hash、同 user/session 的 elevated primary NonAC token digest，再写同一 lease 的 ack。
4. helper 从 own 固定 journal 验证仍存活 owner、同名 held Job 的 exact limit 和 accounting，复用冻结 v15 `CoordinatorBoundary` 的 Filter200/INDEXED64、合同派生 scope 与实际 assigned weight。安装完成回执必须与真实 helper exit、PID/creation/nonce/scope/phase/hash/weight 绑定。句柄 close 不代表 helper 已停止；helper 未确认 actual exit 时不派第二 helper。
5. probe 使用 atomic JOB_LIST、精确三个 stdio handle、DETACHED `0x8040c`、可写命令缓冲和最小环境。创建后的 process/thread 先接管，再做 PID/creation/token/image/hash/member 验证；写 bound journal 后才 Resume。ready 后必须 Job Active1/Total1。
6. broker wrong-peer 使用 coordinator 自身客户端验证拒绝；真实 child 通过现有 tuple/held PID peer admission 后做随机固定长度 marker 往返。stdio 为 ready→broker→broker_done→matrix→outcomes→finish→done，nonce 与固定 keys 严格校验。一帧在途、收回复再发下一帧；每次写不超过 4096 字节，适配管道容量；读端每行最多 8192、累计最多 32768 字节，并有固定超时。
7. child 逐行调用主控 `MatrixSocketFixtures.Probe`，只处理合同角色和 fresh 本机地址，不做 DNS/公网请求。`Complete` 只收集观测；child exact exit/Job0 后最后 `DrainVerified`，再读取 `AllNegativeBlocked`，不得沿用早期通过值。只有对应同步 Connect/SendTo 的原始 10013、正控完整、最后排空与零接收才能 blocked；timeout/refused/wouldblock/地址不可用都不是拒绝证明。
8. finally 先停止/核查 own child 和 held Job，再关闭父持 child stdio endpoints 后读 EOF，避免创建失败时自己持有写端制造假 pending。cleanup helper 只在原 helper 已 actual exited、child exact closed 或真实 never-created、held Job Active0 后启动；有 child 写 closed journal；从未创建 child 使用 prepared rollback，绝不伪造 closed child。
9. 规则删除+postabsence+helper actual exit/receipt 之后释放 owned Job/process/stdio/pin/socket。所有关闭失败保留所有权、允许 close-only 重试并粘滞失败。构造器失败无法返回对象时的 close 失败通过全进程 ledger health 进入 pending。未知不填零，Dispose 不填业务通过事实；若实际入口意外漏出异常，Main fallback 标 native_executed/cleanup_pending=true。

## 脱敏诊断与恢复边界

公开报告只含固定阶段、布尔/nullable 数值、角色结论与 attempt UUID，不输出身份、地址、marker、路径、原始异常或 CLI 内容。coordinator failure_stage：1=身份/路径，2=fixture 正控，3=安装 helper，4=spawn/binding，5=broker，6=矩阵协议，7=正常退出等待，99=最外层未知失败。private helper/probe `*-report.json` 只写固定 stage/completed/error_code；helper 1=preflight/lease，2=规则操作，3=回执；probe 1=身份/文件/Job，2=broker，3=矩阵及完成协议。

attempt 目录保留 immutable prepared/spawning/bound/closed、ready/ack、receipts、固定诊断及 copied candidate，用于限定恢复。helper timeout/未知不会通过 close process handle 冒充停止，也不会启动另一 helper或全局清规则。本包没有通用后续恢复入口；任何 pending 必须先由主控查明同 attempt 的 actual helper/child 与规则状态，另行准备限定恢复，不能换 UUID 当已清理。

runtime 的 `matrix_passed` 仅指这次本机固定 own image 的八行矩阵、peer 与精确回收；永不提升 production isolation、human gate 或真实 CLI/模型验收。WFP AppId 仍是 copied image path 规则，不是 executable hash/instance 隔离。

## 冻结与验证

历史冻结 runtime **01/v1**。独立增量审计在下列 runtime/native/socket 三 hash 上未发现剩余 P1/P2；这是代码审计。冻结快照/exe 保留不动，current runtime/test 的 v2 修改不继承此表 hash。v1 actual 结果见本文顶部。

| 材料 | SHA-256 |
| --- | --- |
| `tmp/p6-r7-review/native-appid-matrix-runtime-01.cs` | `B3ECBA788E95E95ED004FE40CFC094E538EC99D65057CD55200DEA835B8BC3D8` |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.cs`、`tmp/p6-r7-review/native-appid-matrix-runtime-adapters-01.cs` | `F2D3B35A1E6D1763930BA7F9A82AB8DBB595E02D5D720216A0161DBCE8A0D0AB` |
| v1 runtime 专项测试当时 hash（current 测试已进入 v2） | `2EAE8FFCF518F9C2867C89C7DB0509A92EB25821D5B74C3E5034D6FF0E8AB711` |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.test.mjs` | `85D8FC3BD26F610CB4D47F9B4E98CF7984D6FF8C76CFFD1F17FC863FFF60DFF6` |
| `tmp/p6-r7-helper/windows_text_gate_appid_matrix_runtime.v1.exe` | `21CC6EE87FF30B573E10E7A2AF86E0BE8B0EA4DC51F66A372A8C81F81E377295` |
| `tmp/p6-r7-review/native-appid-matrix-sockets-02.cs`（主控） | `E11FDD027187429B2D000A5323B897E59FC28282BAEEC2B7C990B1ECEBAF21DE` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs` | `C1F07E9487B8CE25D0ACC2D5BBB03B69C975CBB7E448698D288FF6263CFF9311` |
| `tmp/p6-r7-review/native-appid-matrix-contract-01.cs` | `F70FFB86CE5EFEA2572532E1986F77DDE9622893AD4B90A74F9EC40DA5BA6774` |
| `tools/dev_agent_bridge/windows_text_gate_isolation_helper.cs` | `D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8` |
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs` | `C777023495CCDBF3B52663F49683F5D84DCFD03A36B3D280A75C925F37B7A1EA` |

已执行验证（实际 exit 0）：

```powershell
node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_runtime.test.mjs tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.test.mjs
& .\tmp\p6-r7-helper\windows_text_gate_appid_matrix_runtime.v1.exe --self-test
& .\tmp\p6-r7-helper\windows_text_gate_appid_matrix_runtime.v1.exe --plan
```

Node **19/19**（runtime 10、adapter 9），0 skip。runtime 托管 self-test **166**；另独立反射检查全部 128 cleanup 组合、80 helper/exit 组合。adapter 托管 self-test **166**，含失败句柄 retain/retry/粘滞失败 mock。专项测试只调用 plan/self-test/固定无效参数、公开纯 policy；没有实际动词。冻结 exe 使用明确 `/main:HereIAm.R7.MatrixRuntimeProgram`，Framework64 csc `/platform:x64 /warnaserror+ /reference:System.Web.Extensions.dll` 联合上述七个源文件；编译实际 exit 0。

主控审计后实际入口（worker 未执行）：

```powershell
& .\tmp\p6-r7-helper\windows_text_gate_appid_matrix_runtime.v1.exe --apply-local-appid-matrix
```

仅主控提供的 host-only socket v2 baseline：8 个本机 fixture 正控/排空/关闭通过，报告 `tmp/p6-r7-review/matrix-sockets-host-baseline-02.json` SHA `62F26D4F2D00AD1EC0AD6DE6AC4E811861DC1784AB47336D8267B08C571859D7`。该证据不属于本 runtime actual，也不证明 WFP 拒绝；worker 没有重复这次 socket 执行。
