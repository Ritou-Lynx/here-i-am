# MDA-0 Shadow 状态、故障矩阵与真人 Gate（proposed）

> **状态：** proposed；仅为 MDA-0 的设计证据，不是现有引擎、生产 schema、推断规则或真人通过声明。
> **Owner：** M0-P4。依赖 [`DEVICE_ACTIVITY_V1_ADR.md`](DEVICE_ACTIVITY_V1_ADR.md)、[`DEVICE_CAPABILITY_AND_HARDWARE_BASELINE.md`](DEVICE_CAPABILITY_AND_HARDWARE_BASELINE.md) 与 [`RETENTION_DELETION_AND_TOPOLOGY.md`](RETENTION_DELETION_AND_TOPOLOGY.md)。
> **范围：** 固定 shadow 解释边界、未来测试向量和由 Lynx 执行的 COROS/iPhone Gate；不接触设备、凭据或网络配置。

## 1. 共同前提与硬边界

- 所有状态均是可过期、可替换的活动域投影或 shadow 候选；不得写入 User-truth、Memory V3、SharedLife、聊天或 Project Memory。
- `signal_at_ms` 描述信号发生时间，`received_at_ms` 描述 Core 接收时间。信号可按前者解释，但新鲜度、TTL 和安全接受必须按后者及 Core 时钟判断；迟到补传不能成为“刚刚互动”。
- `probe.heartbeat`、Core health、网络/Tailscale 可达、App 前台 heartbeat、无回复、沉默和单一心率，都不是人醒着、安静、休息或睡眠的证据。
- `quiet_observed` 只表示某一**已启用且连续覆盖**的设备源在明示时间窗内没有允许的互动；它永远不是全人状态。覆盖不连续、权限撤销、探针故障、Core 不可达或 TTL 过期一律不能把沉默补成安静。
- 没有经 MDA-0 真人硬件 Gate 确认的独立第二身体/环境源时，系统**不得产出** `sleep_candidate`。单一 HR、静默、网络、App heartbeat 或任意其组合都不能绕过此门槛。
- 本文不定义分钟阈值、心率阈值或实现算法；具体 TTL/SLO 和候选组合规则只能由后续经 Gate 1A-0 批准的可测试实现固定。

## 2. 状态词典、进入/退出和冲突优先级

### 2.1 每设备状态（projection）

| 状态 | 进入条件 | 退出 / TTL | coverage 要求 | 冲突优先级 | 禁止解释 |
|---|---|---|---|---|---|
| `active` | 接受到该设备允许的、仍新鲜的 `session.unlocked`、`input.activity` 或 `app.category_active` | 其来源 TTL 到期、锁定信号、coverage 失效、撤销或故障时退出；不得凭沉默续期 | 至少该正向事件来源有效；不要求用它证明连续覆盖 | 有效 lock 覆盖旧 active；新的 interaction/unlock 覆盖旧 lock | 不等于人持续使用、在场、可联系或清醒事实 |
| `quiet_observed` | 已启用来源具有 `continuous` coverage，且在该来源声明的观察窗内未见允许互动 | 任何新 interaction/unlock 即退出；coverage 失效、TTL 到期、权限/探针失败即转 `unknown` | 必须连续、可追溯且窗口长度明确；`discrete_best_effort` / `heartbeat_only` 不足 | 正向 interaction/unlock 优先；覆盖缺口优先于沉默 | 不等于全设备静止、人的休息、睡眠或离开 |
| `locked` | 接受到该设备的有效 `session.locked` | 新 unlock/interaction、该事件 TTL 到期、coverage/权限失败时退出 | lock 事件来源须有效；网络可另列但不能补强 | 新 unlock/interaction 优先；网络永不覆盖 lock | 不等于用户不在、安静、休息或睡眠 |
| `network_only` | 只知道此设备/路径网络可达，且没有可用的正向活动、锁定或连续 coverage 证据 | 获得更具体状态、网络事实自身到期或链路失效时退出 | 无人机活动 coverage；仅 transport 可达 | 任何有效 device evidence 优先；否则保留低信息 | 不等于 active、awake、设备正在用或人在线 |
| `unknown` | coverage 缺失/过期、权限撤销、探针/关键链路故障、Core 离线导致远端不可新鲜判断、未支持或状态 TTL 到期 | 仅由新的、通过接受边界且仍新鲜的更具体证据退出 | 无效、不连续或未知 coverage 均归此处 | 覆盖/权限/TTL 失败优先于旧沉默和旧状态 | 不等于 quiet、locked、离线、睡眠或没有发生互动 |

