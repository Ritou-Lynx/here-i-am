# P6-R4 工具行为与真实终止验证

## 授权、基线与当前状态

- 2026-09-07，用户在“先验证额外工具是否真能执行，以及取消是否真正停止”的说明后授权“派任务吧”。承接现有 Goal 1/P6，不新建 Goal，不自动切换模型 API 或计费来源。
- 主控 `/root`，task `01a03e4a-e594-7b32-b3da-25705b8e1eb5`。主分支仍为 `v3-lab@4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`；保留全部原有 staged/unstaged 修改。
- 两个工作包从相同 commit 创建独立 Worktree，并复制 14 个已核对的当前指令与 R2/R3 源/文档作为只读 overlay。该 overlay 不是本轮新成果，不携带其他产品改动。
- 受测 CLI：0.153.4；exe SHA-256 `e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75`。每次运行再次核对，不把不同候选证据混用。
- 当前状态：A/B 已交付并由主控选择性回收；六个新增验证/交接文件已本地集成，主控六文件 Node 组合 40/40。仅新增合成验证与 handoff，生产 profile 继续拒绝，P6/Goal 1 未通过。

## 工作包与所有权

| 工作包 | 执行者 / 路由 | 隔离基线与拥有路径 | 交付标准 | 状态 |
|---|---|---|---|---|
| A 工具实际行为 | `/root/p6_r4_tool_behavior`；Astra high | `.worktrees/p6-r4-tool-behavior`；`codex/whiteboard-w0-p6-r4-tool-behavior`；仅新增 `tools/dev_agent_bridge/workbench_tool_behavior_probe*` 与 `P6_R4_TOOL_BEHAVIOR_HANDOFF.md` | 六例真实 CLI 合成行为断言、专项 7/7；主控核对原始调用/结果并回收三文件 | 已回收 |
| B 中断与真实终止 | `/root/p6_r4_stop_semantics`；Terra medium | `.worktrees/p6-r4-stop-semantics`；`codex/whiteboard-w0-p6-r4-stop-semantics`；仅新增 `tools/dev_agent_bridge/workbench_stop_semantics_probe*` 与 `P6_R4_STOP_SEMANTICS_HANDOFF.md` | 三阶段终态、超时 fake-child 反例；主控补要求后再次取得带前置文本证据的最终报告 | 已回收 |
| W0 标准、复核与回收 | `/root`；当前 Astra | 主工作区；本计划、必要状态、DEVLOG，串行选择性回收验证文件 | 原始报告/最小 diff 已复核；主控 Node 40/40、两探针语法检查通过；生产执行未开放 | 本轮验证已收口 |

主控已冻结本轮触及的 11 个生产/R3 输入文件哈希，用于回收时确认未被顺带修改。worker 不派生协作子 Agent，不改共享文件/Git 索引，不提交/推送。

## 要回答的两个问题

### A：目录声明与真实能力是否一致

R3 仅证明完整工具目录非空，不证明工具已经执行，也不能证明所有工具已被拒绝。R4 使用实际 CLI、隔离临时 home/空 cwd、最小环境与 loopback 假 provider，让固定合成响应提出正确格式的无害工具调用。

- 先证明 harness 能把有效调用交给工具处理器；普通文字命中、未知工具名、坏参数、假 ID 和 no-op 不能充当禁用证据。
- 从实际目录确定最小有判别力样例，区分协议解析失败、工具处理器拒绝、权限拒绝与真实执行。
- 只能使用自造临时标记；不访问真实文件、凭据、数据库或私人对话，不调用真实模型或外部服务。
- 如验证协作工具需要合成子线程，必须限定同一 loopback provider、继承相同隔离与固定短文本、最多一个；继承不可核实则停止该样例并标未知。它不授权开发 worker 派生新的协作 Agent。

### B：请求停止与实际停止是否一致

