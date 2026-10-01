# P6-R7 批次授权候选（2026-09-16）

当前2026-09-19：[下一步交付](../../../tmp/p6-r7-review/next-stage-20260919/NEXT_STAGE_RESULT.md)已将batch11逐行显示view与测试选择性合入本地v3-lab，16/16界面回归及定向分析/独审通过，未构建或部署主线App。真实Node子进程的独立Windows管道输入复现EOF保活仍可登记，隔离候选已最小修复；最终真实进程10/10（7stdio、3独立管道）和同测试器旧实现缺陷对照通过，全部原child与独立管道均actual close，继承stdhandle存活期EOF注入仍未验证；31/31 owner/runner/contract/readiness专项通过，合法closed→EOF仍须原实际退出和最终pin，stderr跨流顺序不误判。旧11的408归档哈希全部保持，新owner/runner字节不继承旧包现场通过或再用旧入口；真实高权helper/Job/WFP死亡、TTL与清理失败矩阵仍独立待验。无新UAC/App/模型/历史队列操作，未提交推送或生产启用，P6/Goal1未关闭。

当前2026-09-18收尾：[batch11最终现场](../../../tmp/p6-r7-review/task-batch-authorization-11/ACTUAL_ACCEPTANCE.md)已于9月17日23:35通过任务原文首/中/尾真实逐行显示、完整2000行自动回流一次，以及completed正常关窗后唯一后继保留同一结果、无自动执行或重复投递。16/16呈现回归、产品UI6/6、定向分析/独审、新构建92.3s/0、critical3/3、406pins及scope2/2有独立记录；原exec93800、两代App/Node、native、Witness/owner全部实际0、batch_closed=true/pending=false，56事件Witness链独审通过。09/10恢复回流和running取消与本批完成本轮有界修复验收；不继承不同包为本批全矩阵通过，不代填P6/Goal1整体关闭。文档工具超时后的记录现已补齐，未重新运行验收、commit/push或启用生产。

当前2026-09-17 23:13：[batch09](../../../tmp/p6-r7-review/task-batch-authorization-09/ACTUAL_ACCEPTANCE.md)已实际验证后继自动显示中断等待、明确恢复及完整2000行结果自动回聊天且仅一份；[batch10](../../../tmp/p6-r7-review/task-batch-authorization-10/ACTUAL_ACCEPTANCE.md)已实际验证running取消、provider interrupted/cancellation_confirmed、后继保持cancelled且不自动执行。两批所有原持柄收尾actual0、batch_closed=true/pending=false，41/44事件Witness链分别独审；09首代provider terminal为completed的竞态如实保留，不写成provider interrupted。09截图发现数字被普通聊天分句器合并为空格，已最小修复task-linked原文显示并保留空正文附件兼容，16/16界面测试、定向分析和独审通过；正在构建全新[batch11](../../../tmp/p6-r7-review/task-batch-authorization-11/ACCEPTANCE_SEQUENCE.md)验证真实窗口逐行显示。下方22:36未启动状态已由本条更新。未启用生产、未commit/push，P6/Goal1整体仍未关闭。

当前2026-09-17 22:36：消息回流修复已完成，12项专项/71项合并回归、定向分析及独审通过；Windows构建521.5s/exit0，critical3/3、210源输入不漂移。新09（owned56/57）和复用相同构建的10（owned58/59）各406pins、真实bootstrap只读0、Dart scope2/2，当前均未消费。09验自动中断等待和完整结果回聊天，10独立验running取消；不在完成任务上伪造取消/重试资格。启动前过程检查候选0，47831/47841身份保持；已询问用户是否仍方便处理下一次Windows确认，尚未得到本次答复，未新触发UAC/App/任务。见[09修复与验证](../../../tmp/p6-r7-review/task-batch-authorization-09/PRELIVE_VERIFICATION.md)、[10验收顺序](../../../tmp/p6-r7-review/task-batch-authorization-10/ACCEPTANCE_SEQUENCE.md)。下方08现场结果和早期失败独立保留；P6/Goal1仍未关闭。

