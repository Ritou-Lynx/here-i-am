# MDA-2 A3-I — 主 Android 原生信号与安全持久边界交接

> 日期：2026-09-13。状态：首个候选 `5f54d5b407ef206ed23899df3ec22b63d8fdc39a` 已被 W0 拒绝；A3-I R1 在同一分支以单一追加提交修复并完成本地自动验证，等待 W0 重新独立审计。不是 APK、部署、真机、Doze/强停/重启或整夜 Gate。

## 身份与固定对象

- 工作包：MDA-2 A3-I；W0/source task：`01a0917d-17fa-7bf3-a282-fd4c551d93b2`。worker task ID 未在当前执行上下文暴露，由 W0 创建回执持有。
- 实际模型 / effort：`gpt-5.6-sol / high`。
- Worktree：`C:/Users/ExampleUser/.codex/worktrees/7990/memex`；分支：`codex/mda2-a3i-android-native-20260913`。
- 精确起点：`v3-lab@c5d7cbfe559eb517b3b1110f27e07dc8308d6442`；启动时 detached HEAD、工作树干净，且该提交由 `v3-lab` 包含。随后才创建临时候选分支。
- 被拒候选：`5f54d5b407ef206ed23899df3ec22b63d8fdc39a`，parent 为固定起点 `c5d7cbfe559eb517b3b1110f27e07dc8308d6442`。拒绝原因是 frozen outbox 的 `lineageBlocked=true` 被 collector 错当成 ownership 已释放，`dispose()` 会遗留 `owner.json` 和进程内 `owner.gate`。
- R1 交付 commit：本文件所在的单一追加修复 commit，parent 必须为 `5f54d5b407ef206ed23899df3ec22b63d8fdc39a`。Git commit 不能在自身内容中包含自己的最终 SHA；完整 SHA 由 worker 最终回报给 W0，W0 必须以 `git rev-parse HEAD` 独立固定。
- 未 push、未 merge、未写 `D:/memex`、未构建或安装 APK、未运行 adb、未连接手机/BLE/真实 Core/凭据/数据库/网络、未读取真实 UsageEvents。

## 路径 manifest

仅有以下候选路径：

1. `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivitySignalPolicy.kt`（新建）
2. `android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt`（新建）
3. `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`（新建）
4. `android/app/src/main/kotlin/com/memexlab/memex/channels/ChannelRegistrar.kt`（仅新增一行注册）
5. `android/app/src/test/kotlin/com/memexlab/memex/activity/ActivitySignalPolicyTest.kt`（新建）
6. `lib/data/services/activity/mda2_android/activity_integrity_key_repository.dart`（新建）
7. `lib/data/services/activity/mda2_android/android_activity_signal_platform.dart`（新建）
8. `lib/data/services/activity/mda2_android/android_activity_collector.dart`（新建）
9. `test/data/services/activity/mda2_android/android_activity_collector_test.dart`（新建）
10. `test/data/services/activity/mda2_android/verify_a3_flutter.ps1`（新建）
11. `test/data/services/activity/mda2_android/verify_a3_android.ps1`（新建）
12. `test/data/services/activity/mda2_android/verify_a3_static.ps1`（新建）
13. `test/data/services/activity/mda2_android/.gitignore`（只忽略 A3 验证 scratch）
14. `docs/development/activity/mda2/android/a3/HANDOFF.md`（本文件）

明确未改：`AndroidManifest.xml`、`PhoneUsageChannelHandler.kt`、`MainActivity.kt`、BLE/Companion foreground/checkin/alarm/workmanager、Core/validator、DB/schema、DI/UI、根依赖、Roadmap、`I_PROJECT_STATE.md`、`DEVLOG.md`。既有 A1 normalizer 与 A2 durable outbox 源码也未修改。

## 实现结果

