<!-- relay:contract v1 -->
# S1 合同：床头哨兵 App（摄像头本地判醒 → ntfy 推送）

> 基于 v3-lab `0a3b903`。起因与方案见 DEVLOG 10-24“催睡来电”与 D2a。

## 背景
- 目标：夜里判断用户还醒着（躺床上刷手机），就给主力三星手机推一条“林埃来电”通知；三星“模式与例程”收到后拉起 Sesame（Call Charlie）。本合同只做“判醒 + 推送”，不改 Here I Am、不改三星手机上的任何东西。
- 硬件：一台闲置 Android 手机（小米，Android 12 以上），整夜插电，用支架固定在床头俯拍枕头区。
- 判醒信号（10-24 白天实拍确认可见）：脸上的屏幕冷光、睁眼、脸在画面里。全部在本机算，用 Google ML Kit 人脸检测（bundled 模型，不联网下载模型），图像只在内存里处理，**任何时候不写盘、不上传**。
- 推送用 ntfy（HTTP POST 到 `<server>/<topic>`），服务器与 topic 由用户在 App 设置里填，不进仓库。

## 完成标准

**工程**
- [ ] 新建独立 Gradle 工程 `tools/bed_watch_android/`（Kotlin，单模块 `app`），与 Flutter 的 `android/` 无依赖；插件版本与 `android/settings.gradle.kts` 一致（AGP 8.11.1、Kotlin 2.2.20）；`applicationId` `com.memexlab.bedwatch`，minSdk 31，targetSdk 与 compileSdk 用 35。不提交 wrapper jar，用本机 `gradle` 构建。
- [ ] 依赖只允许：AndroidX core/appcompat/lifecycle、CameraX（core、camera2、lifecycle）、`com.google.mlkit:face-detection`（bundled）、JUnit 4。HTTP 用 `HttpURLConnection`，不加网络库。

**采样（前台服务）**
- [ ] `BedWatchService`：前台服务，`foregroundServiceType="camera"`，常驻通知显示“床头哨兵运行中 · 上次判断 HH:mm”。只在“监测窗口”内拍（默认 23:30–06:00，可设）；窗口外不开相机。
- [ ] 每 60 秒（可设 30–300）用 CameraX `ImageAnalysis` 取一帧（可选前/后摄，默认后摄），固定曝光补偿为 0、关闭夜景/HDR 类扩展；拿到一帧即分析即释放，`ImageProxy.close()` 后不保留任何像素引用。
- [ ] 开机自启（`BOOT_COMPLETED`，仅在用户已开启监测时）；被系统杀后 `START_STICKY` 重启。

**单帧特征（纯函数，可单测）**
- [ ] `FrameFeatures(face: Boolean, eyesOpen: Float?, glow: Float, frameLuma: Float)`：
  - `face`：ML Kit 检测到至少一张脸（取最大框）；`eyesOpen` 取左右眼睁眼概率的较大值，无则 null。
  - `glow`：脸框内平均亮度 ÷ 整帧亮度中位数（无脸时为 0）；`frameLuma`：整帧平均亮度 0–255。
- [ ] 亮度计算在 `LumaStats` 纯函数里（输入 Y 平面字节数组 + 宽高 + 框），便于用合成数组单测。

**判定（纯函数状态机，可单测）**
- [ ] `AwakeJudge`：输入按时间排序的 `FrameFeatures`，输出每帧 `awake | asleep_like | unknown`：
  - `awake`：`face` 且（`eyesOpen ≥ 0.6` 或 `glow ≥ 1.6`）。
  - `asleep_like`：无脸且 `frameLuma < 40`（暗且没人对着屏幕），或 `face` 且 `eyesOpen < 0.3` 且 `glow < 1.3`。
  - 其余 `unknown`。阈值做成配置常量，App 设置可改。
- [ ] 触发：最近 4 帧中 ≥3 帧 `awake` → 发一次推送；之后冷却 10 分钟（可设），冷却结束仍满足就再推；`unknown` 不推、也不清零。
- [ ] “今晚放行”开关：打开后到次日 12:00 前不推（仍记录）。

