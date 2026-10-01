# MDA-2 A3-D — Android 真机诊断与短场景 Gate

> 2026-09-14；W0 验收主窗计划。固定源码起点：`v3-lab@be18b91a2882d4b86e300e5d10c819d4ca3da58b`。
> A3-I 最终候选：`c0bf3d49cf145cb2505750bd2d4e4d26e2e1eb9c`，已通过 W0 并在主线落地。
> A3-D 只验证真实 Android 平台行为与现有隐私边界；它不建立生产自动采集、服务端 binding、Core 传输或一晚 shadow 结论。

## 当前缺口与本轮闭环

A3-I 的 Kotlin 通道、Dart collector、Keystore 仓库和 no-backup outbox 已在本地自动测试中成立，但正常 App 中没有 caller、DI、UI 或服务端 source binding 注入。因此直接构建当前 `main.dart` 只会证明默认关闭，不能执行 mapped UsageEvents、权限撤销、屏幕广播、进程死亡和重启场景。

A3-D 分三段串行执行：

1. **A3-D0 诊断入口候选**：独立任务实现一个显式、仅用于 hereIAmV3 Debug 真机 Gate 的入口。它不进入正常 `main.dart` 启动链，不新增生产 DI/UI，不自动启动 collector。
2. **A3-D1 W0 独立审计与唯一 APK**：W0 固定候选 commit，在干净导出复跑专项/相邻测试与 critical fixes；接受后形成一个唯一 hereIAmV3 Debug APK，记录本地和设备 `base.apk` SHA-256。
3. **A3-D2 真人短场景**：在同一 APK hash 上执行权限、屏幕、进程、重启、Doze/OEM 与 BLE 共存矩阵。APK hash 一旦变化，旧设备结果全部失效。

## A3-D0 诊断入口要求

- 使用独立 Dart entrypoint 或等价的 Debug-only 入口；正常 `lib/main.dart`、router、settings、DI 和产品启动链不得引用它。
- 必须有显式“开始诊断”动作。开始前不得 provision key、注册 receiver、查询 UsageEvents、创建 outbox 或分配 sequence。
- 诊断 binding 必须在类型、命名和界面上明确标为 synthetic/local diagnostic，只能进入本机 A3-D outbox，禁止接 sender/Core/网络，禁止被描述为服务端签发 binding。
- 只显示/导出固定 readiness、权限枚举、粗类别、时间、sequence 与非敏感计数。不得显示或写出包名、App label、原始 UsageEvents、Intent、路径、密钥、token 或异常正文。
- category mapping 只在原生查询输入中使用；未映射 App 和未知 event 不得返回 Dart。诊断证据中只允许粗类别与计数。
- 使用现有专用 Keystore namespace 和原生 `noBackupFilesDir`。缺 key、缺任一 binding、权限拒绝/撤销、existing state 或平台异常均 fail closed。
- 诊断状态不得伪造连续覆盖：划掉任务、process death、force-stop、重启、Doze 或 receiver 缺口一律显示 unknown/gap；重启后不自动恢复、不补写历史。
- 如需重置，只能由显式“清理本次 A3-D 诊断状态”动作删除已核对的 `mda2_activity` 诊断 outbox，并在 collector 已 dispose、无 owner 时执行；不得清 App 数据、数据库、BLE、聊天或其他目录，不得自动轮换 key 掩盖损坏/丢失。
- A3-D0 可以补诊断入口自身测试、固定码/隐私负例和交接材料。若真机所需修复触及 A3-I 生产源，必须最小化并在 handoff 中单列原因、diff 和回归。

## 独立任务拥有路径

- 新的 A3-D 独立入口及其专用 UI/控制代码；优先放在 `lib/a3d_device_gate_main.dart` 与 `lib/ui/a3d_device_gate/**`。
- `integration_test/mda2_android_a3d_device_gate_test.dart` 或等价的诊断入口自动检查。
- `test/data/services/activity/mda2_android/**` 中新增的 A3-D 测试/静态守门。
- `docs/development/activity/mda2/android/a3d/**` 的 handoff、场景协议与证据模板。
- 只有实际缺陷证据成立时，才可最小修改 `lib/data/services/activity/mda2_android/**` 或既有 ActivitySignal Kotlin 文件；必须保持 normal App 默认无 caller。

禁止修改 `lib/main.dart`、正常 router/settings/DI、Android Manifest、Gradle 依赖/版本、数据库/Core/wire、PhoneUsage 通道、BLE/check-in/Alarm/WorkManager/FGS/boot receiver、根状态文档和全局 Roadmap。若某项成为必要条件，停止并交回 W0 裁决。

## A3-D0 自动验收