当前2026-09-17 21:51：[batch08](../../../tmp/p6-r7-review/task-batch-authorization-08/ACTUAL_ACCEPTANCE.md)进一步实际跑通running正常关闭、后继等待、明确resume及精确1–2000输出；两代App/Node、native、Witness/owner/root均actual0、batch_closedtrue/pendingfalse。405pins归档、43事件恢复链独审通过。发现恢复状态/最终结果未自动回聊天，正在补发布接线，新候选仍需验可见性。取消/重试等余项与完整P6/Goal1未关闭；下方batch07及早期失败保留为历史。

## 2026-09-16 23:47 — batch07真实闭环通过

- [完整本批结果](../../../tmp/p6-r7-review/task-batch-authorization-07/ACTUAL_ACCEPTANCE.md)。同一batch `10e71232-81ed-4135-a6c8-70c5b7a71871`、dataset `fafc54b2-e9be-4f8f-a8fc-4a23ea40658e`、owned52/53，405pins运行前后保持；本轮未改冻结源或重新构建。
- 普通UI唯一任务 `7e2161e9-a8d0-4850-bc87-19f107225b5a` 原样入队；条件status pending → start running → pause成功。durable blocked/paused、reason=user_requested；匹配provider interrupted终态和native实际0、六项清理true/pendingfalse。任务保持暂停，未resume/retry/cancel。
- [普通会话收据](../../../tmp/p6-r7-review/task-batch-authorization-07/ordinary-session-receipts.json)：180事件，enqueue/status/start/pause四动作均success，两个精确turn/completed，session closed。
- [首代App/Node关闭](../../../tmp/p6-r7-review/task-batch-authorization-07/first-normal-close.json)与[后继App/Node关闭](../../../tmp/p6-r7-review/task-batch-authorization-07/successor-normal-close.json)均由普通关窗触发、持柄各actual0，无强制终止。唯一后继自动恢复同task/scope，无普通session或任务自动执行；关闭后DB暂停核心字段保持。
- 原exec54978的[真实退出回执](../../../tmp/p6-r7-review/task-batch-authorization-07/runner-actual-exit-07.json)actual0；batch_finished succeeded=true、Witness0、batch_closed=true、cleanup_pending=false、两代登记。owner19508实际0、helper退出true、无首个失败。47831/47841身份未变，候选进程只读缺席。
- [独立最终审计](../../../tmp/p6-r7-review/task-batch-authorization-07/FINAL_WITNESS_REVIEW.md)通过：48事件链、精确退出后的claim/consume、一次许可消费、snapshot/owner manifest三方hash绑定均核实。原始Witness最终stdout帧未单独存档，严格runner合法结果帧门槛及实际退出提供相应证据；不以此推定任务resume/完成。
- 单批授权复用实际链路已通过；人眼是否只出现最初一次Windows确认已向用户核实，未答前不代填。完整输出、resume/cancel/retry与其他P6故障矩阵未在本轮执行；生产入口关闭、未commit/push。

## 2026-09-16 23:11 — 现场修复、网关预检与第六批

