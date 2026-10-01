# A3F-R3 U 工作包交接

## 2026-09-27 现场动作结果覆盖窄修复

worker `/root/r3_ui_action_result_fix`；原始三份 UI 文件与 W0 同 HEAD `b2adc44b` 且逐字节一致。本轮只改 controller、screen、`a3d_device_gate_test.dart` 与本交接；未改 store/platform/collector/native/默认入口/依赖，未构建、操作设备、commit/push。

- 新增仅 UI 使用的不可变最近资源动作结果，普通 stop、无损释放、显式 reset 用各动作局部结果码构造；原生同步和 collector readiness 继续独立更新，不以动作结果参与任何权限/资源判定。动作 finally 中的异步收口也不能被生命周期码覆盖。
- 显式下一动作更新结果；真正接受新的 begin 请求时清除旧结果，拒绝 begin 不清。屏幕新增简洁中文动作/结果与固定公开码；不暴露 owner 标识、路径、token，不改证据 wire schema。
- 复用现有拒绝、未知 begin 回执、部分失败、H4 stop 失败、reset 未确认测试，检查下一前台 tick、refresh、background/resume 后保留动作结果；同时检查 no start/query/stop/permit、lease claim 与原文件字节不变。后续明确成功更新、新 begin 清除（包括随后受恢复门拒绝）、迟到旧 release/end Future 不覆盖较新成功结果。
- 独立验证镜像 `tmp/a3f-r3-ui-actionfix` 使用 W0 当前最终路径修复源码作只读依赖，仅覆盖 U 三文件。`evidence/red-final.log`：原 controller/screen 在较大 widget 视口下，同拒绝提示即时可见、1100ms 后消失，实际 exit 1。原测试输入保存在 `red-regression-test.dart`，全部输入固定于 `red-source-manifest.json`。
- `green-final.log`：最终 UI 31/31，实际 exit 0；`analyze-final.log`：两 UI 文件及测试定向 `--fatal-infos` 分析无问题，实际 exit 0。各 `*-result.json` 保存原始退出码；`final-manifest.json` 核对测试前后 hash 与 U/W0 对应源一致，并固定日志 hash。`git diff --check` exit 0。
- 中间测试缺少一份被 import 的只读依赖、误 await void 生命周期方法、默认小视口尚未构建下方动作行，分别保留 setup/test-compile/small-viewport 日志；已补真实依赖、修调用和设置完整视口，未放宽拒绝文字断言。最终 RED/GREEN 均使用同一完整视口。

本轮冻结 SHA-256（取代下方旧 U UI 指纹）：controller `D6E1424DC279197BCE76727D7D8C4B61C2CA4FA0329E711BA3CEA560BFA3120F`；screen `91C0191EF3067889BCC79599CBAB8B0F284C978472B8BECB0E53430165FEFAF4`；test `CB6C14E01C6108CF5368327747DC42F43737D751F9F2BF4D3D7E8337F66142D0`。

限制：这些是本地合成/Windows 文件 IO/Flutter UI 证据，不是新的 Android APK 或真人 Gate。交 W0 独审、整合与决定后续构建；主窗文件尚未由本 worker 改动。

---

2026-09-27；worker `/root/r3_ui_recovery_impl`。基线 `b2adc44b7c04983a931c39695b81491cd295084b`，分支 `codex/a3f-r3-ui-recovery-20260927`，隔离树 `a3f-r3-ui-recovery/memex`。未 commit/push、构建 APK、操作设备或真实数据。

## 拥有差异与冻结指纹

