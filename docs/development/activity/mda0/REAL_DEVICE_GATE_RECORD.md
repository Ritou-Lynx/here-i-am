# MDA-0 真人设备 Gate 记录表

> 状态：**等待 Lynx 操作**。本表只记录人工选择与观测，不授权构建、安装、Tailscale/计划任务变更、生产 ingress、真实凭据落盘、commit、push 或发布。
>
> 隐私：不得填写 URL、token、设备序列号、窗口/App 原名、消息/通知正文、联系人或逐搏心率值。截图如包含上述内容，先脱敏且不要提交仓库。

## 0. 产品选择 Gate

### D-1 保留期限

- [ ] 接受 proposed 默认：raw event `7 天`、device spool `24 小时`、BLE raw `14 天`
- [x] 修改为：raw event `1 天`；device spool `1 天`；BLE raw `1 天`；最小诊断日志 `1 天`
- 决定日期：`2026-08-30`
- 备注（不得含私人正文）：`所有逐条原始活动/心率数据只滚动保留 1 天；Windows Core 离线超过 1 天时旧离线事件允许到期、不补造历史。实时心率 snapshot 只保留当前 fresh 值，不形成历史。经过约束的机器摘要/结论可长期保留至用户删除；用户明确确认的结论进入 User-truth，遵循其独立生命周期。现有 COROS App 实际仍保留 JSONL 14 天，属于待实现差距，本次选择没有修改设备或代码。`

### D-2 夜间中枢

- [x] A — Windows 插电、登录且不睡眠；显示器可关闭（已选 MVP）
- [ ] B — 私人常在线节点
- [ ] C — 短期加密中继
- [ ] D — 主 Android 本机降级；不承诺跨端汇总
- 未选择时结论：远端夜间能力保持 `unknown` / `unsupported`
- 决定日期与限制：`2026-08-30；接受 Windows 睡眠、关机、注销、任务或网络故障时 Core 不可达，远端活动必须降为 unknown，不把沉默解释成人的状态`

### D-3 iPhone ingress

- [x] 1 — Tailscale iOS tailnet HTTPS，待安全入口获批后验证
- [ ] 2 — 受保护 ingress，待单独安全设计与授权
- [ ] 移出当前 MVP
- [ ] 暂不选择；保持 `unsupported`
- 决定日期与限制：`2026-08-30；Lynx 已下载并登录 Tailscale。第一次 online 后 11:16 曾因 Lynx 手动连接状态而离线；Lynx 重新连接后，Windows 复核为 Tailscale Running、1 个 iOS peer online，脱敏 Tailscale ping 成功。现有 Serve 有 4 个 root loopback proxy、无 Funnel；其中 1 个本机 proxy 的 /v1/core/health 为 iCore authority，但 4 个 tailnet HTTPS health 自检均未成功。尚无获批 activity ingress/write-only 凭据。peer/ping 只算 network.present，不算活动证据`

### D-4 最小采集边界

- [x] 确认默认不采集窗口标题、App 原名、按键、URL、屏幕/通知/聊天正文
- [x] 确认 `network.present`、Core health、App heartbeat、无连续 coverage 的沉默、无回复和单一心率都不能证明清醒、安静或睡眠
- 审阅备注：`Lynx 于 2026-08-30 明确确认上述两条。该确认不授权新增采集器、权限、schema、ingress、凭据、推断、通知或主动介入。`

## 1. COROS 真实硬件 Gate

### C-0 候选身份

- 测试日期：`2026-08-29`
- Here I am V3 已安装候选版本/构建标识：`1.0.30 (113)`
- 主 Android 型号与系统版本：`Samsung SM-S9110 / Android 16 (API 36)`
- COROS 型号/固件版本：`COROS 光学心率臂带；具体设备标识仅保留本机，型号/固件待确认`
- [x] 确认复用当前候选，未重建、未换包
- [x] ADB 检测到一台已授权主 Android；设备未离线
- [x] 系统报告蓝牙扫描、蓝牙连接与通知权限已授予

### C-1 短时字段探测

在 App 内显式扫描并选择设备，不把系统配对当成前置条件。只记录字段是否出现，不记录具体逐搏数值。

