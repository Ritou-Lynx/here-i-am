# P6 普通聊天候选：构建及封包

2026-09-16 01:54 接续：78f6固定四规则实际只读缺席已证；新38/39封包399pins通过并实际启动，38 native预检完整0。用户已复制固定入队文字，但原生输入工具连续检测手动输入，尚未发送或创建新任务。旧36失败保留，执行控制/恢复及P6/Goal1未完成。详见[当前接续](P6_R7_PRODUCT_ACCEPTANCE_20260916.md)，下方状态为历史。

2026-09-16 当前：34过期收尾已完成；36真实enqueue/status成功，start安装阶段timeout/1223、native4，未running/pause/resume。普通232事件与两个精确终态闭合；36失败App/Node已精确收尾、原Witness4，无后继37，失败任务保留。78f6固定规则检查已准备并通过独审，尚未执行，P6/Goal1未完成。证据与后续步骤见[9月16日接续](P6_R7_PRODUCT_ACCEPTANCE_20260916.md)，下方状态为历史。

2026-09-15 当前：c874/7574固定规则只读缺席已证，失败30精确收尾。32真实普通短聊零工具、唯一公开任务enqueue成功，83事件closed和两个turn/completed已核；首App/Node正常退出各0。唯一33后继预检native4/1223失败，未ready/未执行任务，已精确结束App/Node，原Witness4及pending任务保留。251b固定规则仍unknown；执行控制、结果和成功后继恢复待验，P6/Goal1未完成。详见[9月15日接续](P6_R7_PRODUCT_ACCEPTANCE_20260915.md)。下方9月14日状态均为历史，不重用已消费bootstrap。

2026-09-14 23:47 更新。owned28 已在真实普通聊天发送短句，但旧 Codex 客户端导致模型拒绝；匹配 provider failed 和 session closed 已证，零工具调用、tasks[]。第一次 App/Node 正常关闭实际0，唯一后继29预检因 Windows 确认未完成而失败；失败 App/Node 已精确清理，原 Witness actual4 保留。47831 已按既有重启授权改用本机现有新版 CLI，ChatGPT 登录保持、原47841未变；新版实际模型话轮仍待。c874固定四项网络规则的只读检查尚未启动成功，状态 unknown；已准备诊断02，等待人工处理 Windows 弹窗的操作时机。新30/31包399pins匹配但未启动。普通入口、最终恢复与 P6/Goal1 仍未完成。下方旧状态为历史。

## owned28/29 真实普通话轮与失败收尾