**推送**
- [ ] `NtfyNotifier`：POST `<server>/<topic>`，头 `Title: 林埃来电`、`Priority: urgent`、`Tags: telephone_receiver`，正文一句中文原因（如“01:12 你还睁着眼看手机，已经持续 4 分钟”），10 秒超时；失败重试 2 次（5 s、30 s），仍失败只记日志。server 必须是 `https://`。

**记录与设置**
- [ ] 每帧只记数字：`files/bedwatch/<日期>.jsonl` 一行 `{t, face, eyes_open, glow, luma, verdict, pushed}`，保留 7 天自动清理；不记任何图像、人脸框坐标以外的像素信息（框坐标也不记）。
- [ ] 主界面：开关监测、窗口时间、间隔、前/后摄、阈值、ntfy server/topic、今晚放行、“测试推送”按钮、最近 20 帧的判定列表。
- [ ] “调角度”页：相机实时预览（只在此页、只在前台显示，不保存），叠加当前 `face/eyesOpen/glow/verdict` 数值，方便摆支架。离开页面即关预览。

**测试（JVM 单测，合成数据）**
- [ ] `LumaStatsTest`：合成 Y 平面（全暗、亮框、边界框越界被裁剪）。
- [ ] `AwakeJudgeTest`：各分支、阈值边界、4 取 3 触发、冷却、unknown 不清零、放行开关、跨午夜窗口。
- [ ] `NtfyNotifierTest`：用本地 `ServerSocket` 假服务器验证路径、头、正文、非 https 拒绝、超时与重试次数。
- [ ] `JsonlLogTest`：字段只有上面 7 个；7 天清理。

**文档**
- [ ] `tools/bed_watch_android/README.md`：构建与安装（`gradle -p tools/bed_watch_android assembleDebug`、adb 安装）、小米需要的设置（自启动、省电策略“无限制”、锁定最近任务、充电保护）、ntfy 在三星上的订阅、三星“模式与例程”配置（通知包含“林埃来电” → 打开 Sesame / Call Charlie）、隐私说明（图像不落盘不上传）。不写真实 topic。

## 允许修改的路径
- 新建 `tools/bed_watch_android/**`
- `docs/development/handoffs/RELAY_20261024_s1-bed-watch-camera.md`（只由 Claude 改）

## 不做 / 边界
- 不改 Flutter App、`android/`、iCore、MCP；不接 i MCP（另做）。
- 不录视频、不存图、不上传图像；不用云端视觉模型。
- 不在仓库写 topic、令牌、本机路径。
- 止损：同一测试名或错误码连续两个提交失败即 blocked，最多 3 轮。

## 验证命令
- `gradle -p tools/bed_watch_android testDebugUnitTest`
- 不跑 `assembleDebug`、不生成 APK、不安装：协议“永不”禁止 relay 内构建/安装 App（第 1 轮因此 blocked）。`testDebugUnitTest` 只编译并运行 JVM 单测，不出 APK，属于测试。
- 若本机没有 `gradle` 或 Android SDK，不要自行安装，回 blocked 并说明缺什么。
- `git grep -n -i -E "ntfy.sh/[a-z0-9_-]{6,}" -- tools/bed_watch_android` 无结果（只允许占位）

## 真人验收（合并后）
0. 用户另行授权后，在本机执行 `gradle -p tools/bed_watch_android assembleDebug` 出 APK（Claude 另给提示词，不在 relay 内做）。
1. 小米装 APK，授权相机、通知；按 README 设小米后台策略；“调角度”页摆好支架。
2. 三星装 ntfy 订阅同一 topic；建例程：通知含“林埃来电”→ Call Charlie。“测试推送”能拉起 Charlie。
3. 白天关灯模拟：刷手机 4 分钟内收到推送；锁屏闭眼不推；今晚放行打开后不推。
4. 整夜跑一晚，第二天看 jsonl：误推次数、漏判情况、手机温度和电量。

## 审计记录
- 第 1 轮 blocked（10-24）：合同要求 assembleDebug 与协议“永不构建或安装 App”冲突。处理：APK 构建移出 relay，改为合并后由用户授权单独执行；relay 只跑 JVM 单测。
