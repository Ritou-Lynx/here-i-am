# GOAL-20260829-ble-heart-rate-gateway — Android 实时心率接收闭环

> 状态：已完成（COROS 实时心率接收 v1）；任务移除/MARs、产品耗电预算与长期 Health Vault 转后续工作
> 验收主窗 task/thread ID：`01a04839-f159-71f1-8fd3-4e3b83ef9178`
> Roadmap：Health 数据源与主动陪伴（用户确认的紧急插入 Goal）
> 基线：`v3-lab@30a73ce3625a01b75ebb6076628a24908452cade`
> 提出日期：2026-08-29
> 确认日期：2026-08-29

## 最终结果

Here I am V3 的 Android 手机端已具备可独立运行的标准 BLE Heart Rate
Service 接收闭环。COROS 心率臂带已完成首次扫描选择、实时 BPM、后台恢复、离腕/复戴、
受控 deep-Doze 故障恢复，以及当前精确 APK 上自然佩戴、拔线锁屏零大缺口 8 小时验收。
本 Goal 按可用 v1 收口；不把三星手动移除任务后的 MARs 强停、整机耗电预算、长期档案、
睡眠判断或主动介入冒充已解决。

## 进入条件

- 第一阶段实时传感器采用 COROS 光学心率臂带。
- 当前唯一开发分支为 `v3-lab`，基线已冻结为 `30a73ce3`。
- 手机端允许新增 Android BLE / 后台连接能力，但不得恢复已否决的三星手表端方案。
- 当前主工作区存在其他未提交改动；功能实现必须隔离，集成时不得覆盖用户改动。

## 完成定义

- [x] 能扫描并只呈现标准 Heart Rate Service（`0x180D`）兼容设备，完成显式选择、保存和忘记；不强制建立并非标准 HRS 所必需的系统蓝牙配对。
- [x] 能订阅 Heart Rate Measurement（`0x2A37`），正确解析 8/16-bit BPM、传感器接触标志以及可选 RR interval，并为每个到达样本写入本机时间戳。
- [x] 对蓝牙关闭、权限拒绝、设备不支持、未找到、连接中、实时、陈旧、断连和重连中提供真实状态，不把无数据伪装成零心率或睡眠。
- [x] Android 锁屏且 Here I am UI 不可见时由独立 `connectedDevice` 前台服务维持接收；进程重建、蓝牙重开和暂时离线后会尝试自动恢复，数据缺口被显式记录而非补造。
- [x] 样本在本机形成可检查的最近状态与连续性记录；Health 页面可查看设备、连接状态、当前 BPM、最后样本时间、RR 支持情况和诊断入口。
- [x] Companion / 林埃可通过只读 `LiveHeartRateSnapshot` 查询当前本机 BLE 快照；只有设备已配置并启用、状态为 `live` 且样本年龄不超过 15 秒才返回 BPM，过期、断连、矛盾状态和平台失败均 fail-closed，不回传历史 BPM。
- [x] 实时心率设备扫描列表会识别当前已选设备：启用时显示“已选择 · 已启用”及运行状态，停止时显示“已选择 · 已停止 / 重新启用”，不再对已运行设备重复显示“选择并启用”。
- [x] 核心解析、状态流、重连/陈旧判断和 UI 关键状态具有自动化测试；无实物条件下已有可复现的模拟状态闭环。
- [x] 精确 analyze、相关测试、关键修复守门通过，并产出唯一 `hereIAmV3` Android debug 候选。
- [x] Goal 状态、项目当前态、DEVLOG 与实现 handoff 收口；未 push、未发布。
- [x] 真人硬件 v1 Gate：COROS 实物识别、实时 BPM、短锁屏、Home 退后台、直接杀进程恢复、离腕停样本→缺口记录→复戴自动恢复、蓝牙关闭/重开、后台豁免后的手机重启恢复、正式锁屏 30 分钟、佩戴舒适度及当前 `3056968E…` 自然佩戴零大缺口 8 小时均已通过。23:14 旧候选的 363.156 秒失败与随后 Doze watchdog 返修证据继续保留，不跨哈希冒充当前结果。
- [ ] 后续产品化 Gate（不阻塞本 v1 Goal）：三星手动移除任务后的 MARs 整包强停仍未恢复；历史整夜和本轮整机耗电都不能单独归因 BLE，隔离 B–A–B 只证明 gateway 相关整机增量可重复，不等于纯射频功耗或产品预算通过；一年 Health Vault、睡眠判断与主动介入尚未实现。
- [x] Doze watchdog 受控故障子 Gate：最终 APK SHA-256 `96680738FF6413C2B30EE26EA9F1EC0C49F36775F0B273480D5C1EB27BA0CFAE` 的设备内 `base.apk` 再次核对一致。12:06:32 屏幕熄灭后以 ADB 将真机置入受控 deep IDLE，用户真实摘下臂带且绿灯熄灭；最后样本 12:06:58.029，12:08:02.932 写入 `sample_timeout_reconnect`。12:08:29.989–12:12:37.609 共九次 `ELAPSED_WAKEUP` exact Alarm 在 deep IDLE 中真实唤醒，九次 manifest `BleHeartRateWatchdogReceiver` 均为 `DELIVERED`，对应九个 `connect_watchdog_timeout` 在 Alarm 后 16–44ms 写入。用户复戴且未打开 App 后，12:12:55.283 自动恢复第一条有效样本（健康数值仅保留本机）；至 12:14:41.189 已连续 107 个恢复样本，最终 snapshot `live`，持久 watchdog plan 与活动 pending Alarm 均清除。故系统唤醒 deadline、Receiver 投递、真实缺口记录和无人为恢复 PASS；硬件本轮还出现 `discovering_services` / `awaiting_first_sample`、`malformed_zero_bpm` 与 `gatt_status_133`，不能窄化表述为“每次 connectGatt 从头到尾零回调”。
- [x] 最终同哈希零大缺口 8 小时 Gate：精确候选 SHA-256 `3056968EA16D10245B7AD4A40B81CF7124C8A4B64B95798E235E6AA201E761D4` 在 2026-09-10 00:30:44.302–08:30:44.302 正式窗口记录 28,870 个 sample，首尾距边界 742 / 421ms，最大间隔 4.872 秒，零 `>15s` gap、零 status/gap、零坏行。BatteryStats 支持窗口前已拔线熄屏，窗内无完整亮屏或接电/充电事件并进入 full idle；晨间设备包哈希一致、BLE FGS 存活、快照 fresh live。14 对同毫秒相邻记录（10 对完全重复）另列数据质量项，不构成长缺口。严格连续性 PASS；隔离电量 B–A–B 不替代本 Gate。
- [x] 隔离电量 B–A–B 工程 Gate：B1 `254.7 mAh/h`、A `131.8 mAh/h`；B2 于 2026-09-01 01:11:30.134–03:11:30.753 测得 `211.2 mAh/h`，97%→86%、无充电/互动亮屏、同 PID 两个 FGS 持续，7,217 samples、0 status/gap、max gap 4.334s。B1/B2 相差 17.1%，满足预设 ≤20% 复现阈值；B 平均 `232.9 mAh/h`，相对 A 的 gateway 相关整机增量估计约 `101.1 mAh/h`。B2 跨后续小版本且 A 只有单窗，故只判工程方向性通过，不判同二进制精密标定或产品预算通过。
- [x] 省电微调候选短 Gate：稳定 live 无 watchdog plan 时的 reconcile 改为纯 no-op，BPM 通知刷新由 12 秒降至 60 秒；新候选 31.799 分钟窗口起终点均为 Dozing，精确日志有 1,913 samples、0 status/gap、max gap 1.881s，连续性通过。同期 `216.7 mAh/h` 与既有 B2 `211.2 mAh/h` 接近，故不判耗电改善；该短窗紧邻充电、没有同哈希改动前基线且不足 2 小时，只用于筛查明显回归。
- [x] sample 快照 30 秒降频软件 Gate：只把稳定 sample 的 app-private preferences 快照持久化由约 5 秒降至 30 秒；首次、force / 状态切换、逐回调 JSONL（臂带实测约 1Hz）、gap/status、EventChannel 与 watchdog 均未降频。墙钟回拨会立即允许新快照。独立复审无 P0/P1，BLE Kotlin `50/50`、critical `3/3` 与 hereIAmV3 debug build 通过；新复合 APK 已安装并核对哈希，佩戴后的 fresh-live 已通过。
- [x] 新复合候选短锁屏 Gate：锁屏稳定后的正式窗口 10:32:45.334–10:37:45.334 全程由轮询确认 `Dozing`、USB connected、BLE FGS 存活；304 个 sample、健康数值仅保留本机、首尾距边界 0 / 502ms、最大间隔 1.263 秒、零 status/gap、零坏行。BatteryStats 记录 10:31:48.407 熄屏、10:31:50.566 进入 screen doze，之后到取证结束无亮屏事件。锁屏初段 10:32:15.619–10:32:41.797 另有 26.178 秒回调到达停顿，随后约 26 条 callback 集中交付；该段不并入稳定窗口，但必须保留为最终 8 小时 Gate 的观察项，不能据短测宣称严格整夜连续。