| 项目 | observed | absent | unknown | 备注 |
|---|---:|---:|---:|---|
| 标准 HRS 设备可扫描/选择 | [x] | [ ] | [ ] | `0x180D；首次 RSSI -53 dBm；已选择 D57F7F` |
| BPM 字段 | [x] | [ ] | [ ] | `72 秒子窗口收到 73 个有效样本；健康数值仅保留本机，非全文件聚合结果` |
| contact support/status | [ ] | [x] | [ ] | `截至 18:16:15 累计 764 样本均未声明 contact supported` |
| RR interval | [ ] | [x] | [ ] | `截至 18:16:15 累计 764 样本均无 RR` |
| energy expended | [ ] | [x] | [ ] | `截至 18:16:15 累计 764 样本均无 energy` |
| 首个样本延迟 | — | — | — | `____ 秒` |

完整性说明：主窗只读复核 App 私有 JSONL：检查点累计有 1 个文件、764 个 sample、0 个 status；RR/contact-supported/energy 出现次数均为 0。全文件聚合与短子窗口范围不同，不能互相覆盖；健康数值及原始采样记录仅保留本机。直接 kill 子测试最大 gap 约 7.87 秒；之后 MARs force-stop 到手动启动形成约 251.307 秒缺口，但 JSONL 没有独立 status/gap 行。

### C-2 19:54 历史候选锁屏 30 分钟预检

- 正式窗口：`2026-08-29 22:06:13.706–22:36:13.706`；屏幕全程 `Dozing / DOZE`。
- 样本：`1,796`；首样本 `22:06:13.751`（距起点 0.045 秒），末样本 `22:36:13.574`（距终点 0.132 秒）；最大间隔 `9.818 秒`。
- status/gap：`0`；窗口未跨越 15 秒 stale 阈值，也未补造样本。
- 真实进程死亡恢复：`22:18:39.305` Android System WebView `installPackageLI` 主动杀死 Here I am PID `13975`；`22:18:41.071` `START_STICKY` 以 `BleHeartRateService` 重建 PID `17074` 并继续采样。
- [x] 无需打开 App、重选设备或手动恢复。
- 结论：`通过（仅限 19:54 历史候选）`。此前约 25 秒短锁屏仍只作更早候选历史证据；23:14 已覆盖新的重连修复二进制，本项不得替代新候选 8 小时 Gate。

### C-3 连续 8 小时运行

- 候选：23:14 安装，APK SHA-256 `BEA15B5784981F385C2AEA21AC683E5ADC327E6CEB8B1EA50F5814072446EBB6`。
- 正式窗口：`2026-08-29 23:41:50.186–2026-08-30 07:41:50.186 +08:00`，完整 8 小时。BatteryStats 事后证明 `23:36:26.081` 已拔线且手机电量为 `100%`，`23:36:56.862` 熄屏；正式窗口内没有 screen 事件。该证据覆盖了起点时无法通过 ADB 实时读取的缺口。
- 样本：跨午夜 JSONL 共 `28,494` 条，零坏行；首样本 `23:41:50.751`（距起点 565 ms），末样本 `07:41:49.542`（距终点 644 ms），`健康数值仅保留本机`。
- 中断：恰有 `1` 个超过 15 秒的 gap；`07:09:54.861–07:15:58.017`，持续 `363.156 秒`。
- 故障链：`07:10:00` 出现 `gatt_status_8`；2 秒 retry 正常执行并创建了一个没有 callback 的 GATT。25 秒 connect watchdog 在 full Doze 中延迟约 321 秒，至 `07:15:49` 才触发；第二次 retry 后于 `07:15:58` 自动恢复。
- 晨间状态：App 未被打开，设备状态未被改变；`BleHeartRateService` 仍为 foreground，snapshot 为 fresh `live`；健康数值仅保留本机。
- 手机电量：正式窗口 `100% -> 84%`。
- COROS 电量：`____% -> ____%`
- 电量归因边界：完整 `10 小时 53 分` 断电段 Here I am UID 约 `210 mAh`，其中约 `192 mAh` / 近整夜 `ForegroundService:WakeLock` 高概率来自 `flutter_foreground_task allowWakeLock=true` 的 Companion FGS；BLE service 没有显式 wakelock。因此本窗口观察到的 16 个百分点下降不能归因给 BLE，须做 Companion FGS/BLE 隔离 A/B。
- 分项结论：`锁屏 8 小时耐久 PASS`；`本次故障自动恢复 PASS`；`跨日与显式缺口记录 PASS`；`严格连续性 FAIL`。失败原因是 Handler-only connect watchdog 在 full Doze 下没有可证明的 25 秒 SLA，产生 363.156 秒真实缺口；没有补造样本。手机电量已观测，但 BLE 独立耗电仍为 `unknown`。

