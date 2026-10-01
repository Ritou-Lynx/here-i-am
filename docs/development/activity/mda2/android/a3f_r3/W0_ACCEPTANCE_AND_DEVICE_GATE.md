# A3F-R3 W0 验证与设备 Gate

2026-09-30 F2 同哈希 H0–H6 真人/受控设备 Gate 独立终审 GO；原正式 E1 完整 hash 与原绑定 BLE 前台已恢复、延时复核稳定。H4 首次因 W0 误触 Home 后安全拒绝，重做同页受控释放成功；停后查询及重复禁用按钮不冒称点击。详见 [F2 真人 Gate](F2_HUMAN_GATE_20260930.md)及本机 `tmp/a3f-r3-human-f2/INDEPENDENT_REVIEW.md`。Goal 完成，无 commit/push。

2026-09-29 F2 最新：Debug APK `0AC428177247F757BA21C95B734A6121610D87735071BFC08E1A377C39324911` 同源组合232/232、critical/build/包名签名通过；三份完整真机trace的手动、返页、受控失证 unknown 发布均严格≤3秒，真实旧running回执在终态后被拒绝且无ready回弹。通知自身停止按钮实际点击，返前台保持 stopped；关闭只删两owner。正式E1已恢复、BLE前台6157及元数据隔时复核，FD非穷尽。F2同哈希人眼H0/H4/H5等完整Gate仍待补，Goal开放，无commit/push。见[自动时序补验](AUTOMATED_TIMING_GATE.md)及本地 `tmp/a3f-r3-timing-device-f2/DEVICE_RESULT_F2.md`；下方F1/旧候选段落均为历史。

2026-09-29 最新：9A旧包H1/H2同步上界775/515ms独审接受。F1D3431A新Debug包三份完整实机trace：checking顺序通过，受控失证后旧running回复由terminal守卫拒绝且有限尾段无ready回弹；unknown投影3,026,775/3,007,425/3,004,019µs，严格3秒均RED，通知按钮自动定位失败不计通过。显式关闭后两owner/gate FD0、其余11项元数据不变；装回E1正式包hash，BLE前台6157/Bluetooth1、Activity缺席与13项元数据不变两次隔时确认，转发清理。本轮H6收尾成立；内部预算返修与新hash设备重验仍待，Goal未完成，无commit/push。详见[自动时序补验](AUTOMATED_TIMING_GATE.md)；下方旧准备和设备状态均保留为历史。

## 固定基线与候选边界

- 基线 `b2adc44b7c04983a931c39695b81491cd295084b`。
- W0 分支 `codex/a3f-r3-w0-integration-20260927`，未提交；候选由基线加文件 manifest 绑定，不虚构交付 commit。
- 构建源来自精确基线和已验差异，1223 文件；输入集合 SHA-256 `8B718AF58970E6D7B240D265E5A8260D0E18C5C99A93DE3751759E86952E18F7`。JNI 1.0.3 的 188 个非生成输入另逐 hash 冻结。
- 主目录原有 59 个脏路径保留；最近核对仅 DEVLOG 与项目状态页因已知共享工作有新内容，本轮23个源码/测试/脚本路径已选择性集成，逐文件hash一致；结果见 tmp/a3f-r3-w0/integration-result.json。
- 默认入口、Manifest、依赖、Core/wire/schema、BLE 零 diff；没有 commit/push/publish。

## 自动与独审证据

| 层 | 最终结果 | 证明边界 |
|---|---|---|
| N 最终 | 77/77，exit 0，镜像 hash 一致 | 6 源码守门、71 JVM 逻辑/文件；不是 Android 生命周期或设备证据 |
| D 分包 | 55/55，analyze exit 0，九输入绑定 | 被最终组合覆盖，不重复相加 |
| U 最终定向返修 | 新反例修前 RED exit 1；修后 UI 30/30、analyze、diff check exit 0 | 原 69/29 仅 tool 输出，无单独旧日志；最终完整行为由 W0 实跑补足 |
| N/D/U 独审 | 最终冻结源码均接受，见 V_REVIEW | 真实 diff、失败断言和收据；审查本身不是执行测试 |
| W0 完整 Flutter 组合 | **181/181**、相关源码/测试分析无问题、exit 0；七测试文件、17 输入逐字节匹配 | 本地合成及 Windows 文件锁，不代替 Android 同进程/第二 engine/跨进程 |
| R3 范围守门 | exit 0，30 路径（含最终候选 manifest），保护区零 diff | 范围/源码标记，不冒充行为证明 |
| 构建前关键检查 | 3/3，exit 0 | 与同次 APK 构建绑定 |
| APK | 第三次构建 exit 0，94.079 秒；包名正确、签名校验 exit 0 | SHA-256 `854F341E108733464A351AAB267A14563033A4CCC6CB0A715862860EDBAD8658`；仍未安装 |

