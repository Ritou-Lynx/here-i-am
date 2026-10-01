# P6 R7 AppId coordinator：v16 启动回收通过与 v16b 只读收尾

## 主控本轮实际结果（2026-09-12）

用户要求重新触发确认后，冻结 v16b helper47684 实际exit0。固定56e435bd实例的三filter与sublayer均回查不存在，pending=false，没有删除对象或签发CLI close/Job-zero。报告 `tmp/p6-r7-review/native-appid-coordinator-inspect-06-v16b.json` SHA `9CFA9E2AC700A33EBD47492359CCFC3D09E94B73FDB676F40DE2313E9ECA3E51`，原件与副本一致，独立复核通过。

随后同一冻结 v16 在新attempt `3c374ccd-0140-43a8-b33c-ce86cc8a37a6` 完整通过无认证detached CLI启动和回收，coordinator实际exit0。initialize/config通过、project层0；两个held活动观察点均Active1/Total1/Terminated0；stdin EOF后child正常exit0，JobActive0和stdio EOF均确认；安装及清理helper实际退出与回执验证通过，规则removed、pending=false。source/exe/源CLI执行前后pin一致，复制CLI同pin；三报告已由独立审计绑定。

| 本轮实际报告 | SHA-256 |
|---|---|
| `tmp/p6-r7-review/native-appid-coordinator-startup-06-detached.json` | `2164FF94EE74D84FF0BFEE5B1314A78B55AA4915A94243F3F3BF959FA44C2E7F` |
| `tmp/p6-r7-review/native-appid-coordinator-install-06-detached.json` | `C4F98B85293097231A10C94F6BD911A6513F948973A85A2F03DAD68B802552A5` |
| `tmp/p6-r7-review/native-appid-coordinator-cleanup-06-detached.json` | `B4CDDE518BBF586FFD8BAC8C04C30B14B8A5D0044185CDBC54A16EAEE066EE27` |

两个活动点单成员不证明持续单例或真实CLI第二创建拒绝；错误peer负控和HTTP0不等于owned-peer正控或网络矩阵。0真实账户/模型请求，single_process_enforcement_tested/network_enforcement_tested/production_isolation_passed/human_gate_passed均false。P6未完成，下一步仍为网络矩阵运行层与其真实证据，再进入账户/生产/App验收。旧失败与冻结记录在下文保留，不能作为仍待用户确认或仍有规则的当前状态。

## v16b 执行前冻结记录（2026-09-12，实际结果见上）

主控实际运行 v16，新attempt **56e435bd-05cb-4569-b86d-ba884d2eb717** 在install_helper阶段返回helper_uac_launch_failed/系统1223，coordinator exit3。CLI未创建，Jobcreated/before/after均0/0/0；没有install报告/回执，原报告保守cleanup_pending=true。报告 `tmp/p6-r7-review/native-appid-coordinator-startup-05-detached-cancelled.json` SHA `02B3285F9234FDF9B772A63410967B4BD573225C35AD3864E309F3285789AD21`。**1223、缺文件、历史Job0都不能证明WFP不存在规则；本次没有达到真实CLI兼容测试。** 2718的历史清理成功不受影响。

新增独立 `--inspect-cancelled-install-v16 <UUID>`，只接受该56 UUID和固定目录 `D:\HereIAm-P6-R7-Isolated\56e435bd05cb4569b86dba884d2eb717`。不启动新attempt、不删规则、不中转普通startup或旧cleanup。五个只读共享锁在检查期间持续持有：

| 原始固定证据 | SHA-256 |
|---|---|
| own ownership.json | `3C46568B216ED4C6C30C8576EBCD1101F091B95FD7D3B796EAC8C028090A5560` |
| own report.json / 上述公开副本 | `02B3285F9234FDF9B772A63410967B4BD573225C35AD3864E309F3285789AD21` |
| own copied codex.exe | `3D6CA7085C932B62EF4EE4877E92F15B050FB94B2EB8E6C10A346A06248C6004` |
| 原 `windows_text_gate_appid_coordinator_helper.v16.exe` | `46BBB00841AB2E3759A33716185575786039B22A1C64B472E639A2F5475B5663` |
| 原 exact `native-appid-coordinator-candidate-16.cs` | `52D9B3BBC02BCFF78775F8D3E95299DD22C75BF8CE7A716209EF6068771158F1` |

运行时内部校验strict journal原ownerhash/attempt/nonce/身份、prepared/nullchild；原报告必须install_helper/1223/固定flags、所有CLI关闭/初始化绑定未出现、0stdout/stderr/HTTP/model计数、三个历史Job记录均querytrue/0/0/0。当前检查者须与journal同user/session且primary/nonAppContainer。worker没有读取或输出私有ownership原文，只有纯合成fixture；实际验证由未来单次检查入口内部完成。

原owner PIDcreation检查只用于排他，不是关闭证明。另枚举原v16固定basename的候选，QueryFullProcessImageName/Wait核对原v16精确路径无活动helper/coordinator；复用copiedCLI固定路径的同类检查。任一候选open/query/wait未知拒绝。五锁hash/canonical及当前owner/两镜像idle在WFP查询前、只读事务内和事务结束后重复核验。仍依赖trustedhost/唯一授权启动者，不声称抵抗恶意同权用户在最后检查后启动实例。

