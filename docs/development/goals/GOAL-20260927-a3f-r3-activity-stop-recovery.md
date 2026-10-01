# GOAL-20260927-a3f-r3-activity-stop-recovery — A3F-R3 停止状态同步与孤立 owner 受控释放

> **2026-10-01 主 worktree 落点**：F2 最终候选的 26 个受控源码、测试和脚本路径现已在 `v3-lab@b2adc44b` 主工作树逐 SHA-256 同哈希；本轮仅补齐早期集成之外的 6 个时序差异路径，主树定向 Flutter 95/95 与相关 Dart analyze 通过。F2 APK 与下述真人 Gate 仍绑定原候选哈希；未重新构建/安装，未 commit/push/发布。详见 [当前项目状态](../I_PROJECT_STATE.md)。

> **2026-09-30 Goal 完成**：F2 同哈希 H0–H6 真人/受控设备 Gate 经独立终审通过。H0 通知目测、锁解与查询；H1 通知自身停止、同钟 native→页面收敛及刷新；H3 双源释放；H4 活锁拒绝和 Debug 残留同页显式无损释放；H5 不自启与非空恢复门；H2 为同 APK 受控真机注入和严格时序，不冒称 OEM 复现。首次 H4 因 W0 误触 Home 安全拒绝，不计正例；显式清理后重做成功。正式 E1 完整哈希恢复，BLE 前台 id 6157、Activity 缺席、13 项元数据延时稳定。重复按钮/停后查询及 FD/GATT 限制见 [F2 真人 Gate](../activity/mda2/android/a3f_r3/F2_HUMAN_GATE_20260930.md)，独审本机 `tmp/a3f-r3-human-f2/INDEPENDENT_REVIEW.md`。下方各“待验”段落保留历史现场。无 commit/push/publish。

> 2026-09-29 现场：同一F2包已重新安装，安装前E1正式hash及BLE前台、13项元数据通过预检；上轮证据封存后显式清理诊断outbox。用户已亲眼确认“活动观察正在运行”持续通知；实读Activity和BLE均前台、两个owner存在，通知目测子项通过。短锁解及查询仍待用户回执，故H0整体未通过；H4/H5及最终正式E1恢复待续。F2仍装在手机，当前Activity运行、BLE未受影响。无commit/push。收据本地`tmp/a3f-r3-human-f2/prepare-receipt.json`、`human-running.json`。下方F2已通过的自动时序及其正式恢复是上一现场。

> 2026-09-29 F2 最新：`0AC428177247F757BA21C95B734A6121610D87735071BFC08E1A377C39324911` 的三份完整真机 trace 中，手动刷新、返回前台、受控失证的无有效回复→unknown 分别为 2,524,287 / 2,504,994（从更早 action 起算）/ 2,506,085µs，均满足严格 3,000,000µs。旧 running 真回执在同代 stopped 后被 terminal 守卫拒绝，有限尾段无 ready 回弹；通知自身停止按钮实际点击，返前台立即核对并保持 stopped。F2 已显式释放 owner，正式 E1 包与原绑定 BLE 前台恢复并隔时复核；FD 枚举非穷尽。独审限已覆盖范围 GO；F2 同哈希真人 H0/H4/H5 等完整 Gate 仍待收口，**Goal 开放**，无 commit/push。详见[自动时序补验](../activity/mda2/android/a3f_r3/AUTOMATED_TIMING_GATE.md)及本地 `tmp/a3f-r3-timing-device-f2/DEVICE_RESULT_F2.md`、`INDEPENDENT_REVIEW.md`。下方 F1 状态为历史。

