# GOAL-20260829-mda0-activity-evidence-contract — Activity Evidence Contract & Real-device Baseline

> 状态：验收完成，由本次受控文档 commit 固化（保留已记录红灯；不取代当前主开发 Goal）
> 验收主窗 task/thread ID：`01a04c62-d569-7332-b0c7-e8aa5b6b04cc`
> 来源 task/thread ID：`01a04839-f159-71f1-8fd3-4e3b83ef9178`
> Roadmap：`docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md` 的 MDA-0
> 基线：`v3-lab@7fa6cbb9e44fe1771aae44c579d5e3a2f9e393f1`
> 验收窗：`C:/Users/ExampleUser/.codex/worktrees/1765/memex`，detached at baseline；集成目标仍为 `v3-lab`
> 提出日期：2026-08-29
> 确认日期：2026-08-29
> 收口确认日期：2026-08-30

## 最终结果

在任何生产 schema、activity ingress、探针、推断或主动介入实现开始前，形成一套可由用户审阅、可用 fixtures 与故障矩阵验证、并能在真实 COROS 与 iPhone 上逐项执行的 MDA-0 证据契约；所有未知、权限缺失、链路沉默和不连续 coverage 都诚实降级，且本 Goal 明确停在需要 Lynx 操作的真人 Gate。

## 进入条件

- 用户已明确批准 MDA-0 作为隔离的只读/设计 Goal，并授权本验收窗按项目协作协议创建、拆包、派发、等待、回收和统一验收。
- 当前 P4 主开发 Goal、Voice 并行 Goal 与正式 Gate 1A-0 顺序保持不变；MDA-0 不取消、不取代、不解锁它们。
- 当前验收窗为 detached worktree，但精确 HEAD 与 `v3-lab` 当前基线一致；`v3-lab` 主工作区已有大量未提交用户改动，因此本窗不得切入或覆盖主工作区。
- 专题 Roadmap 当前只存在于 `D:/memex/docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md`，且在主工作区为未跟踪文件，不属于本 Goal 的 Git 基线。它可作为用户指定的设计输入，但在任何提交前必须先解决其版本化与审计归属。
- 进入本 Goal 时，Android 标准 BLE HRS 软件闭环已有交付证据，而 COROS 实物字段与恢复能力尚未真人验证；后续已完成的真机子项与仍待项以“当前结果”为准。

## 完成定义

- [x] 固定 Windows、主 Android、第二 Android、iPhone 与 COROS 的真实支持范围、证据来源、权限、coverage 模式、关闭方式、故障与未知项；不把规划写成已支持。
- [x] 形成 `device.activity.v1` proposed ADR、事件/状态/权限词典与 threat model，明确 Gate 1A 的单写者、epoch、fencing 和 Core 接受边界是后续实现前置条件。
- [x] 形成不含私人正文的正反 fixtures，覆盖 canonical payload、双幂等键、时钟偏差、TTL、coverage、非法 kind/字段、超大 payload、重放与跨设备冒充。
- [x] 写明原始活动事件、BLE 原始日志、设备投影、shadow 推断、用户确认记录、spool、导出与备份的 proposed 保留/删除语义；具体期限仍等待真人确认。
- [x] 把 Windows iCore 夜间拓扑与 iPhone ingress 方案写成显式选择；未选择或未真机通过时相应能力保持 `unsupported` / `unknown`，不进入 MVP 承诺。
- [x] 固定 shadow 状态语义、反例、故障矩阵与解释规则；没有经 MDA-0 硬件 Gate 确认的第二身体/环境源时不得产出 `sleep_candidate`。
- [x] 产出 COROS 与 iPhone 可逐项执行的真人验证清单和记录模板；自动 Gate 与真人 Gate 分栏，未执行项保持待验。
- [x] 主窗逐份审计所有 worker 交付与关键断言，运行文档/fixture 自动 Gate，记录矛盾、风险、未决选择和返修结果。
- [x] Goal 状态页能独立解释当前成果、未完事项、真人停点与后续 MDA-1 进入红灯；未修改生产代码、schema、设备或外部运行环境。