### C-4 恢复矩阵

| 操作 | 自动恢复 | 恢复延迟 | 需要人工动作 | 结论/失败原因 |
|---|---:|---|---|---|
| COROS 离腕停样本与复戴恢复 | [x] | `离腕后约 17 秒 stale、约 62 秒 disconnected；复戴后等待既有 retryAt，到期后约 2.145 秒恢复首样本` | `无：未打开 App、未重选设备、未手动重启` | `Lynx 确认真实摘下且绿灯熄灭、传感器朝上不接触物体；未继续产生伪 BPM。服务全程存活并有界重连，复戴自动恢复通过；但退避最长 300 秒，最坏可等待约 5 分钟` |
| 正式 30 分钟 Gate 前的另一次复戴 | [ ] | `持久 retryAtMs 已过期，但内存 retry 未执行；诊断期间才恢复` | `恢复紧邻 SIGQUIT 取栈，触发因素不确定` | `独立可靠性缺口，不计为正式锁屏 Gate 失败，也不能写成纯被动复戴通过。设计允许 runnable 静默取消后永久停滞，具体竞态尚未证明` |
| Android 蓝牙关闭后再开 | [x] | `重开请求后约 3.43 秒恢复首样本` | `无：未打开 App、未重选设备` | `19:54 历史候选通过。20:07:10.763 关闭请求，最后样本 20:07:10.678；约 0.8 秒后持久状态为 bluetoothOff / adapter_off，服务仍运行且配置仍 enabled。20:08:06.092 重开，20:08:09.525 自动恢复首样本` |
| 直接 `kill -9` 后恢复 | [x] | `约 7.87 秒内恢复样本` | `无` | `START_STICKY 以新 PID 重建并新增 9 个样本；持续通知正常。该子测试未跨 15 秒 stale 阈值` |
| 最近任务移除触发三星 MARs force-stop | [ ] | `未自动恢复` | `用户重开 App 仍未拉起；之后需从 App UID 手动启动专用服务` | `失败。ApplicationExitInfo：18:07:51，USER REQUESTED / FORCE STOP，description=MARs #2；BleHeartRateService 消失` |
| MARs force-stop 后普通 App relaunch auto-resume | [ ] | `无` | `需要额外手动启动专用服务` | `失败。配置仍 enabled、持久快照仍 live，但 18:09 重开 App 不会自动恢复采样` |
| Home 退后台 25 秒 | [x] | `持续` | `无` | `服务与样本持续正常；只通过短后台子项` |
| 主 Android 重启后恢复 | [x] | `receiver delivery 开始后约 2.048 秒恢复首样本；完整重启形成 177.543 秒真实缺口` | `前置：Lynx 已设 Android“不受限制”并加入三星“永不休眠”；重启后未打开 App` | `在明确后台豁免前置下通过。首次受限态 receiver 被跳过且冷启动不自愈的失败证据保留` |
| 整夜 `gatt_status_8` / 无 callback GATT | [x] | `363.156 秒真实缺口后自动恢复` | `无；App 未打开、设备状态未改变` | `自动恢复通过，但严格连续性失败。首次 2 秒 retry 已执行；25 秒 connect watchdog 在 full Doze 中晚到约 321 秒，第二次 retry 后恢复` |

### C-5 舒适度与 COROS 结论

