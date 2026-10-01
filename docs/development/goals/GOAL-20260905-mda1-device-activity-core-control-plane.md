# GOAL-20260905-mda1-device-activity-core-control-plane — `device.activity.v1` Core 控制面

> 状态：完成；自动 Gate、独立终审与 Lynx 三 probe 真人 Gate 均已通过；停于 MDA-1，不取代 P4，也不自动进入 MDA-2
>
> 验收主窗 task/thread ID：`01a04839-f159-71f1-8fd3-4e3b83ef9178`
>
> Roadmap：[`MULTI_DEVICE_ACTIVITY_ROADMAP.md`](../../companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md) 的 MDA-1
>
> 隔离基线：`codex/mda1-activity-core@95c7b97649e21b49f71342cc446f03a6ae48a4db`
>
> 集成目标：本 Goal 的隔离分支；真人 Gate 已通过，仍未并回 `v3-lab`
>
> 提出并确认日期：2026-09-05

## 最终结果

在不污染 chat change feed、Card、User-truth、Memory V3、白板、BLE 生命周期或主动介入链路的前提下，建立 `device.activity.v1` 的 Core 控制面：活动探针只能以服务端强制的最小 scope 写入自身设备事件；Core 能幂等接收、保留、投影、撤销、删除并用 coverage/TTL 诚实表达 `unknown`；主 Android 只能读取带来源与新鲜度的最小 summary。完成自动 Gate、独立安全审计和三 probe 真人 Gate 后停止，不自动进入 MDA-2。

## 进入条件

- [x] MDA-0 已由 Lynx 接受以已记录红灯收口，`device.activity.v1` 事件、隐私、保留与真实设备边界已固化在 `2edaf17a`。
- [x] Gate 1A-0 已完成独立终审与 Lynx 真人 Gate，合同分支收口于 `a0bfba4b`；它只冻结 authority/recovery 合同，没有切换生产权威。
- [x] Lynx 于 2026-09-05 明确要求“隔离，继续”，批准本 Goal 作为拥有路径完全隔离的并行例外；P4 继续保留自己的候选、设备和真人 Gate。
- [x] 已从 Gate 1A-0 人审通过链建立干净 worktree，选择性纳入邮件桥提交 `86c7394f`，并以 `95c7b976` 固定 Windows checkout 的 Gate fixture 字节。
- [x] 基线自动验证通过：iCore/邮件 Node `47/47`；Gate 1A-0 Dart 组合 `27/27`；工作树 clean。
- [x] 原主工作区未跟踪的专题 Roadmap 以源 SHA-256 `DB541FAFA9E0DD0C0EE059EDD2A0FDC40FDF7F1E2F1E05EF18AEFE13B22DDFD5` 原样复制到隔离分支后再做本 Goal 状态对齐；源文件保持不动。

## 完成定义

- [x] 建立 activity probe 独立配对与服务端强制授权；`capabilities_json` 只作展示，不能自报 `activity.write`、`activity.read_summary` 或 `activity.admin`。
- [x] probe token 只可为绑定的 `device_id/probe_id` 写白名单事件；不能读 chat/change feed、Card、Memory、其他设备事件或管理面。
- [x] 建立 append-only activity events，验证双时间戳、event ID + origin sequence 双幂等键、canonical payload 不可变冲突、乱序、补传和时钟漂移。
- [x] 建立每设备投影与最小 summary，显式公开 source coverage、TTL、最后接收、权限/故障与 `unknown`；沉默、Core 停机或网络在线不能被解释为 quiet/asleep。
- [x] 实现单 probe 撤销、删除、限流、审计与已确认的 1 天 raw/最小诊断保留；实时 snapshot 只保留当前 fresh 值，长期结论不在本 Goal 生成。
- [x] 实现 retained watermark、最早可读 cursor、`resync_required` 与最小 snapshot 恢复；保留清理不能静默冒充设备离线。
- [x] 覆盖 schema migration、备份与离线恢复校验、回滚、Core 正常关闭后的原路径重启和旧 Core/旧客户端兼容；正式备份是 whole-Core 只读验证产物，不能直接激活为可写 Core；健康端点只公开 activity feature 版本，不把 schema 存在冒充端到端可用。
- [x] 主 Android 增加最小只读 summary 客户端与纯单元/协议测试；本 Goal 不增加 collector、UsageEvents 常驻采集、Android FGS、Manifest receiver 或 UI 扩张。
- [x] 自动 Gate 覆盖 Roadmap MDA-1 全部正反例，现有 iCore 与邮件桥回归保持绿；独立审计无未关闭 P0/P1。
- [x] Lynx 真人 Gate：三个测试 probe 分别配对、写入、查看状态和撤销；撤销后不能再写且此前从未能读 chat；Core 停机/恢复不丢已接受事件，也不把停机窗口投影成 quiet/asleep。
- [x] Goal、专题 Roadmap、`I_PROJECT_STATE.md`、DEVLOG 与 handoff 同步；真人 Gate 后停止并等待 Lynx 决定是否进入 MDA-2。