- batch03 / owned44 的 Dart Witness pin、batch04 / owned46 的 Node Witness pin仍指向旧包，先后阻止Node登记/启动；已同时修正App、Node、两代host真实绑定，新增Dart封包对照。两批root原持柄实际exit4；App正常关闭实际0；owner实际0、batch_closed=true、cleanup_pending=false。见[03收尾](../../../tmp/p6-r7-review/task-batch-authorization-03/startup-failure-close.json)、[04收尾](../../../tmp/p6-r7-review/task-batch-authorization-04/startup-failure-close.json)。
- 新native为GUI subsystem2，SHA `20efa85f47d501cf8c94bf6088e89bb2e1fc8ce9bd45e1ae5996f14f6398cdd9`；Witness SHA `c753fdf05e684de1deb664b419fafe68aaae4aed7ff71b9125c8d35351e278f7`。App重新构建实际0、critical3/3，209源文件和完整bundle均封入pins；不能仅凭未变的Flutter runner exe hash判断Dart bundle未变。见[04实际构建](../../../tmp/p6-r7-review/task-batch-authorization-04/app-build.json)。
- batch05 / owned48 dataset `4e8337da-8a9a-4f5b-9216-34a654cf901f`：预检实际0、六项关闭true/pendingfalse；Witness接受admission_ready与bind_origin，owner在预检后保持有效。通过普通输入框发送唯一固定enqueue原话后，UI返回电脑Codex不可用；guardian为conversation_start_unknown、session_id=null、turn_ids=[]，只读DB任务0。未发送start/pause/resume/retry/cancel。
- 现场只读health不含runtime adapter，capabilities返回404 experimental_runtime_disabled，确定今日旧47831进程未开启能力。失败guardian不可重试；正常关窗未确认后，精确持柄结束Witness35456/App27592/Node41308，各actual -1。root实际4、owner实际0，batch_closed=true/pendingfalse；无后继49或正常恢复权威。见[05失败收尾](../../../tmp/p6-r7-review/task-batch-authorization-05/failed-conversation-close.json)、[root实际退出](../../../tmp/p6-r7-review/task-batch-authorization-05/runner-actual-exit-05.json)。
- 沿用此前明确的47831启用/重启授权，核实旧PID26308/creation/镜像/命令、同用户、无直接子任务后重启。新PID20744、creation `134340446518248929`；本机现存CLI `0.154.0-alpha.6.2`，SHA `960c111d47afd61669954b9df9e56083e302edbfa3ef6962d81dcc14a30051dc`。47841原PID1652保持，认证/模型配置未改；能力只读通过，authenticated=true/auth_type=chatgpt。见[受控重启回执](../../../tmp/p6-r7-review/enable-product-gateway-05-result.json)。
- 新增固定回环两次GET readiness，有限超时/64KiB/安全错误码，runner在任何owner/UAC/Witness创建前执行；失败零session/turn/queue动作，审计槽仍不可复用。owner/runner/readiness专项22/22、独立审计通过；此前host/launch47、Dart绑定/相邻30、Witness/绑定66、Node绑定11通过。06 Dart封包对照2/2、405pins和实际C#BootstrapConfig只读核验通过。
- [06封包](../../../tmp/p6-r7-review/task-batch-authorization-06/package.json)：dataset `cf561f2c-feee-473c-a269-bc21072de709`，batch `e1ed2d6a-eed3-4b49-a319-9679118780f3`，owned50/51；config SHA `dc10a5d70a62cf4120bbbd08ad569c341b4f4af0ab6c2d0cc9f9b8f75eccbdde`，runner SHA `13c7b8eff963b1ef5ed2bfd0fea882b6b789117a926ba9a9621dfb1f552661e8`。原exec57037在23:07:31启动，gateway_ready后authorization_requested；未有authorization_ready。23:09:33 owner actual2、batch_frame_invalid，root原持柄实际4/外层1，registered_generations=0。原生顶层异常只输出rejected计划，未保留具体系统错误，不能断言用户点了拒绝或确定UAC超时原因。
- 06未启动Witness/App、owned50/51事件文件和独立dataset均未产生。23:10:52只读CIM候选进程0、未知镜像0；该缺席不替代原helper退出证明。batch_closed=false、cleanup_pending=true原结果保留；没有任务或native attempt，不把本次记为正常清理/恢复通过。见[06实际退出](../../../tmp/p6-r7-review/task-batch-authorization-06/runner-actual-exit-06.json)、[06事件](../../../tmp/p6-r7-review/task-batch-authorization-06/batch-events.jsonl)。
- 当前需要用户在场处理下一次系统确认；本批审计槽已消费，不能重用或自动反复弹窗。同一已接受批次可复用安装/清理授权；失败后的新批次仍单独授权。人眼实际弹窗次数未确认，任务执行/暂停、正常关闭、自动后继仍待；生产入口关闭，未commit/push。
- 23:13已准备未启动的[07新包](../../../tmp/p6-r7-review/task-batch-authorization-07/package.json)与[受控启动脚本](../../../tmp/p6-r7-review/task-batch-authorization-07/invoke-batch-07.ps1)：owned52/53，dataset `fafc54b2-e9be-4f8f-a8fc-4a23ea40658e`、batch `10e71232-81ed-4135-a6c8-70c5b7a71871`，config SHA `0b1915aa687bffc0476f5c382e952a3b74ac9625f276f71803838bdaa46f3dfe`；405pins和真实bootstrap只读验证0。没有启动、UAC或队列操作；接续前仍须新鲜身份、能力与未消费检查。