设备 state 是每一设备/探针的解释，不能在没有声明的聚合规则时拿一个设备覆盖另一个设备。例如 Windows `locked` 与主 Android `active` 可以同时为真。

### 2.2 人的 shadow 状态（candidate）

| 状态 | 进入条件 | 退出 / TTL | coverage 要求 | 冲突优先级 | 禁止解释 |
|---|---|---|---|---|---|
| `awake_evidence` | 任一已接受且新鲜的允许 interaction/unlock；用户正向交互同等或更高优先 | 只在其明确 TTL 到期、被撤销/删除或覆盖语义使其不可用时失效；失效后是 `unknown`，不是反向候选 | 正向来源可为离散，但须可认证、未过期 | **最高：任何新正向交互立即拉回此状态**，覆盖所有 resting/sleep 候选 | 不等于持续清醒、可用、应被打扰 |
| `activity_candidate` | 未来策略识别到非互动的、允许且新鲜的活动线索；必须保留输入 ID 和策略版本 | 输入 TTL/coverage 失效即 `unknown`；新 lock/quiet 可取代设备解释但不自动证明人状态 | 由后续策略明示；低质量网络/heartbeat 不足 | 新正向交互转 `awake_evidence`；关键失效转 `unknown` | 不等于醒着、运动、在场或健康事实 |
| `resting_candidate` | 未来经批准的多源 shadow 策略判断“与休息相容”；不得仅由低 HR 或沉默进入 | 任一关键输入过期/coverage 缺失即 `unknown`；新正向交互立即转 awake | 所有被策略列为关键的来源必须新鲜、coverage 已知 | awake 优先；关键失效优先于静默 | 不等于睡眠、医学状态、不可打扰或介入许可 |
| `sleep_candidate` | 未来经批准的多源策略同时满足：关键 coverage 完整、无更高优先级 awake 证据，且有经真人硬件 Gate 确认的**独立第二身体或环境源** | 任一关键源过期、失效、撤销、coverage 缺口或新交互即退出；退出到 `unknown` 或 `awake_evidence`，不得滞留 | 第二身体/环境源及所有策略关键源都必须在其声明 TTL 内；未完成硬件 Gate 时该状态不可用 | awake 绝对优先；关键失效/冲突不确定性优先于候选 | 不等于已睡、诊断、User-truth、自动通知/Chat/来电许可 |
| `unknown` | 没有足够、完整且新鲜的候选输入，或存在未解决冲突 | 新的、完整且符合本表条件的证据才可退出 | 未知、间歇、失效或过期 coverage | 安全降级；不以统计猜测填补 | 不等于安静、未回复、睡着或拒绝互动 |

### 2.3 统一冲突处理顺序