> 状态：9A099611旧包H1/H2同步上界775/515ms独审接受。新Debug APK `F1D3431A92A3A7C6EC569033C488BD2246F45F855306B341F7278441BF70AF70`在实机完成三条封口时序：checking逻辑顺序通过，受控失证后旧running回复实际交付并由terminal守卫拒绝、有限尾段无ready回弹；但manual/resume/受控场景的unknown发布分别为3,026,775/3,007,425/3,004,019µs，均超过严格3秒，**本候选整体RED**。通知按钮自动定位失败不算通过。两owner/FD释放后恢复实际E1正式包hash；BLE前台6157/Bluetooth1、Activity缺席及13项元数据不变已两次隔时核对，调试转发清理。内部时限返修中，Goal未完成，无commit/push。详见[自动时序补验](../activity/mda2/android/a3f_r3/AUTOMATED_TIMING_GATE.md)及本地`tmp/a3f-r3-timing-device/DEVICE_RESULT_F1.md`。
> 验收主窗：`01a0e1b1-9716-7e31-9a2f-bc4d7df958e8`。
> 基线：`v3-lab@b2adc44b7c04983a931c39695b81491cd295084b`。
> 提出日期：2026-09-27；确认日期：2026-09-27（“可以，开始派发吧”）。
> 上位路线：[MDA Roadmap](../../companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md) 的 MDA-2 / A3-F 限定诊断线。
> 流程：[协作执行协议](../COLLABORATION_EXECUTION_PROTOCOL.md)。本候选不替代 P6 / Goal 1，也不宣告 MDA-2 整体通过。

## 1. 进入依据

### 2026-09-28 自动时序补验授权

用户已授权先完成可独立执行的补验工作，并明确区分真人关机重启与自动化时序验证。据此仅将剩余时序项改为W0自动操作同一诊断候选并采样；已完成真人功能记录保留，自动结果如实标注，不冒称真人操作。允许在当前设备可达、无需凭据解锁的条件下执行诊断控件的显式清理/开始/失证注入/停止释放、通知自身停止按钮及返页导航；保持既有APK/权限/蓝牙/绑定边界，结束恢复原正式包及已授权原绑定BLE。失败不盲重装、不放宽3秒定义，不唤醒用户反复配合工具排查。

此段记载当时9A同包只读取证方案；该方案不能证明剩余状态赋值与旧回复实际拒绝，后续在同一Goal范围内改用单独Debug候选的[最小验证支持](../activity/mda2/android/a3f_r3/DEBUG_TIMING_PROBE_PLAN.md)。不新增产品功能或自动采集入口，不改变fail-closed、持续通知、隔离和保留记录的要求；单个测量段仅绑定一个真实观察代，跨代不能混算时限。

权威设备结论是基线中的 [R2 最终设备 Gate](../activity/mda2/android/a3f_r2_review/W0_ACCEPTANCE_AND_DEVICE_GATE.md)「2026-09-27 最终设备结果」。其后保留的旧“待验”段落是历史记录，不能覆盖该最终结果。

- R2 诊断 APK `EACA6DFA0E7E5AEB15C41259EE6F17226014BDB96CC195FFF20BB389ADD6C384` 在 SM-S9110 / Android 16 上完成启动、可见持续通知、锁解三事件、提取、显式停止和 BLE 隔离 Gate。
- 一次三星 SystemUI `SwipedOut: true / REASON_CANCEL_ALL` 后，Activity 按通知连续性门停止，但页面仍 `ready`，普通停止未能释放旧 owner。用户未主动清除；对照锁解及查询不能复现，原因保持未知。
- 最后已恢复正式 APK `E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37`，设备 base hash 一致、冷启动成功、Activity 诊断服务不存在、BLE 存在、Bluetooth=1。
- 本轮只读核对确认当前 HEAD 与上述基线相同；相关 Activity 源码、测试及 R2 Gate 无工作树差异。其他并行改动保留，后续不可从主目录脏工作树直接构建。

源码缺口已交叉核对：原生 Service 停止后没有独立终态推送；Channel 已有 `getReadiness`，Dart 尚未接入；页面“刷新”仅重算本地快照。collector 的停用/关闭异常目前可能只记 audit 后清引用，页面不能据此证明 owner 已释放。这些是源码事实，不把现场残留的精确成因当作已复现。

## 2. Goal 与完成定义

**Goal：在默认关闭的 hereIAmV3 Debug Activity 诊断中，服务从页面之外停止或因连续性失证停止后，页面可靠退出旧的 ready；用户可显式停止并无损释放自己持有的 owner，或在严格验证后受控释放孤立 owner。未知、失败和部分完成如实呈现，恢复采集仍受既有显式 opt-in 与持续通知门约束。**