## 明确不做

- 不实现睡眠分期、失眠诊断、呼吸暂停判断或基于单一心率的自动来电。
- 不恢复或继续扩展三星 Galaxy Watch 手表端 App / HTTP server 方案。
- 不实现 iOS、COROS 云端同步、固件更新或厂商私有协议。
- 不把可选 RR interval、原始 PPG、体动或离线补传写成 COROS 已保证能力。
- 不 push、不发布；不修改与本 Goal 无关的白板、语音、i Gateway 或现有用户改动。

## 工作包状态

| ID / 名称 | 执行方式 | task/thread ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P0 现状与契约审计 | 子 Agent | `hr_goal_health_audit` / `hr_goal_android_audit` / `hr_goal_ui_store_audit` | `30a73ce3` | 只读主工作区 | 已审计 | — | 本页决策区 | 通过 | 三项只读审计完成 | 不需要 | 按冻结设计派发 P1/P2 |
| P1 BLE HRS 核心与本机记录 | 隔离写工作流 | `hr_gateway_impl` | `30a73ce3` | `codex/ble-heart-rate-gateway` / `.worktrees/ble-heart-rate-gateway` | 已完成 | `1aee5fe3`，集成后 `fd2a48b7` | `docs/development/handoffs/BLE_HEART_RATE_GATEWAY.md` | 通过 | HRS parser 单测与 hereIAmV3 Kotlin 编译通过 | 待实物 | 按本页真人 Gate 验收 COROS 输出 |
| P2 Android 后台与 Health UI | 隔离写工作流 | `hr_gateway_impl` | `30a73ce3` | 同 P1 | 已完成 | 同 P1 | 同 P1 | 通过 | 新增 Flutter 测试 `6/6`，入口测试 `1/1`，定向 analyze 通过 | 待实物 | 验收锁屏、杀进程、重启与蓝牙切换 |
| P3 集成、构建与收口 | 验收主窗 | 本任务 | `30a73ce3` | `v3-lab` | 已完成 | `fd2a48b7` | Goal / DEVLOG / 项目状态 | 通过 | 关键守门 `3/3`；hereIAmV3 debug APK 构建成功 | 待实物 | 安装同一 APK，禁止用旧候选 |
| P4 重连停滞返修与整夜候选 | 验收主窗 + 只读复审 | 本任务 / `retry_fix_design_audit` / `retry_fix_code_review` / `retry_test_audit` / `hr_long_gate_review` / `hr_disconnect_review` / `hr_battery_review` | `1f77633a` + 当前未提交修复 | `v3-lab` 主工作区 | 8 小时取证完成；返修待定 | — | 本页 / DEVLOG / 项目状态 | 分项复核完成 | coordinator `7/7` + parser `5/5`；关键守门 `3/3`；APK 构建成功 | 锁屏耐久 PASS；本次自动恢复 PASS；严格连续性 FAIL；电量归因未验收 | 持久化并独立唤醒连接 watchdog；隔离 Companion FGS wake lock 后重跑连续性与 A/B 电量 Gate |
| P5 Doze connect watchdog deadline 返修 | 验收主窗 + 独立只读复审 | 本任务 / `watchdog_service_audit` / `watchdog_test_contract_audit` / `final_watchdog_diff_review` / `fault_gate_result_review` | `1f77633a` + 当前未提交窄修 | `v3-lab` 主工作区 | 软件、受控 deep-Doze 故障与后续复合候选长 Gate 完成 | — | 本页 / DEVLOG / 项目状态 | 最终无 P0/P1；真机证据独立复核一致 | BLE Kotlin `37/37`、critical `3/3`、diff check、Kotlin 与 hereIAmV3 build PASS | 同哈希安装、fresh live、九次 deep-IDLE Alarm / Receiver / timeout、复戴自动恢复 PASS；后续 `3056968E…` 自然佩戴 8 小时零大缺口 PASS | 任务移除/MARs、产品耗电预算继续单列 |
| P6 sample 快照 30 秒降频 | 验收主窗 + 独立只读复审 | 本任务 / `snapshot_persist_optimization` / `snapshot_change_review` / `ble_candidate_drift_audit` / `short_lock_review` / `overnight_jsonl_review` / `overnight_power_review` | 当前精确 APK `3056968E…` | `v3-lab` 主工作区 | 新哈希 8 小时 Gate PASS | — | 本页 / DEVLOG / 项目状态 | 30 秒语义、长测 JSONL 与 BatteryStats 均独立复核 | BLE Kotlin `50/50`、critical `3/3`、Shortcut Mail client `6/6`、历史 hereIAmV3 build PASS | 28,870 samples、max gap 4.872s、零 `>15s` gap/status、无完整亮屏/充电、进入 full idle；晨间 fresh live | 严格连续性关闭；另做日志去重、MARs 与产品电量预算 |