1. 验证 credential、epoch/fencing、envelope、`received_at_ms` TTL、删除/撤销和来源能力；任一失败的输入不进入状态机。
2. 对每个来源先应用 sequence coverage、普通 coverage、权限与探针健康：未补齐的真实 sequence interval 强制该来源及其依赖候选为 `unknown`；高于 retained floor 的乱序补 gap 事件可 ledger-accept，纯 `sequence_regression` 诊断不单独强制 `unknown`。
3. gap 补齐后按逻辑 sequence 重算 replaceable projection；只有 clock、TTL、权限和普通 coverage 也有效时才恢复具体状态，不按 receipt 到达顺序覆盖。
4. 新鲜的 interaction/unlock 或用户正向交互优先于所有 HR、静默、network 和旧候选，立即得到 `awake_evidence`。
5. `sleep_candidate`/`resting_candidate` 只能在没有上述更强证据且关键覆盖完整时保留；冲突无法解释时降为 `unknown`，不以多数投票生成睡眠。
6. 设备状态并列保留来源，不将多设备静默折叠为人状态。解释面必须显示输入 receipt、coverage 窗口、TTL、冲突和 policy version。

## 3. 统一故障矩阵（未来自动 Gate / 解释面）

| 场景 | 正确结果 | 必须保留的理由 | 禁止结果 |
|---|---|---|---|
| 仅 Tailscale/网络可达 | 该端 `network_only` | transport 可达，未观察到人机互动 | `active`、`awake_evidence`、安静或睡眠 |
| probe heartbeat 过期 | 该来源及依赖候选 `unknown` | heartbeat/TTL 已过期 | 延续 `quiet_observed` 或升级睡眠 |
| Windows 锁定但仍有网络 | Windows `locked`，可并列 `network_only` | lock 新鲜；网络只说明链路 | 因网络流量判人在操作 |
| Android Usage Access 撤销 | Android activity source `unknown` | 权限失效时间、last valid receipt | 使用旧 `lastUsed` 续作实时证据 |
| iPhone Shortcut 漏触发/未配置 | iPhone `unknown` 或 `unsupported` | 离散 trigger 无负向 coverage | 判定 iPhone 没被使用或降低人状态 |
| Core 离线、主 Android BLE 正常 | 本机 BLE 仅 local degraded；远端 `unknown` | Core 不可达与 BLE 新鲜度分别展示 | 假装远端仍新鲜或由 BLE 得出 sleep |
| BLE 陈旧/断连 | body source gap；依赖候选 `unknown` | 最后样本、15 s stale/60 s reconnect 候选阈值仅作当前接收器质量语义 | 用最后 BPM 延续趋势或升睡眠 |
| COROS 真实离腕后复戴但仍处重连退避 | body source 保持 gap/`unknown`，直到新样本 receipt；展示 retryAt 与最长 300 s 体验缺口 | 离腕已证实停样本并写 stale/disconnected；复戴本身没有 contact 事件，只有新样本才能结束 gap | 因绿灯、网络或旧 live 快照提前标记恢复，或把等待期判为睡眠 |
| Android 最近任务移除触发 OEM/MARs force-stop | App/BLE 来源立即 `unknown`；保留退出原因和最后真实 receipt | START_STICKY 在 force-stop 下不运行；普通 relaunch 若未拉起专用服务也不能恢复 coverage | 沿用持久 `live` 快照、假装自动恢复或补写停机期间 coverage |
| 迟到补传 | 若安全接受，按 `signal_at_ms` 记录历史，当前新鲜度仍按 `received_at_ms`/TTL 判定 | 双时间戳、延迟与顺序 | 把旧互动显示为“刚刚”或倒灌当前 awake |
| 解锁/输入与低 HR 冲突 | `awake_evidence` | 新鲜正向交互优先；HR 只为 body 线索 | 让低 HR 覆盖交互、维持 sleep |
| 关键探针/coverage 失效 | 人候选 `unknown`；其他无关设备各自保留 | 哪个关键输入失效及其 TTL | 把所有设备沉默合成为 sleep |
| `sleep_candidate` 后出现新交互 | 立即 `awake_evidence` | 新 receipt、发生/接收时间、候选失效原因 | 等固定窗结束才更新，或继续介入 |
| 用户设为“今晚不打扰” | shadow 仍可记录；交付路径关闭 | 用户例外与 delivery suppression | 通知、Chat、来电或把它解释为睡眠 |
| 一次提醒后无回复 | 保持已证据状态或 `unknown` | 无回复不是 probe | 判为睡着、升级频率或连续追打 |

