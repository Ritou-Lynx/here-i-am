# A3F-R3 自动真机时序补验（2026-09-28）

## 2026-09-29 F2 严格时序三项 GO；同包真人 Gate 待补

F2 Debug APK `0AC428177247F757BA21C95B734A6121610D87735071BFC08E1A377C39324911` 源自同一 b2adc44b 基线，运行输入根 `BD87D1D414A5B256CB9CA058D6895C828D2174FC6E660C4B4053871A0DB21A35`。两条状态读取路径只把内部等待改为 2500ms，外部严格 ≤3 秒未放宽；源码独审 GO、同源组合232/232、critical3/3、构建与包名/签名通过。安装前 E1 正式包 hash、BLE 前台、蓝牙开启、Activity 缺席、13项元数据一致且手机已解锁。

三份完整封口 trace：手动刷新动作→前台 unknown 发布 **2,524,287µs**；返回前台从更早 action→unknown **2,504,994µs**（foregroundEntered 起算2,504,947µs）；受控失证用例 **2,506,085µs**。全部严格≤3,000,000µs，checking先于选中读取，hold 捕获真实 running。受控用例原 running/rev6 回执在 stopped/rev8 后真实交付并由 `collectorRejectedTerminal` 拒绝，终态后无 ready 回弹。注入不是 OEM 通知丢失复现。

通知自身按钮实际在唯一 Activity 通知行中点击；native stopped 后后台页面即发布 stopped，返前台立即 checking、再 verified stopped。展开通知面板的后台时段不计前台 3秒，不能把最后 running 读取到停止发布的10.57秒误作按钮时限。关闭仅删除两 owner，其余11项元数据不变；可读 gate FD 0但存在不可读FD，不宣称穷尽OS锁。F2→原 E1 正式包完整hash恢复，BLE 前台6157/Bluetooth1、Activity 缺席与13项元数据不变隔时复核；私有连接清理。详见本地 `tmp/a3f-r3-timing-device-f2/DEVICE_RESULT_F2.md` 和 `INDEPENDENT_REVIEW.md`。F2 同包人眼通知/锁解及完整 H4/H5 Gate 未重做；Goal 开放，无 commit/push。下方 F1 RED 和旧状态为历史。

## 2026-09-29 F1D3431A 实机严格时序 RED；正式状态已恢复

新Debug候选三份实机trace均封口完整。manual/resume checking投影分别在动作后824/1790µs并早于选中读取；但无有效回复至unknown投影分别为3,026,775/3,007,425µs，受控迟到场景附带3,004,019µs，均超过冻结的≤3,000,000µs，不能以标称3秒Timer或舍入通过。受控通知失证后旧running/revision6真实交付，由本代terminal守卫拒绝；拒绝后128条投影无ready回弹。该分项不代替通知按钮/OEM场景，按钮自动定位失败回执保留。[本轮结果](../../../../../../tmp/a3f-r3-timing-device/DEVICE_RESULT_F1.md)与独立复审保存在本地tmp。

已显式释放两owner，可读FD枚举中的两gate计数0、其余11项元数据不变；有3个FD不可读且全局锁不可读，不提升为独立穷尽的OS FD关闭证明。实际装回E1正式包，BLE前台6157/Bluetooth1和Activity缺席两次隔时确认，13项元数据不变，私有调试连接已清理。本轮H6运行态收尾成立，GATT/BPM质量不在此证据范围。手机随后断开；下一步只返修无回复unknown投影预算，新hash重验；Goal仍未完成，无commit/push。

## 2026-09-29 新时序候选已本地封包，设备待连接

Debug 候选 `F1D3431A92A3A7C6EC569033C488BD2246F45F855306B341F7278441BF70AF70` 来自基线 b2adc44b 的隔离 W0，1224 项运行输入根指纹 `80B24B2B39B9398C0CD014AB08C2D2B6F62C713A20469F4707A53B9D409AD35F`。最终源码获独审 GO，冻结镜像 228/228，构建前 critical 与 Debug 构建通过；包名和旧签名一致。详见本地 `tmp/a3f-r3-timing-candidate/candidate-manifest.json`、`SOURCE_REVIEW_DEADLINE_FINAL.md`、`final-combined-v2-result.json`、`build-result.json`。先前两份源码 RED 保留。