组合涵盖 normalizer、FileStore、collector、observation platform/collector、owner release、诊断 UI。具体断言与失败历史见各 handoff、控制合同及独审页。

## 环境与可恢复证据

C 盘曾耗尽；停止写入并运行 doctor 后，保全 N 六个已审文件及 344 个镜像文件并逐 hash 核对，再用应用工具可恢复归档已完成 N 树。D 未验收 collector 曾截断，已从保全副本重建并重新验证。其他任务、工作树和共享缓存未清理。

离线依赖解析分别为构建和组合镜像生成 package_config/package_graph 后，在共享 cache active_roots 登记阶段 exit 66；明确保留失败记录。另验证构建 337、组合 60 个包根全部存在，构建 pubspec.lock Git blob 与基线相同，随后使用 --no-pub / -NoResolve；不伪写解析成功，不更新共享依赖版本或源码。构建输入首次枚举因 Git 转义中文路径拒绝，改为仅本命令 core.quotepath=false 后成功冻结，未更改全局配置。

本机证据相对主工作区：
- `tmp/a3f-r3-w0/native-current-result.json` 与 `native-current/.verification_android/`：77 项原生镜像、编译和 JUnit XML。
- `tmp/a3f-r3-dart-verification/final-source-manifest.json`、`test-final.log`、`analyze-final.log`：D 最终证据。
- `tmp/a3f-r3-w0/u-verification/evidence/`：U 最后一个 P2 的 RED/GREEN、分析和最终 manifest。
- `tmp/a3f-r3-w0/combined-final.log`、`combined-result.json`、`combined-source-manifest.json`：W0 181 项及分析、17 文件绑定。
- `tmp/a3f-r3-w0/static-final.log`、`critical-final.log`：最终范围/构建前检查。
- `tmp/a3f-r3-w0/build-source-manifest.json`、`jni-source-input.json`、`build-result.json`：构建输入与实际执行收据。
- `tmp/a3f-r3-w0/protected_start.json`：进入执行时原脏路径指纹。
- `tmp/a3f-r3-w0/candidate-build/`：隔离候选构建目录；最终 APK 见 CANDIDATE_MANIFEST.json。

构建首轮因 --no-pub 未生成插件注册失败（exit 1），调用现有 Flutter SDK 的 ensureReadyForPlatformSpecificTooling 补生成；第二轮在 JNI 全局 Pub-cache .cxx 写入失败（exit 1）。将预先冻结 JNI 188 文件原字节复制到本轮 jni-input，仅改生成 package_config 的 JNI URI，再用 SDK 重生成注册。独审核对 337 包其余配置不变、原/副本 hash 一致、pubspec/lock 未变。第三轮重新运行 critical 3/3 后构建成功；前两份失败收据保留。全程未调整 Gradle/NDK 配置，已有版本兼容性警告保留。

最终候选：`A3F-R3-b2adc44b-8b718af5`，包 `com.memexlab.hereiam.v3`，版本 `1.0.30 (113)`，384776581 字节。签名为同机 Android Debug，证书 SHA-256 `0011cc0372b17ccec1544eea667d2466adebade94ac91adb39239f3be8712e4e`。APK、源码、测试脚本与收据映射见 [CANDIDATE_MANIFEST.json](CANDIDATE_MANIFEST.json)。

原始本机证据不提交；项目交接只留相对引用及脱敏结果。

## 真人 Gate

**H0–H6 全部待验。** 不继承 R2 的 APK 设备结论，具体触发、时限与失败标准见 Goal 和 W0_CONTROL_CONTRACT。