- [x] 佩戴体验真人检查通过；个人反馈保留本机，不在公开文档复制。
- 公开记录只保留佩戴体验检查结论，身体与皮肤反馈留本机。
- 总结论：`部分通过`
- 未通过或未完成的子项：`严格连续性已失败：23:14 候选整夜出现 363.156 秒真实 gap，full Doze 令 Handler-only connect watchdog 延迟约 321 秒。任务移除/三星 MARs force-stop 后恢复、普通 relaunch auto-resume 仍失败；确切离腕→复戴 stall 尚未在新候选上刻意重放，Service/真实 Handler/GATT 自动化集成仍为 P2；仍缺持久 watchdog deadline + OS/Doze 调度兜底、后台豁免设置引导、boot delivery 被跳过时的 cold-launch self-heal、旧 raw live 快照纠正与 receiver/FGS 分段诊断。手机电量下降已观测，但 BLE 独立归因须做 Companion FGS/BLE A/B，COROS 本体电量仍未知`
- [x] 确认本 Gate 不验证睡眠准确性，也不解锁医学结论
- [x] 已证实本次真实离腕会停样本并诚实进入 stale/disconnected，复戴可自动恢复；但设备仍无 contact-supported 字段，单一 BPM/停样本不能泛化为佩戴、清醒或睡眠判断，`sleep_candidate` 继续禁用

离腕/复戴时间链（来源：Lynx 物理确认 + 另一主窗设备/日志核对；本窗未重复访问设备）：最后样本 `18:30:16.830`；约 17 秒后诊断为 `stale / sample_timeout`；约 62 秒后 JSONL 写入 `disconnected / sample_timeout_reconnect`。复戴时绿灯重新亮起，既有最长退避的 `retryAt=18:47:50.364`；第一条新样本 `18:47:52.509`，距 retryAt 约 `2.145 秒`。记录不保存这两条逐搏 BPM 值。

### C-6 19:54 历史候选边界（另一心率窗口交付）

- 另一窗口新增 Companion 只读 `LiveHeartRateSnapshot` 与设置页选中/启用/接收状态展示；本主窗只读复核了窄 diff。工具仅在 configured + enabled + `live` + 样本年龄不超过 15 秒时返回 BPM，失败路径不返回历史 BPM；提示明确禁止由单一样本推断睡眠、清醒、焦虑、疾病或主动来电。
- 该窗口报告定向测试 `21/21`、9 文件 analyze 零问题、critical `3/3`，并于 `2026-08-29 19:54` 将 SHA-256 `6612467855BCF30D105C44485DB283434C2B271E4D959A3A966227AE395E7887` 的 hereIAmV3 APK 原位覆盖到 `SM-S9110`；安装后专用服务前台运行且取得约 10 秒内的 live 样本。相关窄实现后来由用户另行授权，在 `v3-lab@66017099` 之上提交为 `012c5eb524a9941dd8e39614ce0873ab097c7dcd`；MDA-0 主窗没有构建、安装、commit 或 push。
- 这是新的候选边界。任何跨过 19:54 的连续性样本不得合并成同一候选的连续 Gate；正式 30 分钟项目已在后续 C-2/C-9 独立通过，8 小时仍须从该安装后计算。该窄修复不改变 MARs/relaunch、retry stall 或整套 COROS Gate 仍未完成的结论。
- 新候选剩余真人 UI 子项由心率窗口负责：聊天询问当前心率、设置页选中态视觉确认；它们不属于多设备 activity probe/ingress，也不解锁 shadow 推断。

### C-7 当前候选蓝牙关闭/重开

- 来源：心率真机窗口 `01a04d3c-f6bb-72b1-9ea4-33c53a9fa5c7` 的设备/持久状态核对；候选为 19:54 安装的 SHA-256 `6612467855BCF30D105C44485DB283434C2B271E4D959A3A966227AE395E7887`。
- `20:07:10.763` 发出关闭蓝牙请求；最后一条样本为 `20:07:10.678`。约 0.8 秒后持久状态诚实写为 `bluetoothOff / adapter_off`；`BleHeartRateService` 仍运行，配置保持 enabled。
- `20:08:06.092` 重开蓝牙；`20:08:09.525` 自动恢复第一条样本，约 3.43 秒。期间未打开 App、未重新选择设备。
- 结论：19:54 历史候选的蓝牙关闭/重开自动恢复子项通过；该子项本身不外推到手机重启、MARs force-stop、连续性或睡眠判断。30 分钟后来由同一历史候选独立正式窗口通过；23:14 新候选需重新完成 8 小时。