| U 文件 | SHA-256 |
|---|---|
| `lib/data/services/activity/mda2_android/file_activity_outbox_store.dart` | `C25510CBEA960B252867A12951774EEAED154BDAD5D8174C2A6B6695E89AD496` |
| `lib/ui/a3d_device_gate/a3d_device_gate_controller.dart` | `A6F30102D139A0F4714A2C57ADA350442013D2A75A0506B5A3C15603D25F3571` |
| `lib/ui/a3d_device_gate/a3d_device_gate_screen.dart` | `B6B9475EC814624643FADC6371DD9206229119783AEB602869CA92A447922BB8` |
| `test/data/services/activity/mda2_android/a3d_device_gate_test.dart` | `8CFD2D5430CE13C211791F64E1C1DB1FEF2117046147623350E2F47C06E24228` |
| `test/data/services/activity/mda2_android/a3f_r3_owner_release_test.dart` | `3D7FE2EA3CD44C371CCB5A0F2207C549C730D1643E717DA9EB47A2F05BD6C3A6` |

原 `file_activity_outbox_store_test.dart` 未修改，作为回归输入运行。树中 platform、collector、新 process-lease 文件均为 W0 复制的 D 只读依赖，不属于 U 差异：collector `DD7F1F65F850A3FE339CDD329066411612CDF632BA2C97CED9EE3C31254D2F68`；platform `8F41CDC6F1CB90014E0F7C4EF0DDC1BF1C03CC1904F1C80D76C4CAF028661F34`；lease `EC88ACA09332484282D355B0E89948665C5FF21BC56115ADB958A31049124A41`。

## 实现

- FileStore create/open 传入 processLease 时始终验证；Android 缺失即拒绝。先 claim 再开 gate，closeSync 确认后才解除 claim；关闭不确定保留资源证据。
- `ActivityOutboxReleaseTarget` 私有不可变精确根/binding/owner/state/anchor 字节关联。`inspectOwnReleaseTarget`、`inspectReleaseTarget`、`verifyReleaseTarget` 只读，不打开 gate、不恢复 journal、不 claim sequence。`releaseExactOwner` 在 process claim 和 OS gate 内复核原目标，仅删除 owner。重复缺席返回 `targetAbsent`，不声称本次删除；journal、路径/结构、签名、原字节或 successor 不符均拒绝。
- 新 `beforeOwnerDeleteForTesting` 默认 null，仅 own-owner 核对后、真实删除前调用。失败经 finally 真实关闭 FD，旧 store 不可继续写。H4 调用 D 的一次性 Debug seam，用户另点按钮才无损释放。
- UI 分开原生状态、同步状态与逐源 close/FD/claim/process lease 结果。前台每秒只读兜底；resume/refresh/query 前复核，读取 3 秒无结果降 unknown；初始化等候 12 秒，保留 R2 原生 10 秒门，超时保存 collector 供明确 stop。
- `ready` 和 `canQuery` 分离。只读 running 不抹掉 query/权限失败；用户可明确查询重新核验，只有有效新 batch 恢复。初始化失败仅凭 D 的 `canRetireWithoutObservation` 退休，不用空集合 every 推断资源已释放。
- 恢复先取得精确 terminal permit、两源 broker lease、两源预检，再逐源窄释放。保存失败/部分完成；重试也重验已释放目标，successor 不删除、不报全部完成。无损释放不调用 open/reset、不删除 root、不自启，保留非空 outbox 恢复门。
- 已知 token 的 release/end 等待 3 秒，超时保存身份/Future，下一次明确动作可幂等重发同 token；未知 token 的 begin/acquire 只保存并接续原 Future。迟到回执只属于原对象。reset 使用相同两源 broker 门，保留未确定资源并允许显式收口。
- H2 调用真实 Debug 通知证据失证 API，只 arm、不伪造停止；标注非 OEM 复现。target/session/token/key/path 均不进入 UI 证据或导出。

## 最终 P2 修复与落盘证据

最终独审确认：上轮已删 owner、broker 释放回执失败后，本轮双源预检虽通过，primitive claim 前仍可能被拒绝；历史成功集合会错误放行 complete/confirm。现每轮清空成功证明，primitive 两类异常均移除该源。新增回归在该窗口生成真实签名 successor 后拒绝 claim，断言 partial、失败源未退休且仍保留原 close 失败、successor 字节不变。仅测试 lease 增加可选 claim 前 callback，默认行为未变。

实际落盘证据根：`D:/memex/tmp/a3f-r3-w0/u-verification/evidence/`：