## 2026-09-16 22:10 — 首批现场失败定位及新封包

- 原 batch01 / owned40 实际通过授权并完成 native 预检；`preflight_verified` 为 21:43:59，native actual exit 0、六项关闭事实 true、`cleanup_pending=false`、无任务执行。不能由此宣称整个批次正常关闭或已经证明真人只见一次弹窗。
- 随后 Witness 已接受 `admission_ready`，但未接受 `bind_origin`；App 创建独立数据库，实际 `task_rooms` 为 0。封包错误确定：scope 的 `profile_id` 使用 `workbench_text_only_v1`，实际 Dart 授权函数使用 `desktop_workbench_task_queue_v1`。两者只在后续绑定原点时校验，预检成功不能排除此错误。
- owned40 错误 hash 为 `f329eb157b1066a4cf76219445ee4973241751a53a3e8712fc4edd2102b4cafc`，App 实际算法期望 `1e935c86b6f5422575b31f321a94b5315306cb2dccd5f6f3bd9ca8b43b3fe78d`。此根因经独立审计；未修改正确的 text runtime profile。
- 正常关窗没有退出。在重新确认 DB 零任务、无普通会话、原预检清理完整后，只对精确 PID/creation/hash 的 App 38608 与 Node 42352 持柄收尾，两者 actual -1；原 root runner 持柄观察实际 exit 4。Witness 实际 exit 未持久记录，不推定成功或恢复授权；owned41 未启动。见 [失败收尾](../../../tmp/p6-r7-review/task-batch-authorization-01/forced-failure-close-01.json)、[原 runner 实际退出](../../../tmp/p6-r7-review/task-batch-authorization-01/runner-actual-exit-01.json)。
- 曾调查私有管道 FIRST_INSTANCE 生命周期；独立同机三轮实验实际 exit 0 证明旧 server dispose 后即使 client 持有句柄也可重新创建，不支持该假设。未修改这项安全边界。
- 新 [batch02](../../../tmp/p6-r7-review/task-batch-authorization-02/package.json) 使用独立 owned42/43、dataset `e10a5c1d-b9e7-4074-b78e-bbd8e11341f2`、batch `61aa05da-a20b-4953-b2b6-c7d4923d60b9`。仅修正 scope 封包，复用逐 hash 验证的同一 App/native/Witness；不重建或覆盖 batch01 的证据。
- 新 run-config SHA `d26c507856f9d9a340ddfeaa880571f861cc09b8a65aff88dcfc28c1fcde608a`；404 pins、真实 C# BootstrapConfig 只读核验 actual 0（`42af16`）；全新槽、现场目标进程为 0、两项本机服务原身份均核实（`1e147a`）。新批次此时尚未启动，仍须记录后续实际结果。

## 2026-09-16 22:26 — 第二批实测及进程组计数复现