- owned26 同样在等待输入期间到期，未发送模型话轮、tasks[]。精确 App39124/Node53628 清理的新 held actual exit 均 -1（`fe116b`）；原 Witness actual4 / first_close（`fe68f7`），旧失败不改写。
- owned28/29 新包 SHA `1549c64a4170c855f1912d09ee2971835b1ef6e63a8fddeadf59eaccce0b7bec`，dataset `30f79438-aff7-4c80-972d-b75f18291f5b`，bootstrap SHA `d5f1684c3549ff0f1a406af9381026cf848aef62a7992f5e41b122853d0e6a10`；399 pins 重算一致。App/Node/native/Witness05 冻结字节保持，真实构造器 `7e4ab5` exit0，实际启动 `31bbf4`。
- owned28 通过单键输入在真实聊天发送 `hi`。普通 session `21547d44-27a7-4165-936d-8d4c5c42ed3b`、provider thread `01a0a07f-7dc6-7f32-a5fc-ca353fec2c29`、turn `01a0a07f-8270-7b80-9709-07e4b5bdbe31` 实际终态 failed：HTTP400 明确要求升级 Codex 才可使用 `gpt-6-astra`。22项有序事件、零 tool call/result、精确 session closed 已由 [ordinary-events-03](../../../tmp/p6-r7-review/app-lifecycle-owned-28/ordinary-events-03.json) 校验（`c1c5ed`）；[限量失败投影](../../../tmp/p6-r7-review/app-lifecycle-owned-28/ordinary-first-failure-01.json) 保留错误（`0cd43c`）。这是实际失败，不是短聊通过。
- 通过真实标题栏关闭 owned28。普通 guardian terminal 已确认、host closed；Witness 原始持有 App50988 与 Node3632 的句柄分别 actual0，先于唯一 successor29（audit seq102–106，`a368b5`）。第一次正常关闭通过不代表整个恢复场景通过。
- successor29 preflight native17656 / attempt `c8749dc7-94b8-4221-ae73-29b6c6304530` 返回 actual4、`task_helper_shell_execute_win32_1223 / native_startup_timeout`。未创建 native child/普通 session/任务，upstream0；原 `cleanup_pending=true`、六项关闭证明不齐。关窗请求仍 `shutdown_unconfirmed`。
- 原 protected prepared SHA `465a60d9f290171bcb32418d12ba177a9f8a1ecae70fde6ce8bc70e7bb587808`、final SHA `26959e684c47034e74349f97aeecc0a0f017552edf75209090452c36bb24aacc` 已限量只读核实（`fb56c8`）。固定 c874 四键检查器仅从既审 3118 替换身份常量，编译及3/3静态检查通过；首次实际启动检查器未成功，collector_started=false、operation_exception（`59768b`），没有 WFP 查询结果，规则状态仍 unknown。
- [精确清理 v2](../../../tmp/p6-r7-review/cleanup-failed-product-29-v2.ps1) 在实际 VerifyOnly 后，只终止 App53652/Node51920，新 held actual exit 均 -1；已识别 conhost38344 仅观察自然 actual0（`20187e`）。原 Witness 实际退出4 / successor（`1c786b`）。未终止 native/Witness/共享服务、未改规则或数据，不授予恢复 authority。首次预检因未纳入已观察 conhost 而拒绝的记录保留。
- 最终 [Witness 失败链](../../../tmp/p6-r7-review/app-lifecycle-owned-28/witness-final-failed-01.json) 已只读校验；[同库最终投影](../../../tmp/p6-r7-review/app-lifecycle-owned-28/db-final-failed-01.json) 仍 tasks[]（`0019c8`）。真实任务 `fc91503a-0e59-4f7f-a480-14215e67cb05` 未操作。
- 旧普通 Gateway 实际选择 npm Codex `0.147.0`，并非 PATH 的现有桌面 CLI `0.154.0-alpha.6.2`。已定位默认 resolver 对 npm-js-entrypoint 的优先选择；本次修复使用现有 `start_bridge.ps1 -CodexExecutable` 的单进程启动绑定，不改模型、认证、provider 或费用路径，不替换受限 native CLI pin。新版兼容性必须另经实际话轮复验。
- [服务重绑定04](../../../tmp/p6-r7-review/rebind-product-gateway-04-exec.jsonl) 实际 VerifyOnly/Execute exit0（`92b2d6`）：正常停止旧 app-server 后，原 held 七节点全部退出；vendor CLI/Node/conhost各0，四个自动 MCP 适配器各1。随后只终止旧 bridge9640（-1），其 parent40996自然退出-1。新 parent21348 creation `134338743252880457`、Node7384 creation `134338743257110609`；实际子50692为固定桌面 CLI `app-server --stdio`，SHA `081e4de4be8e38fac6ed4d95e3b1a0b9f6d31c090ddc36e1696b349fe406f575`。limited auth为authenticated=true/auth_type=chatgpt，47841原25332 identity保持（`0afd76`）。旧 API没有全量活动session census；本次依据已授权的精确47831重启，不虚构其他会话空闲证明。
- 新30/31仅生成准备文件：package SHA `772d027e21485bcc187f3d7f380a84c9bb86619c416c3abdba55564e25294b0d`，dataset `a297924b-2e2f-4ae0-8272-f624a03a9f36`，bootstrap SHA `89addf73c5211b0361b662ecf4dd9c8a6581f5ea85c7f28146bc5db1e65502af`。399/399 pins逐项匹配，209 source/152 bundle及原冻结closure未变；未创建其 DB/运行组件。ordinary collector v4仅绑定30/31并通过语法检查，尚未执行，不继承28的failed话轮为通过。
- 30的实际纯配置构造器校验已通过（`ec964c`，23:51）：固定Witness05反射调用`BootstrapConfig`，399项 pins打开验证后实际Dispose；未调用Main/Runner、未建进程或DB。[原始结果](../../../tmp/p6-r7-review/app-lifecycle-owned-30/bootstrap-constructor-01.json)。
- 下一次只使用主控从固定v3机械生成的`verify-product-prestart-v5.ps1`（SHA `ea2b675efc32a55d3d7db7835592bbde81cfb5799182bb3f3c0370f8b7eb644a`）与`invoke-product-recovery-v5.ps1`（SHA `55a2490e88e24501d7d24647df4d17715c5ac26d40e3828d34ee2ea21b64dd7c`）。它们保留原候选/47841/完整封包保护，增加60秒新鲜检查及新Gateway/正确CLI镜像、创建时间、命令和listener现场核验；只完成语法解析，未prestart/启动。worker准备的v4错误把50692当Node并漏旧guard，已拒绝，不可运行；ordinary-events-v4为另一份正确只读collector，不受此命名影响。

