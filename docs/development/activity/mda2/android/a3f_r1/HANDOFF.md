# A3F-R1 有界迟到重扫与确认交付

状态：isolated local candidate，等待 W0 独立审计/集成；没有 APK、安装或真人 Gate 通过声明。
基线/唯一 parent：`6b7546715acea81948874809daf67a32c208b238`。
分支：`codex/mda2-a3f-r1-late-events-20260916`；候选为本文件所在提交，完整 SHA 由 worker final 和 W0 `git rev-parse HEAD` 核对。
工作树：W0 `tmp/mda2-a3f-r1-worktree`；不得把默认主窗工作树当成本包源码。

## 结果与契约

- `sealedThroughMs` 只保留历史字段兼容及查询进度，不是系统发布完整性水位。查询重新扫描当前连续允许 epoch 内仍有效的 300000ms 尾部，忽略 UI 前移起点；不跨 boot/owner/service/watcher/撤销与恢复区间回填。
- native ledger 最多保留2048个 reduced identity（含过期去重），单在途128项；ACK绑定epoch/id，逐项accepted/duplicate/显式终止拒收后退休；retry保留。重复查询不创建重复pending，ACK丢失不重复sequence。容量溢出按“发生溢出的查询批次”计数，不伪称唯一丢失事件数。
- FGS主动本机 `onBatch` → Dart durable enqueue → epoch/id/dispositions ACK；手动query使用同一ledger。30秒查询与5秒交付重试只是调度，不是发布watermark。只有诊断变化、没有新事件时也能交付诊断。
- occurrence、TTL、Core wire和outbox schema不变。迟到而早于已durable顺序边界明确`late_out_of_order`；超龄明确`expired_before_acceptance`；不伪造时钟回退。有效同批事件先入库，随后只标记本地delivery gap，不插入now时间错误事件误伤剩余occurrence。
- 本地遗漏累计不随fresh清零；诊断永远显示`publication_completeness=unknown`。仅refresh直接读取当前collector的sequence/coverage/fixedCode，同时保留stop快照。
- storage outbox_full在delivery专用入口保留真实授权barrier；原native责任一直retry到原TTL，届时显式expiry omission。现有FileActivityOutboxStore没有原地释放容量API，合成accepted receipt也保留records，**不承诺满容量自行恢复**。可解除的瞬时拒写已用注入接口验证原occurrence仅产生一个sequence。
- engine失联保留有界内存pending及可见断连计数；重新可用时报告超龄/遗漏。进程死亡来不及保留的尾部仍unknown，新epoch不回填；本包没有新增native磁盘spool，也没有承诺完整无损。

## 真实验证与失败记录

| 检查 | 最终结果 |
|---|---|
| `verify_a3_android.ps1 -ReuseHarness` | **31/31**，原22＋ledger7＋迟到2；源集编译通过、逐字mirror一致；1m25s，5任务执行/17复用 |
| W0原`LatePublicationTest` | 原断言保持；EMPTY反例由1fail转green；另测非空raw后UI起点前移仍能重扫 |
| `verify_a3_flutter.ps1 -NoResolve` | **25/25**，源码/测试analyze无问题、最终mirror一致；含真实MethodChannel主动receipt、ACKloss、满容量重复retry、瞬时拒写解除、TTL、同ms、乱序与diagnostics-only |
| `verify_a3d_flutter.ps1 -NoResolve` | **15/15**，入口/UI/测试analyze无问题、最终mirror一致；主动batch后仅refresh、不poll的sequence/readiness/遗漏投影一致 |
| `verify_a3f_r1_static.ps1 -WorkingTree` | scope/privacy通过，Manifest/Gradle/pubspec/lock/共享outbox/Core/全局状态零diff；最终commit静态见worker final |
| `git diff --check` | 通过 |

保留的实际失败：最初沙箱阻止Flutter SDK lock、默认Gradle离线插件解析失败；提升运行权限后复用原缓存通过。离线pub生成配置后active_roots登记失败，后续NoResolve使用本地已生成配置；A3-D补齐同依赖的package_config/package_graph，rootUri指向各自镜像。初次Dart编译有可选delivery接口类型收窄错误，修正为显式接口cast；专项22pass/1fail暴露outbox_full错误推进barrier，已由delivery专用入口修复；随后清除3条lint。没有改候选依赖或删安全检查。既有verify脚本显示“Downloading packages”来自`pub get --offline`的缓存解算输出，没有网络解析。

## 未完 Gate / 收工边界

W0执行最终commit独立反例、相邻A1/A2及统一回归，决定是否集成；APK构建/安装、真实锁解、设备权限边沿仍未执行。后续真人协议应在完整授权epoch中锁屏/亮屏/解锁，解锁后立即在手机query并刷新，交付明显短于5分钟、不等待主窗回执；缺项仍未知，不用等待当完整性watermark。
本包不写DEVLOG/I_PROJECT_STATE/Roadmap，由W0统一维护。单次本地commit使用已有`SKIP_PROJECT_STATE=1`例外并恢复原环境；无push/publish。

## Path manifest

- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityDeliveryLedger.kt`
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityPermissionEpochStore.kt`
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`
- `android/app/src/test/kotlin/com/memexlab/memex/activity/ActivityDeliveryLedgerTest.kt`
- `android/app/src/test/kotlin/com/memexlab/memex/activity/LatePublicationTest.kt`
- `docs/development/activity/mda2/android/a3f_r1/HANDOFF.md`
- `lib/data/services/activity/mda2_android/android_activity_collector.dart`
- `lib/data/services/activity/mda2_android/android_activity_normalizer.dart`
- `lib/data/services/activity/mda2_android/android_activity_signal_platform.dart`
- `lib/ui/a3d_device_gate/a3d_device_gate_controller.dart`
- `lib/ui/a3d_device_gate/a3d_device_gate_screen.dart`
- `test/data/services/activity/mda2_android/a3d_device_gate_test.dart`
- `test/data/services/activity/mda2_android/android_activity_collector_test.dart`
- `test/data/services/activity/mda2_android/verify_a3_android.ps1`
- `test/data/services/activity/mda2_android/verify_a3_static.ps1`
- `test/data/services/activity/mda2_android/verify_a3d_static.ps1`
- `test/data/services/activity/mda2_android/verify_a3f_r1_static.ps1`
- `test/data/services/activity/mda2_android/verify_a3f_static.ps1`