- batch02 已实际启动（原入口 exec85478）。native 预检 actual0、六项关闭 true、`cleanup_pending=false`；Witness 明确接受 `bind_origin`（audit seq12），证实 scope 封包修复生效。外层随后报告批次失败，而 App/Witness 仍在 ping。无任务、无模型话轮；不能继承预检结果为批次关闭成功。
- 重新只读确认 task_rooms=0 与原生清理完整后，持柄结束精确 Witness33360 / App24076 / Node35036，各 actual -1，未删除数据或规则。原 runner26332 持柄 actual4；PowerShell 外层 exit1 单独保留。见 [精确失败收尾](../../../tmp/p6-r7-review/task-batch-authorization-02/forced-failure-close-02.json)、[原进程实际退出](../../../tmp/p6-r7-review/task-batch-authorization-02/runner-actual-exit-02.json)。owned43 未启动。
- 独立非提权 Job probe 使用同一 C# 源码、相同显式重定向父启动及 `JOB_LIST + CREATE_SUSPENDED + CREATE_NO_WINDOW`。Console target 的固定子进程实际0后出现另一短暂 PID，Active1/Total2 随后变 Active0/Total2，严格 Total1 检查失败；GUI target 3/3 均实际0、立即 Active0/Total1。限制始终 `0x2008 / ActiveLimit1`，所有持有句柄关闭成功。见 [A/B 与哈希](../../../tmp/p6-r7-review/task-batch-authorization-02/probes/comparison.json)。额外 PID 的镜像未识别，原批次 broker 没有足够原因记录，现场是否同因此时仍待复验。
- 新 candidate03 只把 native 编译目标改为 `winexe`，保持单进程、原子入 Job、真实退出、token/镜像及完整清理检查；不放宽计数。新 native SHA `20efa85f47d501cf8c94bf6088e89bb2e1fc8ce9bd45e1ae5996f14f6398cdd9`，PE GUI subsystem2 实读和重定向 `--self-test` 95/95、actual0（`26f5be`）。Witness 只重绑定路径和新 native pin。
- Node 外层补首次固定失败原因、UTC、原 owner exit、标准关闭帧与 stderr 字节数；不记录 grant/lease、原始异常或 stderr 内容。原严格拒绝规则保持。App 因 native pin 改变重新构建，不沿用旧 App 验收结论。

## 行为与权限范围

- 每个明确批次由 medium owner 只发起一次 `runas`，启动限时高权 broker。该 broker 为本批次的固定隔离安装及清理创建短命 worker，继承已获授权的 token，不再逐次 `runas`。封装候选期限 3600 秒、最多 16 个 attempt；新批次仍需单独授权。
- 普通 App、Node、任务 CLI 保持 medium。高权 worker 以暂停态原子加入独立 kill-on-close Job，验证精确身份、token、镜像和单进程 Job 后才运行。保留每个真实 helper 的退出观察，不将 broker 的存续冒充 helper 已退出。
- grant 仅为发现信息，不授予任意子树权限。Witness 持有实际 App；通过私有管道的内核 PID 核实 App 与精确 Node。root 收到实际 native owner 登记回执后，Witness 才 ACK App；App 随后通过私有 stdin 放行 Node。Node 再通过内核 PID 绑定其实际 native 子进程。没有通用 `allow_tree`。
- 明确出现但无效的批次授权、身份漂移、缺失 ACK、超时、断管道或退出状态未知均拒绝；不退回旧的逐次提权路径。授权撤销、owner / broker 死亡或期限到达时停止活动 Job；清理必须保留原身份、子进程死亡和规则证明。不能证明时保留失败与 `cleanup_pending`，不以动态 WFP 自动删除替代关闭顺序。
- 两代 App 使用独立批次登记通道；旧 recovery 的 claim / consume 协议保持，只有真实消耗恢复许可才允许后继。正常 terminal ACK 后允许管道关闭，但仍核实原服务进程句柄、存活、creation、镜像与 hash。App 关闭失败时保留依赖，成功后再释放客户端，允许明确的关闭重试。

本次未降低 UAC 设置、安装系统服务、启动验收窗口、写入队列或调用真实模型。批次系统权限不扩展普通队列动作的用户授权；enqueue、status、start、pause 等仍使用各自实际回执作为下一步条件。

## 精确来源与产物

