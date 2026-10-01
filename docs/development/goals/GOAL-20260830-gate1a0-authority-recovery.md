# GOAL-20260830-gate1a0-authority-recovery — 数据权威、单写者与恢复边界

> 状态：完成（第八次独立终审 PASS；Lynx 真人 Gate 通过）
> 验收主窗 task/thread ID：`01a050d0-c04d-7da1-b62c-53cc802ca00b`
> Roadmap：`docs/companion-first/PRODUCT_ROADMAP.md` Gate 1A-0；吸收 MDA-0 已确认决策
> 基线：`v3-lab@2edaf17a3f8bb733e6ac6f54024941267d7f32a4`
> 执行分支 / Worktree：`codex/gate1a0-authority-recovery` / `C:/Users/ExampleUser/.codex/worktrees/422e/memex`
> 提出日期：2026-08-30
> 确认日期：2026-08-30
> push / 发布：未授权

## 最终结果

在不改变生产运行权威、schema、设备或外部配置的前提下，用正式 Authority ADR、跨领域接受矩阵和只使用合成数据的确定性故障 harness，冻结“谁能写、何时算接受、旧 writer 为什么不能复活、删除与恢复如何可核查”的总契约；通过自动 Gate 与 Lynx 真人审阅后停止，不自动创建 MDA-1。

## 进入条件

- [x] Lynx 已明确确认本 Goal，并授权按项目协作协议创建、派发、等待、回收和统一验收。
- [x] 起点 `HEAD == refs/heads/v3-lab == 2edaf17a`；MDA-0 受控文档 commit 是当前精确基线。
- [x] 本 Goal 以隔离 `codex/` 分支执行，不覆盖 P4 主开发、Voice 并行 Goal或其他工作树。
- [x] `GOAL-20260826-authority-preflight` 的 A1/A2 只作为预备证据复用，不冒充正式 Authority ADR。
- [x] `docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md` 当前只存在于 `D:/memex` 的未版本化文件；本 Goal 必须在正式收口前解决其版本化归属或明确降级为非权威设计输入。
- [x] 当前 iCore worker lease/fencing 只证明同一 Core 内 workload 单执行；跨 Core epoch、灾难接管和旧 writer 返网隔离仍未实现。

## 完成定义

- [x] 冻结 Core/桌面权威根、唯一接受者、客户端 intent、投影/索引/备份角色与单写者不变量。
- [x] 形成 chat、User-truth、activity 及既有 Card/Source/Evidence/Dreaming/TaskArtifact/Capture/ImportCandidate/Link Inbox Item 的接受矩阵；没有未分类对象。
- [x] 冻结 Core instance、device installation、probe lineage、worker holder、credential generation、scope、撤销、重新配对、epoch/fencing 和旧 writer 返网合同。
- [x] 冻结 outbox、receipt、cursor、retained watermark、`resync_required`、snapshot、删除、备份到期与灾难恢复边界。
- [x] 正式选择中性 Card/User-truth 目标物理 schema、Markdown/RichText 唯一正文权威与逐项映射，形成无未分类对象的正式迁移矩阵。
- [x] 冻结跨 Markdown/Source/operation log/SQLite/FTS/Receipt 的 journal、commit/recovery、rollback 与旧→新→旧→新协议。
- [x] 严格 canonical fixtures / harness 覆盖双 Core、旧 epoch、撤销重放、跨设备冒充、幂等冲突、outbox 到期/满载、watermark resync、旧 snapshot、删除/备份到期及合成 migration；真实执行 crash/restart/replay，报告保持生产 `migrationExecuted=false`。
- [x] 自动专项、组合审计、文档链接、隐私/越权扫描、确定性报告和 `git diff --check` 全绿，并由独立终审确认没有可假绿路径。
- [x] Lynx 已核对正常写入、Core 不可用、新 Core 接管/旧 writer 返网、watermark resync 与删除/恢复五条时间线，并明确真人通过。
- [x] Goal、W0、Roadmap、`I_PROJECT_STATE.md` 与 DEVLOG 已收口；当前会话未暴露 i closeout 工具，不自动创建 MDA-1。

## 明确不做