官方 [App Server](https://learn.chatgpt.com/docs/app-server) 区分 `turn/interrupt` 请求与 `turn/completed` 最终状态；R4 用合成流式响应核实本机行为。

- 匹配精确 thread/turn，分别记录中断发出、ACK、terminal 状态与 provider 连接结束。
- 验证正常中断、关闭、断线/终止回执缺失和迟到输出。不把客户端不再接收等同于真实远端已停止生成。
- 主控源码预审：`client.stop()` 超时路径会在发出 `child.kill()` 后 resolve，未等待进程 close；`adapter.closeSession()` 的不可用分支本地标记 interrupted，不含真实 provider terminal。必须用负例区分这些状态，不能签发真实终止证明。
- 正常 synthetic provider 中断成功只证明该条实际 CLI 路径，不证明真实账户后端、全进程树或全部异常路径。

## 门槛与执行顺序

1. A/B 提供边界内最小验证实现与证据；主控检查请求固定、provider 仅 loopback、配置无真实认证、进程仅本次所有。
2. 主控复核正负控与关键断言，必要时只修探针/测试；逐包回收，保持现有生产源不变。
3. 按证据判断：工具确实可执行则隔离缺口成立；明确拒绝则仅记相应样例；证据不足则保持未知。单个拒绝不能外推为全部工具关闭。
4. 当前 `workbench_text_only_v1` 既有要求和生产拒绝门控不变。本轮不把“目录为零”静默改成“抽样拒绝”，不凭假 provider 结果签发真实账户隔离/终止回执。
5. 若发现可行受限执行路径，交付下一最小接线/验证方案；若需要更改已确认权限定义、外部 provider/费用或更完整进程隔离，明确剩余决定后再实施。
6. 本轮不构建/安装、不操作原 App/Bridge/手机、不启动或修改真实等待任务。新候选及真人生命周期 Gate 保持后置。

## 相关证据

### W0 回收结论（2026-09-07）

- A 最终报告目录后缀 `9s5uio`：动态正控回传、合法 exec 在 excluded 下被明确拒绝；同配置 `list_agents` 实际返回合成根任务。仅打开 code-mode host/enabled 的对照用真实 cell ID 与 wait 返回 42；非法 JS 单独得到 SyntaxError。主控核对调用类型、namespace、call ID 与输出，未将解析失败计成禁用。
- B 最终报告目录后缀 `ibijBy`：中断前已有匹配文本 delta（count=1），ACK 时通知序号 12，matching interrupted 终态序号 14，观察窗口内终态后文本增量 0；normal 为 completed，合成断线为 failed，清洁进程 close 已观察。主控复核原始时序；这不证明任意真实远端或全进程树已停止。
- 当前真实缺口不是“所有目录项都只剩名字”：至少一个无副作用协作查询仍可调用；未验证 spawn、shell、真实文件或外部网络。生产 tools-disabled 条件仍未满足，不能因此把未测能力视为安全或危险已证实。
- 独立 timeout contract 明确复现 stop resolve 早于 child close；生产 adapter 未就绪时的本地 interrupted 也不能签发 provider-terminal-confirmed。后续最小修复应区分请求接受、实际 terminal、进程退出与未知状态，不改普通聊天语义；本轮未实施生产修复。
- 主控选择性新增 A/B 共六文件，运行原四文件相邻回归 + A 专项 + B timeout contract，**40/40**，两探针语法检查通过。未重跑 R2 的 Dart 122/122，不构建/安装或代替真人验收。
- 回收后主控复核：六个交付文件与 worker 冻结文本一致，11 个预存生产/R3 输入哈希全部未变；主分支/HEAD 与原五项 staged 集合不变，相关 tracked 文档 diff check 通过。
- R4 证明了样例行为与终止语义，未完成生产隔离、真实账户接线或 P6 生命周期真人 Gate。下一步保留 Codex 路线的可行性评估；若需要改变权限定义或 API/费用，仍须用户决定，不能把纯文本 API 写成已选路线。

- [A 工具行为交接](P6_R4_TOOL_BEHAVIOR_HANDOFF.md)
- [B 终止语义交接](P6_R4_STOP_SEMANTICS_HANDOFF.md)

- [R2 返修集成](P6_R2_REPAIR_PLAN.md)
- [R3 目录隔离复核](P6_R3_EXECUTION_ISOLATION_AUDIT.md)
- [P6 原始验收与交接](P6_LONG_TASK_QUEUE_HANDOFF.md)

OpenAI Docs 仅用于核对接口语义；通过与否由实际请求、事件及测试结果决定，不用文档替代本机行为证据。