## 明确不做

- 不实现 Windows probe、第二 Android Tasker/旁路 APK、iPhone Shortcut activity webhook 或主 Android activity collector；这些属于 MDA-2/MDA-3。
- 不修改 BLE 心率 Service、watchdog、重连、日志、Android Manifest/FGS、手机设置或设备安装；不读取或重跑当前 COROS 真机 Gate。
- 不做睡眠/清醒推断、shadow 夜间、通知、Chat、来电、连续追打、锁机、惩罚或任何主动介入；这些属于 MDA-4/MDA-5。
- 不把活动事件或投影写入 chat change feed、SharedLife、Card、User-truth、Memory V3、Dreaming、Project Memory 或白板。
- 不改 Gate 1A-1/1A-2/1A-3 的中性 Card、Markdown Vault 或全局 Core writer 迁移；activity domain 只在自己的命名空间内落地。
- 不改 P4/P5/P6、白板 Runtime/Receipt/Undo、i Gateway、邮件 relay 的语义与运行配置；邮件只做回归。
- 不改 Tailscale Serve、Windows 计划任务、真实凭据、生产数据或真实服务；不构建/安装 APK，不 push、不发布。
- 不扩大 raw 字段、设备范围或保留期；不采 App 原名、窗口标题、按键、URL、屏幕、通知或聊天正文。

## 工作包状态