## 明确不做

- 不迁移或新增生产 schema；不实现 activity ingress、probe、collector、outbox、投影、推断、通知、Chat、来电或自动化配置。
- 不修改生产代码、共享运行契约、依赖、生成文件、Tailscale Serve、Windows 计划任务或设备安装状态。
- 不把网络在线、Tailscale peer、Core health、App 前台 heartbeat、无连续 coverage 的沉默、无回复或单一心率判为清醒、安静、睡眠或医学事实。
- 不恢复历史高频催睡、无回复判睡、连续追打、默认来电、锁机、罚款或羞耻/惩罚机制。
- 不让 Windows、第二 Android 或 iPhone 安装完整 Here I am；完整产品只在主 Android，其他端只规划最小探针/系统自动化。
- 不把逐搏心率、活动事件、shadow 状态或真人标注写入 User-truth、Memory V3、SharedLife、聊天或 Project Memory。
- 不 commit、不 push、不发布；文档草案不自动成为已批准的共享契约。

## 工作包状态

| ID / 名称 | 执行方式 | task/thread ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| M0-P0 Goal 控制面与基线冻结 | 验收主窗 | 本任务 | `7fa6cbb9` | detached 验收窗 / 集成目标 `v3-lab` | 已审计 | — | 本页 | 通过 | 基线、分支、脏工作区与输入文档核验通过 | 不需要 | 等待真人 Gate |
| M0-P1 四端信号、官方能力与 COROS 真机基线 | 子 Agent | `/root/mda0_device_baseline` | `7fa6cbb9` | 共享只读基线；只写 `docs/development/activity/mda0/DEVICE_CAPABILITY_AND_HARDWARE_BASELINE.md` | 已审计 | — | 同拥有路径 | 通过；主窗校正 coverage/event 命名与仓库行号 | 官方链接、本地证据、支持/未知分栏通过 | COROS 锁屏耐久/恢复通过但严格连续性失败；MARs/relaunch、Doze watchdog 与电量归因仍缺 | 心率工程窗修复 watchdog、做电量 A/B 后重跑新候选 |
| M0-P2 `device.activity.v1`、权限与 threat model | 子 Agent | `/root/mda0_event_security` | `7fa6cbb9` | 共享只读基线；只写 ADR 与 fixtures 目录 | 已审计 | — | `docs/development/activity/mda0/DEVICE_ACTIVITY_V1_ADR.md` 与 `fixtures/` | 通过；主窗补齐 chat-read/admin 越权反例并统一 envelope | 5 文件、19 案例、事件/coverage/权限词典通过 | proposed 契约审阅待验 | Lynx 审阅后仍须 Gate 1A 权威 ADR |
| M0-P3 保留/删除与中枢、iPhone ingress 拓扑 | 子 Agent | `/root/mda0_retention_topology` | `7fa6cbb9` | 共享只读基线；只写 `docs/development/activity/mda0/RETENTION_DELETION_AND_TOPOLOGY.md` | 已审计 | — | 同拥有路径 | 通过；主窗校正本地链接、未跟踪 Roadmap 边界与 event 命名 | 删除面、watermark/resync、四方案矩阵通过 | 产品选择完成：Windows A、iPhone Tailscale 1、所有 raw/诊断 1 天、长期可删结论与最小采集边界已确认；peer + ping 通过，tailnet HTTPS health 未通过 | 保留 ingress red gate；主窗审计 MDA-0 退出条件 |
| M0-P4 Shadow 语义、故障矩阵与真人测试模板 | 子 Agent（第二波） | `/root/mda0_shadow_gate` | `7fa6cbb9` | 共享只读基线；只写 `docs/development/activity/mda0/SHADOW_STATE_AND_REAL_DEVICE_GATE.md` | 已审计 | — | 同拥有路径 | 通过；主窗统一 event/coverage 命名和 Android 扫描措辞 | 13 类故障、12 条 synthetic timeline 与禁止推断通过 | COROS 部分通过；iPhone peer + ping 通过但 activity ingress 当前 unsupported | 保留红灯，等待 MDA-0 收口确认 |
| M0-P5 主窗交叉审计与自动 Gate | 验收主窗 | 本任务 | `7fa6cbb9` | detached 验收窗 | 已审计 | — | Goal 与上述文档 | 通过 | JSON、词典、隐私字段、本地链接/行号、范围检查全部通过 | 不需要 | 保持活动，等待真人 Gate |