## 21:40 接续记录（历史）

- owned24 最终 `launcher_deadline / shutdown_unconfirmed`；guardian 未尝试普通 session，任务为空。`cleanup-expired-product-24.ps1` 在核对精确 PID、创建时间、镜像哈希、完整参数及无任务/无普通 session 后，只结束该 App/Node；本轮新打开的 held handles 实际退出均 -1（`3e485f`），并非原始启动句柄，也不是正常关闭证据。原 Witness 运行尾部实际退出4、`owned_recovery_frozen / first_close`（`3282a4`）；旧失败原样保留。
- 新包 `app-lifecycle-owned-26/recovery-package.json` SHA `432ad92e500edd78cd65bc9ca46c4e1d23375d0589b063faf079b14c5bd2a710`，dataset `968469b4-2baf-467c-adcf-23fb135f2b32`，后继27。实际准备`806972`及真实配置构造器`1f1aff`均exit0；App清单仍为`75632c…5315`，209源/152bundle/24Node闭包保持，独审重算399/399 pins匹配。
- 新 prestart-v2 / invoke-v2 完整复核后实际启动（`be1a0c`）；13:31:19Z ready/port2793、Node53628。`db-before-short-chat.json`读取为tasks[]（`922b2d`）。运行尚未结束，首阶段30分钟期限仍适用。
- 原生UI输入检查：精确候选窗口可展开并取得输入焦点，单个`a`按键能显示；批量中文type_text不显示，fresh UIA set_value报元素不在缓存，窗口还曾被最小化。代码只读复核未见未发送时清空/重建controller的路径；语义聚合不能证明输入故障根因。已请求用户只手动粘贴短测试句、不发送并保持窗口展开；没有向模型发送测试句或入队。
- 只读 ordinary-events-v2 固定26/27、新包及dataset，保留严格关闭/逐话轮终态要求，尚未执行。见 `app-lifecycle-owned-26/independent-v2-collector-handoff-01.md`。本次未提交、推送或改写冻结候选；主目录HEAD已由其他工作前进到`aeb7f71a`，不据此改变冻结构建基线`389aa735`。

## 本轮现场进度

- 服务脚本02 Execute 实际exit0（`38003b`）：只结束原Node32976，held实际退出码-1；新父40996、Node9640。没有修改已保存认证或模型配置。`384848`确认health与experimental feature、authenticated=true/auth_type=chatgpt；普通默认text-only profile仍拒绝。收据：[服务启用](../../../tmp/p6-r7-review/app-lifecycle-owned-24/gateway-enable-receipt-01.json)。
- `21e41d`复核同包399pins；`800fcf`实际前置确认新候选及两代运行文件缺席，47831新身份匹配、47841原25332及原StartTime保持。固定启动助手SHA `0e81ed55f381043686ffc9789ae154e5a5823c1dca3a3cf887c96b64a97334fa`。
- owned24 已由Witness05实际启动（`a218cf`，会话尚未结束）；App窗口与自有Node53056已见。12:31:30Z `preflight_verified`，host54774，预检owner0/native37404实际0，六项true/pendingfalse、upstream_attempts=0。它仅是预检，尚未执行公开任务。
- `bf5ceb`读取本次新库任务数0。窗口随后被用户调整并最小化，主控暂停键鼠并询问桌面可用时间；未发普通聊天、未创建任务。预检成功不能替代普通聊天、任务和最终关闭恢复结果。