1. 新增独立 MethodChannel `com.memexlab.memex/activity_signal`。它不调用、不复用、不修改 `PhoneUsageChannelHandler`；后者继续只服务现有按需聚合查询。
2. UsageEvents 原始包标识只进入 Kotlin 内存分类查找。调用方注入 package-to-category 白名单，固定类别仅为 `chat/social/video/reading/work/other`；Dart 只接收 `type/signal_at_ms/category`，没有 package、app label 或 raw UsageEvents。
3. Kotlin 查询窗口固定为 `[start_ms, end_ms)`；只接受 `ACTIVITY_RESUMED`，过滤未知事件、无映射包和窗口外事件，去重后按信号时间排序。首次无 Usage Access 是 `denied`；曾 granted 后丢失是 `revoked`；两者都返回空活动列表。
4. `ACTION_SCREEN_ON/OFF` 与 `ACTION_USER_PRESENT` 只通过运行期 receiver 映射为 `screen_interactive/screen_non_interactive/user_present`。receiver 只有 native activation gate 通过才注册，在 deactivate、engine restart 或 engine destroy 时注销；Manifest 没有新 receiver。
5. native activation 同时要求 `enabled=true`、Dart 已确认完整 integrity authority、以及 `android_usage_events` / `android_screen_state` 两个 source binding。重复 activation 固定拒绝。缺任一项不注册 receiver、不查询 UsageEvents。
6. Dart `AndroidActivityCollector` 再次在 native activation 前验证总开关、专用 32-byte key、两份不同服务端前缀/source binding、允许 kind/capability 和 `no_backup_private` 根目录。失败只返回固定 readiness，sequence 保持 0。
7. 两个 source 分别使用 `noBackupFilesDir/mda2_activity/<source>`、独立 `FileActivityOutboxStore`、独立 binding/lineage/sequence 和独立 `AndroidActivityNormalizer`。固定 wire 仍是现有 `device.activity.v1/schema_version:1`；未扩 kind、payload、Core response 或 validator。
8. 专用完整性密钥使用 `flutter_secure_storage 10.3.1` 的 Android Keystore 包装 + AES-GCM 默认后端，独立 namespace `mda2_activity_integrity_v1`，且 `resetOnError=false`、`migrateOnAlgorithmChange=false`。显式 provision 生成 32-byte `Random.secure()`；read 缺失、损坏、后端失败、写后不一致和 clear 失败均 fail closed，不自动换 key、不记录 key。
9. native/Dart 异常、readiness 与 audit 只保留固定码和整数计数。MethodChannel 对 native signal 使用精确字段白名单；额外 package/app/private 字段整体拒绝且错误不回显原值。
10. 没有 sender/HTTP/认证/timer/backoff/WorkManager/Alarm/FGS/boot receiver/自启/UI。Channel 虽随 engine 注册，但 collector 无 DI/caller、默认关闭；当前产品不会自动开始采集。

## W0 拒绝与 R1 修复

1. `5f54d5b4` 的 `_closeStores()` 以 `store.lineageBlocked` 跳过 `close()`。A2 的 `lineageBlocked` 同时表示 closed、poisoned 或 frozen，不等价于 ownership 已释放。W0 在干净 Git 导出副本复现：usage store 以非允许 kind 冻结为 `scope_denied` 后，collector `dispose()` 仍保留 owner。
2. R1 删除该错误捷径。collector 对每一个当前持有的非空 store 都调用现有 A2 `close()`，单个失败只记录固定码并继续尝试另一个 store，最后清空引用。没有修改 A2 API、状态机或恢复语义。
3. R1 对 usage 与 screen 各增加同等回归：先冻结对应 store，确认 owner 存在；`dispose()` 后确认 owner 删除；再以相同 source/binding/key 在同进程 `open()`，证明稳定 gate 可由精确后继取得并仍保留 frozen lineage；后继 `close()` 再次释放 owner。
4. frozen store 仍持有有效 owner，因此现有 public `close()` 可以并且必须释放。already-closed 或 poisoned store 可能由 public API 返回 `sequence_authority_required`；collector 保持 fail closed、只审计固定码并继续关闭其余 store。poisoned 路径的 A2 实现已在自身故障处释放 lease，但若 owner evidence 因清理失败保留，必须继续走 A2 精确恢复权威，R1 不猜测、不删除、不扩 A2 API。
5. Kotlin 新增纯 `ActivitySignalRequestPolicy`：`activate` 精确要求 `enabled/integrity_authority_ready/bound_sources/category_mapping`，`queryUsageEvents` 精确要求 `start_ms/end_ms`；missing、unknown、重复 source 或错误类型在 receiver、raw query 和状态变更前以固定码拒绝，错误不回显输入。
6. 查询窗口校验被提升为纯 policy，并由 raw-query lambda seam 固定调用顺序。负数、空窗口与逆序窗口都在 `UsageStatsManager.queryEvents` 边界调用前返回 `invalid_query_window`；单测证明 raw query 计数保持 0。
7. `verify_a3_static.ps1` 现在强制显式 `-BaseCommit`，可选 `-CandidateCommit` 默认 `HEAD`，只比较已解析的 `Base..Candidate` commits，要求 base 是 ancestor、变更数非零，并以同一 commit 对核对 allowlist、protected paths、Manifest blob 和负面源码规则。它不再用 `git diff HEAD` 读取空工作区假装验证候选。