真人执行统一回填：`docs/development/activity/mda0/REAL_DEVICE_GATE_RECORD.md`。该表不得记录 URL、token、设备序列号或私人正文。

## 依赖与集成顺序

1. P0 冻结本 Goal 的硬边界、基线、输入事实与未提交 Roadmap 风险。
2. P1、P2、P3 以完全不重叠的拥有路径并行；worker 不得修改 Goal 页、Roadmap、产品总路线、项目状态或生产代码。
3. P4 在首波 worker 空出并发位后执行，复用 P1–P3 的证据但不得替它们改写契约。
4. P5 由主窗检查官方能力陈述与仓库事实、ADR/词典/fixtures/故障矩阵一致性、删除覆盖面、Gate 1A 红灯和所有禁止推断。
5. 自动 Gate 通过后只生成一个压缩的 COROS+iPhone 人工清单；真实操作由 Lynx 执行，结果回填前 Goal 保持活动/等待用户。
6. 即使真人 Gate 通过，本 Goal 也只证明设计与基线；MDA-1 仍需 Gate 1A-0 对 activity event/projection/retention、Core 接受边界、outbox、epoch/fencing 与灾难恢复关系给出权威 ADR，并由用户另行确认 Goal。

## 自动 Gate

- Markdown 相对链接与必需章节可解析；草案状态、owner、未知项和真人 Gate 不得缺失。
- JSON fixtures 全部可解析，`schema_version`、事件 ID、设备/探针、origin sequence、双时间戳责任、confidence、TTL、source、payload 与 expected outcome 可追溯。
- 正例/反例覆盖非法 kind、未知字段策略、缺字段、未来/倒退时钟、TTL 过期、无 coverage 沉默、重复 ID 同/异 payload、跨 device 冒充、错误 scope、撤销后重放和超大 payload。
- 词典、fixtures、故障矩阵和真人模板对同一状态/事件使用一致名称；`network_only`、`unknown`、`quiet_observed`、`awake_evidence`、`resting_candidate`、`sleep_candidate` 的进入/禁止解释一致。
- 仓库 diff 只能触及本 Goal 页与 `docs/development/activity/mda0/**`；不得出现生产 schema、代码、依赖、设备配置或生成文件变更。

## 真人 Gate

### Lynx 操作前置

- COROS：使用已经安装的同一 Here I am V3 候选执行短时字段探测、锁屏预检、长时连续性、断连/蓝牙重开/进程/重启恢复、电量与舒适度记录；不重建、不换包、不把自动测试写成实物通过。
- iPhone：先从文档二选一确定 Tailscale iOS tailnet HTTPS 或受保护 ingress；随后在真实 iPhone 上逐项验证当前 iOS 实际可配置的 trigger、HTTPS 可达、错误凭据、重复重放和 token 撤销。没有可用且安全的 ingress 时，webhook 结论必须是未支持。
- 产品审阅：逐端确认“能知道/不能知道什么”，确认默认不采窗口标题、App 原名、按键、屏幕/通知/聊天正文，并确认保留/删除默认与中枢选择。

### 当前结果

