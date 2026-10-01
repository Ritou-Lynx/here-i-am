# Goal 1 / P6 普通入口接线候选（2026-09-30）

## 10 月 1 日同候选受控终态交付故障与唯一 retry

沿用 App exe SHA-256 `A8A3FF2943B2B6F6837A1945F9ED7AEF6CC5F9BC232FB492B59F34C789A192C3`、原生 v2 SHA-256 `4B052BDF2DAE7F239A94CBC2C289A55A0E50F9995C914835370CE6536EAE3905`。新任务 `b2b1680e-8ff4-4ddc-b451-f14daf8223f6` 的标题“公开文字验收”与目标“只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。”均逐字核对；入队 pending/0%、retry0 且从未启动。应用按条件查询后唯一 start，返回 running。隔离代理确认目标 session/turn，并仅在真实 `turn_status=completed` 交付时把该事件替换为同序号本地 error；一次性标记被消耗，事件记录为 `injected_terminal_delivery_local_error`、sequence 2。持久态随后为 failed/0%、retry0、`provider_execution_failed`，没有把此合成错误称作真实提供方失败。

应用再次先查状态，仅在 failed/retry0 时唯一 retry，返回 running/retry1；最终持久态 completed/100%、retry1、execution completed。执行请求恰好一条 start 与一条 retry，未创建新任务或再次重试。最终结果 8892 字符、2000 行，逐字等于从 1 到 2000 每行一个整数，SHA-256 `929EA644021B8159E97D4B2D3C28F917419420D9A51C4C82089785879BF45A00`。两次原生尝试 `19c9505e…826d`、`07973906…bb73` 的 process/job/stdio/rules/handles/helpers 六项关闭事实均 true、owner exit 0、`cleanup_pending=false`；应用普通关窗实际退出，隔离 Bridge/代理停止且 47832/47833 均无监听，SQLite integrity check 为 ok。脱敏证据 `tmp/goal1-p6-combined-20261001/terminal-delivery-retry-result.json` SHA-256 `ED08CBDB11BD05F327AD030742E530846E9821AE03FF9CCE0CBAB6BF49F9C9E5`。

同一 exe 普通关闭后再打开，隔离库仍为 7 条任务；本任务保持 completed/100%/retry1、仅 start/retry 两条请求、8892 字符原结果，SQLite integrity ok。继代窗口再次普通关闭后仍如此，隔离端口均无监听。当前源码清单的 104 个路径与封存 SHA-256 均一致。尝试补白板最小复核时，该隔离入口仅显示受限聊天页，未取得白板真人操作结果；P4 已接受的正式入口 Gate 不据此改写，也不把本轮计入跨包白板复核。

同一组合候选的普通入口 P6 隔离生命周期已覆盖正向结果、暂停/恢复/取消、完成态及异常退出恢复、关闭故障和这次受控 failed→retry→completed；这是隔离验收结论，不能推导真实 provider 故障、其它包真人 Gate 或生产启用。父 Goal 仍活动，生产保持 fail-closed，无 commit/push/发布。

## 10 月 1 日已确认启动后的本地故障复验与后续候选

上轮 `19bfcd63…59d53` 的 503 在代理转发前被拦，原生六项清理已证实；隔离 App 普通关窗门控未放行。固定状态证据后，只结束核对过精确路径与启动时间的隔离进程，停止 47832/47833 服务；旧任务仍 blocked/interrupted/retry0，数据库 integrity ok。收尾证据 `tmp/goal1-p6-combined-20261001/isolated-window-disposition.json` SHA-256 `28F838337F33E9AF0AF57DD3286B8189F778F67064AEAACA67120973C54F07DE`，不将人工隔离收尾回填为普通关窗通过。

新任务 `7a4aec55-03cc-4d3f-82dd-4d49fcb0034e` 的公开标题与逐行 1–2000 目标逐字核对，pending/0%、retry0、未开始后唯一条件 start。隔离代理 `confirmed-turn-local-fault-proxy.mjs` 先确认目标 session 和 local/provider turn，再在第一次事件读取注入一次本地 error，标记被消耗；App 启动回执为 running，持久态随后 blocked/0%、retry0、`runtime_connection_lost`，无结果、仅一条 start 请求。因此 failed/retry0 条件仍不成立，未 retry/resume/cancel 或创建别的任务。原生尝试 `22c0a155-2e67-4196-9d32-751d4a06577c` 六项 true、`cleanup_pending=false`、owner exit 0；App 普通关窗实际退出，Bridge/代理停止、47832/47833 无监听、SQLite integrity ok。脱敏证据 `tmp/goal1-p6-combined-20261001/confirmed-turn-local-fault-result.json` SHA-256 `8920109621E7CEB637119EEA4D02A5B9E33A33EFB49AB01CA1BBC14A4187F1B2`。本地 error 是合成故障，不声称提供方失败。