使用正确Filter200 Get按own UUID派生三keys+sub，只读事务 `FWPM_TXN_READ_ONLY=1`；[官方fwpmu.h L3215](https://raw.githubusercontent.com/microsoft/win32metadata/main/generation/WinSDK/RecompiledIdlHeaders/um/fwpmu.h)定义此常量，[官方对象管理](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/FWP/object-management.md)说明只读事务隔离。结束调用Abort结束只读事务，不调用任何Add/Delete/Commit/Set，不修改WFP或其它网络状态。

只有三filter均明确not-found且sub明确not-found才all_owned_rules_absent_verified=true、cleanup_pending=false；读取错误/未查完/任一存在均pending。存在时只报告固定role下的presence、known key/layer/sub/AppId/condition匹配布尔、flags/weight类型及数值等结构，以及sub的presence/keymatch/flags/weight/provider-null/data-size/pointer-presence；不输出指针、描述、路径或身份，不接受未知weight为清理许可。没有删除动作，deleted counts始终0，process_close_claimed/job_zero_claimed始终false。

只写该目录内新 `install-cancelled-inspect-report.json`（schema p6_r7_one_attempt_cancelled_install_inspection_v1），不改原report/ownership。diagnostic_only=true、system_mutation_requested=false表示没有请求系统网络变更；新报告仍是本次有限磁盘产物。保存失败回到pending，实际已观测absence可独立保留但不会声称交付完成。不签stop receipt，不把helperexit/缺PID/历史Job0冒充新关闭证明。

| v16b 冻结产物 | SHA-256 |
|---|---|
| 当前source / exact `tmp/p6-r7-review/native-appid-coordinator-candidate-16b.cs` | `C7AC2A3F6D8E71560D5A1F060F3745E8716FC9A05E7EB6CDCBCB92615E70A19A` |
| 当前test | `8CAC5E332A38399810A7194F71D73DD80F737E94D4A80E92AD3DDBD631C87FA0` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.inspect-v16b.exe` | `DC916A4F023A5107687910E83B992B1C2E44A2BEC2BB34107C9320BC9F2E1F61` |

Framework64 x64 `/warnaserror+`编译exit0，Node **23/23 pass、0 skipped**，冻结exe self-test **330 assertions、exit0**。新增58项纯断言覆盖固定UUID/目录、读取不全或任一存在不能缺席、prepared/nullchild、历史错误/计数/绑定变化拒绝。Node确认五锁、两固定image排他、只读事务/无规则写入、原v16普通流程和全部旧恢复片段未改。worker未执行真实入口、WFP读取、进程枚举、UAC/CLI/账户/网络。source/test/exe/snapshot已冻结，实际检查须主控独立审阅并决定调用。

## v16 历史冻结与安装阶段1223（2026-09-12）

2718 历史 pending 已由主控运行冻结 v15b 实际清理完成：helper18632 actual exit0；`tmp/p6-r7-review/native-appid-coordinator-cleanup-05-v15b.json` SHA `B0F7C88109776CC9A6D3A8AE2F904F7373A1B1C03B5610C2A1917DC28A5CF47A`。historical_closure_verified/current_path_idle_verified=true，删除3 filters+1 sublayer，transaction/postabsence=true，cleanup_pending=false。旧 v15 startup 报告整体false原样保留，不覆盖历史、不签新close/Jobzero。

主控独立 Job 哨兵 detached 实测：`tmp/p6-r7-review/native-job-limit-probe-03-detached.json` SHA `1DDFAE35807CD68A2B5FB5A9263310052CEDBEDC64CB5C4128F81487D01AD283`；其creation flags0x0008040C，limit0x2008/1，ready唯一probe、second创建失败1816、first正常exit0、afterActive0。**这是哨兵证据，不能继承为真实CLI的限额行为证明。**

v16 新增独立显式入口 `--apply-coordinator-detached-startup-synthetic <fixed CLI source>`，模式名apply_coordinator_detached_startup_synthetic。共享既有Apply/CreateCli的受控布尔分支，仅新入口请求DETACHED_PROCESS：flags精确 **0x0008040C**（EXTENDED_STARTUPINFO_PRESENT、CREATE_UNICODE_ENVIRONMENT、CREATE_SUSPENDED、DETACHED_PROCESS）。旧默认入口仍 **0x08080404**（NO_WINDOW），没有全局改flags。报告requested_creation_flags/detached_requested表达请求值，不冒充系统实际查询返回的flags。

保留3个stdio HANDLE_LIST、原子JOB_LIST、严格Medium primary身份和同identity、精确CLI pin/image/creation/Job预Resume检查、新仓库外fresh目录、原ConfigMatches、正确Filter200/INDEXED64/assigned weight和v2安装清理receipt。冻结v10/v11c依赖、v12e/v13b/v14b/v15b所有单实例回收逻辑未修改，不增加账户、thread/turn、provider请求或原生子进程测试。

coordinator自身已有两个同步观察点，无需修改冻结stdio依赖或复制协议：initialize Reply返回后，以及ConfigMatches严格通过、stdio.Check后且EndInput前。新分支的ObserveLiveCli使用同一个held CLI handle核PID/creation，然后 Wait(0)==TIMEOUT → 单次Job query → 再次 Wait(0)==TIMEOUT。只有两侧均确认同CLI尚未退出才保留active/total/terminated。未运行、wait未知、查询失败或中途退出时计数为null，固定status解释原因；不会把已退出后的Active0当作during唯一。报告不输出PID、creation、路径、身份或配置原值。

`live_cli_observations` 固定after_initialize/after_config_before_eof两个键；single_member_at_observation仅该点确认活跃且Active1/Total1才true。active_cli_observations_complete与single_member_at_both_observations分别汇总两点。**这些是离散观察，不能证明全窗口持续唯一，也没有实际尝试创建第二个CLI。** 未确认的观察不补造证据；候选不扩大本次任务为native sentinel。

`detached_cli_compatibility_passed` 仅镜像原coordinator_startup_passed：仍须固定初始化/config、stdin EOF后实际exit0、Jobzero、readersEOF、0HTTP及真正helper退出+清理receipt/postabsence全部成立。观察的Active/Total不是兼容通过条件，单独报告，避免把启动兼容等同进程限额验收。single_process_enforcement_tested始终false；network_enforcement_tested、production/human Gate仍false。报告写失败也把兼容标志置false。

| v16 冻结产物 | SHA-256 |
|---|---|
| 当前 source / exact `tmp/p6-r7-review/native-appid-coordinator-candidate-16.cs` | `52D9B3BBC02BCFF78775F8D3E95299DD22C75BF8CE7A716209EF6068771158F1` |
| 当前 test | `7C55241695386BDC3FEC5B6FD50779DDF46568FBBB1D95742C78C5E0CA1B721D` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.v16.exe` | `46BBB00841AB2E3759A33716185575786039B22A1C64B472E639A2F5475B5663` |

Framework64 x64 `/warnaserror+`联合编译exit0；Node **22/22 pass、0 skipped**；冻结exe self-test **272 assertions、exit0**。新增18项纯断言覆盖新旧flags、双Wait边界、查询失败/退出不输出计数、Active/Total异常不称唯一、两点完整性。Node确认新入口/默认分支、3handles与Job/token/pin边界、ConfigMatches与EndInput的观察顺序、旧历史和WFP/helper/journal/receipt片段未变。worker未运行actual/UAC/WFP/CLI/Job/network/账户或创建外部目录；源码/测试/exe/snapshot已冻结。

主控审查后由normal Medium进程运行新入口，仍需两次单次系统确认（安装/清理）。不要直接从elevated进程执行coordinator，也不要把清理helper退出当CLI退出。本候选的成功需新实际证据，不能使用上方哨兵或v15结果替代。

矩阵合同另见 `P6_R7_WINDOWS_APPID_MATRIX_HANDOFF.md`：contract-v1已冻结且11/11+self302，但没有native runtime入口，不在v16中接线。

## v15b 历史冻结与实际清理成功（2026-09-12）

主控 v15 实际 attempt **2718ce42-8bc5-42e8-9be3-2a8939c6157d**：仓库外 cwd 的 config checks 全通过，project0、repository_ancestors_absent_verified=true；stdin EOF 后真实 CLI exit0、stdio EOF、stderr0、HTTP/turn0。Job class9 flags8200/limit1/exacttrue；before/after termination 均 Active0/Total2/Terminated0。第二次 cleanup UAC 启动返回系统1223，未启动 cleanup helper，因此规则 pending；这不是自动审批拒绝，也不据此推断用户明确撤销。普通 owner/child/Job 已释放。startup 整体尚未通过，仍不得宣称网络矩阵或生产隔离通过。

v15b 仅新增 `--cleanup-closed-v15 <UUID>`，硬编码该 UUID 及唯一外部目录 `D:\HereIAm-P6-R7-Isolated\2718ce428bc542e89be32a8939c6157d`；不通过旧 DirectoryFor 推导，不接受其它外部路径。普通 v15、v12e/v13b/v14b 恢复代码未改。七个 FileAccess.Read/FileShare.Read 锁绑定如下，事务前至提交后持续持有且重复 hash/canonical 检查：

| 固定证据 | SHA-256 |
|---|---|
| own ownership.json | `410981511E8C926EC0CB6DA2713288A5D5DA911160659FC7150A0AF8A6B61066` |
| own report.json / `tmp/p6-r7-review/native-appid-coordinator-startup-04-outside-repo.json` | `DA55CA15A1BE96201AA112110198C32CEB113AC077CA091F72AB59875C37C04C` |
| own install-report.json | `B98B048235177E34C116D9726821310696594BBEEA930E0FB77400757A1D9A36` |
| own install-receipt.json | `B676B3135BB171B07E220FC29F1CBF64836BF3141D58D080A1561EE9098B44C2` |
| own copied codex.exe | `3D6CA7085C932B62EF4EE4877E92F15B050FB94B2EB8E6C10A346A06248C6004` |
| frozen v15.exe | `323EA1C229043EDC4D5B816D153243DCE62B9AB7C980BDF0D4C527DC6E2F8660` |
| exact candidate-15.cs snapshot | `C1F07E9487B8CE25D0ACC2D5BBB03B69C975CBB7E448698D288FF6263CFF9311` |

内部仍严格校验 closed journal 的精确 child PID/creation、原 owner hash/token，同user/session，v2 install receipt 的 nonce/owner/helper PIDcreation/pin/AppId digest/assigned32766。原报告还须 finished/helper_uac_launch_failed/1223、actual exit0、config/EOF/identity/Jobzero 真值、before/after0/2/0 和 class9精确8200/1。当前 owner/child inactive 只作排他证明；枚举 codex 候选的实际 image 确认 copied path idle，任何 open/query/wait 未知拒绝，不读取 command line 或身份原值。

复用已审 exact Filter200/INDEXED64/3 filters+sublayer32766 的事务检查，只允许全匹配或全缺失；partial/mismatch 保留 pending。仅删该3 keys+sub，提交后全不存在才清理通过。不删目录，不创建新 Job/CLI，不把 missing PID、helper exit 或历史记录签作新的 close/Jobzero。报告 `historical-close-v15-cleanup-report.json` 继续 `historical_closure_verified/current_path_idle_verified`，始终 process_close_claimed/job_zero_claimed=false。受信同权宿主且没有并行启动本复制镜像的前提不变。

| v15b 冻结产物 | SHA-256 |
|---|---|
| 当前 source / exact `tmp/p6-r7-review/native-appid-coordinator-candidate-15b.cs` | `8C167106C5B1516F93DC6BAFBC7795B9DA6C76A249F664C2B1D2411B5B4205D9` |
| 当前 test | `5B9193A7439A487E77082503DF3B41103D595B015699655942AE08E7EB6B4BC0` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.cleanup-v15b.exe` | `7A6BD9A051235DBBBEFED13EC1B3F51FEE39788223E6C39EF5FE5AB715FEBABD` |

Framework64 联合编译 exit0，Node **21/21 pass、0 skipped**，冻结 exe self-test **254 assertions、exit0**。新增30项纯断言覆盖外部固定目录/错误UUID、历史退出条件、原报告计数/limit改变与旧receipt/digest混用拒绝；Node确认7锁及普通v15/旧恢复片段未变。worker没有执行UAC/WFP/CLI/进程枚举或访问账户，source/test/snapshot/exe 已冻结。以下为该历史单次清理命令；已实际完成，不应重复作为新验收：

```powershell
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.cleanup-v15b.exe' -ArgumentList @('--cleanup-closed-v15','2718ce42-8bc5-42e8-9be3-2a8939c6157d') -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
```

并行 matrix 包已暂停：仅新增纯合同草稿 `tools/dev_agent_bridge/windows_text_gate_appid_matrix_helper.cs`，尚未编译、未测试、无实际运行接线，不属于本次冻结，也不能当作可运行矩阵。

## v15 历史冻结与实际配置/正常退出证据（2026-09-12）

此前 d06f 的 v14b 单实例清理已由主控实际完成：helper actual exit0，historical_closure_verified/current_path_idle_verified=true，删除3 filters+1 sublayer，transaction committed、postallabsent=true，cleanup_pending=false。报告 `tmp/p6-r7-review/native-appid-coordinator-cleanup-04-after-close.json` SHA `4F4EA661A09FA83BA68CBAD0154676C95D525683C8EA54A343F559512C5E79C0`。仍不签发新 process-close/Jobzero 证明；该历史结果不替代 v15。

v15 普通 Apply/Elevated/InvokeHelper 仅通过独立 NormalDirectoryFor 使用固定仓库外 `D:\HereIAm-P6-R7-Isolated\<UUID N>`。原 Root/DirectoryFor、v12e/v13b/v14b 单实例恢复保持原逻辑和旧路径。新目录根只在严格不存在时创建并设置 own ACL；已有根仅校验，不重新设 ACL，不修改 D 根或既有祖先。复制镜像、empty-home/empty-workspace/Temp 全在新 attempt 内，绝不复制账户资料。**worker 未创建外部根；主控执行前须具备该外部目录的明确工具授权。**

运行时先 canonical/no-reparse 核对 D 和祖先；创建后的路径再次核验。启动前逐级检查 cwd 到 D 根的 `.git`/`.codex`，并明确检查 cwd 的 `config.toml` 均不存在；仅接受 GetFileAttributesW 的 file-not-found 2，其它错误或现存元数据均拒绝，不读取配置内容。检查分别在准备完成及紧邻 CLI 创建前运行。原 ConfigMatches 完整保留，不接受空 project 层。依据固定 CLI commit 的 [配置 loader](https://raw.githubusercontent.com/openai/codex/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/config/src/loader/mod.rs#L101-L113)，cwd 配置、父 `.codex` 和仓库层可能参与加载；移动目录仍需实际 config/read 证明，不能用本地检查替代。

VerifyHeldClosedChild 删除已退出进程上的 TokenProof.Image 查询；仍核对同一 held handle 的 PID/creation、closed journal 和 signaled。CreateCli 在 Resume 前的 image/pin/token/Job 全校验保持原样，只有完整返回后写 bound，实际 exit+Active0 才写 closed。收尾重新 hash copied image/self 并重读校验 journal；不把 PID 缺失、路径名或 helper exit 当成 child close。

创建 Job 后、UAC/CLI 前新增 class9 ExtendedLimit 实际 readback：x64 Basic64/Extended144/Accounting48 和关键 offsets 先断言，flags 必须精确0x2008，ActiveProcessLimit 必须1。报告固定 query_success/flags/active_process_limit/exact，查询失败数值为null且拒绝。此项验证配置回显，**不证明第二进程被拒绝**；v14 曾观测 Active2/Total2/Terminated0 的行为问题仍待独立 sentinel 验证，本包不追加行为通过声明。no-child 分支仍 Active0+Total0。

| v15 冻结产物 | SHA-256 |
|---|---|
| 当前 coordinator source / exact `tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs` | `C1F07E9487B8CE25D0ACC2D5BBB03B69C975CBB7E448698D288FF6263CFF9311` |
| 当前 coordinator test | `7FF2B637D15A4FF6F616280DF33815F87E3D6C21536C0263DC1BE5E43F39095C` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.v15.exe` | `323EA1C229043EDC4D5B816D153243DCE62B9AB7C980BDF0D4C527DC6E2F8660` |

Framework64 联合编译 exit0；Node **20/20 pass、0 skipped**；冻结 exe self-test **224 assertions、exit0**。新增纯边界覆盖外部根/旧根分离、空 UUID/错误卷拒绝、祖先链、元数据严格缺失、Job limit 精确值；Node 验证入口路由/先验顺序/cwd config.toml/退出后无 Image 查询及旧恢复代码未变，并检查只读测试没有创建任何外部根。主控另复跑20/20+224且独立审计无P1/P2。源码、测试、snapshot、exe 已停止修改，交接文档单独更新。

本包未运行 UAC/WFP/Job/CLI、进程枚举、账户或网络操作。实际候选仍仅无认证 initialize/config-read/EOF；network_enforcement_tested=false，production/human Gate=false。正常启动、实际完整 cleanup 和网络行为矩阵必须分别获取新证据。

## v14b 历史冻结与实际清理成功（2026-09-12）

主控实际 v14 attempt **d06f803f-69b0-44f0-bed9-37252a02dc00**，coordinator exit3。config_diagnostic 的22项 checks 全 true、全部 Disabled 为 false；layers 仅多一个 project（system/sessionFlags/user 各1），非session配置计数0，原 gate 拒绝 project 类型。当前只定位该差异，不改配置通过条件。

实际 Job 记录：created active0/total0/terminated0，child_created 1/1/0，before_termination **2/2/0**，after_termination 0/2/0。原 child 实际退出、Jobzero 与 stdioEOF成立，0HTTP/turn；普通 cleanup 在查询已退出 child image 时出现 `process_image_query_failed`，未启动cleanup UAC，规则仍 pending。**Active2/Terminated0 不能称作已证实的被限额拒绝创建；原 singleton 限制的真实有效性另待调查。** 本候选不修普通启动或替它补通过证据。

v14b 仅新增独立 `--cleanup-closed-v14 <UUID>`，只接受上述 d06f UUID，旧 v13b/12e 历史清理及普通 v14 均逐段保持原样。新包装绑定自己的7个只读证据锁，保留完整 closed journal/owner+child PIDcreation、成功install v2 receipt 的nonce/helper/pin/AppId digest/assigned32766绑定，及原actual-exit/Jobzero/CLIidentity等精确true；额外要求本次 after_termination 的 query_success=true、active0、total2、terminated0。Total2不被解释成新的Job关闭证明。

| d06f 固定证据文件 | SHA-256 |
|---|---|
| own `ownership.json` | `582631A8339C19F7139A1AFD6C01B6DE1E45824EA0D42D5050B72CCF38F5B334` |
| own `report.json` / `tmp/p6-r7-review/native-appid-coordinator-startup-03-config-diagnostic.json` | `F8E33BA1561EA68478758285A5C88AA87152A75335A59BA68073550E8E2D9D9F` |
| own `install-report.json` | `4AB036F0EF372D9CBFD4764A894065CF0B6EC53A008258106ED435850479B00C` |
| own `install-receipt.json` | `49812D1A4F3A619F9D294DBB0C2A794581B19C241389B29BD0D93E20F8DDC6DC` |
| own copied `codex.exe` | `3D6CA7085C932B62EF4EE4877E92F15B050FB94B2EB8E6C10A346A06248C6004` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.v14.exe` | `139DC88B052E6CF3A4340682D2AC756603DA3FADB3AEC9C1DADD89EB35611740` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-14.cs` | `8318E5BC821CC32C8DC579D09D8CCEBE33EEB8836C5FB9AA6A2199A503FD53DC` |

当前inactive和copied-path-idle复用已审v13b实现：原owner/child活跃或未知拒绝，PID缺失/复用仅排他；每个codex候选均查询实际image和wait，查询未知拒绝。7锁及这些证明在事务前/删除前/commit前/提交后反复核验。WFP仅允许exact3+sub或全空；Filter200/INDEXED64/原conditions与weight精确，sublayer32766/flags0/provider与data为空不变；partial/mismatch拒绝，删除后全不存在才cleanup_pending=false。不删目录、不扩大到其它attempt、不运行新CLI。

新报告 `historical-close-v14-cleanup-report.json` 使用历史关闭清理schema，输出fixed attempt、historical_closure_verified/current_path_idle_verified、计数和稳定错误；process_close_claimed/job_zero_claimed仍false。只有历史关闭与当前排他证据，不签新stop receipt。可信同权宿主/无并行启动本copied path前提与v13b一致。

| v14b 冻结产物 | SHA-256 |
|---|---|
| 当前 coordinator source / exact `tmp/p6-r7-review/native-appid-coordinator-candidate-14b.cs` | `22F4E29B2551B246F5CB5F7E11827E613D65DC61F20C1DFD761B884F16F5A8C6` |
| 当前 coordinator test | `A7AF005712020A304929B1EED44EFDBCE1067BF6164E2925876D6F3519D8148F` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.cleanup-v14b.exe` | `AEB58BB432EB17272CF2F78E251C9E3BD2017C84D7C38E1C10F91D1D7F0D0065` |

编译 exit0、Node **19/19 pass、0 skipped**、冻结 exe self-test **205**、exit0。新增17个纯边界覆盖d06f UUID/旧owner拒绝、closed phase、actual关闭布尔、原after-termination四项、原cleanup错误及receipt/digest混用拒绝；Node确认7锁、原v13b和普通v14代码未改。worker未运行 UAC/WFP/CLI/账户/进程枚举。历史执行命令（本次已成功，不应重复当作新验收）：

```powershell
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.cleanup-v14b.exe' -ArgumentList @('--cleanup-closed-v14','d06f803f-69b0-44f0-bed9-37252a02dc00') -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
```

## v14 历史冻结与实际启动失败（2026-09-12）

87c 历史 pending 已实际清理：主控运行 v13b helper，actual exit=true/exit0；`tmp/p6-r7-review/native-appid-coordinator-cleanup-03-after-close.json` SHA `F0C4181E71D4E1884F2B305B3E696AFB5B52D68245FD08CBBAFDF6FD2D3B14D0`。historical_closure_verified/current_path_idle_verified=true，删除3 filters+1 sublayer，commit 后全不存在，cleanup_pending=false；process_close_claimed/job_zero_claimed 仍 false。此历史结果不替代 v14 验收。

v14 仅修正普通 spawned cleanup 的计数门槛，并增加固定诊断。已创建 child 分支不再要求累计 Total==1：coordinator 必须持精确 child handle，核对 closed journal 的 PID/creation、image 和 signaled 状态，再确认 held Job Active0。辅助 cleanup helper 从严格 journal 打开并核对同一 child，持续持有到验证、删除、回执完成后 finally 才关闭；每次清理证明都重新检查该 held handle。receipt v2 的 owner/nonce/pin/AppId/assigned weight 绑定维持原样。未创建 child/安装/rollback 分支仍要求 prepared/null child、Active0 **且 Total0**；ActiveLimit1、atomic JOB_LIST、kill-on-close/no-breakaway 不变。不使用 Total-Terminated 作为放行条件。

`job_accounting` 只在固定 stage 记录一次原生 Query 同时得到的 query_success/active/total/terminated：job_created、child_created、before_termination、after_termination、cleanup、helper_preflight、helper_revalidation（后者保留最后一次结果）。查询失败数值为 null，不冒充0；核心字段只来自同一次 Query。Total/Terminated 是诊断，不抵消真实 Active 或 child 句柄证明。

`config_diagnostic` 仅本地固定投影，diagnostic_only=true。**原冻结 CliStartupContract.ConfigMatches 仍是唯一 config 通过条件**，其真值直接作为 matches；投影不改 args、配置值或原接受条件。checks 中22个逐项 bool 分开定位 model/model_provider、approval、sandbox、web、project doc、agents、mcp、notify、hooks，以及 provider URL匹配/wire API/auth/retries/websockets/凭据来源缺失/headers与query为空和skip-host-skill-discovery。输出只有布尔，不含 URL、路径、配置原值、未知字段或 header/token 内容。

Disabled 特征词表逐字保持 frozen core，一项一个 missing/false/other；原始 value 与未知 key 不输出。layers 只给 shape_valid/types_allowed、非 sessionFlags 含配置的布尔/计数，以及固定10类计数：system/sessionFlags/user/project/packagedDefaults/enterpriseManaged/mdm/legacyManagedConfigTomlFromFile/legacyManagedConfigTomlFromMdm/unknown。未知 type 仅累计 unknown，不回显原串。固定词表参考同 commit 的 [config_layer.rs API 转换](https://raw.githubusercontent.com/openai/codex/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/app-server/src/config_layer.rs)；[config_manager_service.rs](https://raw.githubusercontent.com/openai/codex/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/app-server/src/config_manager_service.rs) 按 cwd 加载层并过滤 packagedDefaults。project 层可能是此前失败原因，但尚未实际观察，不能据此放宽原 gate。

旧 v13b/12e 专用恢复入口逻辑保持不变，源码片段与快照逐段比较；原 v10/v11c 源及全部既有 snapshot/exe 未覆盖。不新增网络矩阵、生产 IPC 或真实模型请求。普通候选仍只 initialize/config-read/EOF，network_enforcement_tested=false、production/human Gate=false。

| v14 冻结产物 | SHA-256 |
|---|---|
| 当前 coordinator source / exact `tmp/p6-r7-review/native-appid-coordinator-candidate-14.cs` | `8318E5BC821CC32C8DC579D09D8CCEBE33EEB8836C5FB9AA6A2199A503FD53DC` |
| 当前 coordinator test | `7E1256A41201D80A944746477D875A82ED37BCAEA4846C454A28CEAED4B5B1C6` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.v14.exe` | `139DC88B052E6CF3A4340682D2AC756603DA3FADB3AEC9C1DADD89EB35611740` |

实际编译 exit0、Node **18/18 pass、0 skipped**、冻结 exe self-test **188**、exit0。新增39个 managed 检查涵盖单次计数投影/unknown不冒充0、spawned与no-child计数区别、每个核心配置组负例、feature三态、未知PRIVATE字段不泄露、layers拒绝及project/unknown固定计数。所有投影 fixtures 的matches和独立谓词汇总均与原 ConfigMatches 真值一致；Node另核对核心词表、原 ConfigMatches 调用、helper held-child 关闭顺序、诊断 stage 及旧恢复代码未变。worker未运行 UAC、实际 WFP/CLI/账户/网络或进程枚举；主控独立审计后再运行当前冻结候选。

## v13b 历史冻结与实际清理成功（2026-09-12）

主控实际 v13 attempt **87c68152-eba1-4012-9edd-8afb6a1f26b3**：install/receipt/实际 weight32766 验证成功；CLI created、identity/Job/pin、wrong-peer 拒绝与 initialize 回复均成立，但 config/read 校验拒绝。退出阶段实际 child exit、Job Active0、stdio EOF 成立，0 HTTP/turn；随后的 Total==1 清理门槛拒绝，因此未启动 cleanup UAC，owner/Job 已释放，规则仍 pending。原报告 SHA 54368... 见下表。

只读审计：core StopAndProveZero 仅要求精确 child 退出 + Active0，普通 coordinator 清理额外要求 Total==1；两者不矛盾。[Windows 官方 Job accounting](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_accounting_information) 明确 Total 包含因限额违规而失败的进程关联尝试，Terminated 只计限额违规终止。当前未记录实际 Total/Terminated，不能确认本次是否由拒绝的子进程尝试引起，更不能直接用 Total-Terminated 放行。配置具体失败字段亦未知，普通 startup 条件本包不改。

v13b 只新增独立 `--cleanup-closed-v13 <UUID>`，硬编码上述 UUID。它不是 never-spawned，也不会被普通 startup 自动调用。七个证据文件以 FileAccess.Read/FileShare.Read 持锁，拒绝写/删除，持续到事务提交后复核：

| 固定文件 | SHA-256 |
|---|---|
| own `ownership.json` | `899163B2BF9C8752145408CB61FD57EAFC5A279E188133DD3F0B299CE9150EF0` |
| own `report.json` / `tmp/p6-r7-review/native-appid-coordinator-startup-02.json` | `54368F7530C8A7F8AFF36BFB88309D16AB07855EE87C8C962397DA0E6D42F0E6` |
| own `install-report.json` / `tmp/p6-r7-review/native-appid-coordinator-install-02.json` | `13C941EFD0FB07B9DFFC144BE43F87771CC72D39F0CB10B6967C070EAD95CB78` |
| own `install-receipt.json` | `273E00B3FFDDF7B594AB82D2DF1861AF520F1DCA0FF6815BD800FB33BA562688` |
| own `codex.exe` | `3D6CA7085C932B62EF4EE4877E92F15B050FB94B2EB8E6C10A346A06248C6004` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.v13.exe` | `FE9110D1C92EEE129D9B97666FC2707DF9B2E6FB182C20322F2F6695EA3F0744` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-13.cs` | `BD69A6CD416B81AC1D5981C62D4EE2F8366BBD6D5679462893CBF17E9B693A18` |

内部校验 strict closed journal、非空 child PID/creation、原 v13 owner hash；原报告的 installed/CLIidentity/owned-child/actual-exit/Jobzero/stdioEOF 等精确为 true，错误阶段和0请求与实际报告匹配；install report 成功且无错误。严格 v2 install receipt 绑定原 nonce/owner PID+creation/imagehash/helper PID+creation/CLI pin/AppId blob digest/assigned weight32766。所有原身份值只在内部验证，不输出。

当前 Full/elevated helper 必须与 journal 同 user/session、non-AppContainer。原 owner 和 child 分别按 PID/creation 检查：同一实例活跃或状态未知均拒绝；PID缺失/复用仅作排他性证据，**不是新 close 证明**。另枚举 codex.exe 候选进程，以 QueryFullProcessImageName 查询实际路径，拒绝精确 copied path 的活进程；任何候选 open/query/wait 未知均 fail-closed。只查询进程名/实际 image，不读 command line、认证或任意文件。证据 hash/无reparse/实际文件句柄路径与当前排他检查，在事务前、事务内删除前、commit前、提交后重复。

使用正确 Filter200 Get，在同一 WFP 事务中仅允许精确三个 filters+sub（INDEXED64、原 action/权重/conditions/AppId、sublayer32766/flags0/provider-null/data空），或四者全缺失；partial/mismatch 拒绝。仅删除该3 keys+sub，提交后确认全不存在才 cleanup_pending=false；不删除目录，不改普通 startup 和旧 v12e 恢复。该路径依赖受信同权宿主且没有并行启动该复制镜像，不声称能抵抗恶意同用户在检查后启动进程。

新报告 `historical-close-cleanup-report.json` / schema `p6_r7_one_attempt_historical_close_cleanup_v1` 仅含固定 attempt、布尔、计数、阶段/错误：historical_closure_verified、current_path_idle_verified、规则删除/absence。始终 process_close_claimed=false、job_zero_claimed=false，不签发 stop receipt；当前独立检查失败仍 pending，不复用旧事实填造新 Job。

| v13b 冻结产物 | SHA-256 |
|---|---|
| 当前 coordinator source / exact `tmp/p6-r7-review/native-appid-coordinator-candidate-13b.cs` | `3C912ABC5361C841CC766944A5068649941BE9E368D8EAD085815D2FCE908296` |
| 当前 coordinator test | `BE0DC13559E79C1AAA1965EF2DBFF7272EF154A9400F3376BDD333D29D221B1C` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.cleanup-v13b.exe` | `7B24588BBBA2AFEDCBEBACD6BD6105AC2DA0F94B30A8BD923D8F2855DE50F2F7` |

联合编译 exit0；Node **17/17 pass、0 skipped**；冻结 exe self-test **149**、exit0。新增31个 pure检查覆盖唯一UUID、closed/child绑定、各历史closure布尔、原阶段/错误/0请求、receipt nonce/digest、PID实例排他与候选路径未知拒绝；Node确认7锁、事务次序、旧普通路径与v12e代码未改。worker没有运行进程枚举、WFP/UAC、CLI、账户或网络。主控独立复核后才可运行一次清理：

```powershell
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.cleanup-v13b.exe' -ArgumentList @('--cleanup-closed-v13','87c68152-eba1-4012-9edd-8afb6a1f26b3') -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
```

## v13 历史冻结与实际启动失败（2026-09-12）

历史 pending 已由主控实际清理：v12e helper exit 0，`tmp/p6-r7-review/native-appid-coordinator-cleanup-02-assigned-weight.json` SHA `39140DECE0A0C9E329ADBF5170C5A3C69B6CCB0FF5547F3434E15E798AF89C8E`。实际删除 3 filters + 1 sublayer，提交后全不存在，cleanup_pending=false；process_close_claimed/job_zero_claimed 仍 false。此证据仅覆盖固定旧 UUID 的 never-spawned 资源回收。

v13 恢复普通 `--apply-coordinator-startup-synthetic <pinned codex.exe>` 及其 install/cleanup helper 入口。默认/plan/token-plan/self-test 仍只读。普通 WFP Add/Get 全部使用本地 Filter200，新的 Add PInvoke 参数明确 `ref InspectionNative.Filter`；coordinator source 不再引用旧 Native.Filter 或旧 Filter Add/Get。输入与读回只接受 INDEXED=64，原 action/weight/type/conditions/AppId 精确条件不变。旧 v12e 单 UUID 清理段、固定证据链及只读 Inspect 保持不变；不把旧 Inspect 用于新 attempt。

安装在事务外和事务内分别要求全部派生对象不存在；添加 sublayer 后在同一读写事务读取 actual UInt16 assigned weight，验证 flags0/provider-null/data-size0/data-pointer-null，再加入三条过滤器，完整精确读回后 commit。提交后再次完整读回。之后所有普通 verify/cleanup 都绑定该实际 weight；不是允许任意变更后的 weight。Microsoft [WFP Object Management](https://learn.microsoft.com/en-us/windows/win32/fwp/object-management) 明确 WFP 支持读写事务及 ACID，并说明操作失败不会自行中止事务；[GetByKey](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmfiltergetbykey0) 支持读取过滤器。候选显式 abort 失败事务；本机事务内读取的实际可用性仍待主控实测。

receipt 升级为 **p6_r7_appid_coordinator_receipt_v2**，增加必需 `actual_assigned_sublayer_weight`。install/cleanup 必须为 UInt16 范围的整数，拒绝旧缺字段、null、负数、超限、字符串或布尔。唯一 `install_rollback` action 允许 null，表示在取得 weight 之前失败且已严格确证全不存在。receipt 仍绑定 attempt/domain/nonce/coordinator PID+creation+imagehash/CLIpin/AppId digest/实际 helper PID+creation；coordinator 先观察精确 helper 实际退出，再接受对应回执。cleanup helper 从严格 install receipt 取 weight；coordinator 验证 cleanup receipt 时再次要求与已保存的 installRun.Weight 一致。

安装 helper 内 install/写 receipt 失败会保留首个固定错误及 Win32 值。仅在先前确证全空，且 owner 仍 live、named Job Active=0/Total=0、journal 仍 prepared/null child 时，尝试 exact-owned 回滚。事务内再次证明 owner/Job/journal，精确读回完整三条+子层或四者全缺失；partial/mismatch 拒绝。删除后 commit，再证明 owner/Job 与全缺失，才写独立 install-rollback-receipt。只有该回执成功写入，helper cleanup_pending 才 false；仅 absence_verified 而回执写失败仍 pending。coordinator 只有 helper 实际 exit3 + 专用回执完整匹配 + 自身仍持空 Job 才认可该清理，不把 helper exit 当 CLI close。

**保守未实现分支**：helper timeout/close 未知，以及 exit0 但 install receipt 缺失或失效，均禁止 CLI spawn，保持 pending；不启动并行第二 helper，不自动运行依赖失效 receipt 的普通 cleanup，也不泛化 missing-Job 恢复。失败 helper 已实际退出但 rollback receipt 缺失/失效也不声称 clean。正常 cleanup 仍需 coordinator 活着并持 Job/实际 child handle，child 实际退出及完整 binding，Active0/Total1 后由第二个 UAC helper 删除；清理回执不是 process/Job stop receipt。

普通 CLI 参数、固定 pin、无认证空 home、medium Limited primary、atomic singleton kill-on-close Job、3-handle stdio allowlist、精确 tuple/PID/creation/image/token peer 检查维持原样。只 initialize/config-read/stdin EOF，要求实际 exit0/readers EOF/Jobzero/cleanup 完整；不发 thread/start、turn 或模型请求。broker 仅返回403，任何实际 CLI HTTP 均使 startup 失败。**network_enforcement_tested=false**，startup 通过也不是 broker 正控、生产接线或 human Gate。

| v13 冻结文件 | SHA-256 |
|---|---|
| 当前 coordinator source | `BD69A6CD416B81AC1D5981C62D4EE2F8366BBD6D5679462893CBF17E9B693A18` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-13.cs` | `BD69A6CD416B81AC1D5981C62D4EE2F8366BBD6D5679462893CBF17E9B693A18` |
| 当前 coordinator test | `EE3E9435160E9140365686DE443D2F1A8053C4F679F206A7ED00AE5175058AEB` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.v13.exe` | `FE9110D1C92EEE129D9B97666FC2707DF9B2E6FB182C20322F2F6695EA3F0744` |

实际联合编译 exit 0、Node **16/16 pass、0 skipped**、冻结 exe self-test **118**、exit 0。新增 31 个 managed 检查覆盖安装各阶段故障/abort 与 postcommit 顺序、回滚证明失败立即停止、strict owner/Job0 条件、实际权重一致性及 receipt 字段拒绝；同时普通 ExactFilter 复用既有正/负 fixture。Node 确认旧 v12e 恢复与 Inspect 未改、正确 Add/Get ABI 和回执/退出顺序。全部只使用 managed/fake/只读 token，不运行 UAC、实际 WFP、CLI、认证或网络；没有继承旧候选的系统通过结论。主控独立复核后才可从已确认的普通 medium shell 实跑，并由用户分别确认安装和清理的两次 UAC。

## v12e 历史冻结与实际清理成功（2026-09-12）

主控实际 v12d inspect exit 0；`tmp/p6-r7-review/native-appid-coordinator-inspect-02-sublayer.json` SHA `F25BE0DAEE071D9E082343725E9B22BB920E5F5AEB59248307EB220734352BD1`，与 own `inspect-report.json` 相同。实际 sublayer weight=32766（0x7ffe），flags=0、data_size=0、data_pointer_nonnull=false、key_match/provider_null=true；三个 filters 均保持此前精确匹配。v12c 清理仍未完成。

v12e 仅为 UUID **dce75105-11ad-49c7-bc16-377823ceecc8** 固定 `NeverSpawnedAssignedWeight=32766`。pure `ExactNeverSpawnedSublayer` 保持精确 key、flags0、provider-null、空 data；另明确要求 data pointer 为 null。**这是本次实际观察值，不是通用任意 weight 许可。** report 固定字段 `fixed_observed_sublayer_weight=32766`，不扩大恢复范围，不声称 process close 或 Job zero。

新增第六个 FileAccess.Read/FileShare.Read 证据锁：本 UUID 的 `inspect-report.json`，只接受上述 F25... SHA。它与原 ownership/report/install-report/copied CLI/原 v12 exe 五个锁一起持续到事务提交后确认，并在每次 VerifyEvidence 重验。原三个记录、exe/pin、同 user/session、owner 排他检查及 never-spawned 链全部不变；不根据新日志传入路径或权重。普通 startup/apply/install/cleanup 仍禁用，v13 未开始修改。

| v12e 冻结文件 | SHA-256 |
|---|---|
| 当前 coordinator source | `3AB4996EF9BE291C3884DD98B0635B56FC5DFE5A4155F97D71226CF09BFFCF2B` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-12e.cs` | `3AB4996EF9BE291C3884DD98B0635B56FC5DFE5A4155F97D71226CF09BFFCF2B` |
| 当前 coordinator test | `0AAACC3A4B5546CF3D671B730B057AEED24F2306828FEBFF7659439B87B15FBF` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.cleanup-v12e.exe` | `168AF0D1AF9D8D87F21B359FB974396081D0C0D8E31DCBA7849BA025FAEA1EFC` |

联合编译 exit 0、Node **15/15 pass、0 skipped**、冻结 exe self-test **87**、exit 0。新增 9 个 managed 检查：32766 接受；32767/0/65535、key、flags、provider、data_size、data pointer 改变拒绝。Node 将 cleanup 与 v12d snapshot 比较，除新锁/固定报告字段外保持一致；只读诊断源码未变。旧冻结依赖、exe、snapshot、原报告不变。worker 未运行 UAC、实际 cleanup/WFP/CLI 或网络；真实清理待主控独立审计后执行。

唯一候选清理命令（worker 未执行）：

```powershell
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.cleanup-v12e.exe' -ArgumentList @('--cleanup-never-spawned-v12','dce75105-11ad-49c7-bc16-377823ceecc8') -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
```

## v12d 历史冻结与实际只读成功（2026-09-12）

主控实际运行 v12c cleanup，helper exit 3；`tmp/p6-r7-review/native-appid-coordinator-cleanup-01.json` SHA `A18835D16F1E35630DE77A74E57C8349E3609BC2632A802EF29879E265FB1DED`。never_spawned_verified 与 owner_inactive 均 true，但 transaction_revalidation 阶段拒绝 `never_spawned_sublayer_mismatch`，transaction_committed=false，未进入删除。历史 pending 尚未清理，v13 普通启动暂停；本轮未修改任何 v13 实现。

v12d 仅扩展 `--inspect-own-appid <UUID>` 只读诊断，在三个 filters 之外新增 `sublayer` 固定字段：present、flags、weight、data_size、data_pointer_nonnull、key_match、provider_null。不存在时仅 present=false；读取失败保持固定错误码。data 指针只比较是否非零，不解引用、不输出；不输出 display、路径、任意 GUID 或结构全文。报告另给 sublayer_layout_size=72；x64 self-test 断言 Flags32/Provider40/Data48/Weight64。既有 scope 与清理谓词不变。

| v12d 冻结文件 | SHA-256 |
|---|---|
| 当前 coordinator source | `59537A3416A2B3AA9739138E8757103D1B80B9CE20B1F52E5B39B70EB9CA58D7` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-12d.cs` | `59537A3416A2B3AA9739138E8757103D1B80B9CE20B1F52E5B39B70EB9CA58D7` |
| 当前 coordinator test | `92B5AE16F30866FED407C427AA19AF92EE1EA8D5665E050D79CC17A18BE8C7E3` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.inspect-v12d.exe` | `9A58299715176A1BBC6116ED0B614F047E8351794B9A4BDA105A3810A1DED8ED` |

实际联合编译 exit 0，Node **15/15 pass、0 skipped**，冻结 exe self-test **78**、exit 0。新增三个 managed 检查覆盖固定 schema、data/display/任意 key 不泄露、错误 key/provider 与空 data 布尔；Node 另逐段比较 v12c snapshot，确保 CleanupNeverSpawned 与 ReadNeverSpawnedRules/VerifyEvidence 未变。旧冻结依赖、exe、snapshot 和原报告保持不变。worker 未运行实际 inspect、UAC、WFP、CLI、账户或网络；不把本地测试视为实际字段证据。

主控独立复核后运行的只读诊断命令（worker 未执行）：

```powershell
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.inspect-v12d.exe' -ArgumentList @('--inspect-own-appid','dce75105-11ad-49c7-bc16-377823ceecc8') -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
```

等待实际字段证据，不据输入 weight 猜测回显或放宽 cleanup；production/human Gate 仍 false。

## v12c 历史冻结与实际失败（2026-09-12）

主控已实际运行 v12b inspect，exit 0；`tmp/p6-r7-review/native-appid-coordinator-inspect-01.json` SHA `DD8A3045AF183B59619C70A426676AB95077B6F8C830E51960674EE22820E741`。三个 own filters 均存在，flags=64、weight_type=1（allow 15、deny 0），所有 key/layer/sublayer/provider/AppId/conditions 匹配。实际 prefix rejection 来自 flags 原先要求 0；Filter union ABI 仍是独立缺陷。此检查没有 CLI 或清理。

v12c 仅新增 `--cleanup-never-spawned-v12 <UUID>`，只接受 **dce75105-11ad-49c7-bc16-377823ceecc8**；普通 apply/install/cleanup 继续禁用。不安装规则、不运行 CLI、不读取账户、不删目录，不泛化 missing-Job 恢复。来源依据是冻结 v12 在 CreateCli 之前先写 phase=spawning，而本次 journal 仍 prepared/null child，固定失败报告证明停在 install-helper 读回失败。owner 退出/缺失/PID 复用仅作排他性检查，**不是 CLI close 证明**；报告始终 process_close_claimed=false、job_zero_claimed=false，成功只称本次 never-spawned 资源清理完成。

强约束：当前 helper 必须 Full/elevated、同 journal user/session、non-AppContainer；规范 UUID/Root/CLI pin/原 owner exe 路径与 hash 全固定。五个证据文件以 FileAccess.Read + FileShare.Read 持锁（拒绝并发写/删除），持续到事务和提交后复核结束：ownership.json、原 report.json、原 install-report.json、copied codex.exe、原冻结 v12 exe。每次复核包含句柄实际路径、路径无 reparse 和原 hash。install-receipt 必须确证不存在；未知文件状态、owner 活跃/未知或任何证据变化均拒绝。

| 固定历史证据 | SHA-256 |
|---|---|
| 本 UUID `ownership.json` | `94FAFCE790A4CD495AC5B5A253DA48A8BF0497B4FE6AA126C3711154C4C349DE` |
| 本 UUID `report.json` | `848839ECD8CB4CAF1F9EDAAF81642515327AA16647F6F3A6930EFD6B58CD5F86` |
| 本 UUID `install-report.json` | `EAE9EA7D6B6907083F8BCCC88C8219E344CD9265AD1A7818C005B0CF3315BB73` |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.v12.exe` | `53021D00EBBEDD9647AFE2AFE135CF63862DC2DF3CD0D6B69F5F651392705CA2` |

WFP 使用正确本地 Filter200 Get。只有完整三条精确派生 GUID+子层，或四者全缺失可接受；任何 partial/mismatch 拒绝。flags **只准实际 0x40**，不接受 0/其他位；权重仍 Type1/原值，不做兼容放宽。[官方 SDK header](https://raw.githubusercontent.com/microsoft/win32metadata/main/generation/WinSDK/RecompiledIdlHeaders/shared/fwpmtypes.h#L439-L476) 确认 INDEXED=0x40、DISABLED=0x20。AppId/conditions/action/key/layer/sublayer/provider 均精确复核，子层须 flags0/provider-null/weight0x7fff/空数据。

开始 WFP 写事务后先完整读取规则、再复核持锁证据、再在同事务内读取确认，随后仅删三个派生 filter keys 与一个子层。提交前再次复核证据；失败 abort、cleanup_pending。提交后必须全缺失并再次确认持锁证据，才 cleanup_pending=false；不盲目恢复旧规则。不产生 process/Job 关闭回执。固定报告 `never-spawned-cleanup-report.json` 使用 `p6_r7_one_attempt_never_spawned_cleanup_v1`，包含 attempt_id、固定布尔/计数/阶段/错误码，无身份原值或自由错误文本。

| v12c 冻结文件 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_appid_coordinator_helper.cs` | `C6C3EE2EF1156A61E7993C4C017F9CF7DB4D1275C3B01FCDE33EBFAA08E02515` |
| exact snapshot `tmp/p6-r7-review/native-appid-coordinator-candidate-12c.cs` | `C6C3EE2EF1156A61E7993C4C017F9CF7DB4D1275C3B01FCDE33EBFAA08E02515` |
| `tools/dev_agent_bridge/windows_text_gate_appid_coordinator_helper.test.mjs` | `7F12C22E228741B2B751A19743561ABC84FD71B0FF20E0EA6877353894208CAC` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.cleanup-v12c.exe` | `93532AA4D5BC1C0DFEA957CBF7EA6214B346054471EE81506B4B9DC2253797F8` |
| `tmp/p6-r7-helper/coordinator-v12c-tests.tap` | `DD0B1C423A58A7016F3D51C8B8BE745665CE5654E1F2528AB58DBC6A19095CFC` |

实际联合编译/self-test exit 0，**Node 14/14 pass、0 skipped，自测 75（原 54 + 21）**。新增验证单 UUID/never-spawned 证据拒绝、flags/weight/action 拒绝、完整/全空/partial 规则边界及持锁/事务调用次序。没有调用真实 cleanup、UAC、WFP mutation、CLI 或网络；不把本地断言当作原生清理证据。旧 v12/v12b exe 与冻结 v10/v11c 依赖保持原哈希。

v12b 当时未保留单独 source snapshot，只有已记录源码 hash 与冻结 exe；没有逆向重建或伪称已有该快照。v12c 快照已按实际源码逐字节保存。

独立审计后由主控执行的唯一 mutation 命令（worker 未执行）：

```powershell
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.cleanup-v12c.exe' -ArgumentList @('--cleanup-never-spawned-v12','dce75105-11ad-49c7-bc16-377823ceecc8') -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
```

普通 coordinator 恢复与 v13 改进不包含在本包；需要先取得本次真实清理结果。以下 v12b/v12 内容为历史记录，不代表当前候选已实测或生产通过。

## v12b 历史冻结（2026-09-12）

主控实际 v12 attempt `dce75105-11ad-49c7-bc16-377823ceecc8` 已失败：coordinator exit 3，install-report stage=appid_filters、error=appid_recovery_filter_mismatch；coordinator stage=install_helper，未创建 CLI，cleanup_pending=true。WFP 可能已经 commit，named Job 随 coordinator 退出已失去。普通 apply 暂停，不将缺 Job/PID 当作关闭，也不在本包实施清理回退。

v12b 只开放默认/token-plan/self-test 与 `--inspect-own-appid <UUID>`；apply/install/cleanup 固定拒绝 `v12b_diagnostic_only`。inspect 仅接受独立 v12 Root/UUID、strict journal、原 owner 冻结 hash `53021d00ebbedd9647afe2afe135cf63862dc2df3cd0d6b69f5f651392705ca2`、同 user/session、固定 copied CLI pin。允许 owner 已退出，不访问任意路径，不启动/UAC/停止进程，不添加或删除 WFP。私有身份只用于比较，报告没有 SID、Session ID、AuthId 原值。

[官方 FWPM_FILTER0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmtypes/ns-fwpmtypes-fwpm_filter0) 的 context union 可容纳 UINT64 或 GUID，必须占 16 字节。新增仅供只读检查的本地结构：总长 200，Action offset 128、Context 152、Reserved 168、Id 176、EffectiveWeight 184；不修改冻结 Native.Filter（192）或旧安装实现。现场 mismatch 是否由此导致仍须检查实际字段，不能仅凭尾部布局断言解释前部 flags/weight 的差异。[FWP_VALUE0](https://learn.microsoft.com/en-us/windows/win32/api/fwptypes/ns-fwptypes-fwp_value0) 的 UINT64 为指针，诊断解引用得到数值，绝不把指针地址当权重输出。

检查仅对三个派生 GUID 读回：固定角色 allow4/deny4/deny6；raw flags、weight_type/适用 numeric、action_type、condition_count；key/layer/sublayer/provider-null/AppId-blob/condition 匹配只输出布尔。condition 最多读取 16 个，未知或不可用数值为 null；不输出原生指针、任意 GUID/key、路径、描述、filterId、raw context 或结构全文。返回 schema `p6_r7_appid_inspection_v1`、diagnostic_only=true、cleanup_performed=false，并仅在 scope 校验成功后写本 UUID 的 `inspect-report.json`。读取失败返回固定错误与可用 numeric status，不做恢复判断。

| v12b 冻结文件 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_appid_coordinator_helper.cs` | `E0F38A816AF24E8E9718F154D5118690AF4BC0F537FC0DABE348C5FBF3EA5AEF` |
| `tools/dev_agent_bridge/windows_text_gate_appid_coordinator_helper.test.mjs` | `18941C7A97821CA94F4492417FD4E2BA7E85594D235C884C6815219ECCDF6367` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.inspect-v12b.exe` | `5C5F243B0F708D6D340D756977A3D4547DF76E1CFF916AC42DD266B7451D2E2A` |
| `tmp/p6-r7-helper/coordinator-v12b-tests.tap` | `F7CC4B4B6F62D9C4DDDA82AC463D50D25D5728C4B93BE86810F4E02CFB6C7554` |

实际联合编译/self-test exit 0；**Node 13/13 pass、0 skipped，自测 54（原 46 + 8）**。新增覆盖 ABI、owner hash、同 user/session、固定输出脱敏、错误 match 布尔、condition 上限和 UINT64 指针读取。旧 v12 exe 与 v10/v11c 四个冻结依赖保持原哈希。worker 未实际执行 inspect、WFP、UAC 或 CLI；源码/exe/test 冻结。

主控只读入口（不更改规则）：

```powershell
& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.inspect-v12b.exe' --inspect-own-appid 'dce75105-11ad-49c7-bc16-377823ceecc8'
```

以下 v12 内容为历史候选记录；其中 apply 命令当前暂停，不能将历史本地测试或本次诊断当作生产/关闭/清理通过。

## v12 历史实现与冻结

2026-09-12。独立 v12 source/test/exe 冻结；worker 只编译、运行 token-plan/self-test 与只读专项，没有 apply、UAC、真实 CLI、账户或模型请求。此包不是生产接线，不签发 stop receipt，production/human Gate 始终 false。

## 已有依据与本候选边界

旧 v11c actual：`tmp/p6-r7-review/native-appid-startup-03-primary-conversion.json`，SHA `434B7076413268E566175A3F36E22AC3FCC53572FBF5F2DB833BB37ED52AE539`。source Type 2、impersonation level 1，DuplicateTokenEx 返回 1346；0 CLI/WFP/HTTP/model，清理完成。该转换路径停止，不继续调权或重复 UAC。

v12 首先交付只读 token-plan 专用 exe。主控从普通外沙箱进程实际观察 Type 1、IL 8192、Limited 3、elevated 0、non-AppContainer、AuthId 非零，coordinator_token_accepted=true。报告 `tmp/p6-r7-review/native-appid-coordinator-token-plan-01.json`，SHA `D916E3A824ECE29F9E543537B1DC15DA18ACD3D7791EA228A62CFEEEE2409686`；专用 exe SHA `F1E040B2B6F3B61A978638F4BA3E5BC2678137A25E686D7E8DF5A2728D3461B6`，当时 source snapshot SHA `D2C1281890AAF9849B8A1FBA7666AD046BEF35B44A86711A21B4FA483CB0E200`。这些只证明普通宿主 token 属性，不证明当前完整 v12 的系统边界或 CLI 通过。

worker 沙箱自己的 token-plan 则显示 ElevationType 1，coordinator_token_accepted=false；没有为沙箱放宽到 Default 1。coordinator 始终复用严格 IsMedium：primary Type 1、IL 8192、Limited 3、elevated 0、non-AppContainer、AuthId 非零。

## 运行分工

- **普通 medium coordinator** 持有 broker、CLI stdio、CLI process handle、named Job。CreateProcessW 继承其自身已核验身份；没有 DuplicateTokenEx、linked token、借 Explorer/token、LogonUser、CreateProcessAsUser 或 impersonation。
- **同一固定 exe 的短命 UAC helper** 只安装或清理本 attempt AppId WFP。它不拥有/启动 CLI，不读取账户，其 exit/receipt 不是 CLIclose。两次系统确认由实际运行时用户决定。
- 新 Main：`HereIAm.R7.CoordinatorProgram`；默认、`--plan`、`--token-plan` 只读取当前进程固定 token 属性。`--self-test` 仅合成逻辑/ABI。只有 `--apply-coordinator-startup-synthetic <pin CLI>`、`--install-own-appid <UUID>`、`--cleanup-own-appid <UUID>` 能进入相应 mutation 路径。

隔离命名完全独立：Root `D:\memex\tmp\p6-r7-appid-coordinator`；每次随机 UUID 目录；WFP key SHA 前缀 `HereIAm.P6R7.CoordinatorV12/<UUID N>/<tag>`；Job 名 `Local\HereIAm.P6R7.CoordinatorV12.<UUID N>`。CreateJobObject 发现 ERROR_ALREADY_EXISTS 立即拒绝，不使用预存对象。Job active limit=1、kill-on-close、无 breakaway。

coordinator 新建 attempt 私有目录，SYSTEM/Administrators FullControl、当前用户 Modify，受保护 DACL；只作用于本次新目录。与 v11 不同，普通 coordinator 必须能写自己的 journal/报告。所有路径做固定派生和祖先 no-reparse 检查，不改旧 D/C 祖先、已有 ACL/完整性标签。只复制精确 pin 的 codex.exe：`3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004`。新 work 下 empty-home/empty-workspace/Roaming/Temp 与合成十键环境，不读取完整用户环境、认证或真实 home 内容。

威胁模型仍是受信同用户宿主/固定 CLI，无恶意同权程序或管理员改写。AppId 识别复制镜像路径，不等于实例/哈希隔离；私有随机路径、pin 前后核验及真实 process/token/tuple 绑定共同限定用途。没有 AppContainer 文件系统隔离，不声称抵抗恶意同权用户。

## 安装、启动、关闭与回执

1. coordinator 创建 named Job、唯一回环 broker，持久化严格 journal，然后经 ShellExecuteExW `runas` 请求唯一安装 helper；保存 OS 返回的真实 helper handle，核验 PID/creation/image，等待该 helper 实际 exit 0。
2. helper 只接收规范 UUID，重算 Root/目录/镜像/Job/规则。要求自己 Full/elevated、与 journal 的 live coordinator 同 user/session；打开实际 coordinator process，核验 PID/creation、同一冻结 exe 镜像哈希、严格完整 token 身份。OpenJobObject **query-only** 验证 Active=0、Total=0。
3. helper 安装一个子层与三条精确 copied image AppId 规则：只允许 TCP/127.0.0.1/唯一 broker 端口，其他 V4 与全部 V6 deny。AppId blob 来自 FwpmGetAppIdFromFileName0，原生内存正确释放；完整读回三条规则的 blob/层/action/条件与子层。install 不接受空/部分规则。
4. helper 写固定 install receipt。coordinator 必须同时得到真实 helper exit 0 与严格 receipt，才能 spawn。receipt 绑定 schema/domain、attempt、nonce、coordinator PID/creation/imagehash、CLI pin、AppId blob SHA、helper PID/creation、action/completed。spawn 前再次验证镜像；进程创建时原子 JOB_LIST + 恰好三个 stdio HANDLE_LIST，不继承 Job/control handle；suspended child 的真实 token 必须与 coordinator 完全 Same（包括 primary Type），再验证 Job、PID/creation 和 pin，保存 child binding 后 Resume。
5. 仅 initialize、initialized、config/read、stdin EOF。broker 读取 payload 前使用既有完整 TCP tuple/PID/creation/image/token admission；错误 host peer 必须被拒绝。任何 admitted CLI HTTP 返回固定 403 且本用例失败，0 upstream/model。没有 thread/turn、Node IPC 或 C# 模型文字门。
6. 正常/异常均对实际 child 执行关闭与 Job zero 证明。只有 child binding 完整、实际退出、Active=0 且 Total=1（尚未 spawn 的 prepared 则 Total=0）后，才请求唯一 cleanup helper。coordinator 此时继续持有 Job 与已退出 child 的 process handle，直到 helper 完成。
7. cleanup helper 再次验证 live coordinator、query-only 打开 named Job、精确 Total/Active，以及绑定 child process 的 creation/image/实际 signaled 状态。PID 不存在、复用、Job 不存在、owner 未知、spawning 缺 binding、任何查询失败都拒绝，不作为关闭证据。只有证据齐全后才删 own WFP，并再次读回严格 absence。cleanup 可接受一开始就确证 0 filter+无子层；部分/错误/未知仍 pending，install 门槛不受影响。

成功要求 config 严格匹配、真实 stdin EOF 后 exit 0、reader 完整 EOF、实际 process exit+Job zero、安装与清理 helper exit/receipt 都精确通过、无 HTTP 或其他错误。helper exit、stdout EOF、broker close、PID 缺失均不能代替这些条件；forced cleanup 不算启动通过。

## 日志与失败边界

- Journal schema `p6_r7_owned_appid_coordinator_v1`，固定 domain/13 键与 nested token 固定 8 键；16 KiB、canonical JSON、拒绝重复/未知字段和所有旧 schema。phase 仅 prepared/spawning/bound/closed，不读任意路径/hash；candidate hash 必须等于正在运行的同一 exe。私有 journal 的 SID/Session/AuthId/PID/creation 仅恢复核验使用，不进入普通报告。
- Receipt schema `p6_r7_appid_coordinator_receipt_v1`，固定 13 键、nonce 与当前两方进程绑定；不同 action/attempt/nonce/hash/PID/creation/blob digest 全部拒绝。helper 写 receipt 不等于 coordinator 已接受。
- 普通报告 schema `p6_r7_appid_coordinator_candidate_v1`，`coordinator_startup_passed` 独立，production/human false。只输出固定 token 属性、布尔/计数、稳定阶段/错误码及可用 Win32 数字；无身份原值、raw stderr/config/错误正文。固定 stderr 分类复用冻结原语，不输出旧 Root 的自由摘录。
- UAC stdout 不作为主要证据：helper finally 在固定本次目录写 `install-report.json`/`cleanup-report.json`，有 schema/attempt/action/stage/稳定错误/Win32。coordinator 仍严格校验 exit+receipt；helper失败报告供主控随后只读定位，不能代替 receipt。
- 任何 UAC 取消/超时、receipt 或状态未知都失败、cleanup_pending、保留 deny 或标明未验证，不重试或自动重弹。完整 startup 的正常路径通常两次 UAC；安装未获证实则不冒险再发 cleanup。
- Job 持有期间的正常清理已实现；**强崩/Job 句柄丢失/缺 owner 的完整恢复尚未实现**。这类 case 保留 deny/pending，不能再用 Job 不存在或 PID 复用作通过。协调进程最终退出后 Job 被关闭，后续 helper 会拒绝缺 Job，不声称该候选已具备跨崩溃回收能力。
- 不递归删除 attempt，保留镜像、合成目录、journal、receipt、报告。无 AppContainer/profile/loopback 全表调用，不改普通 Codex firewall 或生产开关。WFP 规则非 dynamic、非 persistent；BFE/系统重启与非 loopback 正负控仍未验证。

## 冻结哈希与本地测试

| 文件（项目相对路径） | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_appid_coordinator_helper.cs` | `8E8D46B829ABCC39DA95455BF360AF43FBE85666110FF78C22B7B400CD3DD6D7` |
| `tools/dev_agent_bridge/windows_text_gate_appid_coordinator_helper.test.mjs` | `2A65118D2C6018EBD44C87212597D3EF83A18779EA217239B4DEBF5CA1DFB1B8` |
| `tmp/p6-r7-helper/windows_text_gate_appid_coordinator_helper.v12.exe` | `53021D00EBBEDD9647AFE2AFE135CF63862DC2DF3CD0D6B69F5F651392705CA2` |
| `tmp/p6-r7-helper/coordinator-v12-tests.tap` | `5A365C4D619CF415292BCDE309BD526745D259B0D35FD8A6D4469258EA80C277` |
| `tmp/p6-r7-helper/coordinator-v12-self-test.json` | `F7E1D1EBC934A5BAACE13D37021F6E7D045E3D802BCC4A0FB5D9B7EBDF7A7C47` |
| 冻结依赖 `windows_text_gate_isolation_helper.cs` | `D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8` |
| 冻结依赖对应 `.test.mjs` | `3B30A568278284378BB75FB7024F3ED175FE289583B32AAA76C4E4FDDE261D0F` |
| 冻结依赖 `windows_text_gate_appid_startup_helper.cs` | `C777023495CCDBF3B52663F49683F5D84DCFD03A36B3D280A75C925F37B7A1EA` |
| 冻结依赖对应 `.test.mjs` | `91A1579202DF71262329BD8EB06C6628F5075929FF73E4B70E62035C40433AED` |

实际 Framework64 联合编译 exit 0；冻结 exe self-test/token-plan exit 0；**Node 11/11 pass、0 skipped，自测 46 断言**。覆盖严格 primary（Default 1/Type 2 拒绝）、GUID/Job/root 命名、journal/receipt 修改和旧 schema/重复键拒绝、phase/child binding、Total/Active 不一致、install 完整与 cleanup 严格 empty 分界、稳定错误保留。Node 强制禁止所有 mutation 动词，测试前后验证四个冻结依赖哈希及新 Root 未被测试创建/新增 attempt。

这些不是 WFP、named Job、ShellExecuteEx、真实 CLI 或 UAC 实测。候选启动/正常清理、HTTP 正负控、用户第二次取消、强崩/BFE/重启、取消/恢复产品接线均需要另取证；不继承旧 AppContainer 或 v11 测试通过。

## 主控执行入口

**coordinator 必须由普通已验证 Medium primary 宿主启动，不能把整个 coordinator RunAs。** 它自身在安装/清理时各请求一次系统确认。下列 mutation 命令仅供主控复核后实际运行；worker 未运行。

```powershell
& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.v12.exe' --token-plan
& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.v12.exe' --self-test
node --test tools/dev_agent_bridge/windows_text_gate_appid_coordinator_helper.test.mjs

& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_coordinator_helper.v12.exe' --apply-coordinator-startup-synthetic '<verified-absolute-codex.exe>'
```

源码联合编译指定 Framework64 csc，`/target:exe /platform:x64 /reference:System.Web.Extensions.dll /main:HereIAm.R7.CoordinatorProgram`；输入三份 cs（原 v10、原 v11c、新 coordinator）。不得省略新 Main、覆盖冻结 exe，或直接选旧入口；后续修正另版本候选。

主要 API 契约：[ShellExecuteEx/SHELLEXECUTEINFO](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/ns-shellapi-shellexecuteinfow) 的 runas、NOCLOSEPROCESS、NOASYNC 与真实 process handle；[Job object](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects) 的进程统计与生命周期；[AppId blob](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmgetappidfromfilename0) 的路径标识和释放方式。系统真实可用性按本候选后续报告判断。