- 自动 Gate：通过。5 个 JSON 文件可解析，19 个 fixture case 唯一且齐全；16 个事件、5 种 coverage、权限与 outcome 词典一致；真人记录追加后 29 个本地链接有效；未发现私人正文/凭据字段或越界工作区改动。
- 多设备真人基线：进行中。主 Android 已完成锁定/解锁、无操作反例、App 前后台/任务移除和 Usage Access 关闭态；Windows 已完成当前 session idle 增量与 `unlocked → locked → unlocked` WTS 转移。第二 Android（Xiaomi 2203121C / Android 15）已完成系统锁定/解锁、AC 重连与 Tasker readiness：Lynx 新装 Tasker 6.6.20，但 notification/Usage Access/device-idle whitelist/Accessibility/listener 均未就绪且无 profile/outbox/credential，远端保持 unsupported；预装完整 Here I am 与最小探针边界冲突且本窗未改动。Windows suspend/resume 与 iPhone 仍待，所有快照都未冒充生产 collector 或连续 coverage。
- COROS 实物 Gate：部分通过。23:14 APK SHA-256 `BEA15B5784981F385C2AEA21AC683E5ADC327E6CEB8B1EA50F5814072446EBB6` 是唯一当前候选；正式 `2026-08-29 23:41:50.186–2026-08-30 07:41:50.186` 锁屏窗口由 BatteryStats 证明此前已拔线 100% 且窗口零 screen 事件。跨午夜 JSONL 有 28,494 samples、零坏行、健康数值仅保留本机，首尾距边界 565/644 ms。唯一 >15 s gap 为 `07:09:54.861–07:15:58.017`，363.156 秒：`gatt_status_8` 后首次 2 秒 retry 已执行，但无 callback GATT 的 25 秒 Handler watchdog 在 full Doze 中延迟约 321 秒，第二次 retry 后自动恢复；晨间 service foreground、snapshot fresh live（健康数值仅保留本机）。分项结论为 8 小时耐久 PASS、本次故障自动恢复 PASS、跨日/显式 gap 记录 PASS、严格连续性 FAIL。手机 100%→84% 已观测，但完整断电段 UID/wakelock 证据指向 Companion FGS 可能主导，不能归因 BLE，须做 A/B。舒适度已通过；MARs/relaunch、Doze watchdog、确切离腕复戴重放与集成覆盖仍未完成，整 Gate 尚未完成。
- 外部候选变更边界：另一心率窗口在独立窄跟进中新增 fail-closed Companion 实时心率只读工具与设置页选中态，并于 19:54 原位覆盖新 APK（SHA-256 `6612467855BCF30D105C44485DB283434C2B271E4D959A3A966227AE395E7887`）。用户随后另行授权将这 12 个窄文件提交到 `v3-lab`：`012c5eb524a9941dd8e39614ce0873ab097c7dcd`，父提交为 `66017099e54ac6015949eb2419bf9a92e1dc7d55`；未 push。本窗已只读复核 commit 文件范围与 diff check，但未构建、安装或提交；任何跨过 19:54 的长测必须分段。该变更不属于 MDA-0 activity ingress/probe，也不改变整套 COROS Gate 仍未完成。
- iPhone ingress/Shortcut Gate：Apple 官方资料已确认 Sleep、Charger、App 的公开子条件及可无询问自动运行类别，目标 iPhone 也已确认三类入口可见；Lynx 已下载并登录 Tailscale。11:16 的离线快照由 Lynx 说明为手动连接状态；重新连接后 Windows 脱敏复核为 1 个 iOS peer online、Tailscale ping 成功。现有 Serve 的 4 个 root handler 均为 loopback、无 Funnel，其中 1 个本机 health 是 iCore authority；但 4 个 tailnet HTTPS health 自检均未成功。peer/ping 只证明 `network.present`；没有获批 activity ingress 或独立 write-only token，故 activity webhook 当前正式记为 `unsupported`，错误凭据、重放与撤销测试留作 MDA-1/Gate 1A red gate。
- 中枢拓扑/隐私/删除决策：产品选择已完成。Lynx 选 Windows 方案 A 作为唯一夜间 Core，并接受 Windows 不可用时远端状态降为 `unknown`；iPhone 选 Tailscale tailnet HTTPS 路线。raw event、device spool、BLE raw 与最小诊断统一选 1 天；实时 snapshot 只留当前 fresh 值；经过约束的机器摘要/结论长期保留至用户删除，用户确认结论走独立 User-truth 生命周期。默认不采窗口/App 原名、按键、URL、屏幕、通知或聊天正文，网络/Core/heartbeat/沉默/无回复/单一心率不得证明人的状态。现有 COROS JSONL 实际 14 天是待实现差距。