下一隔离代理候选 `terminal-delivery-fault-proxy.mjs` SHA-256 `437D2D719649B1AB1A159A9F90AC82B04A6748E27FD9786A0E561B90302E7F7F`：只对精确新任务及已确认 turn 生效，等待真实 `turn_status=completed` 后，把交付给 App 的这一条事件替换为同序号的本地 error；真实终态仍留在 host ledger。假 Bridge 检查通过无关任务不变、完成前不注入、完成交付只替换一次并消耗标记；尚未实跑，不能称 retry Gate 通过。当前批次按异常即停，Goal 1/生产边界不变。

## 10 月 1 日新单任务故障复验：启动结果未知，按条件停止

用户在上一批按异常结束后授权继续一条新隔离公开任务，目标为一次受控首次失败，并且仅在 `failed/retryCount=0` 时 retry 一次。同一 App exe SHA-256 `A8A3FF2943B2B6F6837A1945F9ED7AEF6CC5F9BC232FB492B59F34C789A192C3`、原生 v2 SHA-256 `4B052BDF2DAE7F239A94CBC2C289A55A0E50F9995C914835370CE6536EAE3905`、有效配置 SHA-256 `CF244F55830AFE0E3BEC69A91FBE773C006963AC47ACB8AFB36160FAD331FD96`。新任务 `19bfcd63-14eb-4d7c-878a-8de99c659d53` 标题、目标与既定公开文字任务逐字一致，入队 pending、未开始、retry0 后只有一条 start 执行请求。代理在文字 turn POST 注入一次 503 并消耗标记；任务持久态是 blocked/0%、retry0、`execution.phase=interrupted`、`reason=runtime_start_outcome_unknown`、sequence 0、无结果。不是 `failed`，因此条件 retry 未执行；未恢复、取消或创建另一任务。

原生尝试 `8e943df5-5c02-4305-8e19-924db77d3c5e` 的六项清理事实均 true、`cleanup_pending=false`、owner exit 0。代理记录随后的 DELETE 返回 200；然而 Dart 文字客户端对 turn POST 结果未知的会话显式拒绝将该 DELETE 认作普通关闭证明，队列 owner 将该绑定保留，普通 WM_CLOSE 两次后窗口仍在。这是当前 fail-closed 门控按代码预期的结果，不能据清理回执推断 provider turn 终态。没有强制结束 App；隔离 Bridge 与代理仍运行以保留现场。脱敏证据 `tmp/goal1-p6-combined-20261001/new-one-task-unknown-start-evidence.json` SHA-256 `F487044D6369F53AC250EA785187759AF9C2A0080A2024D9A79ECFB9F00F7DCE`。本批按异常即停，retry Gate 与 Goal 1 完成定义仍未通过，生产保持 fail-closed；无 commit/push/发布。要验确定性 failed→retry，需另设计在已确认 turn 之后的终态失败注入与新批次，不能复用这次 503 结果。

## 10 月 1 日新两任务批次：首条生命周期通过，第二条异常停止

用户明确授权旧批停止后重新开展最多两条隔离公开任务；同一已验 App exe SHA-256 `A8A3FF2943B2B6F6837A1945F9ED7AEF6CC5F9BC232FB492B59F34C789A192C3`，新 v2 原生 SHA-256 `4B052BDF2DAE7F239A94CBC2C289A55A0E50F9995C914835370CE6536EAE3905`，配置见下节。第一次新任务 `3f620d90-4561-43b9-bab4-2f8c2333bc4f` 标题/目标精确为“公开文字验收”及逐行输出 1–2000；入队 pending/0%、retry0、无执行记录。应用逐步先查当前态，仅满足条件才各执行一次 start、pause、resume、cancel；数据库状态为 running→blocked/paused→running→cancelled，四个 execution request 各一条、retry0。pause 与 cancel 的两个独立原生关闭回执分别为 `9c5e0771…f17e`、`338b29f2…827f`，均六项 true、`cleanup_pending=false`、owner exit 0；同一 Bridge 观察记录，不声称独立 Witness。