- [x] 前台终态同步、进入/恢复页面、手动刷新及查询前复核均使用当前原生状态；旧缓存和迟到回执不能恢复 ready。
- [x] 服务运行、服务停止、状态未知、owner 待释放/释放失败在逻辑上分开；服务已停不等于资源释放成功。
- [x] 普通停止先使本代采集与回执失效，确认服务终态，再关闭本代持有的两 source store；失败保留可重试依据，不吞错宣称成功。
- [x] 孤立 owner 只能由独立、显式的诊断释放动作处理；精确权威验证、OS gate 与并发复核全部成立才成功，重复操作不碰后继 owner。
- [x] 释放不清空 outbox、不删除 key、不重置 sequence、不补写历史，不自动启动。非空 outbox 的既有恢复门保持。
- [x] 下述自动矩阵、独立审计、唯一候选构建及本轮真人 Gate 全部取得各自证据；新 hash 不继承旧设备结论。
- [x] 正式包恢复、状态页、DEVLOG、handoff 与 i closeout 完成，才可关闭此 Goal。

**已冻结同步时限**：页面处于可执行前台时，从“原生确认本代终止”到页面退出 ready 不超过 3 秒。resume/刷新立即进入核对状态，3 秒内无法取得有效状态即显示 unknown/待核实；不能无限显示旧 ready。后台被冻结期间不计 UI 时限，返回前台重新计时。记录通知丢失、原生发现、页面收敛三个时点；不把这 3 秒解释为 R2 通知丢失检测时限，也不改变其现有查询节奏。具体接口见 [W0 控制合同](../activity/mda2/android/a3f_r3/W0_CONTROL_CONTRACT.md)。

## 3. 保留契约与不做事项

1. **fail-closed**：通知、前台服务、AppOps、boot/epoch 或身份连续性失证即停止接受有效事件；unknown/gap 不得显示为 quiet、active 或 asleep。
2. **显式 opt-in**：状态订阅、刷新、resume、释放 owner 均不得 provision key、创建新采集 epoch、查询 UsageEvents、分配事件 sequence 或调用 start。状态查询只读。
3. **持续通知**：保留 R2 启动确认、单调 10 秒 deadline、100ms 异步确认及 token/instance/generation 隔离；通知/FGS 未确认前仍禁止 epoch、receiver、UsageEvents 和 active=true。
4. **BLE 隔离**：不复用、不修改、不启停 BLE/Companion/check-in 的 service、通知、owner 或恢复路径；设备用例只针对 Activity，禁止用全包 force-stop 或清全部通知冒充隔离停止。
5. 正常 `main.dart`、router/settings/DI、Manifest、Gradle/依赖、Core/broker、共享 wire/schema、持久 outbox schema、生产入口与传输不变。可最小补本地 MethodChannel 状态合同，不能借此扩展共享协议。
6. 不调查或修复三星单次 CANCEL_ALL 根因；不新增自动重启、后台自启、无损重新打开既有队列、整夜采集或睡眠推断。不把 OEM/权限撤回/进程死亡/重启/耗电等全部历史矩阵纳入本轮或写为通过。
7. 不把现有“清理本次诊断状态”（会删除诊断 outbox）当作普通停止或释放的内部实现。需要再次启动对照时，仍由用户分别显式执行现有清理与开始，不跳过非空目录恢复门。

## 4. W0 先冻结的最小合同

### 4.1 状态与迟到回执

- 区分进程内 startup owner、原生 epoch ownerFence/serviceInstance、Dart 签名 owner.json + 生命周期 OS gate，不能互相替代证明。
- 终态通知与主动读取使用同一严格白名单状态模型，至少表达 enabled、固定状态/原因、本代关联与顺序；具体字段由 W0 冻结。内部关联值不出现在用户证据、日志或导出中。
- 原生推送及时失效，resume/刷新/查询前读取兜底；前台缺推送时有有界的只读核对。通道异常、未知字段/码、过期状态一律 fail closed。
- 页面“核对中/未知”属于 UI 同步状态，与 native 固定 readiness 分开命名；不把本地超时伪装成原生停止原因，导出仍按白名单投影。
- 旧 start、query、onBatch、ack、旧页面与 detach 后回调不得改写新一代状态、再接受事件或关闭新一代服务。终止确认必须先封住本代交付门；不能用 `shutdownNow()` 或“停止请求已发送”代替证明。
- 只见 `live == null` 或超时可以判定“当前不可用”，不能据此宣称持久 owner 已安全释放或所有异步工作已结束。未知原因不猜测为用户停止。

### 4.2 无损释放与恢复门