| ID / 名称 | 执行方式 | task/agent ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| M1-P0 Goal、Roadmap 与隔离基线 | 验收主窗 | 本任务 | `a0bfba4b` | `codex/mda1-activity-core` / `.worktrees/mda1-activity-core` | 已完成 | `86c7394f`, `95c7b976` | 本页 | Gate/mail 祖先、冲突与换行复核通过 | Node `47/47`; Dart `27/27` | 不需要 | 固化本 Goal 控制面 |
| M1-P1 Core 协议、认证、事件、投影、保留与恢复 | 独立 worker + 主窗集成 | `/root/mda1_core_control_plane_w1`；六轮返修与 fixed review | `1a65d3f3` | worker `codex/mda1-core-control-plane-w1@7916ebe9`；集成 `codex/mda1-activity-core@b0cb32bf` | 已完成并集成 | worker `c6ad35e7..7916ebe9`；集成 `34698bd9..b0cb32bf` | `docs/development/activity/mda1/CORE_CONTROL_PLANE_HANDOFF.md` | 最终安全/事务终审均 P0/P1=0；direct recovery 源四文件零改写，误报的临时目录残留经串行 4/4 复核撤回 | 当时集成 static `14/14`；Activity `107+1 skip`；全 Node `176+1 skip`；Dart `27/27`；CLI `202/202` | 不需要 | 已由 P1F/P1H 与最终集成 Gate 消费完成 |
| M1-P1R Core 对抗预审 | 只读独立 reviewer | `/root/mda1_core_preflight_audit` | `1a65d3f3` | 读取 P1 worktree；零写入 | 已回收 | — | 结论回填本页 | 五类 P0 已锁定并发给 P1 | 身份/feed/migration/revoke/unknown 阻断 Gate 已固定 | 不需要 | 已由 P1 返修与终审消费完成 |
| M1-P2A Android summary 落点预检 | 只读独立 reviewer | `/root/mda1_android_summary_preflight` | `efa5aecd`；不读取未冻结 P1 为契约 | 读取隔离集成树；零写入 | 已回收 | — | 结论回填本页 | 已锁定独立 reader 凭据、纯 model/client/test 与禁止复用 `CoreSyncConnection` | 未运行；仅预检 | 不需要 | 已由 P2 实现与终审消费完成 |
| M1-P1F 固定 fixture 静态合同 | 独立 worker + fixed review | `/root/mda1_fixture_contract_r3` 及后续审计 | `b0cb32bf` | 隔离返修后并入集成树 | 已完成并集成 | `515cf3c8..91d35754` | `docs/development/activity/mda1/PROTOCOL_AMENDMENT_HANDOFF.md` | replacement identity、known-field 与全部 scalar leaf 已锁；fixed review 无未关闭 P0/P1 | static `19/19` | 不需要 | 作为 runner 唯一合同 |
| M1-P1H 真实 HTTP fixture runner | 独立 worker + fixed review | `/root/mda1_http_runner_impl` 及两路审计 | 冻结 fixture | 隔离实现后并入集成树 | 已完成并集成 | `7e111618`, `91b06ee9`, `707f98c6` | `docs/development/activity/mda1/FIXTURE_HTTP_RUNNER_HANDOFF.md` | 独立协议/安全审计无 P0/P1/P2；不把 HTTP 可见结果扩大成内部调用次序 | runner `15/15` + static `19/19`；直接 CLI `26/26`, `213` requests | 不需要 | 固定真实 loopback 合同证据 |
| M1-P2 主 Android 最小只读 summary 客户端 | 独立 worker + 两路 fixed review | reader worker；`/root/mda1_android_reader_protocol_audit`、`/root/mda1_android_reader_security_audit` | `707f98c6` | 隔离实现后并入集成树 | 已完成并集成 | `ed964b21..09859afc` | `docs/development/activity/mda1/ANDROID_SUMMARY_CLIENT_HANDOFF.md` | 协议与安全终审均 P0/P1/P2=0；只读、内存态、无 DI/UI/Manifest/BLE/collector | fake-adapter `15/15`；两文件 analyze `No issues found` | 不需要 | 保持未接线，等待后续 Goal 决定 UI/collector |
| M1-P3 安全/失败语义独立终审 | 只读独立 reviewer | Core、fixture/runner、Android、human-harness 各自 fixed review；总范围 `/root/mda1_integration_scope_audit` | 各固定提交 | 零生产写入 | 已完成 | — | 各 handoff 与本页 | 当前无未关闭 P0/P1；保留删除元数据、同步 deep preflight 性能及启动失败 close 状态三项 P2 | 范围、失败语义与专项证据复核通过 | 不需要 | P2 明示，不扩大本 Goal 修复范围 |
| M1-P4 主窗集成、回归与三 probe Gate | 验收主窗 | 本任务；human harness `/root/mda1_human_gate_impl` + 两路审计 | 已审计 P1/P1F/P1H/P2 | `codex/mda1-activity-core@fbcbceb0` | 已完成；Lynx 明确通过 | `ef53d7a6`, `34698bd9..fbcbceb0` | 本页与 `SYNTHETIC_HUMAN_GATE_HANDOFF.md` | 合成 Gate 首候选因 teardown 假通过被拒；返修后 protocol/security 均签字，Lynx 接受最终报告与备份边界 | full Node `207 pass + 1 skip`；human `11/11`；Dart `27/27`；CLI `202/202`；Android `15/15` | PASS（2026-09-06） | 停止；等待 Lynx 另行决定是否启动 MDA-2 |

## 拥有路径与并行规则

- P1 唯一拥有者可修改 `tools/i_core/i_core_store.mjs`、`tools/i_core/i_core_server.mjs`、新增 `tools/i_core/activity_*`、对应 Node 测试/fixture，以及自己的 MDA-1 handoff。
- P2 只在 P1 API/fixture 冻结后启动；优先新增 Dart service/model/test，不修改 Android 平台通道、Manifest、BLE 或共享 UI。
- Goal 页、专题 Roadmap、`I_PROJECT_STATE.md` 与 DEVLOG 只由验收主窗修改；worker 不触碰。
- 任何需要共享 chat schema、Card/User-truth、全局 authority、设备、网络、真实服务或 Flutter 全局构建的发现都必须停止并提交变更请求，不得自行扩大。
- P4/白板继续在自己的 worktree、候选和真人设备窗运行；MDA-1 不构建 Windows/Android 候选，不停止其他进程，不占用设备。

## 自动 Gate

