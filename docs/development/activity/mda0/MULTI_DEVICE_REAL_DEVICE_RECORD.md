# MDA-0 多设备活动真人基线记录

> 状态：**进行中 — 当前优先验证主 Android**。
>
> 本记录只保存最小状态类别与测试结论，不保存设备序列号、当前 App/窗口原名、通知/聊天正文、URL、token 或按键。ADB 只做只读系统快照；不安装、不改权限、不配置探针、不调整网络或计划任务。

## 1. 解释边界

- 单次 ADB 快照只证明读取时刻的系统状态，不等于生产 activity probe 已实现。
- `Awake` / screen interactive 是设备电源状态，不等于人持续清醒或正在操作。
- App 进程存在、App 前台、USB/网络在线或 heartbeat 都不能独立证明人的状态。
- 未建立并验证连续 collector、TTL 和 SLO 前，快照之间的沉默没有负向 coverage，只能是 `unknown`。
- 当前不采集其他 App 名称、窗口标题、输入、屏幕内容或通知正文。

## 2. 主 Android

### A-0 候选与权限基线

- 测试日期：`2026-08-29`
- 设备：`Samsung SM-S9110 / Android 16 (API 36)`
- Here I am V3：`1.0.30 (113)`，复用既有安装候选
- ADB：`1 台已授权设备；无 offline / unauthorized`
- 蓝牙扫描、蓝牙连接、通知权限：`granted`
- `PACKAGE_USAGE_STATS`：App 已声明；AppOps 返回 `default / no operations`，因此当前没有证据证明 Usage Access 已显式授予
- [x] 未构建、未安装、未改权限、未启动 BLE 扫描

### A-1 首次只读状态快照

- 主机记录时间：`2026-08-29T16:18:24+08:00`
- Android wakefulness：`Awake`
- device locked：`false`
- display suspend blocker：`held`
- USB powered：`true`
- 电池：`33% / charging`
- Here I am 进程：`存在`
- Here I am 前台：`false`
- 允许结论：读取时设备为唤醒、未锁定并通过 USB 供电；App 进程存在但不在前台
- 禁止结论：不能据此断言用户正在操作、持续清醒、可响应或存在连续 activity coverage

### A-2 锁定/解锁转移测试

| 步骤 | Lynx 操作 | 只读观测 | 允许结论 | 状态 |
|---|---|---|---|---|
| A-2.1 | 短按电源键锁屏并保持 10 秒 | `2026-08-29T17:35:43+08:00`：`Dozing`、`deviceLocked=true`、display suspend blocker released、keyguard 未被遮挡 | 确认本机系统可提供 lock/power 状态转移；不代表人离开或睡眠 | 通过 |
| A-2.2 | 正常解锁并停留 10 秒 | `2026-08-29T17:38:31+08:00`：`Awake`、`deviceLocked=false`、display suspend blocker held、keyguard 未被遮挡 | 确认本机系统可提供 unlock/power 正向状态；不代表持续交互 | 通过 |
| A-2.3 | 解锁后不操作 2 分钟；不改变现有屏幕超时 | Lynx 确认期间未操作；`17:54:34` 至 `17:57:48`（约 194 秒）起止均为 `Awake / unlocked`、display suspend blocker held | 设备因 USB 供电保持唤醒；长于屏幕超时的无操作沉默仍不能判定离开、交互或睡眠 | 通过（边界场景） |

A-2.1 与 A-1 的相邻快照证明本次人工操作前后状态确实不同；由于当前没有生产 collector、事件时间戳或连续 coverage，这仍只是主窗通过 ADB 读取的两次离散观测，不能声称 App 已经捕获 `session.locked` / `screen.non_interactive` 事件。

A-2.3 首次尝试：基线 `17:38:56`；期间 Lynx 明确报告有数次操作；末次 `17:52:18` 为 `Awake / unlocked`。该样本受交互干扰，判为无效，不用于任何状态或 coverage 结论。