- `u-final-p2-red.log`：修复前新反例真实失败，预期 partial、实际 complete，exit 1。
- `u-final-p2-ui-tests.log`：修复后新增反例 + 原 29 项 UI，30/30，exit 0。
- `u-final-p2-analyze.log`：U store/UI、两个 U 测试，No issues found，exit 0。
- `u-final-p2-manifest.json`：源树及运行镜像逐文件 SHA-256、依赖来源、日志 SHA-256 与实际退出码。全部运行镜像字节与对应源文件匹配。

最后 `git diff --check` exit 0。本轮不重复原 store/组合矩阵；W0 独立执行最终组合。下表 69/69 与 29/29 属于 P2 修复前历史运行，仅保留当时工具输出，未另存日志或 manifest，不把现在生成的证据说成旧运行收据。

## 修复前验证记录

使用现有 `D:/flutter`（Dart 3.12.0），镜像位于 `D:/memex/tmp/a3f-r3-w0/u-verification`。TEMP/TMP/LOCALAPPDATA 仅进程内重定向至该目录；未修改全局配置、依赖或共享脚本。

运行命令：`D:/flutter/bin/cache/dart-sdk/bin/dart.exe D:/flutter/bin/cache/flutter_tools.snapshot test --no-pub <下列测试路径> --reporter expanded`。

| 测试 | 结果 |
|---|---|
| `test/data/services/activity/mda2_android/file_activity_outbox_store_test.dart` | 31/31，组合 exit 0 |
| `test/data/services/activity/mda2_android/a3f_r3_owner_release_test.dart` | 9/9，组合 exit 0 |
| `test/data/services/activity/mda2_android/a3d_device_gate_test.dart` | 29/29，组合 exit 0；最终纯大括号修正后单独 29/29、exit 0 |
| 三文件组合 | 69/69，exit 0 |
| `dart analyze --fatal-infos`：U store/UI、两 U 测试 | No issues found，exit 0 |
| `git diff --check` | exit 0 |

新增反例覆盖单次 claim 不可复用、删除失败保原字节/旧对象不可写、真实 Windows OS gate 竞争、journal 不动、successor/临门替换、签名/binding/结构；终态推送及漏推送、3 秒未知/迟到、初始化无回执、H4 保 state/anchor/sequence/key、不自启/恢复门、原生已 end 但丢回执、release/end 永久 pending 的同 token 重试、begin/acquire 未知身份等待原 Future、reset 挂起释放收口。

## 失败与修正历史

1. 初轮新增测试试图读取活 gate，触发 Windows 真锁拒绝（4 例）；取证改为数据文件，避免观察时打开第二 gate FD。
2. 离线 pub 已生成配置但共享缓存 active_roots 登记失败（exit 66），随后使用已生成配置 --no-pub。迁移时遗漏 package_graph 导致工具 exit 1，补齐原解析图后运行；未下载/更新依赖。
3. C 盘耗尽时停止写入，由 W0 恢复空间；后续验证输出全在 D 盘。
4. 初版替身错误允许重复 claim，依 V 审查改为真实一次认领语义并补旧 lease 拒绝断言；H4 直接测试新前置 seam。
5. 首次 UI 组合失败来自旧同步刷新未 await、屏幕测试仍用无代 onSignal，改为异步刷新及带代 batch。曾误收紧显式权限重核，已按 W0 恢复原 regrant 契约，并验证只读刷新不自行 query、不清失败。
6. 独审提出的 liveness、资源退休、原 target 重试问题均补实现及反例。最终分析修正 3 处纯大括号后，已复验最终 UI 字节。

## 限制与后续

本交接只证明本地合成、真实 Windows 文件 IO 与 Flutter 测试；不证明 Android 同进程双 engine、真实第二进程或真人 Gate。不宣称复现 OEM 通知丢失；无构建、安装、正式包恢复或设备验收。W0 继续跨层独审、候选与真人阶段。未知 acquire/permit Future 永久失证时保留原请求，不猜 token 或释放他人 owner，也不报告成功。