- 不迁移或新增生产 schema，不切换默认运行权威，不双写，不读取真实用户数据库、Vault、附件或凭据。
- 不实现 activity ingress、Windows/Tasker/iPhone probe、collector、推断、通知、Chat、来电或主动介入。
- 不配置 Tailscale、Windows 计划任务、电源策略、Shortcut、设备权限、安装或服务。
- 不实施 Gate 1A-1 / 1A-2 / 1A-3、Gate 1B、Gate 1C 或真实硬盘/S3/新电脑恢复演练。
- 不把网络、Core health、heartbeat、沉默、无回复或单一心率解释为清醒、安静或睡眠。
- 不覆盖 P4、Voice、BLE 真机候选或其他工作树；不 push、不发布、不自动创建 MDA-1。

## 工作包状态

| ID / 名称 | 执行方式 | task/thread ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1A0-P0 控制面、证据差异与版本化边界 | 验收主窗 | 本任务 | `2edaf17a` | 本 Goal 分支 / Worktree | 已审计 | `eadf1c2c` | [`BASELINE_AND_CONTRACT_DELTA`](../data-authority/gate1a0/BASELINE_AND_CONTRACT_DELTA.md) | 通过 | 基线、链接、`diff --check` 通过 | 不需要 | 回收 P1–P3 |
| 1A0-P1 权威根与跨领域接受矩阵 | 子 Agent | `/root/gate1a0_p1_authority` | `2edaf17a` | 共享 Worktree；独占文档路径 | 真人通过 | `eadf1c2c` | [`P1 handoff`](../data-authority/gate1a0/handoffs/P1_AUTHORITY_ACCEPTANCE_HANDOFF.md) | 组合审计通过 | 包内链接、`diff --check` 通过 | 通过（W0） | Goal 收口 |
| 1A0-P2 身份、epoch/fencing 与旧 writer 返网 | 子 Agent | `/root/gate1a0_p2_fencing` | `2edaf17a` | 共享 Worktree；独占文档路径 | 真人通过 | `eadf1c2c` | [`P2 handoff`](../data-authority/gate1a0/handoffs/P2_EPOCH_FENCING_HANDOFF.md) | 组合审计通过 | 包内链接、`diff --check` 通过 | 通过（W0） | Goal 收口 |
| 1A0-P3 outbox/cursor/删除/恢复合同 | 子 Agent | `/root/gate1a0_p3_recovery` | `2edaf17a` | 共享 Worktree；独占文档路径 | 真人通过 | `eadf1c2c` | [`P3 handoff`](../data-authority/gate1a0/handoffs/P3_RECOVERY_RETENTION_HANDOFF.md) | 三处冲突修订后组合审计通过 | 包内链接、`diff --check` 通过 | 通过（W0） | Goal 收口 |
| 1A0-P4 合成 fixtures 与隔离 harness | 子 Agent + 主窗接管 | `/root/gate1a0_p4_harness` | `2edaf17a` | 只写 fixture/harness 拥有路径 | 已交付 | `eadf1c2c` | [`P4 handoff`](../data-authority/gate1a0/handoffs/P4_SYNTHETIC_HARNESS_HANDOFF.md) | 独立终审失败：case schema 与 crash 状态机不足 | 旧专项 6 组、组合 13 组可复现但证明力不足 | 不需要 | 由 R2 返修替换 |
| 1A0-R1/P5 物理 schema、Markdown 与跨介质协议 | 子 Agent | `/root/gate1a0_schema_markdown` | `a1b97319` | 共享 Worktree；独占新文档 | 真人通过 | `8797adf8` | [`P5 handoff`](../data-authority/gate1a0/handoffs/P5_SCHEMA_MARKDOWN_RECOVERY_HANDOFF.md) | Formal32 已收紧为唯一 32-row / 九字段 exact literal，逐行特殊语义无通用默认 | 链接、范围、whitespace 与 literal 解析通过 | 通过（W0） | Goal 收口 |
| 1A0-R2/P6 strict schema + transition harness | 子 Agent | `/root/gate1a0_state_machine` | `a1b97319` | 只写 harness/test/P4 handoff | 已集成 | `8797adf8` | [`P4/P6 handoff`](../data-authority/gate1a0/handoffs/P4_SYNTHETIC_HARNESS_HANDOFF.md) | 第八审 PASS，无 P0/P1/P2；boundary/ledger/malformed/Formal32/六域攻击均闭合 | 专项 `20/20`、组合 `27/27`、CLI 202/202 双跑逐 byte 相同 | 不需要 | Goal 收口 |
| 1A0-W0 统一审计、集成与真人 Gate | 验收主窗 | 本任务 | R1/R2 最终树 | 本 Goal 分支 / Worktree | 真人通过 | `8797adf8` | [`修复后 W0`](../data-authority/gate1a0/W0_REPAIRED_AUTOMATIC_AND_HUMAN_GATE.md) | 第八名全新独立Sol终审PASS；旧W0/旧候选继续撤回 | 自动Gate完成 | 2026-08-30 Lynx“通过” | 关闭 Goal；停止 |