第二次新任务 `398e0363-a199-4ecc-be78-7da125d13550` 标题/目标同样精确，pending/未开始后只执行一次条件 start，最终持久态 failed/0%、retry0、`runtime_start_failed`，无 session/turn/结果。代理一次性文字请求 503 标记在失败后仍存在，事件日志无本次注入；标记已精确移除，故不能把失败归因于受控故障。原生尝试 `9839c55d-c494-429e-b2df-1cd569762c97` 有 prepared 和完整 pin CLI 副本，但没有 child、install receipt 或文字请求；prepared 写于 04:39:28、final 写于 04:41:32，约 124 秒与 Node 默认 120 秒 `native_startup_timeout` 相符，支持系统确认等待超时的推断，但未取得本次原始 Win32 错误码，不能定因。owner 后来退出，其 final receipt 记 `started=false`、`cleanup_pending=true`，rules/helpers/stdio 等未证实。按授权“异常即停止”，未 retry，也未碰旧任务。精确四键只读检查器 `tmp/goal1-p6-combined-20261001/InspectTask2Rules.exe` SHA-256 `10553DC2E385B96DBD814C13842904C6E34916F610B1DDF3D9CC76BF61F0CAFD`，键算法用既有成功检查案例核对；普通权限只读事务返回 Win32 5；用户处理系统确认后，同一检查器在只读事务中报告 `allow4/deny4/deny6/sublayer` 四键全 absent、`present_count=0`、`transaction_abort=0`、`engine_close=0`。结果 `tmp/goal1-p6-combined-20261001/task2-rules-inspection-result.json` SHA-256 `EFA0FC017573D9BB33669661CAED32D11BF4CCDCC52F80603212E0DCF3CC108A`。这是检查时规则缺席证据，不能回填原始 final receipt 的 `cleanup_pending=true`。隔离 App 正常关闭，Bridge/代理与 47832/47833/8434 端口均退出；脱敏状态摘要 `tmp/goal1-p6-combined-20261001/new-two-task-batch-evidence.json` SHA-256 `68F5CA341B025AF1C1526555A0BEEC0365802916C7E2BE156390D7B4114787F8`。此批通过首条 start/pause/resume/cancel 窄 Gate，不通过第二条 retry、整体清理和 Goal 1 完成定义；生产保持 fail-closed，无 commit/push/发布。

## 10 月 1 日后续生命周期批次实际停止点

用户授权同一隔离普通 App 包新建最多两条公开任务，第一条按状态条件依次 start/pause/resume/cancel，第二条模拟首次失败后在 failed/retry0 时 retry 一次。英文输入模式下完整校验标题与目标后，第一条新任务 `35976878-9ada-4f47-982f-22c556e5b044` 入队为 pending/0%、retry0、无开始时间。应用确认条件后只发一次 start，返回 `runtime_execution_failed`；持久态为 failed/0%、retry0、`runtime_start_failed`，无 sessionId、turnId、结果或 lastStartedAt，execution request 恰好一条 start。代理的文字故障标记不存在、事件日志无文字故障注入；先前完成任务 `ae49501d…d75148` 未变。依授权的“异常即停止”，未执行 pause/resume/cancel，也未创建第二条任务或 retry。

失败原生尝试目录 `da89130a5c6647c9993ebf1b968d76a2` 只留下 268369920 字节 `codex.exe`，没有 `prepared.json`、安装或 final receipt；成功尝试 `07078951…9c46` 的副本为 295408944 字节且 SHA-256 与固定 pin 一致。检查时 D 盘仅余 3596288 字节，截断复制与磁盘空间不足高度吻合；没有原始 Win32 错误码，不能把它写成直接证明或六项清理成功。现场 App、Bridge、代理及 47832/47833 监听均已退出。精确核验后删除本次截断副本，D 盘升至 271966208 字节；再删除 `build-disposition.json` 明确标为 rejected 的首包 `bundle/data/flutter_assets/kernel_blob.bin`，升至约 414 MB。通过 Gate 的 `bundle-47832`、数据库、源/产物清单和 `native-close-receipts.jsonl` 均未删；被拒首包如今不再是完整可启动产物。

诊断期间 Codex 桌面更新：原生 `TaskPaths.SourceCli` 固定的 `7ac07f4ce733f89a` 安装目录已经不存在，当前命令指向另一安装目录且哈希不同。因此即使只补空间，当前固定 native/source pin 也无法重新启动。后续应先建立可核验、不会随桌面更新消失的受限 CLI 来源，校验新原生/Bridge 配置和足够空间，再对新候选做零任务启动诊断；本批不再做队列动作。此前同一 App 哈希的正向、恢复和关窗 Gate 仍按各自原始证据成立，但本批生命周期 Gate 未通过，Goal 1 保持活动、生产仍 fail-closed、无 commit/push/发布。

上述固定来源与空间修复随后完成：从先前成功尝试取原 pin `3D6CA708…48C6004` 的 295408944 字节 CLI，逐字节核验后复制到 `C:\Users\Public\Documents\HereIAm-P6-Text-Cli\codex.exe`；未修改 Codex 安装或凭据。原生每尝试根由空间不足的 D 盘改到 C 盘公共文档下的受保护 `HereIAm-P6-R7-Task-Executor`，创建时仍按用户/System/Administrators 精确 ACL、无重解析点和空工作目录校验。第一次复制到 AppData 的 v1 候选因原生看到重定向路径而被 `task_files_cli_source_canonical_rejected` 拒绝，未出现系统确认、未写 prepared；不计通过。改用非重定向公共目录后，v2 原生 exe SHA-256 `4B052BDF2DAE7F239A94CBC2C289A55A0E50F9995C914835370CE6536EAE3905`；有效配置 `tmp/goal1-p6-combined-20261001/croot-v2/text-host-config.json` SHA-256 `CF244F55830AFE0E3BEC69A91FBE773C006963AC47ACB8AFB36160FAD331FD96`。托管 2/2（712 断言）、原生 self-test 95 断言、相邻 Node 39/39 通过。用户确认可处理系统弹窗后，v2 实跑零任务/零模型 no-auth probe：started/config/thread/无 turn 关闭、进程退出均 true，上游请求/host request 均 0，原生六项清理 true、`cleanup_pending=false`、owner exit 0；报告 `native-croot-v2-no-turn-probe.json` SHA-256 `266999FD26083DE211541EAE5C4E1EE1A17E3BAE58C46AEF28F13C03D15240B8`。这是新的原生候选窄 Gate，不是同哈希 App 队列的 pause/resume/cancel/retry 真人通过；旧批次仍按异常条件停止。