- 探针授权：错误/缺失/revoked token、跨 device/probe 冒充、scope 提升、probe 伪装 admin、write token 读取 chat/change feed 全部拒绝。
- 事件不变性：同 event ID 或同 `(probe_id, origin_sequence)` 的同 payload 幂等成功、不同 canonical payload 冲突；批量中任一非法项时全批原子失败。
- 时间与 coverage：乱序、24 小时离线补传、未来/倒退时钟、过期 TTL、coverage 缺失、权限撤销、Core 停机均给出确定且保守的状态。
- 生命周期：撤销后重放、删除后的 API/summary/export/spool、1 天清理、watermark/cursor/snapshot resync、重启、迁移、备份、回滚与旧客户端兼容全部有确定性测试。
- 隔离：activity 不出现在 chat change feed、Card/User-truth/Memory/白板数据面；健康端点的 feature version 与实际 migration 状态一致。
- 回归：现有 iCore、邮件桥、Gate 1A-0 fixture 全绿；变更范围、秘密/私人字段扫描与 diff check 通过。

## 真人 Gate

1. 主窗只启动隔离测试 Core，创建三个无真实设备信息的测试 probe；Lynx 不需要提供聊天、手机或 COROS 数据。
2. 每个 probe 分别完成配对、合法写入和最小 summary 查看；验证只能看到自己的许可面。
3. 逐个撤销；旧 token 后续写入明确失败，并验证它们从未能访问 chat/change feed。
4. 在已接受事件后停止并恢复 Core；事件仍在，停机窗口只显示 coverage gap/`unknown`，不显示 quiet/asleep。
5. 清理测试实例与测试凭据，记录结果；任何一项失败都回到同一 Goal 返修，不自动进入 MDA-2。

## 决策与变更记录