- **本代仍持有 store**：优先复用正常 close，仅处理自己的 owner；停止失败、close 失败和两 source 部分成功分别返回，不能无条件丢失引用并报告完成。停止采集按钮和释放动作的可用性分开，不能因 active=false 隐藏待释放资源。
- **孤立 store**：只覆盖 native 提供的 no-backup 诊断根及既有两个固定 source；显式动作绑定精确 source/binding/owner/anchor。复用 signed inspection + recovery authority + 稳定 OS gate，持有独占 gate 后再次核对身份和 anchor，直至释放结束。
- 活跃或启动中不能按孤立状态回收；未知终态、gate 被占用、签名/绑定/anchor 不符、路径/结构不符、损坏、读写/删除失败均拒绝成功。两个恢复者、恢复期间的新 start、owner 替换必须被现有所有权门或最小本地控制门串行隔离，禁止 check-then-delete。
- 只移除经验证的目标 owner 并释放相应租约，保留诊断事件、state/anchor/journal、sequence 与失败证据；不得轮换 key、删除 root 或用空目录掩盖故障。若复用 open/close 会修改其他持久内容，先证明可保持上述语义，否则使用更窄的释放路径。
- 对同一已释放目标重复操作可返回已完成；若已有 successor，返回目标已变化，不释放 successor。部分失败保留逐 source 结果，重试不能重新处理已换代目标。
- **释放完成不等于可直接重新开始**：基线初始化对非空目录仍返回 `recovery_authority_required`。R3 保留此门；若将来要求保留队列直接续开，另立范围决定。

### 4.3 真人触发方案先行

W0 冻结合同时一并确定 H2/H4 的可控触发方式及拥有路径，优先复用既有设施；不能留到构建后才确认硬 Gate 是否可执行。确需新增时，N 只拥有 Activity 原生侧的 Debug 限定触发，U 只拥有诊断 UI/本地合成残留入口，均须显式操作、绑定同一唯一候选且不进入正常产品入口。H2 必须经过真实连续性检查，直接调用 stop 或伪造停止回执不能代替；H4 合成残留同时建立原生终态已知、旧 OS lease 已释放的可核验证据，否则预期结果就是拒绝。触发方案不成立时先解决验收设计，其他独立只读/自动验证设计可继续。

## 5. 工作包与顺序

N/D/U 已在精确基线的独立 Worktree 开始。W0 冻结控制接口后，N/D 并行实现，U 先实现已接受接口下的窄释放与文件锁测试，再接 D 的完整 UI 接口；组合验证仍在依赖实际回收后串行。两份早先只读审计不算实现交付，worker 不再派生。

| 包 | 执行者/路由 | 拥有路径与交付 | 依赖/状态 |
|---|---|---|---|
| W0 / 合同与阶段验收 | 当前主窗，GPT-6 Astra，保持当前 effort | 本 Goal；本地状态合同、路径 manifest、验收表；串行共享文档和集成 | 活动；控制合同已冻结，验收触发路径已确定 |
| N / 原生终态与关联隔离 | `/root/r3_native_impl`；GPT-6 Astra / high | `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`、`channels/ActivitySignalChannelHandler.kt`（同 Kotlin package 根）、专用状态/进程租约 helper；对应 Kotlin 测试，必要最小 startup helper；N_HANDOFF | 已回收：74/74、镜像 hash、独审通过；六文件已汇入 W0 隔离树，设备待验 |
| D / Dart 状态与停止结果 | 初版 `/root/r3_dart_impl`；Terra / medium；由 `/root/r3_dart_finish` Astra / high 接管完成 | `lib/data/services/activity/mda2_android/android_activity_signal_platform.dart`、`android_activity_collector.dart`、`activity_outbox_process_lease.dart`；collector/platform 专项测试；D_HANDOFF | 已回收：55/55、定向 analyze 0、九文件镜像绑定、最终独审通过；六个 D 文件已汇入 W0 |
| U / 诊断 UI 与 owner 释放 | `/root/r3_ui_recovery_impl`；GPT-6 Astra / high | `lib/ui/a3d_device_gate/`、`file_activity_outbox_store.dart` 窄释放路径；`a3d_device_gate_test.dart`、`a3f_r3_owner_release_test.dart`；U_HANDOFF | 最终接受：历史成功标记 P2 已用真实 RED/30项 GREEN 闭环；8 输入与3日志绑定、独审通过，已汇入 W0 |
| V / 独立对抗复核 | `/root/r3_native_audit`，GPT-6 Astra / high | 只读候选 diff、关键断言、专项复验及自身 handoff；不改实现 | N/D/U 最终均接受；W0 181项组合收据/17输入及12改动构建输入绑定已独立核对 |
| W0 / 候选与真人 Gate | 当前主窗 | 已接受差异的串行本地集成、干净候选、唯一 APK/安装/恢复收据、最终状态 | 23路径已选择性集成；唯一APK构建/包名/签名通过；H0–H6待验 |