## 4. Synthetic timelines（未来测试向量，非已有引擎）

下表是后续确定性状态机的最小测试输入。时间为相对 `T0`，每个向量都应断言来源、coverage、TTL、解释理由和禁止结果；它们**不证明当前仓库已有实现**。

| ID / 输入 | 预期状态 | 理由 | 禁止结果 |
|---|---|---|---|
| ST-01：T0 只有 Tailnet reachability；无允许 activity event | device `network_only`；person `unknown` | 网络不是活动 coverage | active / awake / quiet / sleep |
| ST-02：T0 heartbeat；T+TTL+1 无新 heartbeat，且无连续 coverage | source、device 与 person `unknown` | liveness 过期不能生成负向证据 | quiet_observed / resting / sleep |
| ST-03：T0 Windows lock；T+2m 网络仍可达 | Windows `locked`（network 可附注） | lock 高于 network | active 或 awake |
| ST-04：T0 Android Usage Access revoke；T+1m 有历史 last-used | Android `unknown` | 权限撤销截断 activity coverage | 用历史 last-used 推 active/quiet |
| ST-05：T0 iPhone 某 Shortcut 未配置或预期触发未到 | iPhone `unknown`/`unsupported`；person 不变 | 离散自动化没有负向 coverage | iPhone 未用、resting、sleep |
| ST-06：T0 Core offline；主 Android BLE sample fresh；T+16s 无 BLE sample | 远端 `unknown`；body source gap；person `unknown` | Core 与 BLE 状态独立，BLE 已 stale | 远端 fresh 或 sleep |
| ST-07：T0 interaction 的 `signal_at=T-30m`，`received_at=T0`，在允许 TTL 内补传 | 历史记录可接受；当前 person 不因它变 awake | 发生时间陈旧，receipt 不重写发生事实 | “刚刚互动” / 当前 awake |
| ST-08：已形成 device `quiet_observed`；T0 新 unlock | device `active`；person `awake_evidence` | 正向交互即时优先 | 保留 quiet/resting/sleep |
| ST-09：未来硬件 Gate 未通过；T0 单 HR 低 + 30m 无互动 + network alive | person `unknown` | 缺独立第二身体/环境源且沉默不足 | sleep_candidate / resting_candidate |
| ST-10：未来硬件 Gate 已通过、完整关键 coverage 下已有 `sleep_candidate`；T0 新 touch | person 立即 `awake_evidence` | 新正向互动使旧候选失效 | 延迟更新或仍 sleep |
| ST-11：未来候选依赖 Windows continuous coverage；T0 probe error/coverage gap | person `unknown` | 关键 source 失效优先 | 用其他沉默维持 resting/sleep |
| ST-12：T0 用户打开“今晚不打扰”；后续 candidate 变化 | 状态按证据；delivery suppressed | inference 与介入分离 | 通知、Chat、来电；以无回复断言睡眠 |

## 5. 真人验证模板（由 Lynx 执行；均为待验）

自动 Gate 和真人 Gate 必须分开记录。以下清单只定义未来验收记录，不安装、构建、配置 Tailscale、创建凭据或访问设备。

逐项执行与回填使用独立记录表：[`REAL_DEVICE_GATE_RECORD.md`](REAL_DEVICE_GATE_RECORD.md)。

### 5.1 COROS：复用同一已安装候选

