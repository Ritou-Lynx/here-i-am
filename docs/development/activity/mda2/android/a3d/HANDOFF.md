# MDA-2 A3-D0 Android 真机诊断入口候选交接

日期：2026-09-14
状态：`local_candidate_ready_for_W0_review`；不是 APK、部署或真机 Gate 通过证明。

## 1. 身份与固定基线

- 工作包：A3-D0，显式 `hereIAmV3` Debug-only 诊断入口。
- worker 分支：`codex/mda2-a3d-device-gate-20260914`。
- 固定父提交：`be18b91a2882d4b86e300e5d10c819d4ca3da58b`。
- 源码候选提交：`6659c1911cbe2c75a5db15bdce8b066dcb3bf25d`。
- W0 主任务：`01a0917d-17fa-7bf3-a282-fd4c551d93b2`。
- 路由：L2，`gpt-5.6-sol / high`。
- Worktree：`C:/Users/ExampleUser/.codex/worktrees/aadd/memex`。

冻结提交中不存在 `docs/development/activity/mda2/A3D_ANDROID_DEVICE_GATE_PLAN.md`。W0 明确要求不读取或复制 `D:/memex` 的未提交计划，并确认本次派发消息是本包正式契约；本候选按该契约实现并在此记录差异。

## 2. 精确路径清单

源码候选提交只新增以下 6 个路径：

- `lib/a3d_device_gate_main.dart`
- `lib/ui/a3d_device_gate/a3d_device_gate_controller.dart`
- `lib/ui/a3d_device_gate/a3d_device_gate_screen.dart`
- `test/data/services/activity/mda2_android/a3d_device_gate_test.dart`
- `test/data/services/activity/mda2_android/verify_a3d_flutter.ps1`
- `test/data/services/activity/mda2_android/verify_a3d_static.ps1`

本交接文档由后续 docs-only 提交增加，因此不改变上述源码候选对象。

零改动路径：正常 `lib/main.dart`、router、settings、DI、Manifest、Gradle、依赖、A3-I Kotlin/Dart、PhoneUsage、DB/Core/wire、BLE、check-in/background、`I_PROJECT_STATE.md`、`DEVLOG.md`、Roadmap。

## 3. 实现结果与副作用边界

- 独立入口仅在 `kDebugMode && appFlavor == 'hereIAmV3'` 时提供诊断页；其他构建显示固定不可用页。正常产品启动链没有 A3-D 引用。
- 构造 controller 不读写任何状态。点击“开始诊断”前：不创建密钥、不注册 receiver、不查询 UsageEvents、不创建 outbox、不分配 sequence。
- 场景绑定明确标为 `synthetic_local_diagnostic`，不是服务端签发 source binding。只用于本机诊断，不连接 sender、Core、HTTP、网络、定时器、scheduler、WorkManager、Alarm、FGS、boot 或 autostart。
- 完整场景只在用户点击后显式创建专用 A3 key，并启动既有 A3 collector。三种负例（缺 key、缺 Usage binding、缺 Screen binding）在 native/outbox 前 fail closed。
- Usage 查询只能由“查询新 Usage 事件”按钮触发；没有自动轮询或历史回填。窗口从当前诊断会话开始；进程死亡、force-stop、重启、Doze 或权限间隙一律保留为 unknown/gap。
- `com.memexlab.hereiam.v3 -> other` 只作为原生内存分类输入，不进入 evidence、outbox 或 wire；不展示包名或 App 名。
- 已存在持久状态、密钥缺失、binding 缺失、权限 denied/revoked、平台错误均失败关闭；未知异常统一投影为固定 `diagnostic_failed`，不回显异常文本。

## 4. 最小证据与隐私负例

可复制 evidence 只有：

- schema、`synthetic_local_diagnostic` authority、readiness；
- Usage permission 枚举；
- observed time、每 source sequence；
- 非敏感操作/事件计数；
- coarse usage observation（category、开始/结束时间）；
- screen off/on/unlock 的计数与最后时间。

Evidence codec 先精确校验完整 `device.activity.v1` record、coverage 和 payload，再做最小投影。未知字段或形状不合法时整条拒绝，固定错误为 `diagnostic_evidence_invalid`。确定性负例覆盖 `packageName`、`appName`、`rawUsageEvents`、`privatePath`、`token`、`exception`，同时覆盖 payload 和 coverage 注入；这些字段不会进入 evidence/outbox/wire。

## 5. 显式诊断 reset

- 仅允许在 collector 已 dispose、没有 live owner 时手动触发。
- 根目录必须精确解析为 native no-backup 下的 `mda2_activity`，且只接受已知 source 目录与 A2 store 文件；出现未知 child、未知 owner 或无法证明的状态就拒绝，不删除。
- stale owner 必须先通过既有 signed recovery inspection、精确 recovery authority 和稳定 OS gate 核验；缺少证明时保持 `recovery_authority_required`/unknown。
- reset 只删除这个诊断 namespace 的精确 outbox。不会清 app data、DB、聊天、BLE、其他目录，也不会自动轮换或删除 key。

## 6. 本地验证记录