## 改动与边界

新 `lib/p6_r7_product_main.dart` 使用独立候选 DB、真实桌面聊天组件、共享的持久化后发送入口、原 coordinator 和当前原话授权工厂。ordinary guardian 只代理本次精确 session 到47831，关闭须取得匹配 provider 终态；queue 则继续走 App 自有 Node 和严格零工具 native。queue 调用串行，任务持久化/witness/宿主注册完成后才返回结果；关窗先封新工作，最后等待实际关闭和资源尾部后提交 app_closed。

主目录改动包括新 product/session/store/view-model/root、有限 guardian/transport/host binding，以及原发送 helper 的共享提取。普通 main/router/dependencies 没有为此解锁生产。真实 TaskRoom、聊天/记忆 DB、auth 文件和历史真实任务 `fc91503a-0e59-4f7f-a480-14215e67cb05` 未操作；没有提交、推送或发布。

首个候选仍限定一项公开任务、同一数据集和一次后继：标题“公开文字验收”，目标“只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。”。通过聊天输入与动态工具传入，Store/scope/recovery 继续核对固定内容；不宣称任意目标、多任务或无限恢复。

## 本地验证

| 验证 | 实际结果 | 完成证据 |
|---|---|---|
| 主目录 Node 组合 | 76/76，exit0 | `e1478a` |
| 新 worktree Node 组合 | 76/76，exit0 | `26fdc8` |
| 新 App 与相邻恢复测试 | 191/191，exit0 | `5e16a1` |
| 相关9项源码分析 | No issues，exit0 | `496968` |
| 构建前 critical | 3/3 | 构建启动 `b32b5a` |
| Windows Debug 构建 | exit0，177.1秒 | `a763c0` |
| Witness05 合成 | 10/10及Core553 checks，exit0 | `a2e22c` |
| 新封包配置构造器 | 399 pins实际打开校验后释放；无启动/DB | `d84802` |

修复了拒绝 manifest/config 时提前分配空 owner/index、普通关闭 HTTP 回执遗漏身份字段、异常 HTTP header/body 拒绝后连接未终止的问题。合成 transport 测试实际等待本机服务端 socket close，不以 Promise 拒绝替代连接结束。

离线 Pub 首次因缓存 `active_roots/94` 不存在退出66（`efe921`），仅补齐该子目录后第二次退出0（`5e3323`）；lock未变，旧失败日志保留。Windows 构建有 Nuget 缓存/下载回退提示，因此只称 Pub 使用离线模式，不称整个构建离线。主目录大聊天文件较早全量分析的19项原有提示不归入上述9项通过结论。

## 唯一候选绑定

- 工作区：`.worktrees/p6-r7-product`，分支 `codex/p6-r7-product`，基线 `389aa735ca6003f3141d12f16c734c9a64441c47`。按主目录当前所选字节复制182个Dart文件/23 roots，来源含既有未提交修改，不称纯HEAD。
- 新候选只有Dart和Node的固定witness路径/哈希从04绑定到05；记录于 `product-node-seed-and-witness-pins-01.json`。旧App02/Node39/Witness04/addon02和所有实际失败/成功收据保持。
- App冻结清单：`tmp/p6-r7-review/app-product-build-01/candidate-build.json`，SHA `75632c3ebe0962bcbc9644cf65bdf44ffc64ab7b48dc0b2420a80df657d65315`。209源/152bundle；冻结实际exit0 `0cee5e`。
- `memex.exe`：`b8863b53d3e36e3345fc4388fe007fcfaa97b9f0e5b4d0864776b7204161ec4c`；kernel：`3e8d8bf740eab6441736ec30694e8ac2205771ae66b51f24058a645f58960ba4`。
- Node独审清单：`.worktrees/p6-r7-product/p6-r7-product-host-review.json`，SHA `73f54bd97dd02b6e01ef70eae62afde40a91abd7c15a0d096d1fbe8aba686ea9`；24源闭包SHA `73d256deb9272f22bdb9e6ca4e741e9afaa0cf403b3fbe1bb173a76f8e00ee93`。
- Witness05 exe：`e60ab90477230a593563656d4c27c1bd4835b39655f9b90e3b29895cb818d8fc`，仅新Root/App/host固定路径调整，core/schema/native/node/addon合同未放宽。
- 真实Dart工具schema：`1d6883d52d165afb4923877571bc66cbcf9e7df8c22cbc972143fba613f797de`，865字节。由真实getter直接导出，不手抄；建议首句已由原授权factory验证仅允许enqueue。
- 准备包：`tmp/p6-r7-review/app-lifecycle-owned-24/recovery-package.json`（同25），SHA `d3671e761086d05997b97121c0459852cee2ed7fbbb54890fc784080d368d9c3`；场景normal；399 pins；准备实际exit0 `81db15`。
- 新dataset：`f251a670-81ed-42dd-b4e7-4047fcac2168`；bootstrap SHA `5b46a82136e78f9db9a35268bfa92785369e4b26bf6b974a6a5fb96c701210aa`。24/25只包含准备文件，数据目录尚未创建，未发布admission。