固定状态枚举：`待派发 → 进行中 → 等待用户 → 已交付 → 已审计 → 已集成 → 已构建 → 真人通过`；本 Goal 不构建产品候选，文档/harness 组合验证完成后直接进入真人审阅，但不得把自动 Gate 当真人通过。

## 依赖与集成顺序

1. P0 冻结 Goal、精确基线、MDA-0/Authority Preflight 输入与未版本化 Roadmap 风险。
2. P1 先冻结权威根、角色和跨领域接受矩阵；P2/P3 可并行起草，但不得与 P1 争夺同一文件或自行改变词典。
3. W0 回收并交叉审计 P1–P3；矛盾返回原工作包，不在主窗静默造第二套合同。
4. P4 只从已审计词典扩展合成 fixtures/harness；不得连接生产路径或宣称迁移成功。
5. W0 运行组合自动 Gate、审计 diff 与禁止范围，形成唯一真人审阅包。
6. Lynx 真人确认后完成本 Goal；只允许另行提出 MDA-1，不自动创建或执行。

## 自动 Gate

- 每个对象/领域恰有一个 authority、accepted writer、pre-accept state、receipt/change 规则、delete owner 与 recovery source。
- 撤销、credential generation、epoch/fencing 在幂等与资源读取前生效；旧 writer、旧 token、旧 snapshot 都不能改变新 epoch。
- cursor 落后 retained watermark 必须返回 `resync_required`；客户端原子持久化受认证 snapshot 后才推进 cursor。
- 崩溃注入后只能收敛到完整旧接受态或完整新接受态；无 ghost accepted、重复 event、无 receipt 写入或旧 fencing 写入。
- chat、activity 与 User-truth 互不越权；普通聊天和 activity 不能自动生成 User-truth。
- harness 仅使用合成 fixture 与系统临时目录，连续运行字节级确定，`migrationExecuted=false` 且 `migrationSimulated=true`。
- 变更范围只允许本 Goal、Gate 1A-0 文档、合成 fixture/harness、测试及必要状态文档；生产 schema、代码、依赖、生成文件和外部配置为零。

## 真人 Gate

- 正常写入：Desktop/Android/probe 提交后，只有 Windows Core 接受并分配权威 receipt。
- Core 不可用：远端保持 `pending / expired / unknown`，不产生第二权威，也不补造安静/睡眠。
- 灾难接管：新 Core 恢复并提升 epoch；旧凭据失效；旧 writer 返网及积压 intent 被拒绝或进入 `needs_resolution`。
- resync：cursor 被保留清理跨过时显式 snapshot 恢复，不静默漏数据。
- 删除：在线面立即隔离，异步清理可追踪，新备份不再含已删对象，旧不可变历史等待公开到期。
- MDA-0 决策完整保留：Windows 唯一夜间 Core；Windows 不可用时远端 `unknown`；iPhone Tailscale 方向但 ingress `unsupported`；raw/最小诊断 1 天；实时心率仅 current fresh snapshot；安全摘要/结论长期保留至删除；既定最小采集和禁止推断边界不变。

## 决策与变更请求

- 2026-08-30：Lynx 确认本 Goal，并明确授权按协议执行与派发；没有授权 push、发布、生产迁移或外部配置。
- 2026-08-30：当前执行分支为 `codex/gate1a0-authority-recovery`；集成目标仍是 `v3-lab`。
- 2026-08-30：Gate 1A-0 通过只允许另行提出 MDA-1；MDA-1 与 1A-3 的实现顺序必须在新提案中明确，不得在本 Goal 偷渡。

## 集成记录