A-2.3 重测配置：系统 `screen_off_timeout=120000 ms`；`stay_on_while_plugged_in=15`，当时 `mStayOn=true`。因此超过 2 分钟仍 `Awake / unlocked` 与 USB 保持唤醒策略一致；这证明 power/screen 状态与真实交互必须分开建模，不证明已有连续输入观测。

### A-3 Usage Access 真人 Gate

- `2026-08-29T18:30:32+08:00` 只读复核：App 声明 `PACKAGE_USAGE_STATS`，但 `GET_USAGE_STATS` 没有显式 allow；AppOps 为 `default / no operations`，未修改权限。
- 当前结论：`关闭态已确认；usage 来源 unavailable / unknown`。
- 后续仅由 Lynx 在系统“使用情况访问权限”页面核对开关；未获明确指令前不通过 ADB 或 App 改写权限。
- 开关关闭时预期：usage 来源 `unknown`，不得用缓存或其他信号填补。
- 开关开启后的测试也只能验证查询能力；在生产 collector 未实现前不宣称持续 coverage。

### A-4 App 生命周期与供电

| 场景 | 观测 | 解释 | 状态 |
|---|---|---|---|
| App 进程存在、非前台 | 已观测 | 最多是进程状态，不是用户活动 | 通过 |
| App 前台/退后台转移 | `18:02:06`：前台、进程存在；`18:03:08`：退后台、进程仍存在；两次设备均为 `Awake` | Here I am 前后台可区分；进程存活不等于前台，更不代表设备总体交互 | 通过 |
| 从最近任务划掉 Here I am | `2026-08-29 18:07:51` 后 App 非前台、进程不存在、本包运行服务 `0`；ApplicationExitInfo 明确为 `USER REQUESTED / FORCE STOP`、`MARs #2`；设备仍 `Awake` | 三星把 remove-task 升级为整包 force-stop；App 来源必须 `unknown`，不能假设 START_STICKY 可运行 | 失败（恢复 Gate） |
| MARs force-stop 后手动重开 App | `18:09` App 进程恢复，但 BleHeartRateService 没有自动拉起；配置仍 enabled、旧持久快照仍 live | relaunch 未恢复来源，且 stale 的持久 live 不能当作当前 coverage；失联期间不能补写 | 失败 |
| 从 App UID 手动重启专用 BLE 服务 | 服务和实时样本立即恢复；18:15:25 本窗确认专用服务 marker 存在，18:16:15 JSONL 已增至 764 sample | 这是诊断性人工恢复，不是用户普通 relaunch auto-resume | 通过（仅诊断恢复） |
| BLE 采集进程直接 `kill -9` 后 START_STICKY 恢复 | 另一主窗实测：新 PID 重建、持续通知正常并新增 9 个 HRS 样本，最大 gap 约 `7.87 秒` | 只证明直接 SIGKILL 的短重建路径；不能外推到 MARs force-stop | 通过（短恢复子项） |
| Home 退后台 25 秒 | 专用服务与样本持续正常 | 只证明短后台，不等于长时/Doze coverage | 通过（短后台子项） |

MARs 失败路径的全文件样本时间戳缺口后来达到约 `251.307 秒`，但 JSONL status 行仍为 `0`。这是“整包被停止时没有进程负责写 gap/status”的证据，不是 BLE 长断连状态机通过。
| USB 供电 | 已观测 | 只说明供电，不代表 awake | 通过 |
| 非 USB/充电器变化 | 当前 ADB 链路依赖 USB，未采集 | 不为测试擅自配置无线 ADB | `unknown` |

## 3. 第二 Android

### B-0 只读现状基线