| 自动 Gate（后续实现前） | 真人 Gate（Lynx 在同一已安装 Here I am V3 候选上执行） | 记录字段 / 通过条件 |
|---|---|---|
| 静态确认接收器对标准 HRS 的质量语义：15 s stale、60 s reconnect 候选；不把字段缺失补写为存在 | **短时字段探测**：在 App 内显式扫描/选择（不要求系统配对），并逐项实际观察 BPM、contact/status、RR、energy（不可见即记“不支持/未见”） | 日期、App/候选版本标识、COROS 型号/固件、字段逐项 observed/absent/unknown、首样本延迟、断连次数；不以软件闭环冒充硬件通过 |
| 自动化用模拟断流验证 stale/gap/reconnect 状态，不生成 sleep | **30 分钟锁屏预检**：手机锁屏，记录连续样本、gap、stale、重连和是否需手动恢复 | 开始/结束、锁屏时间、样本/缺口计数、最大 gap、恢复动作、异常；无连续性则本项失败/未知 |
| 自动化覆盖 BLE 服务重启、Core 不可达时本机/远端降级差异 | **8 小时连续运行**：正常夜间或等长连续佩戴，观察采样、gap、App/系统状态 | 实际时段、总时长、最长 gap、是否中断、手机/手环电量前后、是否产生误导性状态；不宣称睡眠准确 |
| 自动化覆盖断连、蓝牙关闭/再开、应用进程被杀、手机重启后均可诚实报告 gap/unknown | **恢复与耐受**：依次记录断连、蓝牙关开、进程终止、手机重启后的恢复；记录电量和舒适度 | 每项操作、恢复结果/延迟、是否需人工动作、失败原因；电量百分比、佩戴不适/压迫/皮肤情况（可空） |

COROS Gate 结论栏：`待验 / 通过（仅列通过子项） / 部分通过 / 未通过`；任何未完成的字段、30 分钟或 8 小时项目都保留 `unknown`，不能解锁 `sleep_candidate`。

### 5.2 iPhone：先选择拓扑，再验证最小离散 webhook

| 自动 Gate（后续实现前） | 真人 Gate（Lynx 在目标 iPhone/iOS 上执行） | 记录字段 / 通过条件 |
|---|---|---|
| 文档审计二选一拓扑：Tailscale iOS tailnet HTTPS 或受保护 ingress；确认 write-only、独立 token、限流、body 上限、pairing-issued prefix、同一逻辑幂等坐标的双 DB 约束/replay 和 revoke 都仍是 MDA-1 red gate | **先作拓扑选择**：选择其一；若两者均不能安全可用，标为 `unsupported` 并移出 MVP | 目标 iOS 版本、选择 A/B/未选择、选择理由、可达性；不能以 peer presence 代替 URL 成功 |
| 协议向量覆盖最小 JSON、缺字段、错误 token、prefix + canonical sequence、错误 prefix/后缀、完全相同重试、撤销后重放和 retained-out | **真实 trigger**：仅选择当前 iPhone 实际可配置的少数 Shortcut（优先 Sleep Focus、充电/断充）；逐项启用、触发并记录结果 | trigger 名称/类别（不记 App 名）、是否可配置、是否实际触发、receipt/失败类别；未配置或漏触发=unknown |
| HTTPS/ingress 自动检查必须区分 TLS、认证、限流、replay 与 Core receipt，且没有成功 receipt 不算已接受 | **HTTPS 与安全失败路径**：验证选定 URL 可达；使用错误 token、重复请求、撤销 token 后重放，各自应被拒绝 | 时间、成功/拒绝类别、是否有最小 receipt、撤销时间与重放结果；不得记录 token 或 URL 秘密 |

iPhone Gate 结论栏：`待选择 / 待验 / 通过（仅列子项） / 未通过 / unsupported`。未选择拓扑、HTTPS 不可达、错误 token 未拒绝、replay 未拒绝或撤销不生效中的任一项，都使 iPhone webhook 保持 `unsupported`/`unknown`；不得以 Shortcuts 理论能力或 Tailscale 可达替代。

## 6. 明确不做

本 M0-P4 交付**不做**代码、schema、推断实现、通知、Chat、来电、安装、Tailscale 调整、计划任务、commit、push 或发布。后续真人记录已证实部分 COROS 子项，但不宣称整套 COROS 硬件 Gate 或 iPhone ingress/Shortcut Gate 已经通过。