### C-8 当前候选手机重启

- 首次受限态：重启前最后样本 `20:13:30.829`（健康数值仅保留本机）。`sys.boot_completed=1` 后，Here I am 进程和 `BleHeartRateService` 均未出现；`BleHeartRateBootReceiver` 与同包其他 manifest boot receiver 在进入 `onReceive` 前被系统标记 `SKIPPED / reason:mBroadcastConsumerSkip`。包状态为 `stopped=false`、`RECEIVE_BOOT_COMPLETED` granted、standby bucket `10`、app hibernation=false，但 `RUN_ANY_IN_BACKGROUND=ignore`。
- 首次失败的冷启动边界：`20:19:52` 冷启动 MainActivity 并等待 15 秒，专用服务仍未启动；持久快照错误保留重启前的 stale `live` BPM。之后 ADB 显式启动 FGS，`20:20:35` 才恢复 fresh 样本（健康数值仅保留本机）；这只是临时测试恢复。
- 受控设置变化：Lynx 将「故我在 V3」设为 Android“不受限制”并加入三星“永不休眠”。随后 `RUN_ANY_IN_BACKGROUND` 从 `ignore` 变为 `allow`，standby bucket 从 `10` 变为豁免态 `5`。
- 同一 19:54 APK 候选再次重启，且未打开 App。`BleHeartRateBootReceiver` 于 `20:32:53.091–20:32:53.307` 正常 `DELIVERED`，随后包自动启动 `connectedDevice` 前台服务；第一条新样本于 `20:32:55.139` 到达（健康数值仅保留本机），距 receiver delivery 开始约 2.048 秒。重启前最后样本为 `20:29:57.596`（健康数值仅保留本机），真实缺口 `177.543 秒`，期间无补造样本。
- 结论：重启自动恢复在“Android 不受限制 + 三星永不休眠”的明确前置条件下通过；受控 A/B 证据把首次失败归因于设备后台策略。仍须保留安装/诊断引导、boot delivery 被跳过时的 cold-launch self-heal、stale raw `live` 纠正与 receiver/FGS 分段诊断缺口；不得外推为默认设置或整夜 Gate 已通过。

### C-9 19:54 历史候选正式锁屏与 retry stall 边界

- 正式 30 分钟窗口的数据、`Dozing / DOZE` 状态和 WebView 更新导致的真实进程死亡/`START_STICKY` 恢复共同证明该窗口 Gate 通过；进程并非只是持续存活。
- 正式窗口之前，臂带已离腕。复戴后曾出现“服务/PID 存活、持久 `retryAtMs` 已过期、内存 retry 不再执行”；恢复发生在诊断期间且紧邻一次 `SIGQUIT`，触发因素不确定。因此该段既不能写成纯被动复戴成功，也不计入正式锁屏窗口失败。
- 只读代码审计表明：`retryAtMs` 只是投影；实际调度依赖主线程 `Handler` runnable，`closeGatt(cancelReconnect=true)` 可静默移除 runnable 而持久 due 仍保留，`staleTick` 没有 overdue 兜底，BLE callback 与主线程状态还有竞态面。设计允许永久停滞，但本次具体交错尚未证明。
- 后续修复建议属于新实现工作：主线程状态收敛、显式 retry generation/due、只在终止路径取消 retry、overdue 自愈与原生确定性测试。MDA-0 仅记录，不实现。

### C-10 23:14 重连返修候选边界

