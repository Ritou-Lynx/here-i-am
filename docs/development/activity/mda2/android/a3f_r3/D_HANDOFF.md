# 2026-09-27 设备失败后的 D 路径边界窄修复

## 独审补验后的最终冻结（66 项）

- 平台实现与 collector 测试 fixture 均不变，只补 observation platform test 两例：已有诊断根为 directory 时系统祖先别名仍返回同一 Dart canonical 根；同一 platform 首次成功后换至另一个由全新 platform 验证为合法的根，固定拒绝 `private_outbox_root_invalid`，channel 仅有 getOutboxRoot，两个 filesystem adapter 只有只读操作，无 write/start/lease。
- 最终 **66/66，actual exit 0**；平台及两个相关测试定向分析 **exit 0，No issues found**；`git diff --check` exit 0。
- 新证据 `D:/memex/tmp/a3f-r3-dart-verification/r3-pathfix-final-green.log`、`r3-pathfix-final-analyze.log`、`r3-pathfix-final-source-manifest.json`。64 项原日志/manifest 均保留未覆盖，9 文件镜像再次逐 hash 绑定。
- 与64项候选相比仅 `android_activity_observation_platform_test.dart` 内容变化；最终测试 SHA256 `490B832BA537CC5C5CE09AA2178FC07404D98E0C9F1A4025BB52D35677FB8DF3`。已审平台仍 `9BFDD427CB8D5D79B878DFBC2511A43601CB6E5E5E1B82A4369078510C08FB99`；collector fixture仍 `0D3C288C66FE6CCC4F62202AC87D284EFA2F4543DCC45B82ABA0681CDFB06C42`。
- 不新增实现或设备操作。新设备正例仍由 W0 唯一候选复验；本节不继承旧 APK 的失败或成功。

本节是原 55 项 D 候选后的新修复，尚未继承或取得新的设备验收；下方原交付保留为历史。

- 设备证据 `D:/memex/tmp/a3f-r3-device-gate-854f341e/h0-dart-scope-read.json`：原生 Context 给出 `/data/user/0/com.memexlab.hereiam.v3/no_backup/mda2_activity`，真实 Dart 对同一根的 resolve 返回 `/data/data/com.memexlab.hereiam.v3/no_backup/mda2_activity`；U 原严格等式误拒。没有从 shell realpath 或 Java canonical 推定等效结果。
- 仅修改 `android_activity_signal_platform.dart`、`android_activity_observation_platform_test.dart`、经 W0 补充授权的 `android_activity_observation_collector_test.dart` 中 Rig 根布局/对应 scratch 清理，以及本 handoff。collector 实现、U、FileStore、native、依赖/schema、broker-before-gate 未动。
- 真实 MethodChannel 返回先查 exact keys、精确 scope、绝对路径、无空/dot segments、末两段 `no_backup/mda2_activity`。原生 Context 的 app-data/no_backup 边界本体必须 followLinks:false 为 directory；只用 Dart 规范化可信父边界，且 canonical(no_backup) 必须是 canonical(appData)+固定 `/no_backup`。
- canonical 父边界再检查为非链接目录且自身 resolve 一致，随后拼固定 `mda2_activity`。现有诊断 root 必须原始/规范两路径类型一致且为非链接目录，两个 root resolve 都须等于拼接目标；不将 root resolve 的任意结果当新安全根。缺失诊断 root 合法但不创建；缺失/不可读父边界固定拒绝，无原始路径回退。重复 getOutboxRoot 重新检查且固定同一个规范根。
- 原生可信 app-data 以上系统祖先可以有不同 Dart 拼写；不会将 appData/no_backup 本体链接或 no_backup/root 子边界逃逸规范化成许可。下层 source/file 反链接仍由原 U/FileStore 原封不动检查。新增测试 seam 仅两项只读 filesystem 操作，真实平台默认 Dart IO，不新增旁路 fake/生产开关。

## RED → GREEN 与最终证据

