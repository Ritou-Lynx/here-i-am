# MDA-2 A3-F W0 独立验收

> 2026-09-16；源码 `5110ea19dd4e851eb8f620acdeb10d6e43149f93`，精确父提交 `add2c1e6e06a8606fa6e6d58061f7540ca2fa958`；19 个交付路径，worker Worktree clean。

## 裁决

**接受限定源码交付并选择性本地集成。** 用户已经接受显式 opt-in、持续通知、额外耗电与 Android/OEM/商店限制。候选只由 A3-D Debug 入口启停，原生还检查 V3 包名与 debuggable；正常 main/router/settings/DI 为零引用。

这不是 APK、部署或设备行为验收。A3-D2 的 OEM 延迟广播反例继续为 FAIL；新 APK hash 产生后必须从零重跑真人 Gate。

## 代码审计

- 动态 SCREEN/USER_PRESENT receiver 只有 query hint，不携带 callback 时钟。screen/keyguard/app activity 只使用 UsageEvents 原始 occurrence timestamp；旧 22:01 事件不会因 00:17 收到广播而变成 fresh unlock。
- Activity specialUse FGS 使用独立 notification channel、停止 action 与生命周期。没有 BLE/Companion/check-in 的 start/stop/recovery 引用，没有 boot、sticky、Alarm 或 WorkManager 恢复。
- AppOps watcher、boot marker、owner fence、service instance、可见通知与实际前台状态共同建立 epoch；查询前后复核及 generation fence 隔离 race。regrant 从当前新 epoch 开始，不回填旧间隙。
- persisted epoch 不能独立授予 authority。旧 open tail、死亡/重启、owner/boot/service mismatch、状态损坏或不可写均 fail closed。cursor 落盘后才释放 reduced signals。
- null、exception、locked、denied、empty 与 unknown gap 使用不同固定码；empty 不证明 inactivity。package/app/raw event 仅在内存粗化，不进入 channel/outbox/evidence。
- 主 Manifest 的 specialUse declaration 属于已确认计划中的明确拥有范围；runtime 的 Debug 限制不等于 release Manifest 移除。未来产品发布仍需单独处理 specialUse 申报与发行范围。

## W0 独立复测

在 Git archive 的干净候选副本执行；测试镜像逐 SHA-256 与候选源文件一致。

| 验证 | 真实结果 |
|---|---|
| Android 候选源集与 authority/policy | exit 0，22/22，BUILD SUCCESSFUL |
| 正式 App hereIAmV3Debug 源集单元任务 | exit 0，22/22，723 tasks，BUILD SUCCESSFUL |
| A3 Dart / analyze / mirror | exit 0，18/18，zero issues |
| A3-D Dart / analyze / mirror | exit 0，14/14，zero issues |
| A1 / A2 / analyze / mirror | exit 0，56/56 + 31/31，zero issues |
| wire / in-memory Core | exit 0，20/20，unknown 6、privacy 7、duplicate/TTL 通过 |
| A3-F / A3 / A3-D static | exit 0 / 0 / 0，精确 19 路径 |
| Git diff check / worker status | exit 0 / clean |

保留环境失败：首次受限 SDK lockfile、隔离 Gradle plugin cache、组合脚本参数/路径与 Pub active_roots registration 均曾阻止运行，未计为通过。正式 App 任务还曾因缺少生成插件映射/registrant，以及未使用的 integration_test dev plugin 动态版本清单而失败。只在测试副本补齐生成对象并排除该未使用开发插件后，正式 Kotlin/Java 源集与22项单元测试通过；候选、产品源码、Manifest、Gradle和依赖声明未改。这些自动结果不替代同 hash 真人 Gate。

## 下一停点

从本地集成后的干净提交构建唯一 hereIAmV3 Debug 诊断 APK；构建前 critical fixes 必须 exit 0。核对可回退正式 APK、设备身份、Usage Access/通知初态和本地/设备 base.apk SHA-256 后，重跑 opt-in、正常锁解、延迟广播、revoke/regrant、死亡/停止/重启、通知、隔离与耗电矩阵。

Android 16 上 own-service foreground proof、OEM AppOps callback 完整性、UsageEvents screen/keyguard 完整性、retention 和实际耗电仍未验证。没有 push、发布、生产 binding、Core transport 或整晚结论。