- 2026-08-30：起点核验通过：验收窗此前 clean detached，`HEAD == refs/heads/v3-lab == 2edaf17a`；MDA-0 commit 文件范围为 Goal、6 份活动文档与 5 个 fixture。
- 2026-08-30：创建隔离执行分支；尚未修改生产代码、schema、设备或外部运行环境。
- 2026-08-30：按互不重叠的文档拥有路径派发 P1、P2、P3；三者禁止提交、push、修改生产路径或继续派生 Agent，主窗保留统一审计与集成权。
- 2026-08-30：P0 差异清单已冻结当前事实、目标合同、对象覆盖、MDA-0 未版本化 Roadmap 风险和后续 Gate 边界；相对链接与 `git diff --check` 通过。
- 2026-08-30：W0 初审 P1/P2 通过；P3 因 `needs_resolution` receipt、旧 epoch 幂等顺序及 workload fence 泛化三处冲突退回原工作包修订，未静默改写。
- 2026-08-30：P3 原工作包完成修订；W0 复核旧 identity/epoch 先于幂等、acceptance receipt/refusal result 分离与 workload fence 作用域后，P1–P3 组合审计通过。
- 2026-08-30：P4 已按审计后的统一词典派发；只允许纯合成 fixture、系统临时输出和 `migrationExecuted=false` 的确定性报告。
- 2026-08-30：W0 拒收 P4 首版 `expected` 回显假绿；原工作包二次尝试仍依赖 fallback 后主动标记未完成，主窗按路由接管并完成显式输入规则引擎与负例测试。
- 2026-08-30：自动 Gate 全绿：新专项 6 组、旧 preflight + 新 harness 组合 13 组、CLI 两次 47/47 且 SHA-256 相同；范围、链接、11 类矩阵、47 条显式输入、隐私与 diff 审计通过。Goal 停在真人 Gate，不创建 MDA-1。
- 2026-08-30：完整 ADR/harness/审阅包已固定为本地候选提交 `eadf1c2c`；Git hook 项目状态检查通过。该提交不是真人通过，也未 push。
- 2026-08-30：独立终审否决 `a1b97319`：正式 1A-0 缺物理 schema、Markdown/RichText、跨介质 commit/recovery 与 migration harness；P4 可由 ID/operation/input 错配和结论式 crash 布尔假绿；P0 Gate 路由冲突且 Authority ADR 状态提前 accepted。旧真人包撤回，Goal 返回同一停止点返修。
- 2026-08-30：R1/P5 冻结中性 Card/User-truth 目标 schema、Markdown 唯一正文权威、32 行迁移矩阵和 SQLite cross-medium journal；主窗完成 Roadmap 对照、链接与无兜底分类审计。
- 2026-08-30：R2/P6 首轮已建立 59-case canonical registry、strict schema 与 A–F restart/replay；主窗发现它未完整消费 P5 明列的 RichText/intake/逐文件 crash/digest/count corpus，且 Set 无法证明无重复副作用，已退回同一 worker 返修，59/59 不计当前 Gate。
- 2026-08-30：R2/P6 最终扩为 148-case exact registry（52 authority/recovery + 96 migration），转换结果仅从 raw object state 推导；补齐 RichText 全 block/mark/asset/IME/history/Anchor、intake stable identity/dedupe、28 个 migration crash phase 与 append/count ledger。主窗独立复跑 format/analyze、专项 `16/16`、组合 `23/23`；CLI 双跑均为 332,197 bytes、SHA-256 `43AAD001...6443D6`、148/148、`migrationSimulated=true`、`migrationExecuted=false`。当前只待全新独立终审，不提前进入真人 Gate。
- 2026-08-30：全新独立 Sol 终审再次否决 148-case 候选：migration expected 仍与 actual 共用实现形成 self-oracle；顶层 invariant hardcode 与逐案 violation 矛盾；RichText raw HTML/嵌套 range、Formal32、intake digest conflict、P2/P5 顺序、crash/failure、跨域 roundtrip 与 fixture digest 均未闭合。自动 `16/16`、`23/23` 和确定性 hash 保留为可复现历史，但不计当前 Gate；P5/P6 已按不重叠路径进入第二轮返修，仍不生成真人包。
- 2026-08-30：第二次终审返修最终形成 202-case sibling literal oracle：202/202 `input` 与 `expected` 分离，manifest/report绑定全案 input digest与scenario/fixture digest，simulator不读取expected，comparator事后生成非空 `invariantResults`。P5/P6统一52个expanded crash点、25个failure token、三类intake blocked零目标、Formal32全字段、可逆raw bytes/exact mark range与六域10字段roundtrip；主窗复跑专项 `19/19`、组合 `26/26`，CLI双跑1,129,604 bytes、SHA-256 `ACEDDC2E...3EF6FA`、202/202。当前只待第三名全新独立终审，仍不生成真人包。
- 2026-08-30：第三名独立 Sol 终审否决 202-case 候选：raw HTML 实际仍以 String/canonical JSON 冒充原始字节；52 个 crash 点折叠到少量粗 checkpoint 且 failure 由结论标签驱动；六域 roundtrip 仍以深拷贝穿行、`userTruthSet` 写集为空；大多数非 migration invariant 未从 actual 状态求值；P5 样例仍残留 self-oracle 字段。自动绿与确定性 hash 只保留为失败历史，P5/P6 已进入第三次返修，新 W0、人审包和候选提交继续禁止生成。
- 2026-08-30：第三次返修已回收：raw HTML 使用非 UTF-8 base64 bytes、长度、raw SHA 与 bytewise恢复；52 点按真实 ordinal 暴露 durable state，25 failure由严格 raw facts推导；六域使用不同物理 envelope完成 old→new→legacy-readable rollback→new，且每域新写非空；非 migration按 operation从 actual evidence求不变量。主窗 format/analyze通过，专项 `20/20`、组合 `27/27`；CLI双跑均202/202、1,219,163 bytes、SHA-256 `DD0E3CB4...87E5C25`。22条变更均在允许范围，链接、隐私哨兵和 `diff --check` 通过；尚待第四次独立终审，不生成真人包或候选提交。
- 2026-08-30：第四名独立 Sol 终审仍判 FAIL：Formal32有8个objectType与矩阵不一致、八字段全String且actual/expected同源；52点由crash标签直接填状态且恢复仍只看粗phase；六域未把baseline→first语义等价纳入domain invariant；snapshot unchanged没有与输入原cursor/state比较。另确认Roadmap/状态页仍写Gate 1A-0尚未创建，Goal真人区仍引用撤回W0/旧候选。真字节链路与raw-fact failure本轮核证通过。控制面P2已修，P6进入第四次返修；仍不生成新人审包或候选提交。
- 2026-08-30：第四次终审返修已回收：Formal32改为精确32类、结构化字段与独立 frozen row digest；52点由ordered action machine产生并在恢复前校验ordinal/hash；六域逐域判baseline→first语义等价，derivedIndex从accepted state重建；snapshot unchanged比较原cursor/state，20个operation均有actual-state负控。主窗format/analyze、专项`20/20`、组合`27/27`全绿；CLI双跑202/202、1,323,488 bytes、SHA-256 `0174E508...45822`且逐byte相同。当前交给第五名全新独立Sol终审，PASS前仍不生成新人包或候选提交。
- 2026-08-30：第五名独立Sol终审判FAIL：Formal32虽有frozen row digest，但通用digest fallback/preserve-new-write/tombstone包装不符合32行各自语义，且非blocked `blockedReason=null` 与矩阵空字符串合同冲突；crash validator未双向绑定actionTrace与granular state，可成对清空ordinal/hash后假绿；六域只检查通用`refs`而漏掉`cardId/sourceVersionId/parentRevisionId`，derivedIndex baseline还提前写入未来operation ID。Roadmap顶部元数据已同步；P6在同一Goal返修，仍禁止新W0、候选提交和真人Gate。
- 2026-08-30：第五审返修已由主窗复核：Formal32 文档 literal 与报告 32 行逐项相同，九个顶层 key、七字段 identity entry、逐行 rollback/delete/index 语义和 frozen digest 均受检；Crash durable state 由 `actionTrace` 前缀从初始 ledger 完整重放后深比较，成对 publish/fsync 篡改转为 `needs_resolution`；六域读取 `cardId/sourceVersionId/parentRevisionId` 等真实引用，derivedIndex 仅在 post-cutover 后出现新 operation。主窗 format/analyze、专项`20/20`、组合`27/27`通过；CLI双跑均202/202、1,409,842 bytes、SHA-256 `7E868CDD...D78A3`且逐byte相同。23条变更全在允许范围，17份Markdown相对链接0断链，`diff --check`通过。当前等待第六名全新独立Sol终审；PASS前仍不生成新W0或候选提交。
- 2026-08-30：第六名独立Sol终审判FAIL：第五审四项与旧假绿复查均已闭合，但Crash52 validator只证明durable state内嵌`actionTrace/initialLedgers`彼此自洽，未绑定scenario原始`crashPhase/initialLedgers`；把另一合法boundary的整套state替入，或同步伪造embedded baseline与current ledgers，仍可能返回old/new。自动`20/20`、`27/27`、双跑202/202与`7E868CDD...D78A3`只保留为失败历史。P6已退回同一worker增加原始事实绑定与整套替换负控；第七审PASS前仍禁止新W0、候选提交和真人Gate。
- 2026-08-30：第六审返修已由主窗复核：正常`_runMigrationCommit`与diagnostic恢复都把声明的crashPoint和input原始initial ledgers传入validator；validator要求trace精确对应boundary、embedded baseline精确等于input，并从该baseline重放完整state。52个canonical durable state正常收敛，52个不同trace的完整合法boundary替换及同步ghost ledger bundle均转`needs_resolution`。主窗format/analyze、专项`20/20`、组合`27/27`通过；CLI双跑202/202、1,409,842 bytes、`7E868CDD...D78A3`逐byte相同，Formal32 doc-report仍精确相等，范围23。合法输出未变，因此fixture/pin未改。当前等待第七名全新独立Sol终审；PASS前仍不生成新W0或候选提交。
- 2026-08-30：第七名独立Sol终审判FAIL(P2)：第六审boundary/initial-ledger绑定、Formal32、六域与旧假绿复查均通过，但malformed durable state虽被validator判invalid，`needs_resolution`分支仍把缺失/错类型/错误元素的receipt/change/projection ledger强转为List/Map并抛TypeError。自动`20/20`、`27/27`、双跑202/202与`7E868CDD...D78A3`只保留为失败历史。P6已退回同一worker补ledger结构前置校验、安全错误统计及缺字段/错类型/错误元素负控；第八审PASS前仍禁止新W0、候选提交和真人Gate。
- 2026-08-30：第七审返修已由主窗复核：ledger合同冻结为exact`{key,digest}`非空有界String，initial map精确receipt/change/projection；embedded/current ledger在任何复制/重放前先做纯结构校验，invalid分支用安全计数返回`needs_resolution`，不再强转。缺字段、String、`List<String>`、缺key/digest、extra、空值、坏embedded baseline均不抛TypeError；坏input明确`inputRejected`。主窗format/analyze、组合`27/27`通过；CLI双跑202/202、1,409,842 bytes、`7E868CDD...D78A3`逐byte相同，范围23、diff全绿。合法输出未变，因此fixture/pin未改。当前等待第八名全新独立Sol终审；PASS前仍不生成新W0或候选提交。
- 2026-08-30：第八名全新独立Sol终审PASS，未发现P0/P1/P2；对所有JSON可表达malformed durable字段、错误boundary、ghost ledger、Formal32、六域及旧假绿路径攻击均未复现崩溃或假绿。独立format、专项`20/20`、组合`27/27`通过；独立analyze在Dart perf清理阶段遇环境故障，主窗analyze明确零问题。修复后W0已生成，当前只待本地候选提交与Lynx真人核对A–E时间线；仍未push，不创建MDA-1。
- 2026-08-30：合同、fixture、harness、测试与修复后W0已固定为本地候选`8797adf84feca2610a9f348fcd040f7299d6ea4a`；pre-commit项目状态检查通过。后续仅追加metadata-only记录，不改变候选合同。当前进入Lynx真人Gate，未push、未发布、不创建MDA-1。
- 2026-08-30：Lynx 对修复后 W0 明确回复“通过”；A–E 五条时间线、Formal32、单写者、resync、删除/恢复与 MDA-0 保留边界获真人接受。主窗只记录通过并关闭 Goal；未 push、未发布、未创建 MDA-1。

