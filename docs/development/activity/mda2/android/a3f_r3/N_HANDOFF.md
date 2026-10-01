# A3F-R3 N 包 handoff

- 日期：2026-09-27；执行 task：`/root/r3_native_impl`；GPT-6 Astra / high。
- 精确基线：`b2adc44b7c04983a931c39695b81491cd295084b`；进入时 HEAD 一致且 clean。
- 分支：`codex/a3f-r3-native-20260927`；隔离 Worktree：`C:\Users\ExampleUser\.codex\worktrees\a3f-r3-native\memex`。
- 交付：未提交最小 diff + 本 handoff；没有 commit / push / 主线集成 / APK 构建 / 设备或真实数据访问。
- 权威合同：W0 主窗的 `docs/development/activity/mda2/android/a3f_r3/W0_CONTROL_CONTRACT.md`。未修改共享验证脚本、全局状态、DEVLOG 或其他工作包路径。

## 结果

- 独立 `getObservationStatus/onObservationStatus` 使用 exact 字段、进程 session、启动 observation、递增 revision。初始 unknown；状态读取无采集/持久写副作用。关联值只在本地控制面使用，未加日志或 UI 导出。
- 原生 stop 先同步关闭 active/交付，再清理 receiver/watcher/FGS；在串行 query executor drain 与 onDestroy 都成立后才发 stopped。3 秒未确认只回 unknown，drain 继续；清理失败或 active epoch 停止写失败投影 unknown，不释放 startup gate 允许后继绕过。
- stop、旧通知 Intent、旧 query/batch/ack、detach 以本代 token / bridge generation / delivery epoch 隔离。旧通知拉起的无 token 空实例只自停；旧 START/STOP 不关闭已认领的后继。该分支使用生产共享决策函数并有行为测试。
- 新 `activateObservation` 校验两 source 当前原生 lease；旧 activate 拒绝为 observation_control_required。旧 deactivate 只停止自己 handler 已拥有的目标。所有新增变更性控制方法限 hereIAmV3 Debug。
- 进程静态两 source lease broker 跨 handler 共用；旧 token 无法释放后继；detach 不释放可能仍活的 writer。恢复 permit 必须精确 stopped 且无 lease，存活期间拒绝 activation、第二恢复者与空 permit acquire；持 permit 按 usage→screen 取两 lease，全部释放后才可 end。
- H2 `debugInvalidateObservationNotification` 只对当前运行代显式掩码 Activity 通知可见性证据，再执行原 `queryAndAccumulate/queryEvidence/prepareQuery/stopForContinuityLoss`；没有直接 stop、改全包权限或清其他通知。属于故障注入，未声称物理通知移除或 OEM 事故复现。
- 保持 R2 10 秒单调启动 deadline / 100ms 检查、显式 opt-in、BLE 隔离及既有 AppOps taint/recheck 语义。running 是服务生命周期，不代表每个 source fresh；权限 query readiness 仍独立。

## 拥有路径与窄扩展

- Service、Channel、Startup helper、新 ActivityObservationControlState helper 与新具名测试。
- W0 额外批准 `AndroidActivitySignalCollector.kt` 仅将 `DynamicScreenSignalReceiver.stop()` 改为 Boolean 确认；注销失败保留 registered=true，让服务不能吞错确认终态。其余 collector 逻辑不变。
- normal 入口、Manifest、Gradle、依赖、Core/wire、持久 schema、outbox、BLE 无 diff。

## 验证

最终执行 `test/data/services/activity/mda2_android/verify_a3_android.ps1 -FlutterSdk D:\flutter -AndroidSdk C:\Users\ExampleUser\AppData\Local\Android\Sdk -Gradle <现有 gradle-8.14/bin/gradle.bat> -JavaHome "D:\Android Studio\jbr" -ReuseHarness`。

