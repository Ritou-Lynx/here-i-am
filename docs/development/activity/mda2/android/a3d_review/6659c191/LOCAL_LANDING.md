# MDA-2 A3-D0 本地选择性集成收据

> 2026-09-14；目标分支 `v3-lab`。

## 结果

- 固定 worker 源码：`6659c1911cbe2c75a5db15bdce8b066dcb3bf25d`。
- 固定 docs-only handoff：`cdc585737f7eca404b0db4420dcf219443934f16`。
- W0 源码集成提交：`7a6c71778636241d44ae15b15724a9213da15d15`，父提交 `be18b91a2882d4b86e300e5d10c819d4ca3da58b`。
- 集成提交只含 6 个候选 source/test 路径、handoff、A3-D 计划和 W0 验收，共 9 个新增路径。
- 6 个 source/test Git blob 与 `6659c191` 逐路径相同；handoff blob 与 `cdc58573` 相同。

## 主目录保护

落地前 `D:/memex` 为 `v3-lab@be18b91a`，index 为空，共 56 个 tracked 并行修改。集成脚本在写入前核对分支、HEAD、空 index 和九个目标路径均不存在；提交前后对原 56 个 tracked dirty 路径逐文件 SHA-256/缺失状态复核，全部保持。集成后 index 再次为空，未 reset、stash、pull、删除、push 或构建主目录。

## 验收继承

W0 已在独立 detached 干净导出复跑 A3-D 14/14、A3 Dart 16/16、A3 Kotlin 12/12、A1 56/56、A2 30/30、wire/Core 20/20 与完整 `testHereIAmV3DebugUnitTest`，全部 exit 0；范围、最小证据、隐私负例、恢复权威与 reset fail-closed 审计通过。详见 [W0验收](W0_ACCEPTANCE.md)。

## 当前边界与下一步

当前完成的是 Debug-only 诊断入口源码本地集成。尚未构建 APK、调用 adb、访问真实 UsageEvents、安装设备或验证 BLE。

下一步从本收据提交后的干净 commit 导出唯一构建树，先运行 `scripts/verify_critical_fixes.ps1`；只构建 `hereIAmV3` Debug 且 target `lib/a3d_device_gate_main.dart`，记录 APK SHA-256。安装前后必须对设备 `base.apk` 做 SHA-256 绑定；任何 APK 字节变化都会使此前设备证据失效。
