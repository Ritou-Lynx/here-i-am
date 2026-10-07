# i_core 规划助手

规划助手把“想到一句”变成可执行事项和按顺序的今日队列。结构化规划只有一个权威：i_core 的 `captures`、`plan_items`、`plan_weeks`、`plan_days`。思源、本机 `plan.json` 和 Markdown 文件不再保存权威副本。

```text
Here I Am / 受信入口
          │
          ▼
  i_core captures feed ──► capture_sync.mjs ──► codex exec “刷新今日单”
          │                                      │
          └──────── scoped planner MCP ──────────┤
                                                 ▼
                         plan_items / plan_weeks / plan_days
                                                 │
                                     可重建 today.md 投影
```

`capture_sync.mjs` 只观察 feed、合批和唤起 Codex。它不保存捕获原文，不做分诊，也不写规划记录。Codex 按 `PLANNER_AGENTS.md` 使用 scoped planner MCP 完成分诊、写入和 `capture_ack`。

## 文件

| 文件 | 作用 |
|---|---|
| `PLANNER_AGENTS.md` | Codex 的分诊、配额、队列、重排和 MCP 写入规则 |
| `capture_sync.mjs` | captures feed 监视器，默认未启用 |
| `capture_sync.test.mjs` | 假 Core 与假 Codex 进程的离线专项测试 |
| `trusted_status_bridge.mjs` | 已由受信本机 UI 完整签名的计划状态 intent 转交库；不监听 inbox、不签字 |
| `trusted_status_bridge.test.mjs` | 真实合成 DomainStore、手机 UI proof 与故障恢复测试 |
| `dot_inbox_bridge.mjs` | 严格解析调用方提供的 dot 回执并形成待批准 capture proposal；只转交另行签好的完整 dot intent |
| `dot_inbox_bridge.test.mjs` | dot proposal、独立合成签名、真实 DomainStore 与既有 phone proof 拒绝测试 |
| `DOT_PLAN_RULES.md` | dot 过单、记事、收工的交互规则 |
| `areas.md` | 首次建立 Core 周记录时使用的模板，不是权威存储 |

`today.md`、`week.md`、`study-quota.md` 可以保留为面向现有消费者的投影。先写 Core，收到接受结果后再更新投影。投影丢失或过期时从 Core 重建，不能反向覆盖 Core。

## 规划规则不变

- 深块、长块、语音块和零碎四种块型。
- 先保本周下限，再按“缺口 × 优先级权重”追目标。
- 今日单是队列，不是课表；按容量八成排，余下放“有余力再做”。
- 欠账只滚一周；连续两周未达下限交给用户决定。
- 新主线、超过 12 块的新目的、容量不足和明显冲突进入待拍板。
- 作息是硬约束，关灯时间不被任务挤占。

字段、完整创建要求、冲突处理和 capture disposition 顺序见 `PLANNER_AGENTS.md`。工具接口由 `tools/i_remote_mcp/domain_tools.mjs` 与 `planner_server.mjs` 提供。

## 监视器行为