## 故障与隐私矩阵

| 场景 | 候选行为 | 自动证据 |
|---|---|---|
| disabled | 不取目录、不调 native、不注册、不查询、sequence 0 | Dart 通过 |
| 缺 usage/screen binding | `source_binding_missing`，无 native effect、sequence 0 | Dart/Kotlin 通过 |
| key 缺失/损坏/后端异常 | 固定 key 错误，无目录/native effect、sequence 0 | Dart 通过 |
| 非 no-backup root | `private_outbox_root_invalid`，不 activation、不分配 | Dart 通过 |
| Usage granted | 只产粗类别+时间；permission readiness 与活动走 A2 | Kotlin/Dart 通过 |
| Usage denied/revoked | 空活动；normalizer 为 unknown/permission unavailable；旧 last observation 清空 | Kotlin/Dart 通过 |
| 无映射/未知 Usage event | 不输出 | Kotlin 通过 |
| 重复 query signal | 进程内固定 identity 去重，不多分 sequence | Dart/Kotlin 通过 |
| 乱序/未来 signal | A1/A2 时间守门拒绝，不分配新 sequence | Dart + A1/A2 回归通过 |
| native query 异常 | `usage_query_failed` + `collection_failed` gap；异常正文不保留 | Dart 通过 |
| engine destroy/restart | 动态 receiver 注销，分类 map 清空 | Kotlin 编译 + 源码审计；非真机 |
| package/app/raw/private 字段回流 | Kotlin reducer 不输出；Dart exact-shape gate 整体拒绝 | Kotlin/Dart 通过 |
| pre-existing durable outbox | `recovery_authority_required`，不自动猜测/接管 | 源码审计；A2 recovery 仍独立 |
| frozen usage/screen store 后 dispose | 两个当前 owner 都确定性关闭；owner 删除；精确同进程后继可取得 gate | Dart 各一条回归通过 |
| invalid query window | raw UsageEvents query 计数 0；固定 `invalid_query_window` | Kotlin 通过 |
| activate/query missing 或 unknown key | 在 receiver/query/state mutation 前固定拒绝，不回显字段 | Kotlin 通过 |

## 最终成功验证

| 命令 | exit | 结果 |
|---|---:|---|
| `verify_a3_flutter.ps1 -FlutterSdk D:/flutter -NoResolve` | 0 | A3 Dart 16/16；含 usage/screen frozen ownership 回归；owned source/test `dart analyze --fatal-infos` 均无问题；镜像字节一致 |
| `verify_a3_android.ps1 ...` | 0 | 隔离 `hereIAmV3Debug` source-set：Kotlin 12/12，compile main/test 均成功，4 个 Kotlin 被测文件字节一致 |
| `verify_flutter_synthetic.ps1 -FlutterSdk D:/flutter` | 0 | A1 56/56、A2 30/30；两目录 fatal-info 无问题；镜像字节一致 |
| `node verify_wire.mjs D:/flutter/bin/cache/dart-sdk/bin/dart.exe` | 0 | validator 20/20、内存 Core 20/20 accepted、diagnostic unknown 6、privacy negative 7、duplicate/TTL 边界通过 |
| `verify_a3_static.ps1 -BaseCommit c5d7cbfe... -CandidateCommit 5f54d5b4...` | 0 | 修复后的脚本在干净已提交旧候选上真实得到 `changed_paths=14`，并输出完整 base/candidate；Manifest blob 为 `69ac7dfaf315cb3f207a1fe4745f21963a573596` |
| `verify_a3_static.ps1 -BaseCommit c5d7cbfe... -CandidateCommit HEAD` | 0 | R1 提交后最终重跑；实际 resolved candidate/full SHA、非零 `changed_paths=14` 与 Manifest blob 由下方最终记录和 worker 回报固定 |
| `git diff --check` | 0 | 无 whitespace error |

最终静态记录：`BaseCommit=c5d7cbfe559eb517b3b1110f27e07dc8308d6442`；`CandidateCommit=HEAD`（即包含本文件的 R1 commit，完整 SHA 见 worker 最终回报）；`changed_paths=14`；`manifest_blob=69ac7dfaf315cb3f207a1fe4745f21963a573596`。W0 必须在接收后以 `git rev-parse HEAD` 和同一显式命令独立复核 resolved candidate。