顺序：W0 合同 → N/D/U 不重叠路径实现 → 逐包复核及依赖接合 → V 对抗/组合 → W0 集成与唯一候选 → 真人 Gate → 正式包恢复与收口。实现 worker 无设备/真实数据/安装权限；3 个 worker。提交仍按后续明确授权执行，当前只交最小 diff + handoff；不附带 commit/push/publish。

| 包 | Worktree | 分支 / 基线 |
|---|---|---|
| N（已可恢复归档） | `C:/Users/ExampleUser/.codex/worktrees/a3f-r3-native/memex` | `codex/a3f-r3-native-20260927`；`b2adc44b`；源码/测试证据已保全 |
| D | `C:/Users/ExampleUser/.codex/worktrees/a3f-r3-dart/memex` | `codex/a3f-r3-dart-20260927`；`b2adc44b` |
| U | `C:/Users/ExampleUser/.codex/worktrees/a3f-r3-ui-recovery/memex` | `codex/a3f-r3-ui-recovery-20260927`；`b2adc44b` |
| W0 组合验证 | `C:/Users/ExampleUser/.codex/worktrees/a3f-r3-w0-integration/memex` | `codex/a3f-r3-w0-integration-20260927`；`b2adc44b`，N/D/U 已汇入；原生77/77，完整Flutter181/181，分析/范围检查通过 |

执行中安全细化：Android/Dart 同进程文件锁不能排除另一 FD 的访问，N/D/U 在既有 OS gate 前补专用全进程 lease broker，覆盖 create/open/reset/release，禁止 detach 自动释放。此为受控释放的必要互斥，不改持久 schema/数据范围。H2 采用 Debug 当前代通知可见性失证注入并走真实连续性检查；H4 采用同代正常 close 的单次 owner 删除失败注入，保留原字节、分别证明句柄/进程租约释放，随后用户显式窄释放。详见 W0 合同；不声称 OEM 复现。

执行环境恢复：C 盘曾耗尽，全部 worker 停止修改并运行 doctor；D 未验收 collector 写入被截断，已保存可恢复初版，由接管者重建并重新验证。N 已完成且无在用进程，其六个已审文件保全于 W0，344 个测试镜像文件复制到本轮 D 盘证据目录并逐 hash 校验后，用应用工具可恢复归档 N 工作树。其他工作树与共享缓存未删除；后续测试临时输出改用 D 盘。此环境故障不记作模型配额或产品测试失败。

handoff 保存精确基线、实际 task ID、分支/Worktree、拥有路径、diff/获授权的 commit、测试命令与实际退出码、失败历史、限制。主窗保留原并行改动指纹，不覆盖共享文档；需要新基线时明确记录来源，不自行 pull。

## 6. 验证矩阵草案

以下是要求矩阵，结果分层记在 [W0 验证与设备 Gate](../activity/mda2/android/a3f_r3/W0_ACCEPTANCE_AND_DEVICE_GATE.md)。N 最终77/77、完整Flutter组合181/181，源码/测试分析与范围检查通过；N/D/U及最终组合证据独审已接受。分包数量不与组合重复相加；6项原生源码守门不当行为证据，Windows文件锁不当Android机制证据。真人 H0–H6 均未执行，R2 数量不计入 R3。

