# MDA-0 活动域：保留、删除与中枢拓扑决策包（proposed）

> 状态：**proposed，等待 Lynx 真人 Gate**。这不是生产策略、schema、iCore API 或部署变更。
>
> 范围：`GOAL-20260829-mda0-activity-evidence-contract` 的 M0-P3。本文只为后续 MDA-1
> 提供可审阅的最小默认与选择 Gate；未选择、未实现或未真机验证的能力必须保持
> `unsupported` / `unknown`，不得写入 MVP 承诺。

## 1. 现状、边界与术语

- 当前 iCore 是聊天同步权威：设备 token 可读 change feed，`capabilities_json` 只是登记字段；
  不存在 activity ingress、probe scope、撤销、保留清理、活动 snapshot 或设备 presence API。
  证据：[`tools/i_core/i_core_store.mjs`](../../../../tools/i_core/i_core_store.mjs#L161-L201)、
  [`tools/i_core/i_core_server.mjs`](../../../../tools/i_core/i_core_server.mjs#L55-L158)。
- 当前 cursor 是带 HMAC 的不透明 change-feed sequence；读取永远从 cursor 后取数据，ack 仅保存
  设备已确认序号。它没有 retained watermark，也不能表达 activity resync。
  证据：[`tools/i_core/i_core_store.mjs`](../../../../tools/i_core/i_core_store.mjs#L505-L527)、
  [`tools/i_core/i_core_store.mjs`](../../../../tools/i_core/i_core_store.mjs#L1079-L1125)。
- 已交付的 BLE gateway 在主 Android app-private JSONL 中按日轮转并保留 14 天；它不是跨端
  活动事件库，硬件连续性仍待真人验证。
  证据：[`docs/development/handoffs/BLE_HEART_RATE_GATEWAY.md`](../../handoffs/BLE_HEART_RATE_GATEWAY.md#L15-L20)、
  [`docs/development/handoffs/BLE_HEART_RATE_GATEWAY.md`](../../handoffs/BLE_HEART_RATE_GATEWAY.md#L42-L49)。
- 活动域绝不进入 User-truth、Memory V3、SharedLife、聊天或 Project Memory；只有用户主动把结论
  写成记录时，才走既有显式记录入口。设计输入证据为主工作区尚未跟踪的
  `D:/memex/docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md:208-215`；它不是本基线内的权威链接。

本文件的术语：**raw event** 是已接收的最小原始活动事件；**projection** 是每设备可重建的当前
状态；**shadow inference** 是有 TTL 的候选解释；**user-confirmed record** 是用户另行确认的记录，
不从活动数据自动产生。`retained_watermark` 是仍可读取的最早服务器 sequence，`cursor` 是客户端
已消费的位置，`resync_required` 表示该 cursor 已被保留清理跨过，`snapshot` 是最小当前态恢复包，
不是遥测历史重放。

## 2. 推荐的最小默认保留与删除矩阵

Lynx 已于 2026-08-30 将 raw event、device spool、BLE raw 与最小诊断日志的 proposed 默认统一选为
**1 天**；这不是现有 iCore/App 行为，也不得因本文自动启用。现有 COROS 候选实际仍保留 JSONL
14 天，因此是待实现/迁移验证差距。`owner` 指后续 MDA-1 的唯一生命周期责任方，不是当前已实现
的数据库表或服务。

| 数据类别 | owner / 权威位置（proposed） | 推荐默认保留 | 删除触发与阻断 | 验证面 | 备份与物理到期 |
|---|---|---:|---|---|---|
| raw event | iCore activity append-only store | **1 天，已选** | probe/device 删除、用户“删除活动数据”、到期清理；撤销后拒绝新写与重放 | activity API、管理员 raw 查询、export、retained watermark | 已进加密备份的副本按公开备份到期，不承诺同步物理删除 |
| projection | iCore activity projection（可由未删 raw 或 snapshot 重建） | 仅当前态；关联来源一删除即失效 | 删除来源/probe 时立即从 read summary 隔离，异步物理删 | summary、snapshot、API、export | 若备份含 projection，随活动数据同一公开到期窗口淘汰 |
| shadow inference | 主 Android 首版本机、TTL 状态 | 最长事件 TTL；默认不做长期历史 | 输入删除、撤销、冲突/coverage 缺失或 TTL 到期即 `unknown` | 本机状态面、诊断、export（若用户请求） | 默认不备份；若未来备份，须单列到期和可恢复边界 |
| derived summary / conclusion | 后续获批的活动/健康摘要存储；当前未实现 | **长期保留至用户删除，已选** | 用户删除结论、删除所属设备/活动域或纠正结论；原始来源到期不等于结论失效，但必须保留来源已到期、生成时间和算法版本 | 摘要列表、导出、删除回执、来源/算法可解释性 | 可进入未来加密备份，但必须随用户删除和独立备份到期；不得成为不可删除的“永久记录” |
| user-confirmed record | 既有显式 User-truth / Record Organizer | 由 User-truth 生命周期决定，**不沿用活动 raw 时长** | 用户按记录产品语义删除；删活动源不静默删除已确认记录 | Memory Review / record export / 删除回执 | 遵从独立 User-truth 备份与恢复政策；来源引用可被标记已删除 |
| device spool | 信号产生设备的加密本地队列 | **1 天，已选** | 成功确认、到期、用户停用/忘记 probe 或删除活动数据；撤销后不得再发送 | 本机队列计数/诊断、删除 probe 后磁盘检查、离线恢复测试 | 默认不进入 Core 备份；设备自身备份必须排除或加密并说明到期 |
| BLE raw | 主 Android app-private JSONL | **1 天，已选；现有实现仍为 14 天** | 用户删除健康/活动原始数据、设备忘记、按日到期；停止采集不抹既有数据 | 本机文件保留可见性、设置诊断、健康导出边界 | 不跨端上传；若全量设备/应用备份包含它，遵循该备份公开到期，不能承诺即时清除 |
| diagnostic | 各端最小诊断日志 | **1 天，已选** | 到期、用户清理诊断、probe 删除；绝不记录 token 或原始 payload | 本机诊断导出、脱敏审计、删除检查 | 默认排除；若纳入备份，必须独立列期限与敏感字段审计 |
| export | 用户选择的导出文件及生成任务 | 生成后即交给用户；服务端临时件建议 ≤24h | 下载完成/到期/用户删除；导出副本不受源数据删除自动追溯 | 导出清单、下载/过期记录、人工文件位置确认 | 用户持有副本不由 Core 物理删除；服务端临时件按 ≤24h 到期 |
| backup | 加密备份库（未来 Gate 1C 体系） | 由备份政策决定，不能沿用 raw 7 天 | 逻辑删除只阻断在线读取与未来备份；历史密文等物理到期 | manifest、恢复演练、到期报告、删除后新备份检查 | Gate 1C 的目标为 72 个小时、30 个日、12 个月版本；尚未作为本活动域已实现承诺 |

### 2.1 Watermark、cursor 与 snapshot 的 proposed 语义

1. iCore activity store 每次清理后公布 `retained_watermark`（最早仍可读的 activity server
   sequence）与 `snapshot_version`。不能用 chat cursor 代替 activity cursor。
2. 客户端以不透明 activity cursor 增量拉取。若 `cursor >= retained_watermark`，服务可正常返回
   后续事件；若 `cursor < retained_watermark`，服务必须返回 `resync_required`、当前
   `retained_watermark` 和受认证保护的最小 snapshot 入口，**不得静默跳过旧事件**。
3. snapshot 只含每设备的当前 projection、来源/coverage、最近接收时间、TTL、撤销/删除世代及
   snapshot 生成时间；不含过期 raw、逐搏 BLE 或用户内容。客户端持久化 snapshot 后才推进 cursor。
4. retention 清理、Core 离线和探针沉默是三种不同状态：前者触发 `resync_required`，后两者按
   coverage / TTL 降为 `unknown`，绝不能写成 `quiet_observed`、睡眠或离线删除。
5. `retained_watermark` 是 server activity feed 的读取边界；每个 probe lineage 另有持久化的
   `retained_origin_floor`，是 ingress / event replay 的含端点隐私闭包。两者不可互换：前者只控制
   读取 cursor 的 `resync_required`，后者只控制提交坐标的 `event_retained_out`。对 floor 及以下的
   提交必须返回 terminal `event_retained_out`，不得因其看似能补历史 sequence gap 而重新接收。
6. 高于 `retained_origin_floor` 的首见较小 `origin_sequence` 可因网络乱序进入 ledger 并补 gap。
   retention 不得把“收到顺序回退”当删除或冲突；只有未补齐的真实 sequence interval 才使该来源
   projection 保持 `unknown`。缺口补齐后按逻辑 sequence 重算，而不是按 receipt 顺序覆盖。
7. 这里的 **1 天**是隐私保留上限，不是逐条 raw 的最低可读保证。Core 只使用自己的
   `received_at_ms` 判定到期；任一到期事件把 lineage floor 推到其 origin sequence 时，必须在同一
   事务中退休该 floor 及以下的全部 accepted raw replay detail，即使其中某个较低坐标接收得更晚。
   probe 的本地队列与已发出请求也必须从 materialization 起在 1 天内到期；迟到到 floor 以下的
   请求只返回无敏感细节的 terminal 错误，不恢复 raw，也不生成活动状态。

### 2.2 撤销、逻辑删除、异步清除与备份到期

| 时点 | 必须效果 | 允许异步的部分 | 禁止表述 |
|---|---|---|---|
| probe 撤销 | 立即拒绝该 token 的写、读、重放；summary 不再采纳其新事件 | 删除其 raw、projection、spool 的物理任务 | “已经从所有备份即时抹除” |
| 删除活动数据 / 忘记设备 | 在线 raw/projection/shadow 的读取面立即隔离，任务有可查询 receipt | 存储压缩、设备 spool 清理、索引/导出临时件清理 | 删除用户已确认记录或把旧 silence 当安静 |
| 备份到期 | 到期作业与可核查 manifest 证明历史密文被淘汰 | 跨副本的自然到期时间差 | 逻辑删除当成 WORM/离线副本即时物理删除 |

**推荐默认**：撤销是同步访问控制，删除是先逻辑隔离再异步物理清理，备份是独立、公开期限的
物理到期。MDA-1 需要为每个删除任务输出可审计 receipt（scope、开始、在线面隔离、各存储面
完成/待到期），但本 MDA-0 不定义或实现该 API。

## 3. 删除验证矩阵（MDA-1 自动 Gate 的最低覆盖）

`✓` 表示该数据类别必须在该验证面被明确检查；“备份到期”只能在公开期限后以 manifest/恢复
检验，不要求即时缺失。

| 操作 / 验证面 | API raw | summary / snapshot | export | 本机 spool / BLE | account / probe 权限 | 备份到期 |
|---|---:|---:|---:|---:|---:|---:|
| 撤销 probe 后使用旧 token 写入与重放 | ✓ 拒绝 | ✓ 不更新 | ✓ 不出现新项 | ✓ spool 不再发送 | ✓ token 独立失效 | — |
| 删除单 probe 的活动数据 | ✓ 不可读 | ✓ 来源移除或 `unknown` | ✓ 不含 raw/projection/shadow | ✓ 对应 spool 删除；BLE 仅用户选择时删除 | ✓ 其 token 已撤销、其他 probe 仍可用 | ✓ 新备份不含；旧件按期 |
| 删除设备全部活动数据 | ✓ 不可读 | ✓ 当前态移除 | ✓ 新导出不含 | ✓ 该设备 spool 删除；BLE 依独立选择 | ✓ 设备/所有 probe 均失效 | ✓ 新备份不含；旧件按期 |
| 删除 shadow history（若未来持久化） | ✓ 不适用或不可读 | ✓ `unknown` / 不保留历史 | ✓ 不含 | ✓ 本机候选缓存删除 | ✓ 不影响 raw token 边界 | ✓ 依其单列策略 |
| 删除 user-confirmed record | — 与活动删除分离 | ✓ 记录产品不再展示；活动源不回填 | ✓ record export 不含 | — | ✓ 不改变 probe 授权 | ✓ 由 User-truth 备份到期 |
| 24h spool / 7d raw / 14d BLE 自动到期 | ✓ raw watermark 前 cursor 得 `resync_required` | ✓ snapshot 连续且不伪称静默 | ✓ 新导出不含过期内容 | ✓ 分别检查 spool 与 BLE 文件 | — | ✓ 新备份与历史到期分别可证 |

额外的 account 验证：删除/撤销后，以已撤销 probe、另一个仍有效 probe、主 Android summary
reader（未来 scope）三种身份分别测试；前者一律 401/403，后两者只能看到其被授权的最小数据。
当前 iCore 的所有 device token 可读 `/changes`，故这项测试是 **MDA-1 前置 red gate**，不是
现有能力。设计输入证据：`D:/memex/docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md:189-206`
（尚未跟踪，不作为本基线内权威链接）。

## 4. 夜间中枢拓扑：比较与选择 Gate

共同不变项：活动 Core 未来仍须保持单一权威；Tailscale 只提供私网可达与传输边界，peer/network
presence、ping 成功或 health 均最多是 `network.present`，绝不是人机活动。当前 server 默认只监听
loopback；不能把 Windows 同机 Core 在睡眠、关机或注销后写成仍可达。证据：
[`tools/i_core/README.md`](../../../../tools/i_core/README.md#L21-L47)，以及主工作区尚未跟踪的设计输入
`D:/memex/docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md:109-120`。

| 方案 | 可用性 | 隐私与网络面 | 单权威 / 删除责任 | 失败语义 | 所需真人证据 |
|---|---|---|---|---|---|
| A. Windows 夜间保持运行（**推荐管线 MVP**） | Windows 插电、已登录、系统不睡眠、显示器可关闭时可用；当前登录计划任务只在登录后启动 | iCore loopback + Tailscale HTTPS；不扩大到 LAN/public ingress | Windows iCore 是唯一活动权威；各端 spool 自管 | 注销、睡眠、关机、任务/网络故障即 Core 不可达；远端 `unknown`，不是安静 | 连续夜间：计划任务、锁屏、Tailscale HTTPS、恢复后 cursor/snapshot、无错误推断 |
| B. 私人常在线节点（NAS/树莓派/软路由） | 可覆盖 Windows 关机时的接收；需另建并迁移/接管能力 | 私人节点仅 tailnet/受保护 TLS；需独立密钥、更新、物理保护 | 同一 Core 数据与 epoch/fencing 必须保证唯一权威，不能双活 | 节点断电/网络失败则远端 `unknown`；旧 Windows 回来不得接管写入 | 真实节点断电、重启、备份恢复、旧 Windows 返网 fencing、撤销/删除与数据保留 |
| C. 短期加密中继 | Windows 睡眠时仅暂存有界、加密、不可读活动包；恢复后转交 | 入口须 TLS、限流、体积上限、重放防护、独立撤销；中继不保存 chat/正文 | iCore 仍是唯一接受/投影权威；中继只管理短期 ciphertext spool | 中继不可用或满时客户端 `unknown`/本机 spool；不能伪称已接受 | 断网、重复包、旧 token 撤销、过期清空、Windows 恢复、无第二权威读写 |
| D. 主 Android 本机降级 | 无 Core 时主 Android 保留本机 BLE/活动解释；不接受远端实时汇总 | 不开放 Android 长期入站；不把 VPN presence 当活动 | Android 只拥有本机短期状态与队列，不成为跨端权威 | Core 不可达时所有远端设备过期 `unknown`；恢复后拉 summary，不补造历史 | 强杀/重启/Doze、Core 离线恢复、BLE 本机连续性、远端未被误判 |

### 4.1 必须由 Lynx 选择的夜间 Gate

在 MDA-1 之前，Lynx 必须明确选择：

1. **现在只做 A（推荐）**：接受 Windows 未运行即全局 Core 不可达，先完成 Windows + 主 Android
   管线；或
2. **选择 B 或 C 的设计方向**：另开 Goal 制定单权威、epoch/fencing、备份和运行维护 ADR；或
3. **选择 D 的降级体验**：不提供跨端夜间汇总，仅保留主 Android 本机解释。

未作选择时，唯一允许的结论是：Windows 同机 Core 的工作窗口内可做设计/管线验证，**夜间跨端
可用性为 unknown / unsupported**。

**已选（2026-08-30）**：方案 A。Windows 是唯一夜间活动 Core；保持插电、登录且系统不睡眠，
显示器可以关闭。Lynx 接受 Windows 睡眠、关机、注销、任务或网络故障时 Core 不可达，远端活动
立即按 coverage/TTL 降为 `unknown`，不补造、不转义为安静或睡眠。该选择不授权本 Goal 修改
Windows 电源策略、计划任务或 Tailscale 配置。

## 5. iPhone ingress：二选一、未通过即移出 MVP

前提：iPhone 没有自研 App，Shortcuts 只可在目标 iOS 上真机确认的离散 trigger 发送最小白名单
事件；不能宣称通用锁屏/解锁/持续前台活动。iPhone webhook 也绝不能直连 Windows loopback 地址。
设计输入证据：`D:/memex/docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md:265-280` 与
`:118-120`（尚未跟踪，不作为本基线内权威链接）。

| 方案 | 可用性与最小实现 | TLS / 限流 / 体积上限 / 重放 | 独立撤销与权威边界 | 失败与真人 Gate |
|---|---|---|---|---|
| 1. Tailscale iOS tailnet HTTPS（**推荐优先验证**） | iPhone 安装并启用 Tailscale；Shortcut 访问 tailnet 内 HTTPS ingress；Windows 必须处于已选的可达方案 | 使用 Tailscale HTTPS 或明确 TLS 终止；ingress 仍必须有每 probe 限流、固定小 JSON body 上限、pairing-issued event prefix + canonical origin sequence 的重放/冲突检查，并以 `event_id` 与 `(device_id, probe_id, origin_sequence)` 两个 DB 约束守住同一逻辑坐标 | 独立 iPhone write-only probe token；无 chat/read/admin；Core 才能接受、投影和删除，中继/Serve 不是权威 | iOS VPN/Shortcut 未运行、Core 不可达、错误凭据、重复请求都诚实失败；真机验证 HTTPS 可达、错误 token 拒绝、重复重放、即时撤销 |
| 2. 受保护 ingress | 仅在 iPhone 无法稳定运行 Tailscale 时考虑；公网/中继 HTTPS 只转发有界加密活动包 | TLS 1.2+、每 token/IP 限流、明确 body 上限、短时 timestamp/nonce + 同一 structured event coordinate 的双 DB 约束重放防护；拒绝超限 | 每 iPhone probe 独立撤销；入口不能借 device token 读聊天；只短期转送，不能成为第二数据/投影权威 | 入口宕机、限流、重放、token 泄露都不得生成静默或睡眠；真机验证上述失败路径、撤销和最终 Core receipt |

**必须由 Lynx 选择的 iPhone Gate**：在目标 iPhone/iOS 上先二选一并执行一次最小事件的成功与失败
验证。选 1 时需确认 Tailscale iOS 连接和 Tailnet HTTPS URL；选 2 时需确认 TLS、限流、body
上限、重放防护及独立撤销的实际配置。二者均未选择、URL 不可达或任一真机安全测试失败时，
**iPhone webhook 从 MVP 移出，状态为 `unsupported`，不得用 tailnet peer presence 替代。**

**已选（2026-08-30）**：方案 1，优先验证 Tailscale iOS tailnet HTTPS。Lynx 已下载并登录；
Windows 端第一次 online 后，11:16 曾因 Lynx 手动连接状态而离线；Lynx 重新连接后，脱敏复核为
Tailscale `Running`、1 个 iOS peer online 且 Tailscale ping 成功。现有 Serve 的 4 个 root handler
全为 loopback proxy、无 Funnel；其中 1 个本机 health 是 iCore authority，但 4 个 tailnet HTTPS
health 自检都未成功。peer/ping 只证明 `network.present`，当前仍没有获批活动入口、独立 write-only
token 或请求结果证据，
因此选择/peer online 不等于 Gate 通过，也不授权本文创建配置、凭据或 Shortcut。

## 6. 与 Gate 1A / 1C 的关系及未支持结论

- Gate 1A-0 必须先把 activity event / projection / retention 的对象归属、Core 接受边界、outbox、
  epoch/fencing 和灾难恢复关系写入权威 ADR；本草案不绕开该门槛。
  设计输入证据：`D:/memex/docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md:107`。
- Gate 1C 的备份目标包括权威根、可恢复 manifest 与独立副本，并明确不可变历史只能按保留到期；
  因此活动删除不能作“即时从所有备份物理清除”的承诺。
  证据：[`docs/companion-first/PRODUCT_ROADMAP.md`](../../../companion-first/PRODUCT_ROADMAP.md#L241-L277)。
- **当前未支持**：activity raw/projection/snapshot API、retained watermark、`resync_required`、
  write-only probe scope、probe revoke/delete、iPhone webhook、短期加密中继、Windows 外的常在线
  Core、活动数据 export/delete receipt，以及 activity-aware backup expiry reports。

## 7. 给主窗的压缩验收清单

1. 已确认 raw、device spool、BLE raw 与最小诊断均为 **1 天**；机器摘要/结论长期保留至用户删除，用户确认结论走独立 User-truth 生命周期。现有 BLE JSONL 14 天是待实现差距。
2. 已选择夜间 A，并接受 Windows 睡眠/关机时跨端 `unknown`；本选择不授权修改 Windows 配置。
3. 已选择 iPhone Tailnet HTTPS；待 Lynx 完成 Tailscale 安装/登录后，在同一 iPhone 完成成功、错误 token、
   重放、撤销四项；失败即将 webhook 标为 unsupported。
4. MDA-1 ADR/fixtures 必须落实第 2–3 节的 watermark/resync/snapshot 与删除矩阵，且在 Gate 1A-0
   前不得迁移 schema；备份物理到期另受 Gate 1C 验收。

## 8. 2026-08-30 产品边界确认

Lynx 已确认最小采集与解释边界：默认不采窗口标题、App 原名、按键、URL、屏幕、通知或聊天正文；
`network.present`、Core health、App heartbeat、无连续 coverage 的沉默、无回复和单一心率都不能证明
清醒、安静或睡眠。至此保留期限、Windows 中枢、iPhone 路线和最小采集四项产品选择完成；本确认
不授权 MDA-0 创建 schema、probe、ingress、token、Shortcut、计划任务或推断实现。