## 风险与未决选择

- 专题 Roadmap 尚未进入 Git 基线；在它被审计并版本化前，任何 MDA-0 提交都可能成为孤立契约。
- 当前 iCore 与被观察 Windows 同机；Windows 睡眠、关机或注销时不能继续汇总。需在“夜间保持运行 / 私人常在线节点 / 短期加密中继 / 主 Android 本机降级”中明确选择。
- iPhone 没有自研 App，也没有承诺通用锁屏/解锁/持续前台流；实际 Shortcut trigger 以目标 iOS 真机为准。
- 当前 `capabilities_json` 不是服务端权限 scope；任何探针 token 设计都只能是 proposed，MDA-0 不得假装已有 write-only 权限。
- COROS 软件闭环不证明设备广播标准 HRS、实际包含 RR/contact/energy 或能稳定整夜运行。
- 所有 raw/最小诊断已选 1 天；这意味着 Windows Core 离线超过 1 天时旧事件允许到期，并必须通过 watermark/resync 明示，不能补造。长期结论仍必须可删除，不能变成不可撤销的永久记录；备份物理清除只能按公开到期窗口验证，不能承诺即时抹除。

## 决策与变更请求

- 2026-08-29：用户明确授权 MDA-0 作为不取代 P4/Voice/Gate 1A 顺序的并行设计 Goal。
- 2026-08-29：验收窗不切换或写入正在承载用户改动的 `D:/memex`；所有本轮成果先留在隔离 detached worktree，未授权 commit。
- 2026-08-29：任何 worker 发现需要共享契约、生产 schema/代码、设备安装、Tailscale/计划任务或真实凭据时立即停止并回报，不自行执行。

## 集成记录

