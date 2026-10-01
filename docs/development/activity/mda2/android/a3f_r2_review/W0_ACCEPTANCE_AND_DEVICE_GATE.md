# A3F-R2 W0 独立验收与设备 Gate

2026-09-27。本轮源修复已接受并本地集成，唯一诊断 APK 完成真实启动、通知与三事件 Gate；诊断结束后已恢复原正式包。

## 2026-09-27 最终设备结果

- 设备重新授权后，安装包仍精确为 R2 `EACA6DFA…6C384`。初次开始返回 `recovery_authority_required`，证明当时没有进入通知启动；用户通过唯一显式诊断清理一次后得到 `diagnostic_reset_complete`，未清完整 App 数据。
- 清理后开始：页面 `ready`，Activity 与 BLE 服务并存，FGS 标志、系统通知记录、固定通道和用户人眼可见的“活动观察正在运行”全部成立；12秒后仍稳定。R2 启动与持续通知 Gate 通过。
- 第一轮锁解/提取得到最新有效序列3锁屏、4亮屏、5解锁；页面锁屏2、亮屏2、解锁1，usage/screen均fresh，collection gap 0。之后三星 SystemUI 在13:24:14记录`SwipedOut: true`与`REASON_CANCEL_ALL`，同时移除本包BLE/Activity及其他应用通知；用户明确未主动清除。R2按通知连续性fail-closed于13:24:18停止Activity，页面仍显示ready，且普通“停止”无法清理失去service实例的旧owner。这是独立的状态同步/恢复缺口，不回写为R2启动失败。
- 对照轮在显式清理后真实启动；不打开通知栏时稳定。只做锁屏约10秒/解锁，Activity与BLE服务及通知均保留，没有新`CANCEL_ALL`；原生序列1锁屏、2亮屏、3解锁。再查询/刷新后页面sequence3、三类各1、usage/screen fresh、collection gap 0，服务与通知继续存在。因此锁解与查询/刷新均不能复现13:24全清；该次保持为三星SystemUI单次未归因事件，不声称是用户动作或App调用。
- 用户显式停止后，页面`collector_disabled`，Activity服务及其活动通知消失，BLE保留。随后覆盖恢复原正式APK`E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37`：安装Success、设备base hash一致、冷启动exit0、Activity诊断服务不存在、BLE服务存在、Bluetooth保持1；未清完整数据、未push/publish。
- 结论：R2修复在SM-S9110/Android16上的启动、可见持续通知、锁解三事件、提取、显式停止与BLE隔离 Gate 通过。后续应单独处理“系统通知被外部移除后Flutter页面仍ready、普通停止不能释放旧owner”；OEM/权限撤回/进程死亡/重启/耗电等其余矩阵未因此自动通过。

## 源与边界

- 隔离冻结源：`7e0798358e4915ef8da1565be2ae20d616c30da8`，parent `aae59e18f142e0854c033a0b2e31c65bc3fd0e88`。
- 主线选择性集成：`v3-lab@8d84e20135e5f6cbadd677467245b89c0abb87d3`；59 份 tracked 并行修改逐 hash 保留，index 空，未 push/publish。
- 仅八候选路径：Activity 启动确认、必要 Channel 回执隔离、对应测试/静态校验及命名交接。未改 Dart、Manifest、Gradle/依赖、BLE、Core/wire/schema/outbox 或生产入口。
- 通知与 foreground 未确认前禁止 epoch.start、screen receiver、UsageEvents query 和 active=true。单调全程 10 秒 deadline，100ms 非阻塞确认；API31+ 请求立即显示；stop/revoke/destroy、旧 token/owner/bridge generation 和成功回执投递前停止均隔离。

## 可复核验证

- 旧 Service 源码与新增源接线契约测试：32 项中新增一项 RED、旧31项通过。它证明即时失败的源码接线，不能替代真实 Handler/AppOps 注入或三星根因复现。
- 候选 Android SDK/Flutter embedding 实际编译：53/53；W0 从精确 Git 字节独立镜像编译、另加8项生命周期对抗和保留2项迟到反例：63/63，零失败/错误/跳过。
- 实际 App 源集 `testHereIAmV3DebugUnitTest`：53/53，65.7秒，零失败/错误/跳过。来源窗只读完整 diff/关键断言交叉审计无阻塞；没有冒充其独立编译。
- static WorkingTree/Commit 均通过，八路径、保护区零 diff、隐私投影通过；diff check、project-state hook 通过。
- APK 构建前 critical 3/3；唯一 hereIAmV3 debug，入口 `lib/a3d_device_gate_main.dart`，Flutter 构建 exit0、151.4秒。复用自有缓存目录，但1213 runtime 输入逐项绑定候选 Git 字节，188 local JNI 源 hash 匹配；测试后源码与 APK hash 未变。未将目录名 `34718949` 当作 R2 源版本。
- 构建后的收据相对路径首次写错，修正收据后保存；构建本身成功，没有因此重构建。现有 NDK/Kotlin 警告未引入依赖升级。

## 唯一 APK 与安装

- APK SHA256：`EACA6DFA0E7E5AEB15C41259EE6F17226014BDB96CC195FFF20BB389ADD6C384`；384275350 bytes。
- 包名 `com.memexlab.hereiam.v3`，1.0.30(113)，debug 签名 SHA256 `0011cc0372b17ccec1544eea667d2466adebade94ac91adb39239f3be8712e4e`。aapt、签名验证通过，DEX 含两个新启动确认类。
- RFCWC01PBKK / SM-S9110 / Android16：2026-09-18 17:48:40 UTC 覆盖安装 Success、设备 base hash 精确一致、冷启动 exit0。仅安装所需 package force-stop；未清完整数据/修改通知权限/Bluetooth。
- 17:48:50 UTC 诊断页显示 `diagnostic_not_started`、sequence0；Activity 服务不存在、BLE 存在。这是安装后初态，不是启动验收。
- 用户随后点“开始诊断”并报告“仍然没有通知”。17:51:12、17:51:25 UTC 两次 hash 绑定读取：Activity 服务不存在、BLE 存在，V3非当前焦点；当前错误尚未读取。该结果不能宣称修复在设备通过，也不能直接归因为原通知竞态。

## 待验与恢复

先返回诊断页并实读固定 readiness/error；若恢复门拒绝，保留失败并仅用既有显式诊断恢复，禁止删 owner 或清完整 App 数据。通知真人可见、三事件 occurrence/delivery、停止/授权撤回/死亡/重启/OEM/隔离/耗电矩阵均待验。新 hash 需要新 Gate，旧 A3-D2 FAIL 不变。

通知启动经设备与用户确认后，才进行锁屏约10秒、解锁、立即查询提取及刷新，避免超5分钟 TTL。诊断结束恢复原正式 `E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37` 待办；其签名与新包一致。旧R1 `99995837…46779A4` 已独立保存作回退证据，当前手机为新 EACA 包。

## 自有证据

- `tmp/a3f-r2-w0-7e0798358e49/W0_UNIT_RESULT.json`、`W0_SOURCE_BINDING.json`、对应8套 XML。
- `tmp/a3f-r2-landing.json`；`tmp/mda2-a3f-device-evidence/r2-7e0798358e49/` 内 `build_binding.json`、`build_result.json`、`formal_app_unit.json`、`apk_candidate.json`、`dex_binding.json`、`install_receipt.json` 及具名设备快照。
- 构建输出：`tmp/mda2-a3f-device-build/34718949/build/app/outputs/flutter-apk/app-hereiamv3-debug.apk`。临时证据属于W0本机可复核收据，不是提交到仓库的用户数据或测试通过之外的验收声明。
