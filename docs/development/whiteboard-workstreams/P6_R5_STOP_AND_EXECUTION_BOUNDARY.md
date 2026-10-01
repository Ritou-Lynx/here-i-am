# P6-R5 停止回执返修与受限执行路径核对

更新：2026-09-07。承接 [主验收交接](GOAL1_MAIN_ACCEPTANCE_HANDOFF.md) 与 [R4 实际行为证据](P6_R4_BEHAVIOR_VERIFICATION_PLAN.md)。

## 授权、基线与本轮边界

- 用户在新主验收任务回复“继续”，恢复既有 Goal 1 / P6 范围内的调查、本地返修与自动验证；不创建自动 Goal，不重开 P4。
- 主控 task `01a07b2e-1717-7582-8555-909389a9c03e`；`v3-lab@4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b` 加当前未提交的 P5/P6 源。原有五项 staged 与其他并行修改保留，不提交或推送。
- 停止返修使用 `.worktrees/p6-r5-stop-receipts` / `codex/whiteboard-w0-p6-r5-stop-receipts`；从相同 HEAD 建立，再覆入 15 个已冻结的当前指令、R4 证据和 Bridge 输入。此次 overlay 不是新成果。
- 本轮先修已证实的停止语义缺口，并查明当前 Codex 路线是否存在可验证的全局工具禁用机制。生产 text-only 拒绝门控保持；真实账户、新候选及生命周期真人 Gate 后置。
- 不操作原 App、Bridge、手机或真实队列，不读取认证内容；自动验证只使用测试进程、内存数据和固定合成输入。若需改变权限、验收定义、执行架构或 API/费用，先给出具体取舍，不静默替换路线。

## 分工与完成条件

| 工作包 | 执行者 | 拥有路径 / 输出 | 状态 |
|---|---|---|---|
| 停止回执返修 | `/root/p6_r5_stop_repair`，Astra high | 隔离目录的 client/adapter 及对应测试、stop contract；自身 R5 handoff | 最终七文件已回收；两项 P2 及关闭清理竞态已修复并独立复核 |
| 受限执行路径核对 | `/root/p6_r5_isolation_audit`，Astra high；主控执行固定合成验证 | 当前协议、CLI 能力及官方文档；目录 / 实际行为探针 | 新配置已验证、独立复核通过；生产隔离未通过 |
| 消费契约、独立复核与集成 | `/root`，当前 Astra | 主目录只读核对 Dart 消费者；串行集成获审差异与维护本页、当前态及 DEVLOG | 本轮完成，Node 70/70；真实 CLI 合成停止三场景通过 |

停止返修必须满足：

1. `client.stop()` 在 kill 请求之后继续有界等待实际 child close；未观察 close 时不签发进程已停止结论，不丢失活进程的跟踪与清理能力。
2. 中断请求接受、匹配的 provider turn terminal、进程退出和结果未知分别表达；本地不可用分支不能伪造 provider terminal。
3. 并发 stop、终态先于 ACK、迟到 close、kill 失败、错误或缺失终态均有专项负例；普通聊天不获得虚假的 text-only 隔离回执。
4. 主控复核当前 overlay 的最小 diff，运行 client/adapter/API/profile 相邻回归。构建与真人通过单独记录，自动测试不能替代。

工具隔离继续使用既有完成定义：空 dynamicTools、prompt 约束、配置回显或个别工具拒绝均不证明全部工具已禁用。R4 的 `list_agents` 实际执行证据仍有效；未测工具继续未知。不原样重复 R3 已失败的配置组合。

## 主控当前核对

- Dart 文字任务客户端已经要求版本化隔离回执与 exact 本地 session 的停止确认；缺失回执会拒绝成功。普通 Runtime 的关闭返回不能替代此证据。
- 队列控制在关闭未确认时写 `blocked/interrupted` 与 `runtime_stop_unconfirmed`，不写取消成功；此轮优先修底层事实来源。
- 既有停止回执契约尚未绑定具体 turn；真实 profile 接线前须核对 exact provider thread/turn、终态来源及启动结果未知路径。本轮不因通用 adapter 新增停止证据而启用专用 profile。

## 新的工具隔离证据