- 根因/返修交接：另一心率窗口将 retry 生命周期收敛到纯 Kotlin `BleReconnectCoordinator`，用 generation token + due time 使被替换/取消的旧 callback 失效、early callback 重排，并从 persisted future/overdue deadline 重建或一次性恢复；GATT callback 统一排入 Service 主线程并校验 generation + GATT 实例。`closeGatt` 不再隐式取消 retry，只有 STOP/FORGET/destroy/adapter-off/显式连接等边界取消。Store 新增 `activeRetryAtMs`。
- 本主窗只读核对了新 coordinator、Store deadline 读取、Service 接线和 7 条 coordinator 测试的存在；来源窗口报告 coordinator `7/7` + parser `5/5` = `12/12`、critical `3/3`、diff check、Kotlin 与 hereIAmV3 debug 构建通过，独立复审无 P0/P1。Service/真实 Handler/GATT 自动化集成仍为 P2，不能由静态审计代替。
- 新 APK：462,900,023 bytes，SHA-256 `BEA15B5784981F385C2AEA21AC683E5ADC327E6CEB8B1EA50F5814072446EBB6`；`2026-08-29 23:14` 原位覆盖 `com.memexlab.hereiam.v3`，版本仍 `1.0.30 (113)`，保留数据。该未提交二进制成为今晚唯一真机候选；19:54 及更早结果只作历史证据。
- 快速锁屏 Gate：`23:16:12.868–23:19:15.558` 全程 `live / Dozing`；JSONL 183 samples、max gap 1.263 s、健康数值仅保留本机、0 status/gap。它只证明新候选当前连接与短锁屏可用，不替代 8 小时或确切离腕→复戴 stall Gate。
- 电量/起点边界：`23:27` 手机为 100%，但仍 `USB powered`。Lynx 后续确认已拔线；因 ADB 随拔线不可见，设备侧 `USB=false`、fresh sample 与精确起点电量未实时读取。为避免高估时长，联合 Gate 保守取记录时刻 `23:41:50.186` 为起点；最终仍须由晨间 JSONL 证明起点后的实际采样。
- 最终状态：BatteryStats 与跨午夜 JSONL 已补足起点和正式窗口证据。8 小时耐久、本次失败自动恢复、日切/显式 gap 记录通过，但严格连续性因 363.156 秒 gap 失败；旧 retry 永久丢失未复现，新增风险是 Handler-only connect watchdog 无 Doze SLA。任务移除/MARs 仍失败，确切离腕→复戴 stall 尚未刻意重放，返修代码与文档未 commit/push/release。

### C-11 整夜故障与电量归因边界

- 这次 `gatt_status_8` 后首次 2 秒 retry 确实执行，因此不能把 363.156 秒 gap 归因于旧的 retry runnable 永久丢失；已观测的新失效点是无 callback GATT 的 connect watchdog 在 full Doze 中晚到。
- 后续实现建议属于新的工程修复：持久化 watchdog deadline，增加 OS/Doze 可兑现的调度兜底，并加入 Service 级晚到/无 callback 确定性测试；完成后必须在新候选上重跑零 gap 8 小时 Gate。MDA-0 只记录，不实现。
- `100% -> 84%` 是当前候选与整机前台服务组合的观察值，不是 BLE-only 结果。下一次电量 Gate 必须隔离 Companion FGS 的 `allowWakeLock=true` 与 BLE service，至少做同条件 A/B；在此之前不得给出 BLE 续航结论。

### C-12 Companion FGS / BLE 隔离电量 B–A–B

- B1（Companion + BLE）为 `254.7 mAh/h`；A（Companion only）为 `131.8 mAh/h`。B2 正式窗口为 `2026-09-01 01:11:30.134–03:11:30.753 +08:00`，charge counter `3,627,195→3,204,825 µAh`，即 `422.370 mAh / 2.000 h = 211.2 mAh/h`，电量 97%→86%、温度约 31.6→30.9°C。
- B2 起终点均为未充电；Battery event log 最后一次断电为 00:49:59，窗口内无重新供电。互动 `screen` 自 00:50:01 后未开启；01:16:44–01:16:54 仅有一次 10.458 秒 `screen_doze` 脉冲。BLE 与 Companion 两个前台服务全程保持同一 PID `7570`。
- JSONL 精确窗口有 7,217 samples、0 status/gap；首样本距起点 93ms、末样本距终点 356ms，最大间隔 4.334s，健康数值仅保留本机，严格 15 秒连续性通过。
- B1/B2 相差 `43.5 mAh/h`，相对 B1 为 17.1%、相对均值为 18.7%，满足预设 ≤20% 复现阈值。两个 B 平均 `232.9 mAh/h`，相对 A 的 BLE gateway 相关整机增量估计约 `101.1 mAh/h`（约 +76.7%）。
- 限定：B2 使用后续小版本，Lynx 确认改动未触及 BLE/Companion 耗电链路；A 仍只有单窗。因此只判 B–A–B 工程复现通过，不判同二进制精密标定。增量包含连接、通知、CPU/wakelock、重连与日志等整条 gateway 活动，不得缩写成纯蓝牙射频功耗，也不自动代表产品耗电预算通过。