- 2026-09-05：Lynx 明确选择隔离继续；本 Goal 成为活动域的唯一实现 Goal，但不取代或干扰仍在其他拥有路径上的 P4。
- 2026-09-05：Gate 1A-1 分支未纳入基线，因为 MDA-1 的 Roadmap 前置只要求已真人通过的 Gate 1A-0；Gate 1A-1 尚无真人 Gate，不能被升级成依赖事实。
- 2026-09-05：邮件桥以单独 cherry-pick 纳入，解决当前 iCore 兼容基线；冲突只在历史状态文档，未把邮件能力混入 activity 域。
- 2026-09-05：Windows `core.autocrlf=true` 曾改变 Gate fixture 原始字节；以窄 `.gitattributes` 和提交 `95c7b976` 恢复跨 worktree 可重复性后才允许派发。
- 2026-09-05：P1 已从 Goal 控制面提交 `1a65d3f3` 派发到独立 worktree；另启只读对抗预审，预审只提供 Gate，不拥有生产代码。
- 2026-09-05：P1R 预审确认五类 P0：现有 device token 不能复用、activity 不能进入 chat feed/cursor、migration/health 必须 fail-closed、撤销/删除必须先于幂等查询且同事务隔离投影、沉默/停机/TTL 只能降为 `unknown`；另固定双键原子批、独立 watermark/snapshot 与旧库恢复 Gate。结论已发送给 P1。
- 2026-09-05：首候选 `c6ad35e7` 不予集成。主窗以确定性反例证明 stale pre-auth 可跨 revoke 写入、delete 可制造 cursor 洞、exact retry 会被 TTL/rate 错拒；返修 `59ddb517` 关闭这些反例并由主窗复跑 Node `87/87`、Dart `27/27`，但该自动绿灯不等于 P1 验收。
- 2026-09-05：主窗继续证明删除 `activity_metadata.authority_epoch` 并重启后仍会 health 假绿和签发 reader，删除 activity index 也不降级；独立审计另报跨域 secret 复用、future cursor/recovery floor、coverage 注册约束、乱序 projection 与删除后长期元数据等阻断。P1 继续隔离返修，P2 仅完成零写入落点预检。
- 2026-09-05：Core 经六轮对抗返修冻结为 `7916ebe9`。安全与事务两条 fixed-candidate 终审均 P0/P1=0；direct recovery 只检查隔离快照，在五类 SQLite 状态和成功/拒绝路径均保持 source main/sidecar byte-level 不变。并发审计曾把其他 PID 的 `activity-preflight-*` 临时目录误判为本调用泄漏；JS finally 语义与串行专项 4/4 证明候选同步清理，该 P1 已撤回，并保留测试不可并行使用同一全局临时前缀的证据边界。
- 2026-09-05：MDA-0 的“只保留 1 天”明确为隐私上限，不是逐条 raw 的最低可读保证；按 Core `received_at_ms` 推进 `retained_origin_floor` 的 bounded prefix closure 可提前退休较低坐标，且不得与 feed `retained_watermark` 混用。协议文档以 `ef53d7a6` 固定。
- 2026-09-05：Core 15 提交逐一 cherry-pick 为 `34698bd9..b0cb32bf`，与 worker 六个拥有文件内容逐字一致；集成树 static `14/14`、Activity `107+1 skip`、全 Node `176+1 skip`、Dart `27/27`、CLI `202/202` 全绿。随后从精确 `b0cb32bf` 建立 `codex/mda1-fixture-http-runner`，只进入真实 loopback HTTP fixture 验证，不接设备或生产服务。
- 2026-09-05：runner 首轮已用真实 loopback HTTP 完成 26 cases/212 requests，但 spec audit 证明旧 fixture 的 `pair_new_lineage` 没有显式 replacement identity，runner 若按 `ref` 自拼 ID 会掩盖合同缺口；同时 `case.core`、limits、payload materialization、generation/retention/fence 等 known fields 缺少静态语义消费。主窗不接受该假绿，另建 `codex/mda1-fixture-contract-r3@b0cb32bf` 先修合同；runner 保持未冻结。
- 2026-09-05：fixture 经 R3/R5/R5.2 返修以 `515cf3c8..91d35754` 集成；runner 只消费显式 replacement 和 closed expected leaf，以 `7e111618..707f98c6` 集成。最终 static `19/19`、runner `15/15`，真实 loopback CLI 为 `26/26`、`213` requests；独立终审无 P0/P1/P2。
- 2026-09-05：Android 只读 reader 经六笔提交集成为 `ed964b21..09859afc`。它只在内存中请求最小 summary，未知 source/state 保守归一为 `unknown`，无 DI/UI/Manifest/BLE/collector 接线；协议与安全终审 P0/P1/P2=0，专项 `15/15`、analyze 无问题。
- 2026-09-06：三 probe 合成 Gate 首候选 `8235c31a` 因最终 close/cleanup 失败仍可误报 pending-human 被主窗和双审拒绝；`ab629eed + d41fcbc` 关闭 teardown、临时目录 identity/junction、完整 event prefix lineage、逐页 cursor、no-sleep 语义和运行时 ledger。集成提交为 `0b1b6fd7..fbcbceb0`，双审签字可进入 Lynx 人审。
- 2026-09-06：集成树串行复跑 full Node `208 total / 207 pass / 1 existing Windows case-path skip / 0 fail`，human harness `11/11`，Android `15/15` + analyze，Gate 1A-0 Dart `27/27` 与 CLI `202/202`（1,409,842 bytes，SHA-256 `7E868CDD...D78A3`），HTTP runner `26/26` / `213` requests；全为 synthetic/loopback/fake-adapter，不是设备、睡眠推断或真人通过。
- 2026-09-06：保留三项非阻塞 P2：删除后 principal/credential/deletion receipt 的最小身份元数据没有随 1 天 raw 清理完整擦除；每次 authority preflight/health 使用同步 deep audit，未做性能 Gate；若 Core 在 listen 失败的内部 cleanup 中吞掉 close 错误，整次仍固定失败但报告 `close` 可能过于乐观。三项均不得被写成已完成能力。
- 2026-09-06：完成性复核补充备份兼容边界：正常关闭后的原路径重启可用；正式备份统一标成 whole-Core 只读验证产物，即使未启用 activity 也不能直接作为聊天 Core 启动。备份可写激活、崩溃接管与迁移恢复不属于本 Goal，留待 Gate 1A-3/1C；因此不得宣称“旧 Core 的全部恢复行为不变”。
- 2026-09-06：Lynx 在审看三 probe 合成报告、三项非阻断 P2 与 whole-Core 只读备份边界后明确回复“通过”。真人 Gate 记为 PASS；该接受只关闭 MDA-1，不授权合并 `v3-lab`、真实 collector、睡眠推断、主动介入或 MDA-2。

## 当前停点

MDA-1 已在隔离功能候选 `fbcbceb0` 上完成自动 Gate、独立终审与 Lynx 三 probe 真人 Gate，并已同步 Goal、Roadmap、`I_PROJECT_STATE.md`、DEVLOG 与 handoff。当前停止：不并回 `v3-lab`、不 push/发布、不连接真实服务或设备、不创建 MDA-2；后续只有 Lynx 的新授权才能启动下一阶段。