| 编号/层级 | 场景 | 必须证明 |
|---|---|---|
| A1 / 原生 | 通知连续性失败、通知停止按钮、service destroy、启动中取消 | 终态与原因一致；本代交付已封闭；旧 epoch 不再接受；无 BLE 调用 |
| A2 / 原生与 Dart | stop 与启动成功/query/onBatch/ack/detach 重排；旧状态晚于新 start | 代际隔离，旧回执不恢复 ready、不写新 sequence、不停止 successor |
| A3 / Dart/UI | 前台推送、无推送兜底、resume、刷新、查询前核对 | active 与页面证据收敛；3 秒超时降级；同步本身零采集副作用 |
| A4 / Dart/UI | 状态缺失、坏类型、未知码、超时、桥接断开 | unknown/待恢复；不缓存 ready，不把 unavailable 当已释放 |
| A5 / 停止链 | native stop 失败、owner close 删除失败、双 source 部分失败 | 不吞错；保留固定失败与可重试对象；仅全部证实才报告完成 |
| A6 / owner 正例 | 自持 owner 正常 close；已证实停止后合法孤立 owner 显式释放；重复释放 | 仅目标 owner，保留数据/sequence/key；无自动 start；重复幂等 |
| A7 / owner 反例 | 活锁、启动中、未知、签名/绑定/anchor 错、损坏、结构/路径异常 | 拒绝释放，原证据保持；OS gate 用实际文件锁验证，不能只 mock boolean |
| A8 / owner 竞态 | 双恢复者、inspection 后替换、新 start、旧操作碰 successor、部分失败重试 | gate 内二次比对；无越代删除；逐 source 结果真实 |
| A9 / 保留恢复门 | 非空 outbox、释放后刷新/重进页面、再次开始 | 无自动清理/续开；非空目录仍按既有恢复门拒绝；新 start 仍须显式动作 |
| A10 / R2 回归 | 10 秒启动确认、100ms 异步检查、未确认零采集、迟到成功反例 | R2 fail-closed 与 opt-in/通知前置条件保持 |
| A11 / 静态与隐私 | 变更路径、默认入口、白名单证据、BLE/Core/wire/schema 保护区 | 保护区零 diff；package/app/raw/path/key/token/异常正文不进入展示/导出 |
| A12 / 组合 | Activity Kotlin、A3 collector/platform、A3-D UI、A2 owner 对抗专项 | 各层真实计数/exit；源码字符串守门与真正行为/文件锁测试分开 |
| A13 / 候选 | 定向 analyze、diff/static、critical fixes、唯一 hereIAmV3 debug 构建 | 固定源码/依赖/JNI 输入和 APK hash；任何前置失败不进入设备 Gate |

复用既有 `test/data/services/activity/mda2_android/verify_a3_android.ps1`、`verify_a3_flutter.ps1`、`verify_a3d_flutter.ps1`、A3-F/R2 静态守门及对应 Dart 测试；必要时补 R3 的精确路径守门，由 W0 串行拥有共享脚本。镜像测试须绑定候选字节。实际 App 源集单元任务与镜像结果分别记录；已有源文本断言不冒充 Android 生命周期注入。

通过专项后按实际边界运行相邻回归，不为了形式重复全仓。每次 Flutter build 前执行 `scripts/verify_critical_fixes.ps1`；最终入口仍是 `lib/a3d_device_gate_main.dart`，flavor `hereIAmV3`，包名 `com.memexlab.hereiam.v3`。

## 7. 真人 Gate 草案

安装/设备操作在候选冻结后的真人阶段由 W0 统一进行，保留用户在场和物理安装授权。当前尚未接触设备。安装前核对当时真实正式包，不把 R2 恢复记录当作设备现在未变化的证明；保存可回退 APK。安装后 device base hash 必须等于唯一候选；签名/hash/权限异常停止。

