<!-- relay:contract v1 -->
# H1 合同：心率臂带夜间记录导出与质量小结

## 目标
催睡觉方案以心率判睡：先攒 3–5 晚臂带数据，对照 COROS 入睡时间定阈值。现状是 `BleHeartRateStore` 已把 1 Hz 样本和断连状态写进 App 私有目录 `ble_heart_rate/<userKey>/<yyyy-MM-dd>.jsonl`（保留 14 天），但 App 里没有任何读取历史的入口，用户拿不到数据。

本合同只做“看得到、导得出”：
1. 原生端按“夜”汇总质量（覆盖、缺口、断连），并生成每分钟汇总 CSV。
2. 设置页新增“夜间记录”区：列出最近 7 晚的质量小结，每晚可一键导出原始 JSONL 和分钟 CSV（系统分享面板）。

判睡、来电、阈值都不在本合同。

## 定义
- **一晚**：以日期 D 命名，时间窗为本地时间 D 日 18:00 到 D+1 日 12:00（左闭右开），跨两个 JSONL 文件读取。
- **样本行**：`type == "sample"` 且 `timestampMs`、`bpm` 是数字。`bpm` 不在 30–220 范围内记为 suspect：计数，但不参与中位、最小、最大。
- **状态行**：`type == "status"`，原样保留，计数。
- 无法解析的行：跳过，计入 `malformedLines`，不得抛错。
- **缺口**：窗内相邻两条样本间隔大于 15 秒（与现有 stale 判定一致），计一次缺口，缺口秒数为间隔减 1 秒。

## 完成标准

**原生汇总（纯 Kotlin，可单测）**
- [ ] 新建 `android/app/src/main/kotlin/com/memexlab/memex/ble/BleHeartRateNightReport.kt`：
  - 纯函数部分不依赖 Android 类型：输入为按时间读出的 JSONL 行序列和窗口起止毫秒，输出夜间小结与分钟行。
  - 夜间小结字段：`night`（D 的 `yyyy-MM-dd`）、`windowStartMs`、`windowEndMs`、`firstSampleMs`、`lastSampleMs`、`samples`、`suspectSamples`、`statusEvents`、`disconnectEvents`（`status` 为 disconnected/reconnecting/bluetoothOff/stopped 的状态行）、`gapCount`、`maxGapSeconds`、`totalGapSeconds`、`coveredMinutes`（首末样本之间至少有 1 条有效样本的分钟数）、`spanMinutes`（首末样本之间的分钟数）、`bpmMedian`、`bpmMin`、`bpmMax`、`malformedLines`。无样本的晚上数值字段为 null，`samples` 为 0。
  - 分钟行（只覆盖首末样本之间的分钟）：`minuteStart`（本地时间 ISO-8601，带偏移）、`samples`、`bpmMedian`、`bpmMin`、`bpmMax`、`suspect`、`missingSeconds`（60 减去该分钟内出现样本的不同秒数，最小 0）、`statusEvents`。
  - 时区用 `ZoneId.systemDefault()`，但纯函数接收 `ZoneId` 参数，测试里固定 `Asia/Shanghai`。
- [ ] 文件读取部分：按 `BleHeartRateStore` 现有目录规则找到 D 和 D+1 两个文件，逐行流式读取（不得把 14 天文件一次性读进内存）；文件不存在视为空。
- [ ] 导出：在 `cacheDir/ble_heart_rate_export/` 下写 `heart-rate-<night>.jsonl`（窗内原始行，原样复制）和 `heart-rate-<night>-minutes.csv`（UTF-8，表头为上面的英文字段名）。每次导出前清空该目录旧文件。文件名不含 userKey、设备地址或用户名。
- [ ] 读取与导出都在后台线程执行，结果回到主线程交给 `MethodChannel.Result`；不得阻塞 UI 线程，也不得与服务端 `BleHeartRateStore` 的写入线程共享或关闭 writer。导出可能缺最后约 7 秒未 flush 的样本，属已知限制，写进代码注释。

**通道**
- [ ] `BleHeartRateChannelHandler.kt` 新增两个方法，参数都要求 `userId`（缺失时返回 `USER_REQUIRED`，与现有方法一致）：
  - `listNightSummaries`：`{userId, nights?: int=7}`，返回从昨晚起（若当前时间晚于今天 18:00 则含今晚）倒序的小结列表；没有数据的晚上也返回一条 `samples=0` 的记录。
  - `exportNight`：`{userId, night: "yyyy-MM-dd"}`，返回 `{jsonlPath, csvPath, summary}`；`night` 格式不合法返回 `INVALID_NIGHT`；不在 14 天保留期内返回空导出（文件仍生成，只有 CSV 表头）。
- [ ] Dart `lib/data/services/ble_heart_rate_gateway.dart` 新增 `BleHeartRateNightSummary` 数据类（`fromMap`）和 `listNightSummaries(userId, {nights = 7})`、`exportNight(userId, night)`；非 Android 平台返回空列表或 null，沿用现有平台判断写法。

