# MDA-2 A3-D0 W0 独立验收

> 2026-09-14；固定源码候选 `6659c1911cbe2c75a5db15bdce8b066dcb3bf25d`，父提交 `be18b91a2882d4b86e300e5d10c819d4ca3da58b`；docs-only handoff `cdc585737f7eca404b0db4420dcf219443934f16`。

## 裁决

**接受并允许选择性本地集成。** A3-D0 只增加一个 `hereIAmV3` Debug 独立诊断入口、专用 controller/UI 和测试守门；正常 `lib/main.dart`、router、settings、DI、Manifest、Gradle、A3-I 源码、PhoneUsage、Core/wire、BLE 与后台生命周期均为零改动，正常产品代码也没有引用该入口。

该裁决只接受诊断入口源码。它不是 APK、安装、真实 UsageEvents、BLE 共存或 A3-D 设备 Gate 通过证明。

## 独立审计结论

- 构造 controller 时没有 key provision、receiver、Usage query、outbox 或 sequence 副作用；所有诊断动作都从显式按钮开始。
- binding 明确为 `synthetic_local_diagnostic`，没有 sender、Core、HTTP、网络、timer、scheduler、WorkManager、Alarm、FGS、boot 或 autostart 路径。
- `com.memexlab.hereiam.v3 -> other` 只作为 native 查询的内存分类输入；展示、复制 evidence 与 wire 投影不含包名、App label、原始 UsageEvents、路径、密钥、token 或异常正文。
- evidence 对完整 record、coverage 与 payload 做精确 schema 校验后才投影最小字段；未知字段或非法形状整条拒绝为 `diagnostic_evidence_invalid`，未知异常只暴露固定 `diagnostic_failed`。
- Usage 查询是手动、向前推进的窗口；权限间隙、process death、force-stop、restart、reboot 与 Doze 不补历史，也不解释为 quiet、active 或 asleep。
- reset 只允许在 collector 已 dispose 且 owner 可证明不存在时执行；根目录、子目录和文件均采用精确白名单。stale owner 缺恢复权威或稳定 OS gate 时保持 `recovery_authority_required`，不会凭可解密、mtime 或重启后 uptime 推断安全。

## W0 独立复验

W0 在 detached 干净导出 `cdc58573` 上执行，未复用 worker 运行目录：

| 验证 | W0 结果 |
|---|---:|
| A3-D Dart + analyze + mirror identity | exit 0，14/14，zero issues |
| A3 Dart + analyze + mirror identity | exit 0，16/16，zero issues |
| A3 Kotlin + source mirror | exit 0，12/12，Gradle BUILD SUCCESSFUL |
| A1 / A2 + analyze + mirror identity | exit 0，56/56 + 30/30 |
| wire / in-memory Core | exit 0，fixture 20/20 + Core 20/20；unknown 6、privacy 7、duplicate/TTL 通过 |
| 完整 Android App `testHereIAmV3DebugUnitTest` | exit 0，723 tasks，BUILD SUCCESSFUL |
| A3-D static scope gate | exit 0，精确 6 个 owned source/test paths |
| `git diff --check` / review tree status | exit 0 / clean detached tree |

完整 App task 只为离线测试临时机械生成 44 个 Android plugin metadata、`local.properties` 和 registrant；任务通过后四个临时对象均已删除，review tree 恢复干净，它们不属于候选。

保留失败证据：部分首次离线 resolve 在本机 Pub `active_roots` registration 处 exit 1，但已经生成有效 package config；相同固定源码随后使用 `-NoResolve` 的实际测试全部通过。受限沙箱首次无法访问 Flutter SDK lockfile，获得本机 SDK 访问后同命令通过。这些失败没有被记为测试通过，也没有改动候选。

## 选择性集成与下一停点

只集成源码候选 6 路径、docs-only handoff 和本验收/计划证据。集成前后必须重新核对 `v3-lab` HEAD、空 index 与主目录并行 dirty 指纹，禁止覆盖其他工作。

集成后从新的干净提交构建唯一 APK；构建前 `scripts/verify_critical_fixes.ps1` 必须 exit 0。唯一允许的构建为 `hereIAmV3` Debug，target `lib/a3d_device_gate_main.dart`。记录本地 APK SHA-256 后，才能进入安装前设备状态与 `base.apk` hash 核对。APK 字节一旦改变，旧设备证据全部失效。

设备短场景仍须逐项保留 unknown/gap，BLE 共存只能由同一 APK hash 下真实会话证明；生产 binding、自动调度、Core transport、后台 shadow 与整晚 Gate 均不在本裁决内。