## 依赖与集成顺序

1. P0 先确认当前 Health 数据源、Android 后台基础、存储边界与 UI 入口。
2. P1 先固化可测试的协议解析和连接状态机，再接真实 BLE transport 与本机记录。
3. P2 在 P1 稳定契约上接 Android 后台生命周期、权限与 Health 页面；不让 UI 直接持有 BLE 生命周期。
4. P3 审计 diff 与共享契约，串行跑专项测试、组合回归、关键守门和唯一候选构建。
5. 设备到货后使用同一候选执行真人硬件 Gate；失败返回对应 P1（协议/连接）或 P2（后台/UI）返修。

## 决策与变更请求

- 2026-09-10：Lynx 在自然佩戴零大缺口 8 小时 Gate 通过后明确同意结束并提交心率带功能。本 Goal 因此按“COROS 实时心率接收 v1 可用、已知产品边界转后续”完成；不等待三星任务移除/MARs、产品耗电预算、长期 Health Vault、睡眠判断或主动介入。
- 2026-09-10：提交前当前源码的 `compileHereIAmV3DebugKotlin` 与 BLE Kotlin `50/50` 已重新执行通过，critical `3/3`。Gradle 原动态 AndroidX test 依赖的在线元数据解析被环境网络阻断，专项重跑以未入仓的临时 init script 固定本机缓存版本；这证明当前 BLE Kotlin 专项，不提升为原生产依赖图或完整 APK 重建通过。
- 2026-09-10：提交前静态终审另记一个非阻断 P2：首次有效样本前若只收到 malformed measurement，状态会变为 `malformedData`，现有 connect watchdog 不会把该状态视为活动连接超时；后续有效 callback 仍可直接恢复 `live`。不为修这个罕见边界改动已完成整夜 Gate 的 APK，后续容错补丁须作为新候选重新验证。
- 2026-09-10：当前三星安装包已不是 9 月 5 日上午短锁屏使用的 `C6698F71…`，而是 9 月 5 日 22:58 覆盖的 `3056968E…`；电脑现存 APK 与设备 `base.apk` SHA-256 完全一致，版本仍为 `1.0.30 (113)`。因此旧 short-lock / fresh-live 只保留为历史证据，本轮 8 小时对当前实际使用的新哈希独立验收。
- 2026-09-10：正式 Gate 前电量 91%、USB powered、Awake、BLE FGS 存活，JSONL 尾样本年龄约 3.1 秒；随后约 62 秒预检记录持续增长。Lynx 明确确认已拔线并锁屏后，ADB 不再可见；设备侧 `powered=false`、熄屏精确时间、起点 fresh sample 与 Doze 状态须次晨由 BatteryStats / app-private JSONL 回溯，当前不冒充实时读取。为避免高估，正式窗口保守取 00:30:44.302–08:30:44.302。
- 2026-09-10：晨间未打开 App 的正式取证确认设备/本地 APK 哈希仍一致，BLE FGS 存活且快照 fresh live（健康数值仅保留本机）。正式 8 小时有 28,870 个 sample，首尾边界 742 / 421ms，最大间隔 4.872 秒，零 `>15s` gap、零 status/gap、零坏行；文件顺序零倒退、14 对同毫秒相邻记录（10 对完全重复），后者只列日志质量项。BatteryStats 支持窗前已拔线熄屏、窗内无完整亮屏或充电并进入 full idle。严格连续性 Gate 判 PASS。
- 2026-09-10：本轮 BatteryStats 电量等级 92%→36%，下降 56 个百分点；电荷计数 `3412→1381 mAh` 覆盖约 7 小时 56 分，约 256 mAh/h，但末点早于正式终点约 4 分 48 秒，且它是所有系统/无线电/后台任务的整机观测，不能归因 BLE、不能写成完整八小时精确平均，也不判产品续航达标。
- 2026-08-29：今晚的停止条件是“手机端候选已构建且模拟闭环通过”；实物整夜 Gate 因客观依赖设备到货，单列为次日验收，不伪造通过。
- 2026-08-29：接收链路直接使用 BLE HRS，不依赖 COROS App 或云端；接收端断线期间没有可依赖的历史补传。
- 2026-08-29：P0 审计确认当前没有现役实时健康 Gateway；旧 `HealthService` 只做步数/批量数据，历史 `HealthHub` 依赖未入库，不能复用为运行实现。
- 2026-08-29：采用独立 Android `connectedDevice` 前台服务持有 BLE GATT、重连与样本文件；不复用现有 `mediaPlayback|microphone` Flutter 前台服务，避免心率接收被麦克风权限、通话 isolate 或 `stopWithTask=true` 生命周期绑架。Flutter 通过窄 Method/Event Channel 管理和观察服务。
- 2026-08-29：逐搏遥测只进入本机传感器日志，不写 SharedLife / Memory V3 / 旧 Facts；已选设备和能力使用用户隔离配置，Health 页面只展示实时快照与诊断。
- 2026-08-29：COROS 实物 `COROS 光学心率臂带（设备标识仅保留本机）` 已确认广播标准 HRS `0x180D`，手机不依赖 COROS App 即可发现、选择并持续接收 BPM；超过 400 个真机样本均未出现 RR、contact supported 或 energy 字段，因此当前能力按“仅实时 BPM”处理，不能据此判断佩戴、清醒或睡眠。
- 2026-08-29：锁屏短测与应用进程被杀后的 `START_STICKY` 恢复通过；进程 PID 已重建，样本最大间隔约 7.87 秒。该短中断未跨越陈旧阈值，故没有单独 gap/status 行；随后真实离腕长断连已验证 JSONL 会写 `sample_timeout_reconnect` 与后续连接失败状态。
- 2026-08-29：三星真机额外暴露任务移除失败：18:07:51 系统先以 `remove task` 停止通用 Flutter 前台服务，随后由 MARs #2 将 `com.memexlab.hereiam.v3` 整包 force-stop；专用心率服务随之消失，配置仍为 enabled，原始持久快照仍停在 `live`，重新打开 App 也没有自动拉起服务。普通 Home 退后台 25 秒仍连续采样，故失败边界是任务移除/整包 force-stop，而不是普通锁屏或 Home。
- 2026-08-29：新增 Companion 只读实时心率工具与设备选择态 UI。工具只开放 15 秒内的 live BPM，并在提示与返回结构中明确单一 BPM 不能证明睡眠、清醒、焦虑、疾病或构成自动来电理由；自动睡眠状态机与来电触发仍属于后续 Goal。
- 2026-08-29：19:54 覆盖安装的 APK（SHA-256 `6612467855BCF30D105C44485DB283434C2B271E4D959A3A966227AE395E7887`）成为新的唯一真机候选边界。此前短测证据保留为历史行为证据，但任何跨越 19:54 的样本不得拼接为该候选的连续 Gate；30 分钟与 8 小时长测必须从此次安装后重新计时，或在报告中明确拆成安装前后两段。
- 2026-08-29：当前 19:54 候选的蓝牙关闭/重开自动恢复通过。关闭请求前最后样本为 20:07:10.678（健康数值仅保留本机），约 0.8 秒后写入 `bluetoothOff / adapter_off`，服务持续存在；20:08:06.092 重开蓝牙后，20:08:09.525 自动恢复首样本（健康数值仅保留本机），约 3.43 秒，无需打开 App 或重新选择设备。
- 2026-08-29：当前 19:54 候选的手机重启恢复 Gate 失败。重启前最后样本为 20:13:30.829（健康数值仅保留本机）；系统完成启动后，`BleHeartRateBootReceiver` 与同包其他 manifest boot receiver 均在进入 `onReceive` 前被标记为 `SKIPPED / reason:mBroadcastConsumerSkip`，进程和专用服务均未出现。包状态仍为 `stopped=false`、standby bucket `10`、`RECEIVE_BOOT_COMPLETED` 已授权，但 `RUN_ANY_IN_BACKGROUND=ignore`，与用户/厂商后台限制高度一致；当前只能把它列为首要嫌疑，不能仅凭这一轮断言唯一根因。20:19:52 冷启动 App 后等待 15 秒，专用服务仍未自动拉起，原始持久快照继续停在旧的 `live`（健康数值仅保留本机）；20:20 通过 ADB 显式启动服务后才恢复新样本（健康数值仅保留本机）。
- 2026-08-29：用户把「故我在 V3」设为不受限制并加入三星永不休眠后，设备侧 `RUN_ANY_IN_BACKGROUND` 从 `ignore` 变为 `allow`，standby bucket 从 `10` 变为豁免态 `5`。同一 19:54 候选再次重启，未打开 App：`BleHeartRateBootReceiver` 于 20:32:53.091–20:32:53.307 被正常 `DELIVERED`，专用 `connectedDevice` 前台服务由本包自动启动，第一条新样本于 20:32:55.139 到达（健康数值仅保留本机），距 receiver 开始约 2.05 秒。重启前最后样本为 20:29:57.596（健康数值仅保留本机），真实缺口约 177.543 秒且没有补造样本；因此带上述手机设置前置条件的重启恢复 Gate 通过。
- 2026-08-29：当前 19:54 候选的正式锁屏 30 分钟 Gate 于 22:06:13.706–22:36:13.706 完成，屏幕全程保持 `Dozing / DOZE`，窗口内有 1,796 个样本；首样本 22:06:13.751（健康数值仅保留本机），末样本 22:36:13.574（健康数值仅保留本机），最大样本间隔 9.818 秒，未写入 status/gap 事件。22:18:39.305 系统因安装/更新 Android System WebView（`installPackageLI`）主动杀死 PID `13975`，22:18:41.071 以 `BleHeartRateService` 重建 PID `17074`；`START_STICKY` 自动恢复，样本链没有越过 15 秒陈旧阈值。该外部进程死亡与恢复发生在真实锁屏窗口内，因此 30 分钟 Gate 通过。
- 2026-08-29：正式 Gate 前的第一次锁屏观察不计入结果：臂带在锁屏前已离腕，最后样本停在 21:56:03.730；复戴后服务/PID 仍在且持久 `retryAtMs` 已过期，但内存重试没有按期执行，直到 22:03:59.990 才恢复样本。恢复发生在诊断期间且紧邻一次 `SIGQUIT` 取栈，不能归因为纯被动复戴。只读代码审计确认 `retryAtMs` 只是状态投影，真正调度只依赖主线程 `Handler`；`closeGatt(cancelReconnect=true)` 可移除 runnable 而不清理持久到期时间，`staleTick` 又没有 overdue 兜底，BLE callback 与主线程状态还存在竞态面。该设计允许“服务存活 + retryAt 过期 + 永不再试”，但本次具体交错尚未证明；后续须做主线程状态收敛、显式 retry generation/due、仅终止路径取消重试与 overdue 自愈。
- 2026-08-29：23:14 候选将 retry 生命周期收敛为单一 `BleReconnectCoordinator`：每次计划带 generation token 与 due time，替换/取消后的旧 callback 不能触发新连接；提前 callback 只重排剩余时间；`staleTick` 会从持久 `retryAtMs` 重建丢失的未来 callback，并对已过期 deadline 立即且只恢复一次。GATT callback 统一投递到 Service 主线程，连接代次同时校验 generation 与 GATT 实例；`closeGatt` 不再隐式取消 retry，只有 STOP / FORGET / adapter-off / destroy / 显式新连接等终止边界取消。
- 2026-08-29：新候选以 `v3-lab@1f77633a` 加当前未提交 COROS 返修构建，APK SHA-256 `BEA15B5784981F385C2AEA21AC683E5ADC327E6CEB8B1EA50F5814072446EBB6`，23:14 以同包名原位覆盖安装且保留应用数据。23:16:12.868–23:19:15.558 锁屏快速 Gate 全程 live / Dozing：JSONL 有 183 个 sample，首尾为 23:16:13.178 / 23:19:14.802，最大间隔 1.263 秒、健康数值仅保留本机、零 status/gap 事件。该快速 Gate 证明当前连接与锁屏接收可用，不替代 8 小时或确切离腕→复戴停滞的真机 Gate。
- 2026-08-29：用户明确确认手机已经拔掉 USB，并要求今晚按当前状态继续，不再操作。拔线后 ADB 已不可见，因此不能把 `USB powered=false`、拔线后的 fresh sample、Service 或 Dozing 状态写成设备侧已实时复核；证据等级仅为“用户确认拔线，设备侧起点状态未实时读取”。为避免高估，8 小时正式长测保守起点取验收窗记录时间 23:41:50.186，目标结束不早于 2026-08-30 07:41:50.186；候选哈希仍为 `BEA15B5784981F385C2AEA21AC683E5ADC327E6CEB8B1EA50F5814072446EBB6`。
- 2026-08-30：晨间未打开 App 即先完成只读取证。BatteryStats 反证并补强起点：手机实际于 23:36:26.081 从 100% 拔线，23:36:56.862 熄屏；正式 8 小时窗口内没有任何 screen on/off 变化，只有三次系统 idle maintenance，随后均回到 full idle。服务和进程存活，当前快照仍为 fresh `live`。
- 2026-08-30：正式窗口 23:41:50.186–07:41:50.186 有 28,494 个 sample，首样本 23:41:50.751（距起点 565ms），末样本 07:41:49.542（距终点 644ms），健康数值仅保留本机，跨午夜两份 JSONL 零坏行。07:10 `gatt_status_8` 后首次 2 秒 retry 已执行，但新 GATT 无回调；25 秒 watchdog 直到 07:15:49 才在 full Doze 中运行，第二次 retry 后 07:15:58 自动恢复。最大间隔 363.156 秒，因此锁屏 8 小时耐久与该故障自动恢复通过，严格连续性失败，缺口内不补造数据。
- 2026-08-30：电量在正式窗口从 100% 降至 84%（16 个百分点）。完整 10 小时 53 分钟断电段的 BatteryStats 将 Here I am UID 估算为约 210mAh，其中约 192mAh 对应近整夜的 `ForegroundService:WakeLock`；源码将其归到 `flutter_foreground_task` 的 `allowWakeLock: true` 常驻 Companion FGS，而 BLE service 没有显式 wake lock。该单夜只能表示“BLE + Companion FGS + 系统负载”的组合耗电，不能写成 BLE 耗电 16%；须做隔离 A/B。
- 2026-09-01：隔离电量 B–A–B 只补跑 B2。正式窗口 01:11:30.134–03:11:30.753，charge counter `3,627,195→3,204,825 µAh`，即 `422.370 mAh / 2.000 h = 211.2 mAh/h`；97%→86%，无充电、无互动 screen，同 PID `7570` 的 BLE / Companion FGS 均持续。JSONL 有 7,217 samples、0 status/gap，首尾边界 93/356ms、最大间隔 4.334s。与 B1 `254.7` 相差 17.1%，通过 ≤20% 复现阈值；两个 B 平均 `232.9`，比 A `131.8` 高约 `101.1 mAh/h`。B2 跨小版本，用户确认改动不触及相关链路；结论只覆盖 gateway 相关整机增量的工程复现。
- 2026-09-01：首个 22:36:52 省电短窗因用户于 22:39 后重新充电而作废，未与后续窗口拼接。唯一正式窗口 22:53:19.893–23:25:07.832 的供电事件最后停在起点前 22:51:30.961 断电，起终点均 `Dozing / mIsPowered=false`；两端均观察到两个 FGS 与同一 PID `12517`。charge counter `2,697,240→2,582,385 µAh`，即 `114.855 mAh / 31.799 min = 216.7 mAh/h`，72%→69%。JSONL 全文件 36,808 行均逐行检测到 `timestampMs`；精确窗口有 1,913 samples、0 status/gap，首尾边界 285/179ms、最大间隔 1.881s，健康数值仅保留本机。连续性短 Gate 通过；耗电与 B2 接近，不证明微调收益。没有同哈希改动前基线，刚充电后的短窗可能受电量计回落影响，且未取得完整 screen / 温度 / 后台活动轨迹。
- 2026-09-02：第二项省电窄修只把稳定 sample 的 preferences snapshot 落盘节流从 5 秒改为 30 秒，首次、force / 状态切换、逐回调 JSONL（臂带实测约 1Hz）、gap/status、EventChannel 与 watchdog 保持即时；墙钟回拨视为新周期，立即允许快照，避免负时间差导致无限抑制。独立复审最终无 P0/P1，BLE Kotlin `50/50`、critical `3/3`、hereIAmV3 debug build PASS。
- 2026-09-02：新产物为 `v3-lab@e77045fafebd` 加当前工作区未提交改动，462,938,653 bytes，SHA-256 `8A2C00545BB200D4FEC7C81AAD17E76B7CDB620FA0CD4B73AE5155433191352E`，版本 `1.0.30 (113)`。构建时手机未连接，故未安装、未核对设备 `base.apk`、未取得 fresh sample；一旦覆盖安装，所有新连续性结论必须从该哈希重新计时。
- 2026-09-02：现有 Android raw 为 app-private 按日 JSONL，代码保留 14 天；旧 MDA 草案提出 1 天 raw，但 Lynx 本轮明确希望长期利用每晚数据。两者冲突时不静默改 retention，先保留 14 天安全缓冲，并提出独立 Windows Health Vault + 日包 / 索引 / 摘要 + 只读 MCP 草案；长期 raw 建议 1 年，须由 Lynx 确认后另立实现 Goal。
- 2026-09-05：本地 Windows Health Vault 的逐秒 raw 保留 1 年，用于回看或用新算法重算。产品支持睡眠用途佩戴窗口；窗口可能包含清醒时段，不能整体标为已睡眠。手机仍以 14 天作为未同步缓冲；Vault / 同步 / 到期删除 / 只读 MCP 属后续实现，当前尚未生效。
- 2026-09-05：当前 `v3-lab@455be35e` 的提交增量未触及 Android / BLE，但新二进制同时含已合入的 Shortcut Mail 客户端，因此明确登记为复合候选。critical `3/3`、BLE Kotlin `50/50`、Shortcut Mail client `6/6` 与 hereIAmV3 build PASS；APK 462,936,094 bytes，SHA-256 `C6698F7124BCD915A13D6171656B44AE2B005E4B7F33DD27613B1A9E8044E2BE`。
- 2026-09-05：10:07 在 `SM-S9110` 以同包名覆盖安装，设备 `base.apk` SHA-256 与电脑产物一致，版本 `1.0.30 (113)`，`firstInstallTime` 保持 2026-07-29；已选设备配置与 2026-08-29～2026-09-05 共 8 个 raw 日文件仍在。冷启动 App 后 BLE FGS 存活，但诊断连续为 `gatt_status_147 → reconnecting/disconnected`，未取得安装后新 sample；这不是 fresh-live PASS，也尚不能归因臂带未佩戴，等待用户确认佩戴 / 绿灯后继续。
- 2026-09-05：Lynx 确认臂带已佩戴且绿灯亮后，服务未被人工重启或绕过退避；持久 `retryAtMs` 到期后状态自行进入 `connecting / awaiting_first_sample`，并于 10:26:34.455 写入首条安装后 sample。至 10:29:36.131 已有 183 个 sample，健康数值仅保留本机、最大样本间隔 1.901 秒、末样本年龄 1.5 秒，fresh-live PASS。下一步只做同哈希约 5 分钟 USB 连接锁屏，再进入零大缺口 8 小时 Gate。
- 2026-09-05：同哈希短锁屏取证以锁屏稳定后的 10:32:45.334–10:37:45.334 为正式窗口：304 个 sample，健康数值仅保留本机，首尾距边界 0 / 502ms，最大间隔 1.263 秒，零 status/gap、零坏行；轮询全程 `Dozing`、USB connected、BLE FGS 存活，BatteryStats 在 10:31:48.407 记录熄屏、10:31:50.566 进入 doze，之后未见亮屏，故稳定 5 分钟短锁屏 PASS。正式窗之前的 10:32:15.619–10:32:41.797 有 26.178 秒 callback arrival gap，随后约 26 条回调集中交付；该瞬态单列为 caveat，最终 8 小时 Gate 仍按自然佩戴窗口内零大缺口严格验收。
- 2026-08-30：Android 官方契约审计确认主线程 `Handler` 在 full Doze 下没有 25 秒执行 SLA；普通 alarm/job 会被推迟，`setExactAndAllowWhileIdle` 是有精确闹钟能力时的系统唤醒机会，能力不可用则只能降级 `setAndAllowWhileIdle`。因此 Handler 只保留快速路径，持久 deadline、Alarm Receiver 和每次 Service 启动/周期 tick 的 reconcile 共同构成恢复链；不把 OS 唤醒写成绝对准时保证。
- 2026-08-30：Doze watchdog 窄修为每个连接尝试同步持久化 token / generation / dueAt / address，并同时调度 Handler 与 `ELAPSED_REALTIME_WAKEUP` Alarm；Handler、Alarm、tick 通过同一 durable consume gate exactly-once。旧 token/generation/GATT 均不能关闭新连接，STOP / FORGET / adapter-off / destroy / 新样本等终止边界会清理 plan 与 alarm，timeout 只写真实 gap/status 后走既有有界重连，不生成样本。
- 2026-08-30：独立复审两轮拦下 Receiver 前台服务启动失败无后续唤醒、以及只重排 Alarm 未同步持久 dueAt 的同身份晚到竞态。最终实现先对完整旧 plan 做条件替换并同步 commit，再以同身份 60 秒重排；同身份但早于持久 deadline 的广播只重排、不启动 Service，持久失败不排无主 alarm。最终复审无 P0/P1；保留墙钟大幅校正、持续 FGS 拒绝与 AlarmManager 自身调度失败三项 P2 真机/系统边界。