- `2026-08-29T19:08:13+08:00`：`Xiaomi 2203121C / Android 15 (API 35)`，已授权 ADB。
- 完整 Here I am V3 `1.0.30 (113)` 已预先安装；本窗口没有安装、打开、卸载或修改它。该现状违反“第二 Android 只做最小探针、不装完整产品”的目标边界，必须作为风险而非既定方案保留。
- Here I am 当前进程：`不存在`；前台：`false`。
- Tasker 初始快照为未安装；Lynx 于 `2026-08-29 19:14:44` 自行安装 `Tasker 6.6.20 (5445)`。本窗口未打开或配置它，19:16:42 进程未运行。
- Usage Access：AppOps `default / no operations`，没有显式 allow。
- 设备状态：`Awake / unlocked`、display suspend blocker held；电池 `10% / charging`，AC powered，USB powered=false。
- [x] Tasker 由 Lynx 安装；本窗口未代为安装、未改变权限、未创建 profile、未启动完整 App。

### B-1 当前解释

- 系统只读快照可作为真人能力基线，不等于未来 Tasker/probe 已捕获事件。
- 完整 App 的“已安装但未运行”不能充当 heartbeat、activity source 或 coverage。
- Tasker 现在只证明软件包存在；没有经确认的 profile、离散 trigger、outbox、独立 write-only 凭据或 delivery receipt，第二 Android 的远端活动来源仍是 `unsupported / unknown`。
- 后续如要验证 screen、unlock、charging 或本地 App 类别，应先由 Lynx 确认是否保留这台设备为第二端，并另行授权最小 Tasker/probe 配置；MDA-0 本窗口不安装或配置。

### B-2 锁定/解锁系统快照

| 步骤 | Lynx 操作 | 只读观测 | 状态 |
|---|---|---|---|
| B-2.1 | 短按电源键锁屏并保持 10 秒 | `2026-08-29T19:10:12+08:00`：`Dozing`、`deviceLocked=true`、display suspend blocker released、keyguard 未被遮挡；只证明系统快照，未产生远端 probe 事件 | 通过 |
| B-2.2 | 正常解锁并保持 10 秒 | `2026-08-29T19:11:26+08:00`：`Awake`、`deviceLocked=false`、display suspend blocker held、keyguard 未被遮挡；未产生远端 probe 事件 | 通过 |

### B-3 充电状态转移

| 步骤 | Lynx 操作 | 只读观测 | 状态 |
|---|---|---|---|
| B-3.1 | 短暂拔下 AC 充电器，保持约 5 秒 | Lynx 确认已拔下；ADB 同时消失，无法取得断充后的本机字段，也没有 Tasker event/receipt | 部分证据；远端事件未通过 |
| B-3.2 | 重新插回充电器，保持约 5 秒 | `2026-08-29T19:16:42+08:00`：ADB 恢复、AC powered=true、USB/wireless=false、charging、11% | 通过（本机重连快照） |

充电/断充只证明电源连接转移，不等于用户在场、设备正在交互或人已清醒。

### B-4 Tasker 安装后 readiness（只读，不配置）

| 项目 | 当前结果 | 解释 |
|---|---|---|
| 包/版本 | 已安装 `6.6.20 (5445)`；进程未运行 | 安装不等于 probe 已配置 |
| RECEIVE_BOOT_COMPLETED | declared / granted | 仅具备启动广播声明，不证明小米自启动策略通过 |
| POST_NOTIFICATIONS | denied；AppOp ignore | 无法依赖通知展示后台采集状态 |
| Usage Access | AppOp default / no operations | 未授权，App 类别/usage 来源不可用 |
| 后台 AppOps | RUN_IN_BACKGROUND / RUN_ANY_IN_BACKGROUND 默认 allow | 仍不证明 OEM/MARs/省电存活 |
| Device idle whitelist | false | 未获白名单；本窗不修改 |
| Accessibility / notification listener | 均未启用 | 不采集屏幕/通知正文；也不作为本轮触发来源 |
| Overlay | ignore | 未授权；本轮不需要也不请求 |
| Exact alarm | default | 未验证，不当作可靠调度 |
| profile/outbox/credential/ingress | 未创建、未验证 | 远端状态保持 `unsupported / unknown` |