## 10 月 1 日跨包组合候选与当前真人 Gate

已将隔离产品候选相对当前 `v3-lab@b2adc44b` 的 14 个差异文件和 7 个缺失文件定向并入本地主树；三方合并保留了主树 `AppDatabase.openCandidate` 增量，未触碰其他并行修改或提交。主树普通入口/队列专项 53/53、Bridge 候选及相邻专项修正过期超时断言后 80/80、UI-T/P4/P5 六组组合回归 69/69、构建前关键检查 3/3 通过。独立 `dart analyze` 两次停在启动提示，未取得结论。

首次 Debug 包遗漏隔离 Bridge URL，未启动且明确作废。修正为 `127.0.0.1:47832` 后重新构建成功；冻结包 `tmp/goal1-p6-combined-20261001/bundle-47832/` 含 155 个文件、355449361 字节，App exe SHA-256 `A8A3FF2943B2B6F6837A1945F9ED7AEF6CC5F9BC232FB492B59F34C789A192C3`，kernel SHA-256 `58317D011C3B53880270FDE410A9BE1126EF8665572D4988F48CC39C19A3F1C1`。104 路径的当前源码清单为同目录 `source-manifest.json`（SHA-256 `26261ECCED67D68B679F6D24CC58F788977A3CD31C62F65115F015BDD4719ED1`），产物清单和作废标记也在该目录。

隔离 Bridge 已在 47832 启动并只读证实文字任务 profile 为 `configured:true/available:false/fail_closed:true`；受限原生程序哈希与配置 pin 一致。新 App 已打开，独立数据根创建成功；启动后只读数据库 `task_rooms=0/tasks=0`。电脑输入工具仍未把短句写进 Flutter 输入框，期间检测到用户正在使用电脑，故停止抢焦点。用户在新窗口手动发送 `hi` 后，只读数据库确认 1 条用户 `hi`、1 条非空角色回复，`task_rooms=0/tasks=0`，普通短聊零任务通过。**本组合候选尚无长任务、异常退出或六项清理的真人回执**；不能继承旧 App 哈希的正向结果，Goal 1 仍活动，生产默认拒绝，未 commit/push/发布。

随后给 Bridge 产品适配器加可选的本地原生关闭观察器：只有原生返回的六项事实全 true、`cleanup_pending=false` 且进程退出码存在，才将固定字段同步写入配置目录下的 `native-close-receipts.jsonl`；缺项拒绝记录并使关闭保持未确认。三字段旧配置与默认生产行为不变，四字段配置须哈希固定回执路径。新增专项及相邻 Bridge 回归 82/82，另补外部回执路径负控 4/4；通过后仅重启隔离 47832 Bridge。`text-host-config-audited.json` SHA-256 `2FC2B111C84AF6565AB8043F6E35C4D39B27D8173494BF01EA5F81C4993C11C0`。App 二进制未变；包含最终负控的运行时 104 路径源码清单为 `source-manifest-runtime-v3.json`，SHA-256 `D612BC5668D64AF8EC1341D398DBF50A250A3F3C8E1FDFF6A21A7CD152B88509`。重启后只读能力仍为 configured/fail-closed、隔离任务表仍为零、回执文件尚不存在；这些都不是实际清理成功证明。

同一最终 App 哈希上，用户发送完整入队句后，新任务 `ae49501d-a81e-49ef-a623-5a0c82d75148` 的标题/目标逐字匹配，pending/0%、retryCount 0、lastStartedAt 与 execution 均不存在。用户随后发送精确 ID 的条件启动句；应用先确认 pending/未开始再返回 running，数据库记录恰好一次 start request。最终持久态 completed/100%、retryCount 0、execution completed；唯一结果 8892 字符，逐字等于 1–2000 逐行整数，SHA-256 `929EA644021B8159E97D4B2D3C28F917419420D9A51C4C82089785879BF45A00`。`native-close-receipts.jsonl` 恰好一条原生 attempt `07078951-f5b1-493c-a1e8-ac6285969c46`：原生 SHA 与 pin 一致，owner PID 66924、exit code 0，process/job/stdio/rules/handles/helpers 六项全 true、`cleanup_pending=false`。这条是同一 Bridge 的受限字段持久回执，不声称独立 Witness。