- 默认未开始时：receiver/query/outbox/key provision/sequence 均为 0。
- 缺 key、缺单 source binding、existing outbox：固定码拒绝，零原生效果。
- diagnostic binding 无 sender、HTTP、Core、timer、scheduler、FGS 或 boot/autostart 路径。
- 诊断展示与导出只接受固定 schema；包名/App label/raw/private/path/token/异常正文注入必须整段拒绝或脱敏为固定码。
- 复跑 A3 Dart `16/16`、A3 Kotlin `12/12`、A1 `56/56`、A2 `30/30`、wire/Core `20/20`，并运行完整 `hereIAmV3Debug` App 单元任务和 `git diff --check`。
- worker 只提交候选与 handoff；不构建最终 APK、不调用 adb、不访问手机/真实 UsageEvents/Core/网络/BLE、不 push、不集成主线。

## A3-D1 固定与安装

W0 只从干净、已接受的集成 commit 构建；不得从 `D:/memex` 当前并行 dirty 工作树直接构建。构建前运行 `scripts/verify_critical_fixes.ps1`，必须 exit 0。只允许 `hereIAmV3` flavor 和包名 `com.memexlab.hereiam.v3`。

安装前记录当前设备型号、Android/OEM、电池策略、Usage Access、当前 `base.apk` hash 与可回退 APK；安装后再次读取 `base.apk` hash，必须与唯一诊断 APK 一致。出现签名不匹配、用户限制、hash 不一致或数据迁移风险即停止。诊断结束后恢复先前确认的 hereIAmV3 APK，并再次核对 hash 与 BLE 基本状态。

## A3-D2 短场景与停点

沿用 A3-I handoff 的 14 项矩阵：默认关闭、缺 key/binding、Usage denied、grant 后 mapped/unmapped App、撤销/regrant、三类屏幕广播、划掉/process death、force-stop、重启、Doze/OEM、BLE 共存，以及留给后续 transport 包的 Core offline/recovery。

任一 package/app/raw/private 值进入展示、outbox 或 wire，任一缺口被写成 quiet/active/asleep，任一 Activity collector 与 BLE/check-in 生命周期互相 stop/start，均立即失败并退回 A3-I/A3-D0。短场景全部通过也只表示这个 APK 的 A3-D 设备 Gate 通过；生产 binding、自动调度、transport、无干预 shadow 与至少一晚 Gate 仍需独立计划。

## 派发与回收

- 路由：L2，`gpt-5.6-sol / high`。
- 从固定提交 `be18b91a2882d4b86e300e5d10c819d4ca3da58b` 创建隔离 Worktree，不读取或复制主目录未提交文件。
- worker 不创建子 Agent；交付一个边界清晰的 commit、完整 SHA、路径 manifest、真实测试 exits、失败尝试和 A3-D 设备操作清单。
- W0 回收后逐路径审计并在干净导出复验，只选择性集成被接受的源码；不因 worker 自报通过而进入设备安装。
- 正式 task：`01a09b9c-42f5-7482-9d2b-327ce6bea7d4`；隔离 Worktree：`C:/Users/ExampleUser/.codex/worktrees/aadd/memex`；分支：`codex/mda2-a3d-device-gate-20260914`。创建时 W0 计划文件尚未进入冻结 commit，worker 已停点确认；W0 明确以创建任务首条委派中的完整同义约束为正式契约继续，禁止读取主目录未提交计划。

## W0 回收状态

- 源码候选：`6659c1911cbe2c75a5db15bdce8b066dcb3bf25d`；docs-only handoff：`cdc585737f7eca404b0db4420dcf219443934f16`。
- W0 已在独立 detached 干净导出完成逐路径审计、专项/相邻回归、完整 `hereIAmV3Debug` App unit task、静态范围守门与 clean/diff 检查；未发现需退修缺陷。
- 裁决：A3-D0 接受，允许选择性本地集成；仍未构建 APK、调用 adb、访问设备、真实 UsageEvents 或 BLE。详见 [W0 验收](android/a3d_review/6659c191/W0_ACCEPTANCE.md)。

## A3-D1 唯一 APK 状态

- A3-D0 已选择性落地：源码提交 `7a6c71778636241d44ae15b15724a9213da15d15`，收据提交 `482e1fa96c810a79f4ef2b89a4e07dcd7e5c07b8`；原 56 个 tracked 并行修改保持、index 为空。
- 从 `482e1fa9` detached 干净构建树运行 critical fixes 3/3 后，唯一 `hereIAmV3` Debug / `lib/a3d_device_gate_main.dart` APK 构建成功。
- APK SHA-256：`56A4E8621606545410BC84E3FBEF6E23DDBDC95EE77871ED5C3B655E27B36A4B`；大小 `384166171` bytes；包名 `com.memexlab.hereiam.v3`，版本 `1.0.30 (113)`。
- 安装前 ADB 预检没有发现设备；因此未安装、未读取设备原 `base.apk` hash、未执行 UsageEvents/屏幕/进程/重启/Doze/BLE 场景。设备连接后必须继续绑定同一 APK hash，不得重建替代。详见 [APK候选记录](android/a3d_device_gate/482e1fa9/APK_CANDIDATE.md)。