脚本基线清单不含两个新增文件：执行前将新 helper/test 分别复制到隔离 `.verification_android/android/app/src/main|test/kotlin/com/memexlab/memex/activity/`；执行后额外比对这两个文件的 SHA-256。脚本自身比对其已有源清单。W0 集成时应将这两个路径加进共享脚本清单。

最终 run `48848`：离线 `testHereIAmV3DebugUnitTest --tests com.memexlab.memex.activity.*`，BUILD SUCCESSFUL，**74 tests / 0 failures / 0 errors，整体 exit 0**；镜像所有测试候选文件字节一致。`git diff --check` exit 0。

| suite | tests |
|---|---:|
| ActivityDeliveryLedgerTest | 7 |
| ActivityObservationControlStateTest | 21 |
| ActivityPermissionEpochAuthorityTest | 10 |
| ActivitySignalPolicyTest | 12 |
| ActivityStartupConfirmationTest | 16 |
| ActivityStartupServiceIntegrationTest | 6 |
| LatePublicationTest | 2 |

其中 6 项 ActivityStartupServiceIntegrationTest 是源码字符串契约守门，不是 Android lifecycle 行为测试。其余 68 项是 JVM 逻辑/文件测试；新增 21 项包含状态双门、generation、permit、12 线程同 source 单赢家、真实 epoch authority 停止写失败，以及共享 Intent 决策函数。未新增或宣称 Robolectric / instrumentation / 双真实 engine / Android 跨进程锁证明。

失败/重跑历史：编辑脚本一次默认 GBK 读取中文 Service 失败（此前 helper/startup 修改保留，改显式 UTF-8 后完成）；第一次直接 Gradle --version 因 JAVA_HOME 未设失败，专项脚本使用既有 JDK 后正常。首次专项当时 65 项通过，但在 W0 批准的进一步清理确认改动后收尾 hash 检出 drift，脚本 exit 1，该次不作为候选验证。第二次冻结候选 71 项及完整 hash exit 0；随后 W0 指出旧通知空实例问题，修复及新增 3 项后取得上述最终 74 项结果。

## 限制与下一步

- 这是隔离 hereIAmV3Debug Android 源集镜像编译及 JVM 专项；没有实际 App 完整 source-set 构建、APK、安装、设备 UI/FGS/通知、真实第二 engine/第二进程或真人 Gate 证据。
- 源码中的 drain/onDestroy/receiver/API 接线仍需 W0/V 独审与唯一候选 H1/H2/H3 设备验证。N 不把 helper 测试升级为平台时序通过。
- 原生 broker 不替代 Dart owner.json 签名权威或跨进程 OS gate；必须由 D/U 在所有打开 gate FD 前取 lease，并持至文件句柄关闭。permit 不自动 TTL 清除，异常状态保留恢复身份。
- 无新权限撤回强制 stop 语义；D/U 不得仅凭生命周期 running 把 source 提升为 fresh/ready。
- 本包待 W0 复核/集成，与 D/U 组合验证及后续设备 Gate；没有提前宣称 Goal 完成。

## 候选文件 SHA-256

- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`：`C68EB7DFDB15263532BCDA1DEEE70A622DEC8BC26E28E94D26CFD628E2FFCB5B`
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`：`BFF7CAFB7A275482AC0025C03366B2874C27AD22B9A3A6897F764092B2A76D66`
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityStartupConfirmation.kt`：`2E87EDFFA6374EE3C1F488AEAFFD79B05D56DB1D8B67C0BA23CDF248C3353F5D`
- `android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt`：`2DABC1488D23A6B3AE0435FCF66625686AE219D8670BD73E7C1041FCB60AB295`
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationControlState.kt`：`6A1A3EDA567A9AB095EFAC4A18F27A13ACD6AFC1A3A3DFCA3DF35485A6624C15`
- `android/app/src/test/kotlin/com/memexlab/memex/activity/ActivityObservationControlStateTest.kt`：`3F0EAF394CB40A0D90921AF45ADE34827A3347B8F7088A3DA5F69DE62BC54A8F`