首代窗口经普通关闭退出，同一 App 包重开后聊天历史及 completed/100% 数据库结果保留；继代以核对过的独立候选进程 PID 27876 受控强制退出，再重开同一包，聊天历史与唯一任务、唯一 start request、完整结果哈希均未变。第三代经普通关闭退出后，将同一 Bridge 移至本机 47833，并在 App 固定的 47832 放置一次性透明代理；通过逐键核对的只读查询让新窗口建立普通会话。应用先对含糊的 `status only` 诚实报告“未查询、当前未知”，明确要求调用队列工具后才返回 fresh `completed/100%`、结果已保存，未更改任务。

仅在最后关闭前给代理设置一次性标记；第一次 `DELETE /experimental/v1/runtime/sessions/{id}` 被代理返回 503，真实 Bridge 未收到该请求，App 窗口及 PID 56188 保留并响应。第二次点击关闭时相同请求转发到 Bridge 返回 200，App 退出。代理仅记录去标识的 method/path/outcome，事件序列为 `injected_503`、`forwarded_200`；标记已消耗。最终隔离库仍只有一条 completed/100% 任务、retry0、一次 start request、原结果哈希不变；原生六项回执仍恰好一条。App/原生 owner 均已退出，隔离 47832/47833 端口均释放，diff 检查通过。**此组合候选的普通短聊、正向队列、正常及异常重开、原生清理与关窗失败重试 Gate 通过**；它不覆盖同哈希的 pause/resume/cancel/retry 及其它包的真人 Gate，生产仍 fail-closed。无 commit/push/发布。

## 10 月 1 日普通入口正向与完成态重开

沿用 App exe SHA-256 `310FC91DA84F807AC7AAFF6A344A63D4703EE7D3803B1351E601B34C01AE4252`，隔离 47832 Bridge 已加载产品适配器的 `exchangeTimeoutMs=180000` 且显式使用环境代理；能力保持 `configured:true/available:false/fail_closed:true`。电脑输入工具无法直接写入中文，经英文模式逐字符发送十六进制 Unicode 码点，模型将其解码为标题 `公开文字验收`、目标 `只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。`；发送前草稿逐字核对，隔离数据库入队后两字段也逐字匹配。

新任务 `b85342a8-3d18-4877-85d9-fadfa974a41e` 的应用 status 回执为 pending/0%；数据库同时证实 retryCount 0、lastStartedAt null、execution null。仅发送一次带“仍 pending 且从未启动”条件的 start；应用回执 running/retry0。约 123 秒后持久态 completed/100%、retry0、execution completed，唯一 resultText 长 8892，逐字等于从 1 到 2000 每行一个的预期串（无末尾换行），SHA-256 `929EA644021B8159E97D4B2D3C28F917419420D9A51C4C82089785879BF45A00`。应用只读 status 回执也为 completed/100%。

首代 App 正常关闭且进程退出；同一 exe 哈希继代重开后，聊天历史保留，并重新只读查询同任务得到 completed/100%。前后数据库均恰好三条任务，新任务唯一一条、唯一 start request、唯一相同结果；两条旧任务状态/retryCount 未变。继代正常关闭且进程退出，原生 owner 进程 0，隔离 Bridge 停止后 47832 端口释放。本轮没有独立持久化的六项原生关闭回执，不能用进程与端口缺席替代完整清理证据。普通入口正向输出及完成态恢复这一窄 Gate 通过；父 Goal 的跨包唯一集成候选、组合真人 Gate 与生产接线尚未完成，无 commit/push/发布。

验收后将工作树已通过的 `workbench_text_task_runtime_adapter.mjs`、对应测试及 `start_bridge.ps1` 三处最小差异同步至 `v3-lab`，文件哈希逐一相同；主树 Bridge 相关 51/51、Node/PowerShell 语法与 diff 检查通过。该 Debug App 的 104 文件源清单与主树现状比较为 80 同哈希、17 不同、7 缺失；其中部分差异属于上述新修复，不能直接用旧清单构成新的跨包唯一候选。下一阶段需按路径判定其余差异并构建新组合候选，不继承本次 App 的真人结果。

## 10 月 1 日修复加载后的入队前停止

旧隔离应用窗口与 47832 Bridge 正常关闭、端口释放后，按已核哈希重启同一 App exe 和显式代理 Bridge；产品适配器已加载 `exchangeTimeoutMs=180000`，能力仍 `configured:true/available:false/fail_closed:true`。应用保留先前聊天。本轮英文输入一度受中文输入法影响，失真草稿已逐字清空，未发送；切换输入模式后将完整新建句与目标文本校验一致才发送。

这条请求通过“与本聊天已创建任务相同的标题和目标”引用旧任务，但应用回执“当前上下文缺少原任务的标题和目标，没有新 ID”。发送后只读隔离 `task_rooms` 仍恰好两条旧任务：`7f17962a-0912-46c4-ab36-e484ac4c757d` 为 failed/0%、retryCount 1，`f7b82d10-f3f6-418c-a297-1a1c7e772edb` 为 failed/0%、retryCount 0。本轮零入队、零启动；按用户“任何失败即停止”停在创建阶段，未触发 180 秒执行，也不进行完成态关窗恢复。下一次须显式提供标题 `公开文字验收` 和目标 `只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。`，而不依赖聊天上下文；仍需新的运行证据才能通过 Goal 1。