Android 验证是只包含 A3 Kotlin 源、Android SDK 36、Flutter embedding 与 JUnit 的隔离 `hereIAmV3Debug` source-set；没有生成 APK。W0 集成后仍应在已正常解析全部插件依赖的主线副本上复跑完整 `testHereIAmV3DebugUnitTest`，不能把隔离 source-set 冒充整 App build。

## 失败尝试（不计通过）

- 首次 A3 Dart：使用不存在的 `FileSystemEntity.isAbsolute`，编译 exit 1；改为只接受 Android `/`、Windows drive/UNC 的纯路径判定。
- 第二次 A3 Dart：11 项逻辑测试通过，但验证镜像未声明直接 Flutter SDK dependency，fatal-info exit 1；补声明后通过。随后新增默认关闭和两项 MethodChannel 隐私/activation 测试，最终为 14/14。
- 清理 scratch 后重建 A3 镜像时，离线 resolve 已生成有效 package config，但本机 Pub `active_roots/c0` 路径故障使 resolve exit 1；按 A2 既有受控方式复用该映射并以 `-NoResolve` 完整通过。没有网络下载。
- 首次 Android：未提供 `JAVA_HOME`，exit 1；验证脚本改为显式注入已安装 JBR。
- 第二次 Android：Windows PowerShell 5.1 重写镜像 Gradle 文件时破坏 UTF-8 中文，配置 exit 1；改用显式 UTF-8 读写。
- 第三次 Android：真实 app task进入 Flutter asset compile，但根 `.dart_tool/package_config.json` 不存在，exit 1。
- 根项目 `flutter pub get --offline` 长时间不返回，人工中止 exit 1；它短暂格式化了 `lib/l10n/app_localizations.dart`，已用精确反向 patch 恢复，工作区 blob 与 HEAD 均为 `d6e7e603c342b837c1e8bea3de59f168f9c4d157`。未保留该范围外 diff。
- 第四次 Android：跳过 Flutter asset compile 后，现有 App 的插件类因无生成插件依赖而 unresolved；同时发现 A3 category 可空收窄编译错误，exit 1。修正 A3 错误并改为窄 source-set；最终两次均 exit 0。
- 所有上述失败均发生在本地/隔离 scratch；没有设备、网络、真实数据或生产副作用。
- R1 首次受限环境运行 A3 Flutter 时，Flutter SDK lockfile 不可写，exit 1；转到允许访问既有 SDK/cache 的本机执行边界后继续，未触发 App build、APK 或设备操作。
- R1 首次受限环境运行 Android 隔离 source-set 时，看不到本机已缓存的 Android Gradle plugin，exit 1；同一脚本使用既有 Gradle/JDK/cache 重跑后通过，没有升级或下载项目依赖。
- R1 A3 Flutter 离线解析再次在生成有效 package config 后命中本机 Pub `active_roots/c0` 故障，exit 1；随后 `-NoResolve` 使用该映射执行。第一轮逻辑测试为 14 pass / 2 fail：回归错误地要求 A2 direct `scope_denied` 路径产生 audit，而 A2 合约只保证固定异常码与冻结状态；ownership 删除和后继获取均已成功。移除这项越界 audit 预期后，最终 16/16 通过。

## 真实支持与不支持

当前真实支持：默认关闭；完整本地 authority 前置 gate；Android 原生权限判定、UsageEvents 的内存粗分类、动态屏幕 receiver；A1 normalizer + A2 durable outbox 的双 source 本地接线；no-backup 私有目录；专用 Keystore-backed 32-byte key 仓库；固定码/计数审计；纯合成/单元验证。

明确不支持或未验证：

- 没有调用方/DI/UI，所以当前 App 不会启用 collector，也没有真实服务端 binding 注入流程；测试 binding 仅为合成对象。
- existing outbox 不自动恢复。A2 的 stale-owner recovery 需要显式恢复权威；A3-I 选择 fail closed，未设计 Android 进程重建授权。
- dynamic receiver 只证明 engine/process 生命周期内的注册/注销代码路径；不证明划掉任务、force-stop、进程死亡、重启、Doze、OEM 省电、锁屏整夜、掉电存储或广播实际送达。
- 没有真实 Usage Access 请求/设置页、真实 UsageEvents 查询、App 分类表来源/编辑/持久策略、真实 noBackupFilesDir 或 Android Keystore 设备验证。
- 没有 Core transport/认证/receipt parser、网络离线恢复、batch、backoff、timer/scheduler/WorkManager/Alarm/FGS/boot receiver/autostart。
- 没有 BLE 接线或共存验证；未修改现有 BLE 生命周期。没有状态 UI、推断、shadow、通知、Chat 或来电。
- 没有 APK/build/install/adb/手机/真实 Core/整夜/真人 Gate。自动测试通过不能提升为 MDA-2 Android 端完成。