### C-13 省电微调候选 31.8 分钟筛查

- 候选边界：`v3-lab@722a646de5b0` 加未提交 BLE 窄修，hereIAmV3 APK 462,942,129 bytes，SHA-256 `3C80B594ED403A6C5843AB9C18BEFE8B48BD79402BF01F77D126F5BCE6445F18`，设备版本 `1.0.30 (113)`、`lastUpdateTime=2026-09-01 22:10:46`。稳定 live 的空 watchdog reconcile 不再重复同步清理持久状态/Alarm；通知 BPM 刷新由 12 秒降为 60 秒，状态变化仍即时。
- 22:36:52 的第一次起点在用户随后充电后作废，未进入任何计算。唯一正式窗口为 `2026-09-01 22:53:19.893–23:25:07.832 +08:00`；供电事件最后一次断开为 22:51:30.961，窗口起终点均为 `AC/USB/Wireless=false`、`Dozing`、`mIsPowered=false`，两端均观察到 BLE 与 Companion 两个前台服务及同一 PID `12517`。
- charge counter `2,697,240→2,582,385 µAh`，即 `114.855 mAh / 31.799 min = 216.7 mAh/h`，电量 72%→69%。JSONL 全文件扫描 36,808 行均逐行检测到 `timestampMs`；精确窗口有 1,913 samples、0 status/gap，首样本距起点 285ms、末样本距终点 179ms，最大间隔 1.881s，健康数值仅保留本机。这不等于已用完整 JSON parser 证明全文件每行结构有效。
- 结论：短时连续性 PASS；耗电率与既有 B2 `211.2 mAh/h` 接近，本轮没有显示可测下降。没有同哈希改动前基线；该窗口紧邻充电且只有 31.8 分钟，又没有完整 screen-event、温度和后台活动轨迹，可能受电量计回落与短时系统活动影响。因此不能把差值归因于 App/BLE 或两项微调，不能替代 2 小时同口径 A/B、不能形成产品预算结论，也不能推翻 B–A–B 的工程归因边界。
- 下一低风险候选仅列计划：把 live snapshot 同步落盘由 5 秒降为 30 秒；仅在 Flutter EventChannel 真有订阅者时转发逐样本事件。两项必须分开修改、分开构建哈希和复测，不削弱 1Hz JSONL、7 秒 flush、15 秒 fail-closed、5 秒 stale tick 或 Doze watchdog。

### C-14 当前自然佩戴 8 小时 Gate（2026-09-10）

- 当前精确 APK 为 `3056968EA16D10245B7AD4A40B81CF7124C8A4B64B95798E235E6AA201E761D4`。00:30:44.302–08:30:44.302 独立窗口内 28,870 samples、最大间隔 4.872 秒、零超过 15 秒 gap，当前候选自然佩戴连续性通过。此处汇合已提交 `bbb8025d` 的验收记录，没有重跑设备或继承旧 APK 窗口。
- 该可用 v1 结论不包含三星重启恢复、产品耗电预算、睡眠判断或 MDA-2；C-12/C-13 仍为各自历史候选的限定证据。

## 2. iPhone 真人 Gate

### I-0 前置状态

- iPhone 型号与 iOS 版本：`____`
- D-3 已选方案：`1 — Tailscale iOS tailnet HTTPS；已安装登录，待安全入口验收`
- [x] Lynx 已在 iPhone 下载并登录 Tailscale；11:16 的离线快照由 Lynx 说明为手动连接状态。重新连接后 Windows 脱敏复核为 `backend=Running / iOS peers=1 / iOS online=1 / ping=success`。
- [x] 现有 Windows Serve 脱敏审计：`4` 个 root handler 均代理 loopback，`0` 个 non-loopback proxy，`0` 个 Funnel；其中 `1` 个本机 health 是 iCore authority。
- [ ] tailnet HTTPS health：Windows 对上述 4 个 Serve host 的 `/v1/core/health` 自检均未得到成功状态；不得据此声称 iPhone HTTPS ingress 可用。
- [ ] 已有另行批准的安全测试入口与独立 write-only 测试凭据
- [x] 尚无批准入口/凭据：本 Gate 当前记为 `unsupported`，不得执行 I-2 至 I-5
- 入口类型（只写类型，不写 URL）：`tailnet HTTPS / protected ingress / 无`