- 2026-08-29：回收并逐份审计 P1–P4；主窗只在本 Goal 拥有路径内做术语、链接和 fixture 边界修正。
- 2026-08-29：自动 Gate 通过：`JSON_OK files=5 cases=19 required=19`、`SEMANTICS_OK cases=19 allowedKinds=16`、`ADR_DICTIONARY_OK kinds=16 coverage=5`；追加两份真人记录后复验 `LOCAL_LINKS_OK links=29 docs=6`、工作区范围、隐私扫描与旧术语扫描仍通过。
- 2026-08-29：补充独立、可回填的 `REAL_DEVICE_GATE_RECORD.md`，将保留/拓扑选择、COROS 四段实测和 iPhone 安全子项压缩为逐项清单；该模板创建时尚未执行真人测试，随后实测结果由后续记录覆盖，外部配置仍未由本窗口变更。
- 2026-08-29：Lynx 启动真人测试后，主窗纠正优先级为多设备活动基线，新增 `MULTI_DEVICE_REAL_DEVICE_RECORD.md`；已只读确认主 Android 候选、权限与首次 wake/lock/power/App 生命周期快照，未启动 COROS/BLE 扫描或更改设备状态。
- 2026-08-29：纳入另一主窗回收的 COROS 真机子项；初次短重建检查点为 510 sample、0 status、健康数值仅保留本机、可选字段均未出现，直接 `kill -9` 子测试最大 gap 7.87 秒。该最大间隔仅属于短恢复路径；随后 MARs force-stop 失败证据按下一条覆盖更乐观的整体恢复解释。
- 2026-08-29：覆盖先前过于乐观的恢复表述。ApplicationExitInfo 证实 18:07:51 主进程因三星 MARs #2 被整包 force-stop；18:09 用户重开 App 未自动拉起专用心率服务，只有诊断性手动启动后恢复。直接 `kill -9` 短恢复仍通过，但 MARs/relaunch Gate 明确失败；后续只读聚合显示约 251.307 秒样本缺口、0 status 行。
- 2026-08-29：纳入 Lynx 真实离腕/复戴 Gate。摘下且绿灯熄灭后无伪 BPM，约 17 秒 stale、约 62 秒 disconnected；复戴不打开 App、不重选、不重启，retryAt 到期后约 2.145 秒恢复。子项通过，但最长 300 秒退避是体验缺口，且无 contact-supported，不能外推佩戴/清醒/睡眠。
- 2026-08-29：心率窗口确认已按 MDA-0 审核意见同步 Goal、`I_PROJECT_STATE.md` 与 DEVLOG：19:54 覆盖安装及其 SHA-256 是当前唯一真机候选边界，之前短测只作上一候选历史证据，跨时点样本不得拼接；文档 diff check 通过，未 commit/push。
- 2026-08-29：纳入当时 19:54 候选的蓝牙关闭/重开 Gate。关闭后约 0.8 秒持久状态为 `bluetoothOff / adapter_off`，服务与 enabled 配置保留；重开后约 3.43 秒自动恢复首样本，未打开 App、未重选设备。该子项通过；23:14 覆盖新二进制后，本条只保留为历史候选证据。
- 2026-08-29：覆盖手机重启“待验”表述为当前候选明确失败。boot completed 后包内 boot receiver 均被系统以 `mBroadcastConsumerSkip` 在 `onReceive` 前跳过，进程/服务未出现；冷启动 15 秒仍不自愈，旧持久快照错误保留 `live`，仅 ADB 显式 FGS 启动后恢复。后台限制是首要嫌疑而非已证实唯一根因；下一步需 Lynx 明确授权设置“无限制/永不休眠”后复测，本窗不改设备配置。
- 2026-08-29：重启 Gate 最终修正为“带前置条件通过”。Lynx 手动启用 Android“不受限制”与三星“永不休眠”后，同一候选的 appops/bucket 从 `ignore/10` 变为 `allow/5`；再次重启且未开 App，receiver 于 20:32:53 正常投递并自动启动服务，20:32:55.139 恢复首样本。完整重启 gap 177.543 秒且无伪造样本。首次失败保留为后台策略 A/B 证据；设置引导、cold-launch self-heal、stale raw snapshot 纠正、MARs/relaunch 与长测仍未完成。
- 2026-08-29：只读审计外部心率窄提交 `012c5eb5`：父基线精确为 `66017099`，当前 `v3-lab` 包含该提交；12 文件、589 insertions / 15 deletions，与来源交接一致，commit diff check 通过。该提交不包含 MDA-0 文档、activity schema/ingress/probe，也未 push。
- 2026-08-29：纳入 19:54 候选正式锁屏 30 分钟 Gate：窗口全程 Dozing，1,796 samples、max gap 9.818 s、0 status/gap；WebView 更新导致真实进程死亡后 START_STICKY 自动恢复，故本项通过。Gate 前另一次复戴的 overdue retry 停滞单列为实现缺口；23:14 覆盖新二进制后，本条降为历史候选证据。
- 佩戴体验真人检查通过，个人反馈保留本机；电量仍须以 8 小时窗口前后数据单独记录，不能由佩戴体验检查代替。
- 2026-08-29：纳入 23:14 重连返修新候选。主窗只读核对 coordinator、Store active retry deadline、Service 接线与 7 条确定性测试存在；来源报告原生 12/12、critical 3/3、Kotlin/APK build 与独立复审通过。新 APK `BEA15B…EBB6` 快速锁屏 3 分钟为 183 samples、max gap 1.263 s、0 status/gap。19:54 的 30 分钟降为历史候选证据；严格 8 小时＋电量联合 Gate 从拔线后确认 fresh live sample 的时刻起算，必要时另做确切 stall 重放。返修未 commit/push/release。
- 2026-08-29：Lynx 确认已拔 USB 并要求今晚不再操作。由于 ADB 随拔线不可见，主窗没有设备侧起点快照；保守记录起点 `23:41:50.186`、最早结束 `07:41:50.186`。晨间必须先接线且不打开 App，再取 power/battery/service/package/snapshot 与跨午夜两份私有 JSONL；23:27 插线状态的 100% 只作最近读数，不冒充严格起点电量。
- 2026-08-30：回收 23:14 候选整夜正式 Gate。BatteryStats 事后证实 `23:36:26.081` 拔线 100%、`23:36:56.862` 熄屏，正式 8 小时窗口零 screen 事件；跨午夜 28,494 samples、零坏行、首尾覆盖边界。`07:09:54.861–07:15:58.017` 有唯一 363.156 秒 gap：首次 retry 已执行，但 full Doze 将 25 秒 connect watchdog 延迟约 321 秒，第二次 retry 自动恢复。故耐久/恢复/日切缺口记录通过，严格连续性失败；100%→84% 只作整机组合观察，BLE 归因待 Companion FGS/BLE A/B。下一工程修复为持久 watchdog deadline + OS/Doze 兜底和 Service 级晚到测试，之后以新候选重跑零 gap 8 小时。未 commit/push。
- 2026-08-30：Lynx 先完成夜间中枢 A、iPhone Tailscale 路线和跨端 raw/spool 1 天的初步选择；同日后续安装状态与 BLE raw/长期结论决策由下一条完整覆盖。本条只保留选择顺序，不作为当前状态。
- 2026-08-30：Lynx 明确补充保留语义：所有逐条原始数据（含 COROS JSONL）与最小诊断只保留 1 天；实时心率只保留当前 fresh snapshot；安全摘要/结论长期保留至用户删除，用户确认结论进入独立 User-truth。现有 App 的 JSONL 14 天成为待实现差距。Lynx 同时完成 iPhone Tailscale 下载与登录；重新连接后 Windows 脱敏复核为 iOS peer online、ping 成功。现有 Serve 只代理 loopback、无 Funnel，1 个本机 proxy 是 iCore authority；tailnet HTTPS health 尚未成功。未解锁 ingress/Shortcut Gate，也未修改设备配置、生产代码、凭据或入口。
- 2026-08-30：Lynx 明确确认最小采集与禁止推断边界：不采窗口标题、App 原名、按键、URL、屏幕、通知或聊天正文；网络/Core/heartbeat/沉默/无回复/单一心率不证明清醒、安静或睡眠。产品选择 Gate 至此收口；该确认不解锁 MDA-1、ingress、token、probe、推断或主动介入。
- 2026-08-30：主窗完成 MDA-0 收口自动审计：7 个 Markdown 文件独立 diff check 通过；5 个 JSON 文件可解析，19 个 fixture case 名称唯一；6 个活动文档的 29 个本地链接有效；未发现 tailnet IP/DNS、Bearer 凭据或越界工作树修改。当前只待 Lynx 决定是否接受以已记录的 COROS 红灯、iPhone ingress `unsupported`、Windows suspend/resume 未执行和实现差距收口。
- MDA-0 自身仍无集成到 `v3-lab`、commit、build、安装、push 或发布；专题 Roadmap 和本 Goal 成果目前均未形成可提交的完整基线。外部心率窄提交 `012c5eb5` 不改变这一状态。

## Goal 结论

- 完成时间：2026-08-30；Lynx 已确认接受以已记录的 COROS 红灯、iPhone activity ingress `unsupported`、Windows suspend/resume 未执行和实现差距收口。
- 最终设计基线：`7fa6cbb9`；本次受控文档 commit 以 `v3-lab@1f77633a` 为父固化，仅包含 MDA-0 Goal、活动文档与 fixtures。
- push：未授权。
- 下一步顺序：本 Goal commit 固化后另开窗口处理正式 Gate 1A-0 权威 ADR。只有 Gate 1A-0 满足后才可另行提案 MDA-1；不得自动创建、push 或发布。