| 验证 | 最终结果 | 说明 |
|---|---:|---|
| `verify_a3d_flutter.ps1 -FlutterSdk D:\\flutter -NoResolve` | exit 0，14/14 | A3-D 单测、源码/测试 analyze、mirror byte identity |
| `verify_a3_flutter.ps1 -FlutterSdk D:\\flutter -NoResolve` | exit 0，16/16 | 既有 A3 Dart 回归 |
| `verify_a3_android.ps1`（已缓存 Android SDK/Gradle/JBR） | exit 0，12/12 | 既有 A3 Kotlin 与独立 hereIAmV3Debug source set |
| `verify_flutter_synthetic.ps1 -FlutterSdk D:\\flutter -NoResolve` | exit 0，A1 56/56、A2 30/30 | 既有 A1/A2 回归与 analyze、mirror identity |
| `node verify_wire.mjs D:\\flutter\bin\cache\dart-sdk\bin\dart.exe` | exit 0，20/20 + 20/20 | fixture validator、内存 Core；另含 unknown 6、privacy 7、duplicate/TTL |
| `gradle.bat -p android testHereIAmV3DebugUnitTest --offline --no-daemon --console plain --quiet` | exit 0 | 完整 hereIAmV3Debug Android App unit task |
| `verify_a3d_static.ps1 -BaseCommit be18... -CandidateCommit 6659...` | exit 0 | 6 个 owned path，正常入口/受保护路径/依赖边界通过 |

失败也保留：

- 首次 A3-D、A3、A1/A2 离线 resolve 均因本机 Pub `active_roots` cache registration 失败 exit 1；已存在有效离线 package config，使用 `-NoResolve` 的测试执行本身全部 exit 0。没有下载依赖。
- A3-D widget 首版在 fakeAsync 中等待临时目录创建导致两次手动中止 exit 1；改为 `tester.runAsync` 后 14/14。
- Full App 首次找不到仓库 Gradle wrapper、随后缺 ignored `android/local.properties`、再因 ignored Flutter plugin metadata/registrant 缺失而 exit 1。用现有离线缓存机械生成 44 个 Android plugin metadata 和 registrant 后任务 exit 0；临时脚本、metadata、`local.properties` 和 registrant 全部删除，未进入候选。
- 静态守门首次把自身两个 `verify_a3d_*` 文件误判为范围外并 exit 1；只修正测试脚本白名单后重跑 exit 0，修正已包含在固定候选提交。
- 提交后的 A3-D 最终复跑首次在受限沙箱中无法访问 `D:\\flutter\bin\cache\lockfile`，exit 1；以同一命令获得本机 SDK 访问权限后重跑 exit 0，14/14 与两组 analyze、mirror identity 再次通过。
- Full App 输出仅有 NDK 27/插件要求 28.2 与未来 Kotlin built-in migration 警告；本包未改 Gradle/NDK。

## 7. W0 真机 Gate 清单（后续、需单独授权）

以下均未执行。W0 应先固定并审计 commit，再按同一 APK SHA-256 顺序执行；任何重建导致 hash 变化都必须从头建立证据。

1. 在候选合入目标树复跑 critical-fixes 与上表回归；只构建 `hereIAmV3` Debug、target `lib/a3d_device_gate_main.dart`，记录 APK 大小与 SHA-256。
2. 安装前后核对设备 `base.apk` 与本机 APK SHA-256；不要把安装成功当 Gate 通过。
3. 初始页证明 `diagnostic_not_started`、permission unknown、sequence 0；不点按钮时观察无 receiver/query/outbox 副作用。
4. 分别运行缺 key、缺 Usage binding、缺 Screen binding 三个负例，证明均在查询、receiver、outbox 和 sequence 前失败关闭。
5. 运行完整场景；先 denied 手动 query，再从 Android 设置授予 Usage Access、返回并 query；切换一个未映射 App 后 query，结果只能是 coarse category；撤销、query、重新授予、query，权限间隙只能 unknown/gap，不补历史。
6. 手动执行 screen off、screen on、unlock，每一步点“刷新最小证据”；证据只应出现类型计数与时间。
7. 先复制最小证据，再停止 collector。显式 reset 先验证 active-owner 拒绝，再在 dispose 后验证只删除 `mda2_activity` 诊断 outbox、key 保留、其他 App 数据不变。
8. 把 process death、force-stop、restart、reboot、Doze 放到后段逐项做：前后分别留证；空白期不解释为 quiet/active/asleep。遇 existing/stale owner 必须先显示恢复权威不足/unknown，只有显式核验 reset 后才开始新会话。
9. BLE 共存只能用同一 APK hash 下独立、可观察的既有 BLE 会话证明。诊断入口不读取、启动、停止或控制 BLE；若同一候选无法建立 BLE 会话，该项保持 pending，不得用本地测试替代。
10. 每项记录设备型号、Android/厂商系统版本、Usage Access 页面状态、步骤时间、最小 evidence、APK/device hash；失败时只记录固定错误码和非敏感计数。

## 8. 支持、不支持与回滚

当前支持：本地显式启动/停止；手动 Usage query；A3-I 现有权限与屏幕信号；最小证据复制；严格、显式、诊断专用 reset；确定性合成负例。

当前不支持：正常产品入口、生产 binding、sender/Core/network、后台采集、自启、定时轮询、历史补采、睡眠/活动推断、真实设备结论、BLE 共存结论、整夜记录、APK 构建/安装、发布或 push。

清理顺序：复制证据 → 停止并 dispose collector → 确认没有 live owner → 显式 reset。不要用清 App 数据、卸载、删除 DB 或轮换 key 作为诊断清理。源码回滚是撤销 `6659c1911cbe2c75a5db15bdce8b066dcb3bf25d`；它没有正常产品引用，未构建/安装时无需设备回滚。

## 9. 下一步

W0 独立固定字节、审查 diff 与关键断言，重新运行必要测试；通过后才能决定是否选择性集成。随后另行授权构建和真机短场景 Gate。当前不得把本候选表述为 Android 真机采集、BLE 共存或 A3-D 已通过。
