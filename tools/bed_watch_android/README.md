# 床头哨兵

独立 Android 12+ 应用。CameraX + **bundled** ML Kit 在本机检测最大人脸、睁眼概率与脸部相对亮度，满足最近四帧至少三帧清醒时向用户配置的 ntfy 推送“林埃来电”。不依赖 Here I Am、iCore 或 MCP。

## 构建与测试

需要已安装的 JDK 17+（可使用 Android Studio JBR）、Gradle 8.14、Android SDK Platform 35 和构建工具，以及工程声明的依赖。AGP 8.11.1、Kotlin 2.2.20，minSdk 31，target/compileSdk 35，包名 `com.memexlab.bedwatch`。不附带 wrapper jar。

```powershell
gradle -p tools/bed_watch_android testDebugUnitTest
```

Gradle 不在 PATH 时，可以通过已有缓存 Gradle 的完整路径调用。`flutter doctor -v` 的 `Java binary at` 可定位 Android Studio JBR；只在当前 shell 设置 `JAVA_HOME`。SDK 用进程的 `ANDROID_HOME` 指定。不修改用户/系统环境变量，不把本机路径写进仓库。加 `--offline` 可以严格禁止依赖下载；缺少缓存会失败，不会自动安装工具。JUnit 测试只使用合成数组、临时目录和回环假服务器，不生成 APK。

**以下命令仅供合并后用户另行授权构建/安装；Relay 内禁止执行：**

```powershell
gradle -p tools/bed_watch_android assembleDebug
adb install -r tools/bed_watch_android/app/build/outputs/apk/debug/app-debug.apk
```

## 设置与启动

1. 在主界面填写 ntfy HTTPS 服务器和私有 topic，设置采样窗口、间隔、前/后摄及阈值，允许相机和通知，再勾选启用监测并保存。默认后摄、23:30–06:00、60 秒、10 分钟冷却。时间相同表示全天；窗口结束时释放相机并清空旧投票，冷却时间在重启后保留。
2. 点“调角度”在前台查看实时预览及 face、eyesOpen、glow、luma、verdict。此时暂停服务，离开该页立即关闭预览；返回主界面后恢复已启用的监测。调角度不写帧日志、不推送。
3. 保存设置后生效。“今晚放行”首次开启后到次日当地时间 12:00，不影响采样记录；重复保存不会延长期限。关闭它即可提前取消。
4. 开机且此前已启用监测时，只发一条高优先级通知“床头哨兵已停止，点一下恢复监测”。点击进入主界面，由可见界面启动服务。**不从开机广播启动 camera 服务，不申请电池/后台启动豁免。** `START_STICKY` 重建若被系统拒绝前台服务或抛出权限异常，也改发同一条恢复通知后停止。若用户关闭通知或撤销权限，系统无法显示恢复通知，需要主动打开应用授权。

相机仅在监测窗口和调角度页开启。监测服务持有普通 partial wake lock，让插电、关屏时仍能按窗口调度；不点亮屏幕、不录制视频。采用普通 CameraX Analysis，无夜景/HDR 扩展，曝光补偿固定为 0、手电关闭。ML Kit 未能分析或相机不可用时停止监测并提示恢复，不把失败当成“似睡”。

## 小米后台设置

在小米/HyperOS 设置中允许本应用自启动，省电策略设为“无限制”，在最近任务里锁定应用；保持相机、通知权限可用。整夜插电并固定支架，使用设备提供的充电保护；白天先观察发热。系统菜单因机型而异，不申请系统豁免权限，也无法保证系统绝不杀后台。重启后须点击恢复通知。

## 三星接收

在三星 ntfy 客户端订阅与哨兵相同的服务器/topic，允许通知，先按哨兵的“测试推送”检查投递。服务器必须使用有效证书的 HTTPS，不能把用户名、口令、查询 token 放在服务器地址里；当前版本不支持服务器鉴权头。topic 应由用户自行保密，不能当作强鉴权机制。

在三星“模式与例程”中建立：收到 ntfy 通知且通知包含“林埃来电” → 打开 Sesame（Call Charlie）。实际可用的例程动作与 Sesame 的入口须在手机上确认；本工程不修改三星设置。测试通知通过后，再白天模拟刷手机、闭眼和今晚放行，最后才整夜试用。

## 判定与日志

- `awake`：有脸且睁眼概率 ≥ 0.6，或有脸且 glow ≥ 1.6。
- `asleep_like`：无脸且整帧平均亮度 < 40；或有脸、已知睁眼概率 < 0.3 且 glow < 1.3。
- 其他为 `unknown`。未知帧参与四帧滑动窗口，不清空已有投票，也不会在当前未知帧触发推送。必须收到四帧才开始投票。
- glow 是脸框内均值 / 整帧中位数。分母最低取 1，避免纯黑画面的除零；人脸框只在内存计算。左右眼概率取较大值，均缺失时为未知。
- 推送头为 `Title`（中文标题以 ntfy 支持的 RFC 2047 UTF-8 编码传输）、`Priority: urgent`、`Tags: telephone_receiver`；只 POST 文本。连接和读取超时均 10 秒，失败后等待 5 秒、30 秒重试两次，不跟随重定向。冷却从触发尝试开始，投递失败也不立即重复触发。
- 私有目录 `files/bedwatch/<日期>.jsonl` 每帧只有七个数字字段：`t`（epoch 毫秒）、`face`（0/1）、`eyes_open`（未知=-1）、`glow`、`luma`、`verdict`（0=awake、1=asleep_like、2=unknown）、`pushed`（1=发送成功、0=未发送、-1=重试后失败）。保留今天及前六天，启动与写入时清理，主界面显示最近二十帧。不记录服务器错误正文、topic、URL 或异常详情。

## 隐私与验证范围

图像只在内存使用。没有拍照保存、视频编码、图像上传或云端视觉路径。ML Kit bundled 模型无需首次联网下载；Y 平面只在单次分析内使用，用完清零并关闭 `ImageProxy`。仅标量特征可以交给日志/推送线程。App 禁止系统备份，未声明任何外部存储权限；设置保存在本机私有 preferences。

JVM 测试覆盖亮度、旋转坐标、判定阈值/投票/冷却/放行/窗口、恢复通知策略、真实回环 HTTP 请求/读取超时/重试、七字段日志及保留期限。测试中的 HTTP 回环连接通过传输构造注入，生产默认传输仍强制 HTTPS。它们不代替小米相机、系统进程重建、开机通知和三星例程的真机验收；Relay 不构建 APK、不安装、不操作手机。

参考：[Android camera 前台服务限制](https://developer.android.com/develop/background-work/services/fgs/service-types#camera)、[CameraX 内存图像分析](https://developer.android.com/media/camera/camerax/analyze)、[ntfy 官方文档](https://docs.ntfy.sh/)的 Publishing / Title 一节。