## 10 月 1 日显式代理与新任务正向复验

固定公开短句第二次独立诊断以 Node `--use-env-proxy` 运行：`completed`、`P6_R7_NATIVE_OK` 精确可见、broker 上游请求 1、无 host request，原生 exit 0、六项清理全 true、`cleanup_pending=false`。报告 `tmp/goal1-p6-start-failure-20261001/fixed-public-provider-probe-02.json`，SHA-256 `C1AC406E3A43B4979F153539ABE7BC57FAB6F89D01970683214BF5D3499C1B23`。这只通过固定短句，不代替普通应用队列 Gate。隔离 47832 Bridge 已用 `-UseEnvProxy` 重启，能力投影仍为 `configured:true/available:false/fail_closed:true`。

用户授权在隔离普通入口新建公开长任务、核对 pending 后只启动一次、仅完成后关窗恢复，任何失败即停止。含旧任务 UUID 的首条新建请求被宿主正确拒绝；数据库仍只有旧任务。不含旧 UUID 的第二条创建新任务 `f7b82d10-f3f6-418c-a297-1a1c7e772edb`，标题 `公开文字验收`、目标 `只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。` 均逐字匹配。应用与数据库先确认 pending/0%、retryCount 0，再只启动一次；应用报 running/retryCount 0，约 65.1 秒后数据库终态 failed/0%、retryCount 0、`provider_execution_failed`，执行序列 0、结果空、唯一 start request。按授权停止；未重试、暂停、取消或关窗恢复，旧任务保持 failed/retryCount 1。

该产品 Bridge 使用 broker 默认 `exchangeTimeoutMs=60000`，失败时间与 60 秒上限高度吻合；本次未捕获 broker 精确超时代码，不能把时长推断写成已证实根因。此前已通过的独立 P6 长文本候选使用 180000 毫秒。隔离 worktree 产品适配器已显式设为 180000 毫秒，并在专项测试断言配置；Bridge/Adapter 及相邻 Runtime/Product Host 回归 48/48、语法、diff 检查通过。运行中的 47832 Bridge 尚未加载此修改；本次普通入口正向结果与完成态恢复均不通过，Goal 1 仍开放，生产未切换。

## 10 月 1 日同任务一次条件重试：原生成功、结果失败

首次失败后，经用户处理系统确认，独立只读事务核对同尝试的四个精确 WFP 对象均 absent、`present_count=0`、事务及引擎关闭码 0。该检查只能证明检查时无残留，不能回填首次 final receipt 的 `cleanup_pending=true`。另外运行零任务、零模型的原生启动诊断，结果 `started=true`、native exit 0、六项原生关闭事实全 true、`cleanup_pending=false`、broker drained 且上游请求 0；用户确认看见并点了系统授权。这证明同一原生程序可正常启动和清理，不能推出首次失败的具体原因。

用户另行授权仅对任务 `7f17962a-0912-46c4-ab36-e484ac4c757d` 在 `failed` 且 `retryCount=0` 时 retry 一次。应用和隔离数据库满足条件后只发一次 retry；应用先报 `running/retryCount=1`，随后只读数据库确认持久化 `failed/0%`、`retryCount=1`、`provider_execution_failed`，无完成文本。该次原生尝试已启动并完成六项清理、`cleanup_pending=false`；因此清理成功不等于任务正向完成，仍需定位结果提供阶段。不得对该任务进行第二次 retry 或其他未授权队列动作。

固定公开短句独立诊断已运行：原生启动、配置、ChatGPT 账户、thread/turn、停止回执与六项清理均通过，broker 上游请求恰好一次，但 `transport_failed`、无 HTTP 状态、终态 failed、文本为空；报告 `tmp/goal1-p6-start-failure-20261001/fixed-public-provider-probe-01.json`，SHA-256 `E4D03E86DE21C44D4DDF9FB1B24511AD7A9F75425EC100F5F439598AC178551E`。同机同 Node 的无代理 HEAD 为 `EACCES`，显式 `--use-env-proxy` 后能取得 HTTP 403；这是代理路径差异的证据，不等于认证或模型成功。隔离 Bridge 的启动脚本现加显式 `-UseEnvProxy` 选项，默认行为不变；待固定短句同路径复验，不碰该队列任务。

## 10 月 1 日条件启动：真实执行 Gate 失败

用户明确授权“先查询该任务状态，仅在仍为 pending 时启动一次”。隔离 47832 Bridge 按原配置恢复，配置和原生 exe 哈希与封存值相同；重开同一隔离普通入口。应用只读 status 回执与隔离 `task_rooms` 再查均是任务 `7f17962a-0912-46c4-ab36-e484ac4c757d` 的 `pending/0%`。随后仅对该 ID 发送一次条件 start 指令，应用最终回执 `runtime_execution_failed`，未重试。