配置检查只调用冻结05的真实 `BootstrapConfig` 构造器，未调用Main、StartApp、管道、DurableAudit或synthetic bypass；所有文件句柄实际释放。它不是实际启动/清理证据。

## 实际阻点和接续

有限现场检查 `674957` 确认现役47831为原Node32976、原创建时间及镜像；`8fef40`健康正常但experimental runtime未启用，`/auth`和`/capabilities`返回404。没有在这个检查中发送模型话轮。父进程启动命令也未带启用开关（`2be8c5`）。

主控已请求“启用普通模型入口并重启该现役服务”的明确授权，当前尚未收到；不是重新请求此前隔离验收权限。答复前不操作该服务。准备脚本只默认只读，执行前仍须核对精确原进程、无在途子任务与端口；不杀树、不改47841或主App，不修改已保存登录/模型配置。普通入口启用后先核对有限认证类型/能力属于既有ChatGPT/Codex路径，再进行公开文字Gate。

具体准备脚本为 `tmp/p6-r7-review/enable-product-gateway-02.ps1`。主控修正父进程创建时间/同用户核验、实际原Node退出码记录与PowerShell单条监听数组处理后，SelfTest和真实VerifyOnly均exit0（`d2c1d6`）；此模式仅核验原Node32976及其held handle、父进程32808、唯一localhost listener和无直接子任务，随后结束并释放本轮句柄。Execute尚未调用。脚本不承诺复制未知的旧进程环境，也没有读取完整父环境；只允许同普通用户已保存配置，不传provider/model/APIkey，启动后另核验认证/能力。较早01始终拒绝的准备稿和02首次只读预检失败（`37dc1a`）都保留，不当作实际重启证据。

接续使用本次精确封包，通过普通短聊天确认零入队，再明确enqueue/status和合法执行控制，核对精确结果及普通会话终态、App/自有Node/native资源收尾。动作和恢复矩阵只填真实获得的证据，不能从旧候选直接继承。当前P6/Goal1仍未完成。

独立封包复核已完成，209/209源、152/152bundle、399/399pins和24/24闭包逐项相符，未发现剩余P1/P2。复核最初将Node并行回收独立资源误读为越过App普通关闭屏障，重新核对固定源码后撤回：native owner_closed不是整体host_closed；ordinary未知时仍应尝试回收native，但不得签发host_closed/app_closed或整体成功。

[独立JSON](../../../tmp/p6-r7-review/app-lifecycle-owned-24/independent-package-review-01.json) SHA `9f407df27aaee7b76ae7e0886e8adb3d26442aa34f3cfe0d44a6ed39c8cacaac`；[独立报告](../../../tmp/p6-r7-review/app-lifecycle-owned-24/independent-package-review-01.md) SHA `90e0152a99730307dc11595f9b1d98797854498c81690cef1019628f93ff67f9`。这是只读准备包复核，不是运行Gate。

服务准备脚本02最终SHA `ac7bab93fd85ca6ce8797f644325c5563e536e603f670f94fba2a15d3c8ff7f4`，仍未Execute。工程接线与全部worker交接见[接线方案](P6_R7_PRODUCT_WIRING_PLAN_20260914.md)。