| Gate | 操作与观察 | 通过标准 |
|---|---|---|
| H0 / 初态及 R2 保持 | 同一候选冷启动；先观察，再由用户开始；确认通知人眼可见，短锁解及查询 | 未开始零采集；开始后 service/FGS/通知一致；三事件 occurrence/delivery 保持，BLE 基线记录 |
| H1 / 页面外停止 | 不点页面停止，用户点 Activity 自己通知上的停止入口；前台观察并分别覆盖后台返回、刷新/查询 | 原生终态后页面按时退出 ready；不存在旧 ready 回弹；Activity 通知消失，BLE service/通知与 Bluetooth 不因本动作改变 |
| H2 / 连续性失证 | 使用预先复核、只作用于 Activity 的单通知移除/等价 Debug 故障路径，记录是否为注入 | 真正经过通知连续性 fail-closed，再验证状态同步；不清全部通知、不改权限、不 force-stop 全包。若没有安全且可验证的触发方式，本项保持待验；通知停止按钮不能代填此项，也不声称复现三星原事件 |
| H3 / 普通停止与释放 | 外部终止后点击页面停止/释放本次资源；重复同一操作；核对两 source 状态 | native 终态、两个 owner 释放分别有证据；无损、幂等；失败如实显示，不要求先清空诊断数据 |
| H4 / 孤立 owner | 使用已确认的真实残留或明确标注的 Debug 本地合成残留；先展示待恢复，再显式释放；另作持锁拒绝负例 | exact owner/签名/gate 通过才释放；活锁拒绝；保留数据、key、sequence。注入只证明受控恢复路径，不能冒称现场事故重现 |
| H5 / 不自启与再验证 | 释放后刷新、离开/重入，观察无自启。若需再次开始，由用户分别执行现有清理及新开始，再锁解/提取 | 释放不等于续开；非空目录门不绕过；明确开始后才新 epoch，不补停止期间历史；通知及 BLE 隔离再次实读 |
| H6 / 收尾 | 用户显式停止，恢复安装前确认的正式 APK，核对 base hash、冷启动、Activity/BLE/Bluetooth | 正式包恢复证据齐全，Activity 诊断未运行；不清完整 App 数据，不遗留未说明 owner 或注入状态 |

每项收据：唯一源码候选/获授权的 commit、APK SHA-256、设备/OEM版本、触发路径与是否注入、关键时点、页面固定状态/两 source 释放结果、service/通知/BLE 对照、用户原样确认及限制。原始本机诊断材料不提交；交接只写脱敏结论与相对证据路径。

H2/H4 无法完成时不能标 Goal 完成；先保留自动与已完成设备结果，解决可控触发或由用户另行裁决验收范围。任何身份不明、越代释放、丢数据、旧 ready 复活、无通知采集或 BLE 联动均返修；新候选 hash 重新执行本轮受影响且必要的完整设备 Gate，不拼接旧候选为通过。

## 8. 执行状态与下一步

- 已完成：R2 最终 Gate/精确基线复核、用户确认、活动 Goal 创建、三个隔离 Worktree/包派发、W0 状态/停止/租约合同和 H2/H4 触发方案冻结。
- 已回收：N 原包与 W0 幂等修正、D/U 最终差异及独审，W0 完整组合181/181与分析/范围检查。最终构建输入1223项冻结，JNI188项另绑定。
- 构建完成：首轮插件注册缺失失败，第二轮JNI共享缓存`.cxx`写入失败，收据均保留。现有Flutter SDK补生成注册，冻结JNI188输入原字节隔离；独审确认337包配置仅JNI路径变化，pubspec/lock及源码未变。第三次critical3/3、构建exit0（94.079秒），包名和签名通过。
- 唯一候选：`A3F-R3-b2adc44b-8b718af5`，APK SHA-256 `854F341E108733464A351AAB267A14563033A4CCC6CB0A715862860EDBAD8658`，384776581字节。详见[清单](../activity/mda2/android/a3f_r3/CANDIDATE_MANIFEST.json)。
- 本地集成：23个源码/测试/脚本路径及handoff已进入`v3-lab`工作树，未提交；原59项并行改动逐项保护，主窗仅追加自身全局状态/DEVLOG。
- 未执行：安装、设备操作、H0–H6；已向用户请求手机在场与物理安装确认，尚未收到。无commit/push/publish。全部真人Gate及正式包恢复收口前不能完成Goal。
- 阻塞审计：同一手机在场/物理授权前置条件已连续出现于实现交付回合及随后两次Goal续跑。上一回合补齐本地回退预检和真实按钮操作卡，属于实际进展；当前独立工程准备已完成，没有可替代真人的必要动作。复核APK仍存在且hash匹配、H0–H6仍待验后，Goal工具已返回`blocked`。用户确认在场并继续后，从核对/保全设备当前正式包开始；自动续跑不充当授权。

只读审计回收：`/root/r3_native_audit`（Astra/high）与 `/root/r3_ui_audit`（Terra/medium）；均按基线 Git 字节读取、无修改、无测试/设备操作。主窗已复核关键实现行与差异边界，未直接采用“释放后即可重新开始”等超出当前源码保证的建议。