- 每 60 秒读取一次 `/v1/core/domains/captures/changes`。
- 首次运行或 cursor 失效时读取一致性 snapshot；逐页校验 page digest、最终 collection digest 和 principal / policy / snapshot binding，禁止把不同 snapshot 的分页混用。cursor、待处理 ID、重试状态持久化在规划目录中。
- 第一条 pending capture 到达后等待 3 分钟合批。
- 同一实例的 tick 串行；CLI 另用独占锁阻止两个监视器共用同一 state。锁中登记正在运行的 Codex PID；旧监视器异常退出而子进程仍在时，新实例拒绝接管。两次成功唤起至少间隔 10 分钟。
- cursor 要求 resync 时，新 snapshot 不可见的旧 pending ID 仍保留，只有明确终态记录或经验证的 tombstone 才能移除。principal、credential generation、installation 或 view policy binding 变化时进入 `rebind_required`，不继续唤起或 ack，由部署者核对新绑定后显式重建 state。
- 23:30–07:00 按 `Asia/Shanghai` 计算，只积累 cursor 和待处理项，不唤起 Codex，不受宿主时区影响。
- Codex 通过 `shell: false` 启动，必须在配置中提供可直接 spawn 的绝对可执行文件路径；Windows `.cmd` / `.bat` shim 不被接受。生产运行当前只支持 Windows。执行超时或收到中断时用 `taskkill /T /F` 回收整个子进程树；只有 `taskkill` 明确退出 0 才解除子进程锁。非零退出、启动错误或超时会持久进入 `codex_tree_reap_unverified`，阻止本实例继续唤起和新实例接管，等待部署者人工核对进程树。
- Codex 成功退出后逐条确认当前可见 record 的 planner disposition 已对当前 text revision 终态化，或 Core 明确返回有效 410 tombstone，才 ack feed cursor。401 / 403 / 404 不视为删除。进程失败、验证失败、网络失败或 ack 失败使用 2 秒起、上限 5 分钟、带抖动的持久重试。
- JSONL 日志只记时间、数量、阶段、退出码和固定 allowlist 中的错误码，未知 Core 错误码统一写为 `unspecified_error`；不记录捕获原文、记录 ID 或令牌。

监视器只接受 loopback Core URL，令牌只从环境变量读取。配置文件、state 和日志都不得保存令牌。

## 离线验证

在仓库根目录运行：

```powershell
D:\Nodejs\node.exe --check tools/life_planner/capture_sync.mjs
D:\Nodejs\node.exe --test tools/life_planner/capture_sync.test.mjs
```

测试启动临时假 Core、真正的子进程形式假 Codex，以及内存中的真实 `DomainStore + domain_http` 合成服务。覆盖一致性 snapshot / cursor / binding / digest、3 分钟合批、disposition 复核与 feed ack、不可见记录不冒充删除、失败后跨重启重试、锁与并发、Windows `taskkill` 成功及非零退出/启动错误/超时、持久回收阻断、静默时段和日志净化。非 Windows 环境只用于协议和直接子进程的合成测试，不是生产支持声明。测试不读取真实配置、数据或凭据。

## 上线手册（本源码包不执行）

以下步骤必须由部署负责人在 W2/W3 已上线、用户已批准启用后手工执行。本仓库不会创建 Codex 任务、注册 Windows 后台任务或启动生产监视器。

1. 在 scoped planner MCP 侧准备规划凭据。规划助手按需拥有 `captures:read`、`captures:ack`，以及 `plan_items`、`plan_weeks`、`plan_days` 的 read/create/patch；只有可信用户入口需要的流程才额外给 `plan_items:status`。不授予聊天或其他生活领域。
2. 为监视器单独准备仅含 `captures:read`、`captures:ack` 的 scoped token，放入部署者选择的环境变量。不要把值写进 JSON、命令行、日志或仓库。
3. 建立规划目录并复制 `PLANNER_AGENTS.md` 为其中的 `AGENTS.md`。如保留 dot 和学习导师，只复制它们需要的投影规则；不要迁入旧 `plan.json` 充当权威。
4. 创建不含秘密的配置文件，初始保持禁用：

   ```json
   {
     "enabled": false,
     "core_url": "https://127.0.0.1:PORT/",
     "core_instance_id": "OWNER_APPROVED_CORE_ID",
     "token_env": "I_CORE_CAPTURE_MONITOR_TOKEN",
     "plan_dir": "C:\\Users\\OWNER\\life-plan",
     "codex_timeout_ms": 900000,
     "codex_kill_grace_ms": 5000,
     "codex": {
       "executable": "C:\\absolute\\path\\to\\codex.exe",
       "model": "DEPLOYMENT_APPROVED_MODEL",
       "args": ["exec", "--model", "DEPLOYMENT_APPROVED_MODEL", "--cd", "C:\\Users\\OWNER\\life-plan", "--full-auto", "刷新今日单"]
     }
   }
   ```

   `executable` 必须是绝对路径且能在 `shell: false` 下直接启动。`args` 在 `--` 终止符之前必须恰好有一个 `-m` / `--model` 选项，且值与 `model` 完全一致；重复、冲突、缺值或只在 `--` 后出现都会拒绝启动。模型及 reasoning effort 由部署时当前有效的模型路由规则决定，监视器不提供隐式默认。如当前 CLI 需要显式 effort 参数，同样由部署者按已安装版本的语法加入 `args`。

