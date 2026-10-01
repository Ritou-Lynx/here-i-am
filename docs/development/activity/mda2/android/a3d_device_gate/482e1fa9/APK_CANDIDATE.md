# MDA-2 A3-D1 唯一诊断 APK 候选

> 2026-09-14；源码/收据提交 `v3-lab@482e1fa96c810a79f4ef2b89a4e07dcd7e5c07b8`。

## 唯一候选

- 构建树：从 `482e1fa9` 创建的 detached 干净 clone；没有读取 `D:/memex` 的 56 个并行 dirty 修改。
- flavor：`hereIAmV3` Debug。
- target：`lib/a3d_device_gate_main.dart`。
- 包名：`com.memexlab.hereiam.v3`。
- 版本：`1.0.30 (113)`；min SDK 26；target SDK 36。
- APK：`C:/Users/ExampleUser/.codex/worktrees/832e/memex/tmp/mda2-a3d-device-build/482e1fa9/build/app/outputs/flutter-apk/app-hereiamv3-debug.apk`。
- 大小：`384166171` bytes。
- SHA-256：`56A4E8621606545410BC84E3FBEF6E23DDBDC95EE77871ED5C3B655E27B36A4B`。

构建前及最终成功构建前均运行 `scripts/verify_critical_fixes.ps1`，结果 3/3、exit 0。构建命令为：

```powershell
D:\flutter\bin\flutter.bat build apk --debug --flavor hereIAmV3 -t lib/a3d_device_gate_main.dart --no-pub
```

最终命令 exit 0，产出上方唯一 APK。任何重新构建或 APK 字节变化都会使本候选设备证据失效。

## 保留的构建失败与环境处理

1. `flutter pub get --offline` 完成依赖解析后，在本机 Pub `active_roots/8c` registration 处 exit 1；有效 `package_config.json`/`package_graph.json` 已生成，但此步不计成功。
2. 首次 `--no-pub` 构建因上一步未生成 Flutter plugin metadata/registrant 而 exit 1，已有 `flutter_foreground_task` 和 `GeneratedPluginRegistrant` 无法解析。按已通过完整 App unit task 的同一机械脚本生成 44 个 Android plugin metadata、排除未被产品使用的 `integration_test` dev plugin，并生成 registrant。
3. 第二次构建进入 `jni` CMake 后 exit 1：Android Gradle 把 `.cxx` 工作目录放进共享 Pub cache，CMake 无法在该路径创建文件。没有修改共享 cache；把缓存中的 `jni 1.0.3` 复制到本构建树 `.dart_tool/local_packages`，801 个文件逐 SHA-256 比较、0 mismatch，只在本次忽略的 package config/plugin metadata 中改为本地路径。
4. 再次运行 critical fixes 3/3 后，第三次相同 Flutter build exit 0。输出只保留仓库既有 NDK 27/`jni` 28.2 建议、未来 Kotlin built-in migration 和 Java 8 deprecated 警告；没有改 Gradle、NDK、依赖或候选源码。

构建树 `git status` 保持 clean detached；所有离线元数据、本地 `jni` 副本和 build 输出均为忽略对象，不进入源码提交。

## 设备预检与停点

构建成功后使用固定 Android SDK `adb.exe devices -l` 做安装前只读预检，结果列表为空并返回 `no devices/emulators found`。因此本轮没有读取当前设备型号/系统、原 `base.apk` hash、Usage Access 或电池策略，也没有安装、启动、访问 UsageEvents、重启/强停、Doze 或 BLE。

下一步必须先让目标手机出现在 ADB 列表。W0 随后重新读取设备身份、当前包版本与 `base.apk` SHA-256，确认可回退 APK和 Usage Access 初态，再安装上方唯一 hash。安装后必须从设备重新读取 `base.apk` 并与本地 SHA-256 完全一致，才可开始 A3-D2 短场景。