手机仍未连接；新候选尚未安装，立即 checking、无有效回复 ≤3000ms unknown、真实迟到回复拒绝均无实机结论。17:45 E1 正式包恢复后的 BLE 前台状态仍待本轮 H6 核对。Goal 不关闭，不继承 9A 的真人 Gate。

## 17:45 更新：H1 同步通过，剩余验证支持实施中

同一 9A099611 候选在新测量窗口完成通知自身按钮停止。原始同代仍 running 的读取下界 13838ms，到首次前台 verified/非 ready 的读取上界 14613ms，保守 **775ms**（包含通知面板后台时段）；独审接受此项严格 3 秒同步。返页窗口另算 389ms。原汇总 `sampled_upper_bound_within_3s=false` 保留：整个 case 含后续第二次 Home/return，触发通用 reducer 限制，不推翻已独立核实的首次窗口。

549 条样本/0 读取未知；收敛后 505 条未见回弹，其中含显式关闭后时段。它不证明立即 checking 或任意采样间隙无回弹。关闭恰好删除两 owner、其余 11 项不变；安装前原 PID 的 gate FD 已核实释放。17:45 实際恢复 E1 正式 APK，13 项元数据不变、Activity 服务不存在，但即时 BLE 尚未前台，随后手机断开，**本轮 H6 最终 BLE 核对未完成**。此前 01:21 恢复成功不得代替此次收尾。

证据：`tmp/a3f-r3-auto-h1-r2-9a099611/automatic-h1-witness.jsonl`、`h1-run-continuation-result.json`、`formal-restore-receipt.json`、`REVIEW.md`。首次预检 `running_ready_unconfirmed` 失败原样保留，后续仅重新确认就绪并继续，未重复清理/开始。

立即 checking、无有效回复 3 秒 unknown、迟到回复拒绝的完整时序仍缺证。现按[最小 Debug 支持方案](DEBUG_TIMING_PROBE_PLAN.md)在隔离 W0 实施；新 APK 将另行验证，不继承 9A 真人结果。Goal 未完成，无 commit/push。

## 以下为 01:21 窗口的已归档结论

基线 `v3-lab@b2adc44b7c04983a931c39695b81491cd295084b`；诊断 APK `9A099611F08763B2A73C962557D65970864FB9D4775001D3EE5AB2791ACBB6C3`，23项源码 pin 重核一致。该窗口只修改本地取证工具和验收文档，没有修改产品代码、构建新 APK、commit 或 push。

用户授权先完成可独立执行的补验工作。以下操作均为 W0 自动真机操作，不冒称真人点击；未更改权限、蓝牙开关、绑定，不清全包数据，不使用全包 force-stop，也未绕过凭据锁屏。

## 验收结果

| 项目 | 本轮结论 | 证据边界 |
|---|---|---|
| H2 受控通知失证后的前台同步 | **通过严格3秒中的这一同步项：保守上界515ms** | 原生本代仍running的读取下界16482ms；同代UI verified、非ready读取上界16997ms。使用同一观察器单调时钟，没有混合主机点击时钟。不是OEM通知丢失复现，也不是通知丢失到原生发现的检测时限。 |
| H2 返回前台核对 | 保守上界419ms | 最后后台UI读取下界21103ms，首条前台verified读取上界21522ms；不能替代“resume瞬间立即checking”的证明。 |
| H2 观察尾段 | 397条本代样本、0读取未知；收敛后346条未见原生或ready回弹 | 320ms目标采样周期，实际读窗/间隙留在JSONL；不证明采样间任意瞬间都无回弹。89329ms的checking样本远晚于该次返页/刷新，不移作“立即checking”证据。 |
| H1 通知自身停止 | 功能成立；**严格3秒仍缺证** | 实际点击绑定SystemUI内本应用Activity通知的最近可见行；分组展开、通知展开、停止均有独立收据。但发生在有效测量窗之外，不能借用H2的515ms。 |
| 资源关闭/记录保持 | 通过本轮关闭与保留核对 | 末轮terminal→closed恰好两owner变为不存在，其余11项元数据完全相同。安装前原PID17750的gate FD6/198均已不存在；全局OS锁仍未独立证明。 |
| H6 正式包及BLE恢复 | **完成** | 01:21恢复正式APK完整hash `E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37`；稳定后BLE前台6157/Bluetooth1、Activity诊断服务无；13项持久元数据不变。本轮两条调试转发和生成的私密连接配置已清理。 |