### I-1 真实 Shortcut trigger

- [x] Lynx 在目标 iPhone 的“快捷指令 → 自动化 → 新建自动化”触发列表中确认可见「睡眠」「充电器」「App」三类入口。
- [x] Apple 官方文档已给出公开子条件：Sleep 为 Wind Down Begins / Bedtime Begins / Waking Up（需先配置睡眠日程）；Charger 为 connected / disconnected；App 为 opened / closed。Apple 也将 Sleep、Charger、App 列为可设置无询问自动运行的类别。
- [ ] 尚未创建或实际触发任何自动化；因此下表不把公开能力或“入口可见”写成 trigger 已配置/已通过。无需 Lynx 再人工抄录公开子条件，真人 Gate 只保留实际运行与失败路径。

| trigger 类别 | 可配置 | 可自动运行 | 实际触发 | receipt/失败类别 |
|---|---:|---:|---:|---|
| Sleep Focus on | [ ] | [ ] | [ ] | `____` |
| Sleep Focus off | [ ] | [ ] | [ ] | `____` |
| 充电 | [ ] | [ ] | [ ] | `____` |
| 断开充电 | [ ] | [ ] | [ ] | `____` |
| 可选本地 App 类别事件（不写原名） | [ ] | [ ] | [ ] | `____` |

未配置、不可自动运行、漏触发或无网络均只产生 `unknown`，不提供负向 coverage。

### I-2 至 I-5 HTTPS 安全验证

仅在 I-0 已确认安全测试入口后执行；记录状态码/结果类别，不记录 URL、请求头或 token。

| 子项 | 预期 | 实测 | 通过 |
|---|---|---|---:|
| I-2 正确凭据发送最小白名单事件 | 一次接受并获得可追溯 receipt | `____` | [ ] |
| I-3 错误凭据 | 在资源查询/写入前拒绝 | `____` | [ ] |
| I-4 structured event coordinate 重放 | pairing prefix + canonical sequence；新逻辑事件严格递增且不复用、交付可乱序；相同 payload 在 replay detail 保留窗内复用 receipt；异 payload 冲突；真实 sequence gap 时 summary `unknown`，高于 retained floor 的较小首见 sequence 补齐后按逻辑顺序恢复；floor 及以下返回 `event_retained_out`；不重复投影 | `____` | [ ] |
| I-5 撤销后再次发送 | 立即拒绝，旧凭据不能重放 | `____` | [ ] |

### I-6 停用与 iPhone 结论

- [ ] 停用/删除 Shortcut 后不再产生发送尝试
- [x] 确认 Tailscale peer presence 不替代活动事件
- 总结论：`unsupported（当前 activity ingress）；Tailscale peer + ping 子项通过，不外推为事件通道`
- 未通过或未完成项：`tailnet HTTPS health 未成功；无获批 activity ingress、独立 write-only token、Shortcut 请求/receipt、错误 token、重放、撤销与停用验证。以上属于 MDA-1/Gate 1A red gate，不在 MDA-0 创建`

## 3. MDA-0 真人 Gate 总结

- 产品选择 Gate：`通过：夜间中枢 A、iPhone ingress 1、所有 raw/最小诊断 1 天、长期可删结论和最小采集/禁止推断边界均已确认`
- COROS Gate：`部分通过`
- iPhone Gate：`公开 trigger 与 Tailscale peer + ping 已确认；activity ingress 当前 unsupported`
- 是否满足 MDA-0 退出条件：`是；设计/证据产物已完成，Lynx 接受失败与 unsupported 项作为后续 red gate，不要求在 MDA-0 内修复`
- 若否，唯一下一动作：`不适用`
- Lynx 确认日期：`2026-08-30`

即使本表全部通过，MDA-1 仍受 Gate 1A 权威 ADR、单写者、epoch、fencing 与 Core 接受边界约束；本表不授权自动创建后续 Goal。
