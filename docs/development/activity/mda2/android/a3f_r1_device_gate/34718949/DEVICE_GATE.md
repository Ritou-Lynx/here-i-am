# A3F-R1 唯一候选与真人 Gate

2026-09-17；源码`aae59e18`已由W0独立接受，主线记录`34718949fa74d178c5e366aa08b99084cf8f132f`。源码验收不等于设备验收。

## 构建与安装边界

- 从精确`34718949` Git archive导出，唯一入口`lib/a3d_device_gate_main.dart`、flavor `hereIAmV3`、包`com.memexlab.hereiam.v3`。
- pubspec/lock与已验证缓存基线相同；本地JNI188源码逐hash相同，排除旧build/CMake/Gradle产物。R1的19路径SHA-256与W0独立副本一致。
- 每次构建前critical3/3。首次最终APK复制与report写入因C盘不足失败（811.5s/exit1），未更新手机；仅清理本工作区旧6b754671的`build/app/intermediates`，约2.66GB，旧B34B APK/源码/证据/原包保留且hash相同。相同干净源码重试94.1s/exit0，不改Gradle/依赖/安全检查。
- 唯一APK **SHA-256 `99995837138ED7DCB33BA17EC9C717F1740546075F25561A6ED68472446779A4`**，384210543 bytes，包`com.memexlab.hereiam.v3`，1.0.30(113)。aapt包名核对、APK及回退签名验证均exit0，certificate SHA-256同为`0011cc0372b17ccec1544eea667d2466adebade94ac91adb39239f3be8712e4e`；新ledger/ACK bridge真实包含在DEX中。
- 实际App源集 **31/31**（四suite无failure/error），Gradle218s/exit0，723任务（执行10/复用713），测试后APKhash不变。初次测试命令因未quoted target被PowerShell拆成`.dart` task而失败，未执行测试；改为literal参数数组后通过，环境/命令错误不算测试通过或代码失败。
- 新设备三事件、通知停止、权限边沿、死亡/重启、OEM及隔离/耗电矩阵均待验。

## 原版本与安装前现场

16:27:36 UTC只读预检：手机RFCWC01PBKK连接已授权；当前原正式base.apk为`E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37`，与本地回退相同。Usage/background allow、POST_NOTIFICATIONS granted、Bluetooth0、Activity source服务不存在、原BLE服务存在。

回退文件：`tmp/mda2-a3d-device-evidence/RFCWC01PBKK/C43B3767/restore_original_20260916_002718/base.apk`。不卸载、不清完整App数据、不改Bluetooth/check-in设置；包覆盖安装按固定协议force-stop和冷启动，生命周期重启与Activity独立stop分开记录。

## 下一真人短协议

1. 若旧诊断状态安全拒绝启动，使用已有“显式清理诊断outbox”，再明确点击完整本地诊断；拒绝时不通过shell删除绕过。
2. 确认持续通知可见并有停止入口。真实锁屏约10秒后解锁，立即在诊断页点击查询/提取并刷新，随后回这里回复。交付在5分钟TTL以内，不等待主窗回执才query。
3. 主窗只读取固定状态、screen occurrence与source/sequence等最小证据；分别核对系统实际发生、native接纳/拒收和durable结果。fresh表示近期事件，`publication_completeness=unknown`，累计遗漏不清零。
4. 三事件通过后再逐项跑其余矩阵；结束恢复原正式APK并重新核对hash。未取得明确证据的Gate保持待验。

旧B34B三事件Gate因证据窗口不足未完成，设备缺失原因未单独证明；源码迟到游标反例已由R1修复。旧A3-D2 FAIL保持历史失败，不提升为通过。

最小证据目录：`tmp/mda2-a3f-device-evidence/34718949`。无push/publish。

## 安装与当前停点

16:54:36 UTC覆盖安装`-r -d -t`确认Success/exit0；设备base.apk逐hash与99995837唯一候选相同。按固定安装协议force-stop整个V3包后冷启动请求exit0，不将此生命周期重启当作Activity独立stop隔离通过。

即时pid读取未确认进程；16:55:31 UTC后续独立读取确认进程存在、BLE服务已存在、Activity source服务不存在，Bluetooth仍0。当前V3非前台，16:56:05 UTC电源Dozing；没有dump或读取其他App界面，没有把诊断标题未可见判成错误入口/设备FAIL。

用户需要解锁并打开V3，使用已有显式诊断清理/开始按钮后执行上述10秒锁解、立即提取刷新协议。human opt-in、可见持续通知、三事件和后续矩阵均待真实回执；没有自动代替人眼/手势验收，旧Gate不提升。

证据：`apk_candidate.json`、`formal_app_unit.json`及四suite XML、`install_receipt.json`、`after_install_before_opt_in.json`、`display_before_human_start.json`，均在上述证据目录。诊断结束仍须恢复原E1B正式包并再核对设备hash。