持久化 `task_rooms` 精确状态为 `failed/0%`，`retryCount=0`，执行阶段 `failed`、序列 0、空结果，失败原因 `runtime_start_failed`；唯一 execution request 键为 `start-7f17962a-0912-46c4-ab36-e484ac4c757d-20261001-1`。本次 Bridge 派生的原生 owner `53692` 随后退出；其受保护的 `prepared.json` 已创建，尚无子进程或 install receipt。受保护的 final receipt 记 `started=false`、`cleanup_pending=true`，其中 Job 空和句柄关闭为 true，但进程关闭、stdio EOF、规则缺席、辅助进程退出均为 false。用户反馈未看到本次 Windows 确认弹窗；这不足以推定 ShellExecute 的实际错误码。未恢复、暂停、取消或新建任务。精确规则只读检查器已准备，普通权限只读事务返回 Win32 5；待用户可处理一次系统确认后再查残留。进程退出不等于六项清理证明，正向执行及清理/恢复 Gate 均未通过；Goal 1 继续开放。

## 9 月 30 日续验：隔离普通入口已启动，长任务 Gate 仍开放

在同一隔离 worktree 补齐 Debug Windows 候选数据装配：首次进入要求空根，安装带候选 ID 的标记，重开须严格匹配；偏好、Drift 数据库及 WAL/SHM、workspace、白板、日志均落 `tmp/goal1-p6-ordinary-candidate-20260930/run01/`。候选模式关闭普通入口的资产服务、旧记忆、同步、备份及其他非验收后台初始化；直接进入普通桌面聊天，并使用独立 Bridge 端口 47832。存储专项 5/5、会话/队列 40/40、Runtime/Coordinator 48/48、Bridge 10/10；每次构建前 critical 3/3，最终 Windows Debug 编译 exit 0。独立 `dart analyze` 未得到完成结果，不计通过。

最终 exe SHA-256 `310FC91DA84F807AC7AAFF6A344A63D4703EE7D3803B1351E601B34C01AE4252`；`kernel_blob.bin` SHA-256 `B9D67928333B49BF6B87EE5856FBE64993E33B6B5A117BF808492036AA292557`。104 个工作区候选文件的当前哈希清单在 `tmp/goal1-p6-product-build-20260930/SOURCE_MANIFEST_V2.json`，清单 SHA-256 `75FE76FCDD4C88181294F6839A6FA3ECC11F67F8159BA27728BCA77C62C10161`。清单包含尚未提交的叠加源码，不能代替提交 ID。

独立 Bridge 仅监听 127.0.0.1:47832，配置/原生 exe 哈希均匹配；只读 capability 正确显示 `configured:true, available:false, fail_closed:true`。首次最终窗口短聊收到 `provider_error`，精确原因为该本地 App Server 版本不支持默认选中的 `gpt-6-astra`。只给隔离 Bridge 配置受支持的 `gpt-5.6-sol` 后，API 诊断 turn `completed`，最终窗口普通短聊也收到“嗯？”并落在隔离数据库；旧 47831 服务未替换。先前窗口的“hi”回复来自修改端口前的旧构建，不作为最终哈希证据。

用户第一次粘贴的公开任务句从“公开文字验收”开始，缺少明确的创建/标题授权前缀；宿主返回 `task_queue_action_not_authorized`，隔离 `task_rooms=0, tasks=0`，无任务 ID。这是正确拒绝，不计失败任务，也不把它重试为有效授权。已请求在同一窗口完整发送原句；收到完整回执后才继续同任务生命周期与关闭/恢复 Gate。下方内容保留前次源码候选的历史快照。

随后系统剪贴板与 Flutter `TextField` 粘贴、快捷键及自动文字注入均未把完整句写入草稿；改用窗口逐键输入可读的英文授权句，引用上一条消息的精确标题和目标。入队实际返回唯一 ID `7f17962a-0912-46c4-ab36-e484ac4c757d`；隔离数据库逐字段核对标题 `公开文字验收`、目标 `只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。`、状态 `pending`、进度 0%，`task_rooms=1/tasks=0`。尝试发送条件 status→start 草稿时，自动审批审查以“原入队请求要求等待下一条指令，任务创建后没有新的可信启动授权”为由拒绝点击；只读复查仍是 pending，未启动，也未绕过拒绝。已向用户请求该精确任务的后续操作授权。正常/异常生命周期及原生清理仍待，不能借用 run11–14 的哈希结果。

状态：**源码与 Windows Debug 编译通过，真实普通入口 Gate 未开始，Goal 1 仍活动**。本轮在已附加的隔离 worktree `p6-startup-handshake` 上，从 `v3-lab@b2adc44b7c04983a931c39695b81491cd295084b` 建立 `codex/goal1-p6-product-wiring`；选取当前 P6、P5 只读及普通桌面相关未提交源码形成候选。主目录的并行修改未合并、重置或提交。

## 接线与边界