- 隔离工作树 `.worktrees/p6-r7-batch-authorization`，分支 `codex/p6-r7-batch-authorization`，基线 `3da91ebc6911d29b5af765b5ac6dfe5231d3eda7`。源码包含选取的现有 P6 文件和冻结产品候选字节，并非仅由该 HEAD 生成。`batch-authorization-baseline.json`、`batch-app-baseline.json` 记录输入与原有字节。
- 原 `.worktrees/p6-r7-product` 和 owned 01–39 不改写；主工作树并行的 A3 / MDA 等改动保留。没有提交、推送、生产接线或部署。
- [编译记录](../../../tmp/p6-r7-review/task-batch-authorization-01/compile.json)：native SHA `b0f930ccc8711b17a318bec5317df84cd5f46db37861745647a9936048378a8c`；Witness SHA `49d910686a52e66abce412713de3ccbb3cfa029c3aab192a842612dec86099df`。
- [最终 App 构建记录](../../../tmp/p6-r7-review/task-batch-authorization-01/app-build.json)：Windows Debug 产品入口、209 个固定输入，App SHA `be703d37e55a6261a346911333f21fb1fe53113bd0789aa166f4680576281e3d`。构建前关键修复检查 3/3；最终构建实际 exit 0，95.1 秒。
- [封存包](../../../tmp/p6-r7-review/task-batch-authorization-01/package.json)包含新的 owned 40/41、独立 dataset `f64b61bc-492f-476d-8d2b-54a9b271bdac`、batch `c61d1ce2-567f-41d3-a3e5-384f32a3029f`、未消费 bootstrap 和只用一次的事件槽。运行配置 SHA `df6f9e2d5874bba7389afd4844798ad97adc8725ea3d9d062ad7ebc737831e49`；404 pins、28 个 host 闭包文件全部通过检查。包中 `actual_uac / actual_app_run / actual_wfp / actual_batch_acceptance` 均为 false。

## 验证证据与限制

- Node 批次 owner、runner、原生登记、私有放行、host、transport、runtime 原专项 106/106；封存前新增静态 ESM 解析测试，受影响 host / launch gate 另复跑 47/47。使用固定 Node 内嵌的 Acorn 与源码 hash，准确解析注释、regex、嵌套模板和转义模块名，拒绝动态 import。两代生成 launcher 的每个本地 import 必须属于 host 闭包，落盘后再读回审计。
- Dart 最终专项 114/114；关闭与启动回归 38/38。分析无 error / warning，1 个空值表达式风格 info。最终修复了发送前必须有管道、精确 ACK 后可断管道、错误非空 PID 不接受这三个边界；独立复核通过。
- C# 新批次托管断言 274，旧 executor 托管 712、self-test 95；新 Witness 托管 226、旧 recovery core 553。均通过；合成私有管道、内核 PID / framing 及私有 stdin ACK 已验证。未运行实际隔离安装 / 清理。
- 高权 worker 原子入 Job、真实 helper 退出证明、Dart terminal 边界均经独立源码复核。局部自动测试与构建不等于真实一弹窗闭环，也不继承旧候选的真人结果。
- 封存后 Node 只读核验 actual exit 0（`637ec3`）；仅调用实际 `BootstrapConfig` 构造、持有文件和验证逻辑的独立 C# 只读检查 actual exit 0（`ffbde5`），未调用 Witness runner 或启动任何 App / native owner。验收槽、数据目录和 actual-run 目录均未消费；见[只读核验记录](../../../tmp/p6-r7-review/task-batch-authorization-01/verification.json)。

## 下一次现场验收

先只读核对封存包全部 hash、候选未消费及现场旧进程 / 规则状态。使用新批次入口，用户只处理开始时的 Windows 系统确认；随后观察预检、任务执行、清理及后继是否均复用同一授权。记录真实弹窗次数、held-process 退出、规则消失、精确任务状态与终态，再决定是否接受该候选。过期、失联和失败清理需要各自故障验证；未知状态不能补成成功。

本次交付限于修改和候选准备，不把仍待现场验证的无人值守体验报告为已经通过。