## A3-D 真机 Gate 模板（仅供 W0 后续授权）

> 本模板不授权本 worker 或 W0 现在构建/安装。W0 先独立审计、选择性集成并取得 Lynx 对唯一真机候选的明确授权。

### 固定候选

| 字段 | 记录 |
|---|---|
| 集成 commit / dirty state | 待填；必须干净 |
| `verify_critical_fixes.ps1` | 待填；exit 必须 0 |
| 唯一 hereIAmV3 Debug APK 路径 | 待填 |
| 本地 APK SHA-256 | 待填 |
| 设备 `base.apk` SHA-256 | 待填；必须与本地一致 |
| 手机 / Android / OEM / 电池策略 | 待填 |
| Usage Access 初始状态 | 待填 |
| BLE 候选 hash / 状态 | 待填；不得沿用旧 hash 结论 |

### 短场景矩阵

| 场景 | 预期 | 实际 / 时间 / 证据 | 结论 |
|---|---|---|---|
| 默认关闭冷启动 | 无 receiver、无 query、sequence 0 | 待填 | 待验 |
| 缺 key / 单 source binding | readiness unknown；无 receiver/query/sequence | 待填 | 待验 |
| Usage denied | screen 可按授权范围工作；usage 无活动 | 待填 | 待验 |
| grant 后指定白名单 App | 仅粗类别+时间；无包名/app label | 待填 | 待验 |
| 未映射 App / 未知 event | 无活动输出 | 待填 | 待验 |
| Usage Access 撤销 | 立即 unknown/gap；不沿用旧活动 | 待填 | 待验 |
| re-grant | 先 permission readiness，再只接收新 observation | 待填 | 待验 |
| SCREEN_ON/OFF/USER_PRESENT | 三种固定映射、无重复/错序 | 待填 | 待验 |
| App 划掉 / process death | 明确实际停止与 gap，不声称连续 coverage | 待填 | 待验 |
| force-stop | 明确不自动恢复；状态 unknown | 待填 | 待验 |
| 重启 | 明确恢复/不恢复事实；无伪补传 | 待填 | 待验 |
| Doze / OEM 省电 | 记录延迟、缺口、恢复；缺口必须 unknown | 待填 | 待验 |
| BLE 同时运行 | activity stop/start 不影响 BLE；BLE stop 不影响 activity | 待填 | 待验 |
| Core 离线/恢复（后续 transport 包） | 本机 outbox 不重造 bytes/sequence；远端 unknown | 待填 | 待验 |

### Gate 停点

- 任一 package/app/raw/private 值进入 Dart/outbox/wire：立即失败，回 A3-I。
- 任一权限撤销、进程/Doze/重启缺口被写成 quiet/active/asleep：立即失败。
- receiver、FGS、BLE 或现有 check-in 生命周期互相 stop/start：立即失败。
- APK hash 变化：之前所有设备结论作废，固定新候选后重验。
- 短场景全过也只允许进入后续无干预 shadow；至少一晚 Gate 与主动介入仍是独立阶段。

## W0 下一步

1. 用 worker 最终完整 commit SHA 固定对象，核对 parent、14 路径 manifest、Manifest/PhoneUsage/MainActivity/根依赖/Core/DB/BLE/全局状态零 diff。
2. 从 Git commit 导出干净副本，复跑 A3 Dart、A3 Kotlin、A1/A2、wire/Core 与静态负面守门；独立审计 receiver unregister、native exact-shape、key reset policy、双 source sequence 和 pre-existing outbox fail-closed。
3. 若接受，选择性集成到唯一 W0 候选并正常更新 `I_PROJECT_STATE.md` / `DEVLOG.md` / Goal 状态；本 worker 的 `SKIP_PROJECT_STATE=1` 仅限最终提交命令，不传递给 W0。
4. 是否另开 A3-D 真实调用方、完整 App test/build、安装和真机 Gate，由 W0 与 Lynx 单独决定；不得由本候选自动启动。