- Bridge 新增 `workbench_text_task_product_host.mjs`：三个本机 opt-in 配置项必须齐全；配置文件及原生 supervisor 均作 SHA-256 校验，不接受额外字段。无配置时 `workbench_text_only_v1` 仍按原门控拒绝；错误配置在启动时拒绝，不回退到普通带工具的 adapter。此项只建立受限执行器工厂，不代表现役 Bridge 已切换或原生 owner 已现场验收。
- 主控/只读复核确认：有效工厂时 text POST/turn/interrupt/DELETE 都走专用 adapter，不回落普通 adapter；`GET /capabilities` 仍投影普通 adapter 的静态 `available:false`，不会拦截请求但会误导调用方。后续应仅报告“已配置、尚未现场验证”，不能仅凭 pin 报 `available:true`。环境内配置路径和哈希也不是独立 admission/Witness 信任根，普通入口实际 Gate 前须补来源约束与真实清理证据。
- 普通 `lib/main.dart` 在 Windows 使用原生 `WM_CLOSE` → Dart 关闭检查：先同步阻止新对话 turn，再中断并等待既有 turn、关闭本机普通会话，最后等待已创建的队列执行 owner 给出关闭结果。任何失败或超时保留窗口，重复请求按本次 request ID 约束，可再次尝试。Flutter detached 仍只是不能等待回执的兜底；页面后台化不取消队列。
- 普通 PersonaChat 的用户原话仍先写入已有聊天存储，再进入 Coordinator。关闭竞态可能留下已保存但未开始 Runtime 的用户消息；本轮不把消息持久化误当成执行成功。普通会话的 HTTP `closeSession` 仍不是 P6 原生 child/Witness 的六项清理证明。

## 自动验证与精确候选

- Bridge 新工厂、拒绝 profile、Runtime API 等专项 36/36；主控复跑其中 15/15。队列既有专项 69/69。补齐隔离 worktree 的 P5 只读来源后，桌面退出与 Coordinator 31/31。`git diff --check` 通过。
- Windows 首次编译因隔离 worktree 缺插件链接，在 CMake 阶段停止；核对依赖配置后只重建 21 个指向本机既有 Pub 缓存的插件符号链接。第二次构建前 `verify_critical_fixes.ps1` 3/3，通过后 `flutter build windows --debug --no-pub -t lib/main.dart` **exit 0**。没有启动 App。
- 源码清单：`tmp/goal1-p6-product-build-20260930/SOURCE_MANIFEST.json`，96 个相对路径及 SHA-256，清单 SHA-256 `0D3E301D520BA28FBD4899A9F5156BA3284D573BAD486F450D5FB7B863B85036`。exe SHA-256 `1257C7B9665AF093464BDC6A742560FCFB37BE5233FB18DD555C8E951E46E972`；`kernel_blob.bin` SHA-256 `47806F46CAC761225C806C364316BF0E2F10C03B42D8F85894AC7991C244D7CB`。产物位于同名 `tmp` 构建目录的 `x64/runner/Debug/`，工作树 `build/windows` 仅指向该目录。
- 指定文件的独立 `dart analyze` 长时间无结果，已中止；相关 Dart 代码有 31 项回归及 Windows Debug 编译退出 0。没有将分析标记为通过。

## 剩余 Gate

1. 复核普通入口的独立数据装配。当前普通 `main.dart` 会使用用户现有的 `UserStorage`/`AppDatabase` 位置，`RootShell._checkUser` 还会写共享偏好，`MemexRouter` 启动会运行其它数据回填/调度/Bridge 同步；只换数据库文件名并不能隔离这些副作用。因此**不得直接运行本候选去创建验收任务**。先让普通入口的验收模式只触达新数据且关闭非验收后台接线，再核对 Bridge 原生 supervisor 的精确配置、身份和默认关闭证据。
2. 在该隔离装配形成的新唯一候选上，实际完成短聊零任务、明确 enqueue/status、合法动作、正向结果、正常及异常重启恢复、原 owner 清理和关窗失败重试；按受影响范围复核既有 UI-T/P4/P5。run11–14 的独立入口真人结果不可填作本候选 Gate。
3. 实际 Gate 通过后再审计并更新 Goal/状态/Roadmap；本轮无现役服务切换、真实队列操作、安装、commit、push 或发布。

## 普通入口隔离范围复核

只读复核确认“仅换 `userId`”不成立：Windows SharedPreferences 在 App Support 下读写 `shared_preferences.json`；Drift 默认写 Documents；`UserStorage.resolveDataRoot` 还可能读取现有自定义 workspace。`MemexRouter` 构造后会启动回填/任务恢复/分析/Bridge 同步/备份等，`MainScreen` 延迟启动 CoreSync 与日程刷新，`LocalServerService` 会绑定固定本机端口。首次 `UserStorage.initL10n` 前必须安装候选专用偏好存储和数据库/workspace 路径，并以明确 Debug-only policy 阻止上述非验收后台动作。推荐共享普通 UI/coordinator/exit gate 的候选入口与正式路径注入 API，而非复用固定任务的 `p6_r7_product_main.dart` 或测试专用数据库工厂。自动测试需证明 prefs、sqlite/WAL/SHM、workspace 只落候选根，非验收启动器零调用；真实启动另核根外无写入。