## 真人验收

- 候选 commit / 新人审包：合同、fixture、harness、测试与修复后 [`W0_REPAIRED_AUTOMATIC_AND_HUMAN_GATE.md`](../data-authority/gate1a0/W0_REPAIRED_AUTOMATIC_AND_HUMAN_GATE.md) 已固定为本地候选`8797adf84feca2610a9f348fcd040f7299d6ea4a`。`eadf1c2c`、`a1b97319` 与旧 `W0_AUTOMATIC_AND_HUMAN_GATE.md` 均为撤回历史。本 Goal无生产运行改动，也不构建产品二进制候选。
- 场景：正常接受、Core 不可用、灾难接管/旧 writer 返网、watermark resync、删除/备份到期。
- 结果：第八次独立终审 PASS；2026-08-30 Lynx 明确回复“通过”，Gate 1A-0 真人 Gate `PASS`。
- 未完事项：本 Goal 无未完事项；push、发布均未授权；MDA-1 与 Gate 1A-1 均未创建。

## Goal 结论

- 完成时间：2026-08-30。
- 最终合同候选：`8797adf84feca2610a9f348fcd040f7299d6ea4a`；真人审阅候选元数据：`48a1ae1faf8fa5b76e4bf32324ef32e0a643a9ed`；收口记录由本次 metadata-only commit 固定。
- push：未授权。
- 下一 Goal 候选：只允许另行提出 MDA-1 或按 Product Roadmap 继续 1A-1；本次均未创建。