5. 先用合成 Core 或隔离副本运行 `--once`。核对：不会写捕获原文；Codex 退出成功但 capture disposition 仍 pending 时不会 ack；同一 cursor 重启后可继续；23:30–07:00 不启动进程。
6. 由 W2 的审定导入脚本迁移 WI 数据。默认 dry-run；核对 ID、字段、引用、周记录和日记录后另行授权正式导入。本规划助手不扫描或导入真实 WI 文件。
7. 只读检查 scoped planner MCP 的 `plan_list`、`week_get`、`day_get`。任一领域为 off/frozen、schema_not_ready 或 scope_forbidden 时停止，不回退到思源或本机文件权威。
8. 用户批准生产启用后，把配置中的 `enabled` 改为 `true`，先人工前台运行一天。确认合批、限频、静默、失败重试、今日 `plan_days` 和 `today.md` 投影一致。
9. 一天实跑通过并再次批准后，才按受控部署规范注册登录自启。记录任务名、配置路径、停用和删除步骤；不得由源码安装过程自动注册。

示例启动命令：

```powershell
D:\Nodejs\node.exe tools/life_planner/capture_sync.mjs --config C:\path\capture-sync.json
```

加 `--once` 只执行一轮，适合人工点验；本轮进入 retry / backoff / rebind_required / reap_required 时返回非零退出码。

## dot 状态回执的受信转交（默认未接线）

`trusted_status_bridge.mjs` 是惰性库，不读取 `inbox/`、不启动服务、不查找凭据，也不提供生产 CLI。调用方只能在受控组合层用 `createTrustedPlanCoreTransport` 注入三项操作：读取当前 capture、按 op id 查询计划操作、提交原样计划操作；回执 JSON 不能选择 transport、URL、令牌或 principal。`getOperation` 只能把已认证 Core 的明确 `op_not_found` 映射为 `not_found`；401/403、不可见、协议错误和网络未知必须抛错并保留待处置。

桥接 envelope 必须严格包含：

```text
{
  schema_version: 1,
  transfer_id: <与 intent.op_id 相同>,
  source: { capture_id, capture_revision },
  binding: { core_instance_id, principal_id, credential_generation, installation_id },
  intent: <完整 plan_items/status user_direct intent，含原样 uia1 authorization_ref>
}
```

桥只接受 `patch={status:"完成"|"放弃"}`，核当前 binding 和当前可见 capture revision，再把冻结的完整 intent 原样交给 Core。它不验证或签发 `uia1`；签名真实性、计划目标 revision、scope 和 actor 始终由 Core 校验。capture 的授权、文字、ID 或 revision 都不能转换成计划状态授权。没有完整 proof 时只生成 `pending_decisions` 的三字段建议，事项保持原状态。

每个 op 使用两个 exclusive-create 文件记录 prepared digest 与成功 receipt，跨进程不做无锁覆盖。同 op 只能绑定同一 envelope/capture revision；提交未知或进程崩溃后先查询同 op，不能换 op、改 ref 或重签。即使 intent 已过期，只要 Core 已接受，仍可按同 op 查询恢复；Core 没有成功 receipt 时保持待处置。已完成的本机 receipt 每次也要与当前 Core 查询结果核对，不单独作为权威。只有 receipt 的 `accepted_op_id` 等于转交 op 才完成；新 op 的语义 no-op 若绑定历史 receipt 会保守拒绝，不伪造新接受。capture 不可见、读取错误、revision/binding 改变都 fail closed，不推断删除。