- 官方 [Subagents 配置](https://learn.chatgpt.com/docs/agent-configuration/subagents#global-settings) 提供 `agents.enabled=false`；它与 R3 使用的 `features.multi_agent=false` / `multi_agent_v2=false` 不同。本轮新增 `agents-disabled` 变体，在原 excluded 配置上只增加此键，不改生产配置。
- 受测 CLI 仍为 `0.153.4`，SHA-256 `e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75`；探针新增哈希拒绝，并复用 R4 的实际 provider / 用户层 / MCP / hooks 隔离检查。临时空 home、空 cwd、最小环境及 loopback 假 provider 无真实认证。
- 目录报告后缀 `9ppRjq`：有效配置确认 `agents.enabled=false`；协作目录消失，剩余 `functions.exec/wait/request_user_input` 三项、零嵌套声明。合成文字完成、零 server request；完整目录非空，`passed=false`。
- 行为报告后缀 `m1b1BB`：同配置下附加动态工具正控返回自造标记；合法 `exec` 返回 `code-mode host is disabled`；`collaboration.list_agents` 返回 `unsupported call`；提问工具在 Default 模式拒绝。四例均匹配完成终态且测试进程退出，行为断言通过；`production_isolation_passed=false`。
- 首行为报告后缀 `KrOO0e` 因分类器未识别 `unsupported call` 保留为未通过；补充分派拒绝分类与测试后重跑取得上述最终报告，未改写首报告。
- `wait` 没有可合法取得的 live cell，因此未以假 ID 的报错充当禁用证明；spawn、shell、真实文件与外部网络没有新增行为验证。本轮不把目录残留静默改成“抽样拒绝即通过”。
- 当前公开协议、CLI exec 帮助及官方文档未找到全局内建工具 allowlist / tools-disabled 开关；这是当前证据范围内的结论，不宣称所有实现架构不可能。SDK / exec 也未取得零工具证明。

临时报告只含合成资料，保留在各自系统临时目录，不纳入产品或 User-truth。

## 结果与剩余事项

- 最终停止包七文件按冻结输入检查后串行回收，主目录与隔离交付哈希全部一致；详见 [停止证据交接](P6_R5_STOP_RECEIPTS_HANDOFF.md)。`stop()` 在 kill 后继续有界等待实际 child close；未确认则抛错并保留清理责任。通用 adapter 分别记录请求派发、ACK、exact provider thread/turn terminal 与本地 binding 关闭，不生成专用 text-only receipt。
- 独立复核两项 P2 已关闭：关闭等待期间拒绝迟到审批/工具请求；未实际派发的中断不能因迟到 interrupted 而被归因为本次取消。补修中发现的关闭清理竞态也已闭环：用户成功答复被拒绝时，有效 callback 保留给 close pass 发送 decline/failed；两条回归只在收到该负面答复后才产生 provider terminal。最后窄复核未发现新问题。
- 主目录最终六文件组合 **70/70**，0 fail/cancelled/skipped；三探针语法检查通过。组合覆盖 client、adapter、stop contract、experimental API、text-only profile 与工具行为探针；worker 自身组合 64/64 的模块清单不同，不混用数量。原 Flutter 122/122 为历史证据，本轮未重跑、未构建。
- 最终真实 CLI 合成停止报告后缀 `86cf9y`，`probe_passed=true`：中断前有匹配文本；派发时通知序号 11，matching interrupted 序号 14，ACK 被读到时序号也为 14；终态后 **300 ms 观察窗**文本增量 0。正常结束为 completed（序号 30），断流为 failed（序号 44）。停止耗时 55 ms，client 回执和独立 child close 观察均在返回前确认退出；此例未触发 kill，kill/失败/迟到 close 路径由专项负例覆盖。
- 首版停止报告后缀 `5rtwLV` 保留为历史调试证据，最终依据上述新报告。报告的 `writes_after_close=1` 是 interval 察觉连接已关闭后停止写入的计数，不代表已向关闭连接成功写入一次；本轮不据此推断远端行为。
- 新 `agents.enabled=false` 只解决本轮已验证的协作目录/查询路径，仍有三个目录入口，生产隔离未通过。`workbench_text_only_v1` 继续拒绝 start/resume；真实账户、专用 exact-turn 停止回执接线、新候选及取消/执行/恢复真人 Gate 均未完成。P6 与父 Goal 1 均未通过。

## 下一步待用户决定

后续决定（2026-09-07，9 月 10 日补记）：用户已回复“同意”，接受下述受限执行口径；不再等待重复确认。实施与当前证据转至 [R6](P6_R6_TEXT_GATE_PLAN.md)。以下保留 R5 当时的提案记录，不代表现在仍未授权。

建议继续保留 Codex，下一轮评估“允许目录残留，但必须证明所有工具调用在执行前被统一拒绝”的受限执行契约。它改变了当前零工具目录口径，尚未获用户确认；本轮只提出方案，不修改完成定义，也不凭已测样例启用执行。若用户确认，下一步先确定可强制执行的拦截位置、默认拒绝规则和覆盖证据；不能完成全范围证明则继续拒绝。专用停止回执仍须绑定 exact provider thread/turn，真实账户与真人 Gate 单独验收。

依据 [R4 门槛与执行顺序](P6_R4_BEHAVIOR_VERIFICATION_PLAN.md#门槛与执行顺序) 第 4 条：“本轮不把‘目录为零’静默改成‘抽样拒绝’”。这不是已选定的新 provider 或费用方案；用户也可以保留现有零目录标准，继续关闭生产执行。

官方语义参考：[App Server 中断](https://learn.chatgpt.com/docs/app-server#interrupt-a-turn)。文档用于界定协议，实际行为以本机测试和事件为准。