## 集成记录

- 隔离提交 `1aee5fe35569979d16e348420f573b35f9b37cde` 经主窗审计后 cherry-pick 为 `v3-lab@fd2a48b7`；未覆盖主工作区既有未提交改动。
- 独立只读复审未发现 P0/P1；其唯一 P2（开机/后台启动前台服务被系统拒绝时静默失败）已在提交前修为显式 `background_start_denied` 诊断。
- 自动 Gate：新增 Flutter 测试 `6/6`、Personal Center 新入口 `1/1`、HRS parser 单测与 `compileHereIAmV3DebugKotlin` 通过；新增/接入文件定向 analyze 无新增问题；关键修复守门 `3/3`。
- 候选 APK：`build/app/outputs/flutter-apk/app-hereiamv3-debug.apk`，462,864,861 bytes（441.42 MiB），SHA-256 `178E9239B4382B4B020EC322A21C7753FE454DEE5D739F5FAA33455C2634F1CF`。
- 2026-08-29 10:12 已在 `SM-S9110` 以 `adb install -r -d -t` 原位覆盖 `com.memexlab.hereiam.v3`；安装后仍仅有该 V3 包，`firstInstallTime` 保持 2026-07-29，应用数据未清除。未 push、未发布；旧 Windows Flutter generated 漂移未进入提交。
- Companion / UI 窄跟进：定向 Flutter 测试 `21/21`，9 个目标文件 analyze 零问题，`git diff --check` 与关键修复守门 `3/3` 通过。hereIAmV3 debug APK 构建成功，462,903,835 bytes，SHA-256 `6612467855BCF30D105C44485DB283434C2B271E4D959A3A966227AE395E7887`；2026-08-29 19:54 在 `SM-S9110` 原位覆盖成功，`firstInstallTime` 保持不变，MainActivity 可见且 `BleHeartRateService` 以前台服务运行。安装后真机快照仍为 `live`，核验时取得约 10 秒内的新样本（健康数值仅保留本机）。本次小修由独立提交收口，未 push。
- 重连返修自动 Gate：`BleReconnectCoordinatorTest` `7/7` 与 `HeartRateMeasurementParserTest` `5/5`，合计 `12/12`、零失败/跳过；关键修复守门 `3/3`、相关 diff check 与 Kotlin / hereIAmV3 debug 构建通过。APK 为 462,900,023 bytes，SHA-256 `BEA15B5784981F385C2AEA21AC683E5ADC327E6CEB8B1EA50F5814072446EBB6`；2026-08-29 23:14 在 `SM-S9110` 以 `adb install -r -d -t` 原位覆盖，版本 `1.0.30 (113)`，`firstInstallTime` 保持不变。安装后专用前台服务即时恢复 fresh live BPM。独立代码复审无 P0/P1；Service/真实 Handler/GATT 生命周期仍主要由静态审计与真机 Gate 覆盖，保留自动化集成测试 P2。未 commit、未 push、未发布。
- Doze watchdog 返修自动 Gate：BLE 纯 Kotlin / Service controller / Receiver policy 共 `37/37`、零失败/错误/跳过；关键守门 `3/3`、`git diff --check`、`compileHereIAmV3DebugKotlin` 与 `assembleHereIAmV3Debug` 通过。最终 APK 462,907,309 bytes，SHA-256 `96680738FF6413C2B30EE26EA9F1EC0C49F36775F0B273480D5C1EB27BA0CFAE`；2026-08-30 11:33 在 `SM-S9110` 原位覆盖，设备内 `base.apk` 哈希一致，版本仍为 `1.0.30 (113)`，`firstInstallTime` 保持 2026-07-29，应用数据保留。11:24 的中间安装不作为正式候选；未 commit、未 push、未发布。
- Doze watchdog 受控真机 Gate：12:06:32 屏幕熄灭并进入受控 deep IDLE；物理离腕后最后样本 12:06:58.029，12:08:02.932 因样本超时开始重连。12:08:29.989–12:12:37.609 的九个 exact Alarm 均由系统记录为 wakeup，manifest Receiver 均在 1–6ms 内开始 dispatch、22–51ms 内完成，九个 timeout 状态在 Alarm 后 16–44ms 持久写入。复戴后首个真实样本 12:12:55.283（健康数值仅保留本机），无需打开 App；107 个恢复样本后仍 `live`，plan / pending watchdog Alarm 清空。最后离腕前样本到恢复首样本的 357.254 秒 gap 已如实保留。该 Gate 证明 no-first-valid-sample watchdog 的 Doze deadline 与自动恢复，不声称精确复现“connectGatt 全程无任何 callback”。
- 并行工作区边界：最终 APK 于 11:31 构建、11:33 安装；主分支随后在 11:37 才前进到仅新增 MDA-0 文档/fixture 的 `2edaf17a`。该并行提交没有进入 APK，也没有改 Android / Dart 构建输入；本候选仍按“`1f77633a` + 未提交 BLE 窄修 + 完整 APK 哈希”界定。