独立测试：

```powershell
D:\Nodejs\node.exe --check tools/life_planner/trusted_status_bridge.mjs
D:\Nodejs\node.exe --test tools/life_planner/trusted_status_bridge.test.mjs
```

## dot inbox 到 capture 的严格提案边界（默认未接线）

`dot_inbox_bridge.mjs` 不扫描或读取真实 `inbox/`。调用方只能把已取得的文件名和完整文本显式传给 `createDotInboxProposal`。解析器要求文件名、标题时间和 `DOT_PLAN_RULES.md` 规定的六个章节严格一致，保留完整文本且拒绝超过 Core capture `text` 上限的输入；它不截断内容。输出始终是 `approval_required`，capture 的 `source` 固定为 Core 已声明的 `dot`，唯一 `source_ref` 是由完整回执摘要生成的 proposal id。它不会把 dot 冒充成 `phone_quick` 或 `claude_web`，也不会生成 op、授权或 Core receipt。

`DotInboxCaptureBridge` 只接受另一个受信 UI 已完整签好的 `captures/create`、`actor=user_direct` intent。intent 的 data、provenance、proposal id、当前 Core/principal/credential generation/installation binding 必须逐字段等于冻结 proposal；桥自身不签名，也不把 proposal 当批准。提交和恢复只经 `createTrustedDotCoreTransport` 注入的受信 Core transport，并使用与状态桥相同的 immutable exclusive-create ledger。未知提交结果只能按原 op 查询；没有同 op 的有效 Core receipt 就保持待处置。

当前没有 production dot signer。现有手机 `uia1` verifier 只批准 `phone_quick`，网页授权只批准既有网页来源；两者都不能给 `source=dot` 的 intent 背书。生产接线仍需 owner 明确选择 dot principal/grant/确认 UI，并由 Core 信任配置完成验签。这里没有文件 watcher、服务、CLI、真实凭据读取或自动提交。

独立测试：

```powershell
D:\Nodejs\node.exe --check tools/life_planner/dot_inbox_bridge.mjs
D:\Nodejs\node.exe --test tools/life_planner/dot_inbox_bridge.test.mjs
```

## 已知限制

陈旧锁若仍登记 `child_pid`，即使该直接进程已退出也不会自动接管，因为这不能证明后代进程退出。须按受控流程核对后再处理；不要把删除锁文件当作正常重试。

- 捕获表达“完成/放弃”时，`plan_set_status` 需要受信入口对完整计划 status intent 签发的 `authorization_ref`。普通 capture 和网页 capture 授权都不可转交；没有 owner 签发的手机 UI `uia1` proof 时，规划助手只能写 `plan_days.pending_decisions`，不能伪造授权或静默改状态。
- `today.md` 仍是 dot 的兼容投影。dot 回执若继续写本机 `inbox/`，必须由部署者提供受信 reader、确认 UI 和生产 signer，再经严格 proposal/transfer 库提交为 Core capture；本规划助手不会把本机文件直接提升为权威输入。
- 锁恢复 guard 若因监视器在恢复中再次异常退出而残留，新实例会保守拒绝启动。部署者必须先核对监视器与记录的 Codex 子进程均不在，再按受控运维步骤处理 guard；源码不自动删除无法证明安全的 guard。
- `codex_tree_reap_unverified` 同时保存在 state 和实例锁中。部署者必须用 Windows 进程工具核对记录的 Codex PID 及其后代均已退出，再按受控运维步骤归档阻断锁并显式重建监视器 state；不能只因父 PID 已消失就自动恢复。Unix/macOS 上的直接子进程终止仅供合成测试，不能作为生产进程树回收保证。
- P3 依赖 W2/W3 已提供的领域与 scoped planner MCP。P1 的上线、运行和验收不依赖本目录，也不应因 P3 未启用而改变。