1. H0：唯一候选初态零采集、用户显式开始、持续通知人眼可见、锁解三事件及 BLE 基线。
2. H1：用户点击 Activity 通知自己的停止入口；确认前台及 resume/刷新退出旧 ready，BLE/Bluetooth 不因该动作改变。
3. H2：显式 Debug 通知可见性失证注入走真实 continuity 门；标注注入，不冒充 OEM 根因复现。
4. H3：外部终止后明确关闭两源资源，无损、幂等、失败如实呈现。
5. H4：同代 close 删除失败合成孤立 owner，再另点窄释放；活 lease 拒绝在第二 FD 之前；保留数据/key/sequence。
6. H5：释放后刷新/重入不自启，非空 outbox 恢复门保持；需要再开始时用户分别清理诊断状态和新开始。
7. H6：恢复安装前真实核对并保全的正式 APK，确认 base hash、冷启动、Activity 诊断不运行、BLE/Bluetooth。

安装前仍需核对当时正式 APK 和回退产物、用户在场及物理安装授权。不能用全包 force-stop 或清所有通知代替 H1/H2；候选构建成功也不能代填真人通过。全部 Gate 及正式包恢复未齐前不能完成 Goal；当前已按持续阻塞审计转为 blocked，等待用户确认继续。

### 安装前本地回退预检

2026-09-27 只读检查：主目录旧 APK 为 `3056968E…1E761D4`，历史 `tmp/device-apk-check/installed-base.apk` 为 `F6AECB0A…8D6912C`，均不匹配 R2 已恢复正式包 `E1B39E9B…0F8EB37`；不能直接作为本轮回退产物。R3 APK 仍为 `854F341E…BAD8658`。仅核对已知本地路径；不推断其他受限目录内容或手机当前状态。收据：`tmp/a3f-r3-w0/local-rollback-precheck.json`。

用户在场后，必须先读取当前设备包名/路径/签名/hash，保存当时真实正式包（如有 split 则保全完整集合），确认回退可行，再替换为 R3。不从脏主目录临时构建另一包冒充原正式包。本项未操作手机，安装许可仍待用户确认。

### 现场操作卡（全部待执行）

按钮文字已按冻结候选源码只读核对；按钮存在不代表 Gate 通过。为避免 H3 先关闭资源导致 H4 无从注入，正例分两个显式开始周期；每次清理诊断 outbox 均是独立用户动作。

| 周期 / Gate | 用户实际操作 | 应记录的证据 |
|---|---|---|
| 安装前 / H0 | 确认物理安装；核对并保全当前正式包后安装唯一 R3 | 安装前回退包、安装后 device base 与候选 hash 一致；初态无 Activity 采集，BLE/Bluetooth 基线 |
| 周期一 / H0 | 选择“完整本地诊断”，点“开始诊断”；若非空恢复门拒绝，先留证，再分别显式清理与开始 | 可见持续通知；短锁解后“查询并提取已验证事件”，三事件及只读刷新 |
| 周期一 / H4 负例 | 活跃时点“无损释放已核实的孤立 owner” | 应拒绝，不释放活 owner，不打开第二 gate FD；不是成功回收 |
| 周期一 / H1、H3 | 点通知自身“停止活动观察”；观察页面、返回/刷新，然后点“停止并释放本次资源” | 原生终态起前台最多3秒退出旧 ready；逐 source close/文件租约/进程租约证据，无损且无 BLE 联动 |
| 周期一结束 / H5 | 刷新、重入，观察不自启；非空恢复门仍拒绝续开 | 释放不等于可重新开始；需要下一周期时分别点“显式清理诊断 outbox”和“开始诊断” |
| 周期二 / H2 | 活跃时点“注入通知可见性失证（非 OEM 复现）” | 注入、原生连续性检查发现、UI收敛三个时点；不以通知停止动作代填、不声称OEM复现 |
| 周期二 / H4 正例 | 原生已 stopped、仍有本代资源时，先点“注入 Usage owner 删除失败并关闭资源”，再另点“无损释放已核实的孤立 owner” | 注入后 owner 保留而FD/进程lease已释放；显式窄释放保留key/state/anchor/sequence，结果及重复/部分失败真实 |
| 周期二结束 / H5、H6 | 确认无自启、显式停止；恢复安装前保全的正式包 | 原正式包hash、冷启动、Activity诊断不存在、BLE/Bluetooth实读及用户确认 |

灰色按钮、未知状态或失败码先留证，不用清理或重启掩盖；失败后是否重试按原目标身份和既有控制合同判断。