- 先保全原 55 项 `test-final.log`、`analyze-final.log`、`final-source-manifest.json` 及其 9 份源码镜像到 `D:/memex/tmp/a3f-r3-dart-verification/r3-pathfix-baseline/`；原 final 收据文件未覆盖。
- **RED actual exit 1**：只添加可注入的窄只读 filesystem seam 和 Android 系统祖先别名 fixture，旧逻辑仍返回 `/data/user/0/...`，期望 Dart `/data/data/...` 失败；日志 `r3-pathfix-red.log`。
- 首轮 GREEN 暴露 Windows 返回分隔符转义错误，修正后复验；失败日志保留 `r3-pathfix-first-attempt-failed.log`，未弱化断言或放宽链接边界。
- **GREEN 64/64 actual exit 0**：原 55 邻近平台/collector 回归全部保留，加 9 个路径边界场景。真实 Dart IO 目录和 `Link.createSync` fixture 覆盖 no_backup/root 链接拒绝、root 文件拒绝、缺父拒绝、首次缺 root 不创建、现存根连续两次一致；没有 skip 链接测试。受控只读 filesystem fixture 模拟 Android 祖先别名及 parent/root resolve 逃逸/不可读拒绝，原始 path/scope/额外字段非法在触及 filesystem 前拒绝。
- 测试命令为既有 Dart + `flutter_tools.snapshot test --no-pub test/data/services/activity/mda2_android --reporter expanded`，日志 `r3-pathfix-green.log`。未再解析或下载包。
- `dart analyze --fatal-infos` 定向上述 3 文件：**exit 0，No issues found**；日志 `r3-pathfix-analyze.log`。format 成功，`git diff --check` exit 0。
- `r3-pathfix-source-manifest.json` 重新绑定 9 文件源码/镜像；与原 manifest 比较，恰好上述 3 个源码/测试文件改变。最小本轮差异在 `r3-pathfix.diff`。
- platform SHA256 `9BFDD427CB8D5D79B878DFBC2511A43601CB6E5E5E1B82A4369078510C08FB99`。
- observation platform test SHA256 `3198A07C3A3CE6772BF6F121FC18BF7BDA389104EA27E0DC2BB71DD83D146326`。
- observation collector test SHA256 `0D3C288C66FE6CCC4F62202AC87D284EFA2F4543DCC45B82ABA0681CDFB06C42`。

本包没有 commit/build/adb/安装/真实数据操作。Android 正例为严格受控 filesystem fixture，真实 OS 别名仍须 W0 新候选设备复验；独立安全审阅及组合由 W0 负责。APK 854F 的失败不能被本地 64 项提升成通过。

---

# A3F-R3 D handoff — 实现与本地专项完成，待独立/组合审阅

- 基线 `b2adc44b7c04983a931c39695b81491cd295084b`；分支 `codex/a3f-r3-dart-20260927`。
- 接管任务 `01a0e1cd-ec2d-7e81-aad9-d705aa05ab49`（`/root/r3_dart_finish`）；工作树 `C:/Users/ExampleUser/.codex/worktrees/a3f-r3-dart/memex`。前 Terra 初版未验收，本记录取代其未完成收据。
- D 交付仅：`android_activity_collector.dart`、`android_activity_signal_platform.dart`、新增 `activity_outbox_process_lease.dart`、原 `android_activity_collector_test.dart` 的 3 行 native 状态字段适配，以及两个新增 `android_activity_observation_{collector,platform}_test.dart`；均位于原 activity/mda2_android 目录，另本 handoff。无 commit/push。
- U `file_activity_outbox_store.dart` 是只读开发依赖，SHA256 `C25510CBEA960B252867A12951774EEAED154BDAD5D8174C2A6B6695E89AD496`；其 diff 不属于 D，不复制为 D 成果。D 没有改 U store。

## 结果与 API

- 将 owned observation 与 observed 当前状态分离：只有本次 activation 回执授予 owner；foreign/read 状态永不成为 stop target。generation 捕获覆盖每个初始化 await、query/batch/ack/status 回调；终态与已退休 native session 不可被迟到 running/activation 覆盖。
- `ready` 是最后有效 query readiness；native running 只更新生命周期。新增 status `canQuery`（默认 false）：仅本代接受有效且 exact owned/current running 为 true，允许用户显式 query 重新核验权限，不自动查询。原撤权→再授权回归期望保持。
- stop 先封本代接受，再等 initialization 收据与 exact native terminal 才 close。initialize、native stop、每 source lease release 默认每个等待上限 3 秒（测试注入 40ms）；超时返回 unknown/失败并保留资源，迟到收据不恢复 ready、不自动 close，下一次显式 stop 可重试。未进入 native attempt 的 preflight 可以释放自身未使用资源；initialize 等待全部收尾后才返回当前 status；不以未知 activation/deactivate 成败关闭潜在服务资源。
- 每个 stop 都返回两 source 结果；owner close、FD claim、process lease 分开。closed/poisoned 对象不再 close；`attempt_in_progress` 是 close 前拒绝，可在原 attempt 退出后显式重试。store 退休但 broker release 失败仍保留同 lease 并可重试；native 幂等应答后清除旧失败状态。
- `releaseTargets` 冻结精确目标；`confirmReleasedOwner(source,target)` 要求同一对象与无 FD/claim/process lease，退休资源并更新释放结果。实际 owner 删除由 U 窄释放承担。
- H2: `AndroidActivityObservationPlatform.debugInvalidateObservationNotification(AndroidNativeObservationStatus target) -> Future<bool>`；Debug 守卫 + native exact target。
- H4: `collector.debugFailNextOwnerDelete(AndroidActivitySource source) -> void`；Debug、owned 身份、未关闭 source store 守卫，下一次本 source owner 删除单次注入，正常路径默认关闭。经 U seam 最终固定 closeCode 为既有 `owner_lock_cleanup_failed`，owner 字节保留；FD/process lease 分别证明。
- 按 W0 已集成 N `ActivitySignalChannelHandler.kt` 对齐 activation 实际 **7 键**：enabled/readiness/usage_source/screen_source/usage_permission/counters/observation_status；校验两 source、permission、counter 白名单/类型。3 键精简假回执拒绝。逐项检查 status、stop、H2、lease、permit 的 map；version 必须 int 1，不接受 1.0。平台正常路径不降级旧 fake。