结论：Tasker readiness Gate 未通过。MDA-0 仅记录缺口；创建 profile、授予权限、配置小米自启动/省电例外或接入 ingress 都属于后续显式授权的实现工作。

## 4. Windows 与 iPhone

### W-0 Windows 调用会话只读基线

- `2026-08-29T18:31:28+08:00`：Windows 11 `25H2`，build `26200.9168`；当前调用会话 `Active`。
- 同一快照的 `GetLastInputInfo` idle 为 `14171 ms`；该 API 只属于当前 session，不代表其他 session，也不证明用户状态。
- 30 秒首次对照没有形成可用输出，随后即时读数已被新输入重置为 `0`，样本无效。
- 10 秒重测：`18:32:45` 起点 idle `0 ms`，`18:32:55` 末点 `641 ms`；窗口接近结束时发生输入，不能声明连续 idle，样本无效。
- 干净 10 秒重测：`18:37:30` idle `13765 ms` → `18:37:40` idle `23765 ms`，增量 `10000 ms`；当前 session 的 idle 累计读取通过。
- `WTSSessionInfoEx` 结构/对齐核验：`18:38:15` 当前 session `connect_state=Active(0)`、`session_flags=1 (unlocked)`；未记录用户名或输入内容。
- 锁定转移：`18:46:04` 当前 session 仍为 `connect_state=Active(0)`，但 `session_flags=0 (locked)`；之后 30 秒轮询未见解锁，锁定半程已证实。
- 解锁转移：Lynx 正常解锁后，`18:47:31` 同一 session 为 `connect_state=Active(0)`、`session_flags=1 (unlocked)`。
- 当前结论：Windows session-scoped idle 与 `unlocked → locked → unlocked` 转移在真机通过；connect state 在锁定期间仍为 `Active`，因此连接状态与锁定状态必须分栏。suspend/resume 仍待，现有 iCore/network 不能替代活动证据。

### IPhone 当前边界

- Lynx 已在目标 iPhone 的新建自动化触发列表中确认「睡眠」「充电器」「App」三类入口可见。
- `2026-08-30`：Lynx 已下载并登录 Tailscale。11:16 的离线快照由 Lynx 说明为手动连接状态；重新连接后 Windows 脱敏复核为 backend `Running`、1 个 iOS peer online，Tailscale ping 成功。未记录设备名、IP 或 tailnet 信息。
- Windows 现有 Serve 有 4 个 root loopback proxy、无 non-loopback proxy/Funnel；其中 1 个本机 `/v1/core/health` 是 iCore authority。Windows 经 tailnet HTTPS 对 4 个 Serve host 的同路径自检均未成功。
- peer + ping 只证明 `network.present`；tailnet HTTPS activity ingress、独立 write-only token、Shortcut 请求与 receipt 均未通过。
- Apple 官方文档已确认公开子条件：Sleep 为 Wind Down Begins / Bedtime Begins / Waking Up（依赖睡眠日程），Charger 为 connected / disconnected，App 为 opened / closed；三类均列入可无询问自动运行的类别。无需再让 Lynx 人工枚举公开 UI。
- 真机尚未创建或实际触发自动化，也没有获批安全 ingress/凭据。未通过前 webhook 仍为 `unsupported`，事件间状态仍为 `unknown`。

## 5. 当前下一步

第二 Android 的只读系统、锁定/解锁、充电重连与 Tasker readiness 基线已完成；不在 MDA-0 内创建 profile 或授予权限。Windows suspend/resume 未执行，方案 A 已明确要求 Windows 保持不睡眠；恢复路径仍作为后续证据缺口保留。iPhone 的公开 trigger 能力、三类入口可见性及 Tailscale peer + ping 已确认；tailnet HTTPS health 未通过，因此 activity ingress 当前记为 `unsupported`。最小采集边界已经 Lynx 确认；下一步是 MDA-0 收口审计，ingress、独立 write-only token 与最小自动化实测继续受 MDA-1/Gate 1A 授权阻断。
