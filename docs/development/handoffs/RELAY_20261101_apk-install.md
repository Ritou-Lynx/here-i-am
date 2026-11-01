# RELAY 2026-11-01：构建并 adb 安装 Here I Am V3（林埃英文声音 V1b）

V1b（#78、#80、#81）已合并进 v3-lab，这一轮在电脑上构建 APK 并装到手机。

- 第 1 轮（write，需用户 👍）：`tools/relay_scripts/app/build-install-v3.ps1`。
  1. 找 flutter 和 adb。
  2. 要求正好一台已授权的 USB 调试设备。
  3. 跑 `verify_critical_fixes.ps1`。
  4. `flutter pub get`，然后 `flutter build apk --debug --flavor hereIAmV3`。
  5. `adb install -r -d -t` 覆盖安装，再启动 App。
- 只做覆盖安装。签名不一致时报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 并停下，绝不卸载（卸载会清空 App 数据）。
- 输出不含路径、设备序列号、账号；失败时只回传构建日志末尾几行，并抹掉本机路径。

装好后：设置 → 语音播放 → 选“家里电脑（英文）”→ 测试连接 → 打一通电话试听。