**设置页**
- [ ] `heart_rate_device_settings_page.dart` 在诊断区之前加“夜间记录”区（`ValueKey('heart_rate_night_records')`）：
  - 每晚一行：日期、记录时长（首末样本，例如 `23:41–07:58`）、覆盖率（`coveredMinutes / spanMinutes`，百分比取整）、最大缺口（秒或分钟）、断连次数；`samples=0` 显示“无记录”。
  - 每行一个“导出”按钮：调用 `exportNight`，成功后用已有依赖 `share_plus` 分享两个文件；失败用页面现有的消息样式提示，不弹出原始异常文本。
  - 页面打开时和下拉刷新（若页面已有刷新入口则复用）时加载；加载失败不影响页面其他区块。
- [ ] 不显示逐分钟心率曲线（留到判睡合同）；不显示具体 bpm 数字以外的健康推断文字（不写“睡着了”“压力大”等）。

**测试（全部合成数据）**
- [ ] `android/app/src/test/kotlin/com/memexlab/memex/ble/BleHeartRateNightReportTest.kt`：跨午夜两个文件拼接；窗口边界（17:59:59 与 12:00:00 不计入，18:00:00 计入）；15 秒缺口阈值（15 秒不算、16 秒算）；suspect 值不进中位；状态行计数与 disconnect 分类；坏行跳过计数；空晚上；分钟行 `missingSeconds`；CSV 表头与转义。
- [ ] `test/data/services/ble_heart_rate_gateway_test.dart` 追加：两个新方法的 mock channel 解析、参数、错误码。
- [ ] `test/ui/settings/widgets/heart_rate_device_settings_page_test.dart` 追加：有数据与无记录两种行的显示；点击导出调用 gateway（分享调用可通过注入或 mock 跳过）。
- [ ] 现有测试不改断言。

## 允许修改的路径
- `android/app/src/main/kotlin/com/memexlab/memex/ble/BleHeartRateNightReport.kt`（新建）
- `android/app/src/main/kotlin/com/memexlab/memex/channels/BleHeartRateChannelHandler.kt`（只加两个方法和后台执行）
- `android/app/src/main/kotlin/com/memexlab/memex/ble/BleHeartRateStore.kt`（只允许把目录路径规则抽成可复用的 internal 函数，行为不变）
- `android/app/src/test/kotlin/com/memexlab/memex/ble/BleHeartRateNightReportTest.kt`（新建）
- `lib/data/services/ble_heart_rate_gateway.dart`
- `lib/ui/settings/widgets/heart_rate_device_settings_page.dart`
- `test/data/services/ble_heart_rate_gateway_test.dart`、`test/ui/settings/widgets/heart_rate_device_settings_page_test.dart`（只追加用例）
- `android/app/src/main/res/xml/` 下 FileProvider 路径文件（仅当 share_plus 分享 cacheDir 文件需要时，只加 `ble_heart_rate_export/`）
- `docs/development/handoffs/RELAY_20261024_h1-heart-rate-night-export.md`、`docs/development/handoffs/COMMANDER_HANDOFF_20261022.md`（只由 Claude 改）

## 不做 / 边界
- 不改采集、重连、watchdog、前台服务、通知、保留期（仍 14 天）和 JSONL 格式。
- 不做判睡、不触发来电、不写 KV、不上传任何数据；导出只走用户手动点击的系统分享。
- 不读 COROS 云端，不改 Companion 心率工具。
- 测试与文档里不出现真实心率数值、设备地址、userKey 或本机路径。
- 不构建、不安装 App，不碰手机。
- 止损：同一测试名或同一错误码在连续两个提交上失败，即判为 blocked。最多 3 轮。

## 验证命令
- `cd android && ./gradlew :app:test<本机常用 Flavor>DebugUnitTest --tests "com.memexlab.memex.ble.*"`（回帖写明实际任务名和通过数；现有 BLE 测试必须同时通过）
- `flutter analyze lib/data/services/ble_heart_rate_gateway.dart lib/ui/settings/widgets/heart_rate_device_settings_page.dart`
- `flutter test test/data/services/ble_heart_rate_gateway_test.dart test/ui/settings/widgets/heart_rate_device_settings_page_test.dart`
- `git status --short`（只出现允许修改的路径）
- Claude 在云端核对 diff；Dart 测试以 PR 的 CI 为准（CI 不跑 Kotlin 单测，以 Codex 本机结果为准）。

## 用户决定（10-24）
- 同意先做导出与质量小结（本合同），判睡另立合同，先只记录不来电。
- 定阈值期间原始心率保留期保持 14 天（产品记录里的 1 天另议）。

## 需要真人的部分
- 合并由用户进行。Codex 回帖并收到 `relay:done` 前不要合并。
- 合并后用户用 v3-lab 重建并覆盖安装 App；第二天早上在设置页看到昨晚的小结，导出一次发给 Claude（或放进项目文件夹）用于对照 COROS。

## 审核记录
（待第 1 轮）