- 新增 `status.canRetireWithoutObservation` 与 `stopResult.noNativeAttempt`：必须 initialize 全 await 完成、无 native attempt，前者还要求两 source close/FD/claim/lease 全释放；无回执 acquire 的 pending task 被保留，stop unknown 不授予退休证明。`completed` 可由明确 noNativeAttempt + 完整资源证明成立，nativeOutcome/status 仍 null，不伪造 stopped。
- 最后预审补齐：preflight release false/throw 后 initialize 返回 held lease 快照、显式 stop 重试收口；lease release 无回执有界失败、晚回执只更新原 lease，下一次显式 stop可收口；pending acquire timeout不能误判无资源退休。新增4项，共55。

## 验证收据

- 独立最小离线 harness：`D:/memex/tmp/a3f-r3-dart-verification`，使用既有 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe` + `D:/flutter/bin/cache/flutter_tools.snapshot`。仅进程内 TEMP/TMP/LOCALAPPDATA 指向 harness；PUB_CACHE 显式指现有缓存。
- 依赖 crypto ^3.0.7、Flutter SDK、flutter_secure_storage 10.3.1、flutter_test、flutter_lints ^3.0.0；`pub get --offline` 最终实际 **exit 0**，没有完整仓库解析/下载/修改 shared cache。首次将 LOCALAPPDATA 移走但未设 PUB_CACHE 导致 cache-not-found（exit 1），补正确缓存路径后成功。
- `flutter_tools.snapshot test --no-pub test/data/services/activity/mda2_android --reporter expanded`：**55/55，actual exit 0**，输出 `test-final.log`。构成原 collector 25 + 新 collector 26 + strict platform 4。新 collector 走真实 MethodChannel Dart 平台、mock native 返回与本地真实 store/FD；不是实际 Android native/多 engine 现场。
- 覆盖 late activation/query/ack、foreign query/status/batch、terminal-before-activation、外部 stopped 后显式 close、unknown stop 保留、H4 两源部分成功/owner 原字节/真实窄释放、broker false及先成功后丢应答重试、query readiness 不被 running 抹掉且显式再query可恢复、nonempty/preflight cancel 不漏lease、active attempt 后可再close、两类无回执timeout、退休session、同revision冲突。
- `dart analyze --fatal-infos` 定向 3 个 D 源文件与 3 个测试文件：**exit 0，No issues found**；输出 `analyze-final.log`。format 成功；`git diff --check` **exit 0**。
- `final-source-manifest.json` 对 3 个 D 源、U store、normalizer、key repository、3 个测试共 **9 文件**源码/镜像 SHA256 逐字节相同。
- 最终核心 SHA256：collector `DD7F1F65F850A3FE339CDD329066411612CDF632BA2C97CED9EE3C31254D2F68`；platform `8F41CDC6F1CB90014E0F7C4EF0DDC1BF1C03CC1904F1C80D76C4CAF028661F34`；lease `EC88ACA09332484282D355B0E89948665C5FF21BC56115ADB958A31049124A41`。

## 失败历史与限制

- 前初版 activation 变量作用域错误、无实际完整测试已修。第一轮真实测试 3 失败：两处旧 native fixture 缺 observation_status、H4 预期码不符 store 固定码；已适配并保留回归。中间 42/42 只验证内部 3-key fake，独审指出实际 native 7-key mismatch 后修复并以最终 55 项替代，不能把 42 项当协议接合证据。
- C 盘满时 collector 一度截断；暂停后由主窗释放本轮可恢复已完成 worktree 空间，从 U 保留的初版和本轮 exact 工具脚本重建，在 D 盘 format 验证再替换，最终测试/9 文件 hash重新绑定。未删除 shared 缓存、他人资料或并行脏改动；最终 C 可用约 6.8GB。
- 无 App 构建/安装、设备、真实 Usage 数据、第二 engine/第二进程、生产接线或 schema 改动。尚需 V 独审、U/W0 组合、唯一候选和本轮真人 Gate；55 项本地合成不等于设备验收。