## 真人验收

- 当前 `SM-S9110` 已安装候选为电脑现存 `build/app/outputs/flutter-apk/app-hereiamv3-debug.apk`，463,009,345 bytes，SHA-256 `3056968EA16D10245B7AD4A40B81CF7124C8A4B64B95798E235E6AA201E761D4`；本地产物时间 2026-09-05 20:57、设备覆盖时间 22:58，设备 `base.apk` 哈希一致，版本 `1.0.30 (113)`。它不同于 10:07 的 `C6698F71…`，因此当前 8 小时连续性结论从 2026-09-10 新窗口独立取证，不继承任何旧哈希真人 Gate。
- 连续性边界：23:14 候选的整夜耐久、自动恢复与 363.156 秒严格连续性失败完整保留为历史证据；11:24 中间安装不计正式候选。最终候选的所有新连续性结论从 11:33 安装后重新取证，不与任何旧哈希样本拼接。
- 场景：首次识别与选择；锁屏 30 分钟预检；连续 8 小时；蓝牙关闭/重开；杀进程/重启；RR 字段；电量与佩戴舒适度。
- 结果：自动 Gate、同包名覆盖安装与安装后 fresh live BPM 已通过。COROS 标准 HRS 识别、约 72 秒亮屏连续接收、约 25 秒锁屏接收和杀进程自动恢复属于 19:54 前上一候选的历史短测证据：亮屏段 73 个样本、健康数值仅保留本机、无非样本/gap 记录；锁屏段新增 23 个样本；杀进程后新 PID 恢复并新增 9 个样本，最大样本间隔约 7.87 秒。当前 19:54 候选已另行完成正式锁屏 30 分钟 Gate，不能把两组候选的样本拼接计算。
- 能力探测：累计超过 400 个样本，`rrSeen=false`、`contactSupported=false`，未观察到 energy；因此只把本设备视为实时 BPM 来源，不据此推断离腕、清醒或睡眠。
- 失败项：三星任务移除触发 MARs 整包 force-stop 后，心率服务没有存活；用户重新打开 App 后也不会按 enabled 配置自动恢复。该项不是离腕或 BLE 正常休眠，必须作为恢复链路缺口处理。
- 离腕/复戴：用户确认实际摘下且绿灯熄灭后，最后样本停在 18:30:16.830（健康数值仅保留本机），未继续伪造 BPM；约 17 秒进入 `stale`，约 62 秒写入 `disconnected / sample_timeout_reconnect`，服务持续存活。复戴且绿灯亮后无需打开 App 或重新选择设备；因当时退避已达 300 秒，18:47:50 到期后约 2.1 秒自动恢复，第一条新样本为 18:47:52.509（健康数值仅保留本机）。恢复正确，但最坏 5 分钟等待需后续产品判断。
- 蓝牙切换：当前 19:54 候选在 20:07:10 关闭蓝牙后约 0.8 秒写 `bluetoothOff / adapter_off`，服务未退出；20:08:06 重开后约 3.43 秒自动恢复实时 BPM，无需打开 App。
- 重启：首次在 `RUN_ANY_IN_BACKGROUND=ignore` 时，本包全部 boot receiver 被 `mBroadcastConsumerSkip` 且冷启动 App 不自愈；解除后台限制后，同一候选、未打开 App 的第二次重启正常投递 receiver 并自动恢复前台服务。重启前 20:29:57.596 到开机后 20:32:55.139 形成约 177.543 秒真实缺口，第一条新样本距 receiver 开始约 2.05 秒；本项在“不受限制 + 三星永不休眠”前置条件下通过。
- 锁屏 30 分钟：正式窗口为 22:06:13.706–22:36:13.706，屏幕全程 `Dozing / DOZE`；1,796 个样本，首尾距离窗口边界分别为 0.045 秒和 0.132 秒，最大间隔 9.818 秒，无 status/gap 事件。期间 Android System WebView 更新于 22:18:39.305 杀死 PID `13975`，服务在 22:18:41.071 以 PID `17074` 自动重建并继续采样；本项通过。
- Gate 前复戴异常与返修：离腕发生在 19:54 候选正式锁屏窗口之前，不作为锁屏失败；复戴后出现“服务/PID 存活、持久 retry 已过期、内存重试不再执行”的停滞。23:14 新候选已以 generation/due 协调器、主线程 GATT 状态收敛、仅终止边界取消及持久 deadline overdue 自愈修复这条设计链，并用 `7/7` 协调器测试钉住；但确切离腕→复戴停滞尚未在新候选上刻意复现，不能把代码/单测写成该真机场景已通过。
- 新候选快速 Gate 与长测起点：23:16:12.868–23:19:15.558 全程锁屏 Dozing；十次轮询均 live，JSONL 精确窗口内 183 个 sample，最大间隔 1.263 秒，健康数值仅保留本机，零 status/gap。23:27 设备侧读到电量 100% 且仍为 USB powered；随后用户明确确认已拔线，但因 ADB 不可见，未实时复核 `USB powered=false`、拔线后的 fresh sample、Service 或 power 状态。正式 8 小时 Gate 因此以 23:41:50.186 为保守起点、以次日 07:41:50.186 为最早结束点，电量起点只能记为“拔线前最近一次设备读数 100%”，不能冒充拔线瞬间设备读数。今晚保持锁屏正常佩戴，不重启、不打开或划掉 App、不做离腕复戴。
- 2026-09-10 当前哈希长测起点：00:28:55.476 设备侧读到 91%、USB powered、Awake、BLE FGS 存活与 3.1 秒内 fresh sample；62 秒预检记录持续增长。Lynx 随后确认已拔线并锁屏，ADB 已不可见，故保守正式窗口为 00:30:44.302–08:30:44.302。用户确认不能替代设备侧 `powered=false` / screen-off / Doze / fresh sample 证据；晨间必须先接线且不开 App，由 BatteryStats 与跨午夜 app-private JSONL 回溯校准。
- 2026-09-10 当前哈希整夜结果：正式窗口内 28,870 个 sample，首样本 00:30:45.044、末样本 08:30:43.881，首尾距边界 742 / 421ms；健康数值仅保留本机，最大间隔 4.872 秒（07:58:17.728→07:58:22.600），零 `>15s` gap、零 status/gap、零坏行。原始文件顺序无倒退时间戳，14 对同毫秒相邻记录中 10 对内容完全重复，作为数据去重质量项保留，不阻断连续性 Gate。
- 2026-09-10 当前哈希后台与电量结果：BatteryStats 在 00:30:07.305 记录 92%、`discharging / plug=none`，00:30:11.565 熄屏，00:32:12.055 进入 full idle；正式窗内无完整 `+screen`、无接电/充电，08:15 的 screen-doze 仅是低功耗显示状态。08:42 后才完整亮屏并接电。正式终点附近电量为 36%；电荷计数差约 2031 mAh / 7 小时 56 分只代表整机，不能归因 BLE。晨间包哈希一致、BLE FGS 存活、快照 fresh live（健康数值仅保留本机），故本候选自然佩戴零大缺口 8 小时严格连续性 PASS，但不判产品电量预算通过。
- 整夜结果：BatteryStats 记录 23:36:26.081 实际拔线 100%、23:36:56.862 熄屏；正式窗口内零屏幕亮起。23:41:50.186–07:41:50.186 共 28,494 个 sample，首尾距边界 565 / 644ms，跨午夜 JSONL 零坏行。07:09:54.861→07:15:58.017 出现唯一大于 15 秒的 363.156 秒 gap，并写入 `gatt_status_8` 与 `connect_watchdog_timeout`；服务在未打开 App 的情况下自行恢复并持续 live。分项结论：锁屏 8 小时耐久 PASS、本次故障自动恢复 PASS、日志日切与显式缺口记录 PASS、严格连续性 FAIL。
- 电量结果：正式 8 小时 100%→84% 仍只代表组合负载；后续隔离 B–A–B 的 B1/A/B2 分别为 `254.7 / 131.8 / 211.2 mAh/h`，B1/B2 差异 17.1% 通过预设复现阈值，B 平均相对 A 高约 `101.1 mAh/h`。因此 BLE gateway 相关整机增量工程 Gate 通过，但不可写成纯射频功耗、同二进制精密标定或产品预算 PASS。
- 最终候选快速结果：启动后真实 COROS 连接写入 `connect_watchdog_alarm_exact_allow_idle`，首样本到达后对应 Alarm 已取消。11:33:54.989 起 189.783 秒有 187 个 sample、健康数值仅保留本机、最大间隔 1.456 秒、零 status/gap。计划的 3 分钟锁屏在真实熄屏 53.497 秒后被设备 `MOTION` 唤醒；该子段 54 个 sample、最大间隔 1.094 秒，只算部分熄屏证据，不算 3 分钟 Gate 通过。
- 最终候选受控故障结果：12:06:32–12:15:50 手机保持锁屏，故障与恢复关键段保持 `mForceIdle=true / mState=IDLE / mWakefulness=Dozing`；九次 Alarm / Receiver / timeout 毫秒级对应，物理复戴后自动恢复并清除 plan / pending Alarm。结束后已执行 `deviceidle unforce`，屏幕仍锁定，未打开 App、未手动启动 Service、未切蓝牙。
- 省电微调候选短测：22:53:19.893–23:25:07.832 共 31.799 分钟，起终点均断电且 Dozing，1,913 samples、0 status/gap、max gap 1.881s；`216.7 mAh/h` 与 B2 `211.2 mAh/h` 接近。当前只证明两项微调未破坏连续性，未证明耗电下降；后续若继续优化，按新哈希分别测试 snapshot 持久化降频与无订阅主线程转发停用。
- 未完事项：自然佩戴零大 gap 的 8 小时严格连续性 Gate 已关闭。仍需把“不受限制 + 三星永不休眠”固化为安装/诊断引导，补冷启动自愈、过期 raw `live` 快照纠正、receiver/FGS 分段诊断和任务移除/MARs 策略，并决定复戴时是否打断最长 300 秒退避；14 对同毫秒记录另列日志去重质量项。电量下一步是定义产品预算并分解 gateway 内连接/通知/CPU/wakelock/日志成本。睡眠判断、主动介入与 1 年 Health Vault 仍属后续 Goal；当前仍不得写成整套 COROS Gate 完成。

## Goal 结论

- 完成时间：2026-09-10（COROS 实时心率接收 v1，含当前精确候选自然佩戴零大缺口 8 小时 Gate）。
- 已提交初始基线：`v3-lab@fd2a48b7`；本次收口提交包含后续重连、Doze watchdog、通知/快照降频和最终验收记录。
- push：未授权。
- 后续工作：三星任务移除/MARs 恢复与产品电量预算；长期 Health Vault；融合多设备活动与床上体动信号的保守清醒概率状态机。