**Goal仍未完成。** 剩余H1严格3秒、resume/刷新立即checking、无有效状态3秒转unknown的完整设备时序，以及迟到回执不恢复ready的连续时序证据，不因本轮部分通过而降低标准。已有源码/合成验证和有限采样各按自身范围使用。

## 取证工具与失败记录

- 单连接只读观察器固定H2→H1或单H1；每段身份不可变，旧段冻结，跨代不混算。只调用状态查询，不调用开始、停止、查询积累、注入或刷新。三份Dart文件分析无问题、26项纯合成断言通过，独审接受其取证边界；这些不是设备通过结论。
- 自动点击使用当前XML中的文字、包名、启用状态和边界；通知先核对active列表精确本包ID5102143，分组展开另核BLE6157，再限定最近无嵌套的通知行。系统面板未稳定时有界重读；不以旧坐标或直接native-stop替代通知按钮。
- 首次编排器被独审发现可复用旧样本、子控件可能被通知行裁剪、旧UI捕获清理不足，W0在H2之后中断。后继动作增加动作后样本水位、通知行可见中心限制；UI捕获改为完整XML只入内存、过滤后落盘、finally清理远端临时文件。修复不改变原始515ms证据窗。
- 第一连接正常在178815ms结束：H2已完成，H1只采到150条运行样本，无终态。第二次连接在握手阶段HttpException、0样本，保留失败；未归因于权限、OEM或产品代码。
- 证明通知控件定位后，仅同包再开一次新进程H1窗口。首次reset点击未产生实际清理，守门拒绝继续；第二次确认页面清理完成后才开始。该窗口118829ms正常结束，289条等待记录；锚定后75条含末条预算结束的未知。17:19:26.720709Z结束，通知停止实际在17:19:47Z发生，仍无终态时限证据。未继续循环重装。
- 正式恢复首次即时快照BLE尚未前台，因此原恢复收据保留`completed=false`；随后独立稳定快照实证BLE前台，最终合并收据才记录恢复完成。启动请求不等于实际前台运行，不推断真实GATT连接或心率样本质量。

## 可复核材料

本地原始材料不提交：

- `tmp/a3f-r3-auto-gate-9a099611/automatic-witness.jsonl`：H2原始读窗及第一段未完成H1。
- `tmp/a3f-r3-auto-gate-9a099611/h2-inject-action.json`、`h2-home-action.json`、`h2-return-action.json`、`h2-refresh-action.json`：自动动作收据。
- `tmp/a3f-r3-auto-gate-9a099611/automatic-h1-witness.jsonl`：重连0样本失败。
- `tmp/a3f-r3-auto-h1-9a099611/automatic-h1-witness.jsonl`：最后一次H1窗口；`h1-notification-stop-action.json`记录窗外自身按钮停止。
- `tmp/a3f-r3-auto-h1-9a099611/h1-terminal.json`、`h1-closed.json`及对应`-files.txt`：关闭与保留；`formal-restore-receipt.json`包含安装前原FD核对及实际APK hash。
- `tmp/a3f-r3-auto-h1-9a099611/formal-restored-settled.json`、`cleanup-result.json`、`final-automatic-result.json`：最终设备和连接收尾。
- `tmp/a3f-r3-pathfix/device-witness-automatic-README.md`：CLI、身份与计时计算、采样限制；不含连接凭据。

下一次独立补验应先完成UI清理/就绪预检，再启动有界测量并立即串行执行已核控件；若就绪未达到、连接结束或样本未知，应结束该窗口并保留缺口。不能为补满矩阵继续无界重装，不要求用户立即参与操作。
