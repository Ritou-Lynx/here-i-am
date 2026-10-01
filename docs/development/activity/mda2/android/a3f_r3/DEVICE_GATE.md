# A3F-R3 手机 Gate 现场

2026-09-27；用户“开始手机gate”授权恢复现场执行。候选 `A3F-R3-b2adc44b-8b718af5`；基线 `v3-lab@b2adc44b7c04983a931c39695b81491cd295084b`，23 个已核源码路径尚未提交。

## 当前结论

2026-09-30 F2 同哈希 H0–H6 真人/受控设备 Gate 独立终审 GO：用户目视 Activity 持续通知、短锁解/查询、通知自身停止、页面释放、活锁拒绝与同页受控孤立 owner 释放；每一步以设备 UI、服务、owner/FD/哈希独立核对。首次 H4 因 W0 误触 Home 安全拒绝，显式清理后重做成功。正式 E1 完整 hash、BLE 前台 id 6157/Bluetooth=1、Activity 缺席与 13 项元数据延时复核均通过。H2 是同 APK 自动 Debug 注入；停后查询禁用、停止按钮完成后禁用，不冒称点击；FD/GATT 限制保留。见 [F2 真人 Gate](F2_HUMAN_GATE_20260930.md)与本机 `tmp/a3f-r3-human-f2/INDEPENDENT_REVIEW.md`。Goal 完成；下方 2026-09-29 状态为历史。

2026-09-29 F2 最新：`0AC428177247F757BA21C95B734A6121610D87735071BFC08E1A377C39324911` 三份完整真机时序中手动/返页/受控失证的 unknown 发布均≤3秒，通知按钮实际停止且返前台已非ready，旧running迟到回执被terminal守卫拒绝。显式关闭两owner，正式E1包/原绑定BLE前台恢复、13项元数据隔时不变；FD核对非穷尽。F2同哈希真人通知/锁解及H4/H5完整Gate尚待补，Goal开放。见[自动时序补验](AUTOMATED_TIMING_GATE.md)和本地 `tmp/a3f-r3-timing-device-f2/DEVICE_RESULT_F2.md`；下方F1/旧候选为历史。

9A旧包H1通知自身停止同步保守775ms、H2受控失证515ms独审接受。F1D3431A新Debug包三份完整实机trace：manual/resume checking逻辑顺序通过，受控注入下迟到旧running回复terminal拒绝且有限尾段无ready回弹；unknown投影3,026,775/3,007,425/3,004,019µs，严格3秒均RED。通知按钮自动定位失败不算通过。两owner/gate FD关闭后正式E1完整hash恢复，BLE前台6157/Bluetooth1、Activity缺席及13项元数据不变两次隔时确认，私有转发清理。本轮H6收尾成立，内部预算返修与新hash实机重验待续；Goal未完成，无commit/push。详见[自动时序补验](AUTOMATED_TIMING_GATE.md)。下文历次候选与真人现场为历史。

## 安装与回退

- SM-S9110 / Android 16；设备单 APK。19:29:03 +08:00 读取实际正式包，备份及设备 SHA-256 均为 `E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37`，匹配 R2 恢复包。
- 签名核验 exit 0，与候选相同证书；回退保存为本机 `tmp/a3f-r3-device-gate-854f341e/rollback/base.apk`，不从脏目录重建替代。
- 19:29:55–19:30:29 +08:00 安装、冷启动 exit 0；设备 base SHA-256 为 `854F341E108733464A351AAB267A14563033A4CCC6CB0A715862860EDBAD8658`，与唯一候选完全相同。
- 初态页面 `diagnostic_not_started`，usage/screen sequence 0、查询/普通停止按钮禁用；Activity 服务不存在。没有替用户点击开始、清理、注入或停止。
- **BLE 基线差异保留**：安装前 BLE 与 Companion 服务存在；安装后 BLE 服务不存在，Bluetooth 前后均为 1。安装替换的影响不能归于尚未发生的 Activity 停止；后续不能把“BLE 仍不存在”写成活跃 BLE 共存通过。
- 未清完整数据、未全包 force-stop、未更改权限或蓝牙开关。

## 待执行与证据边界

用户先在“完整本地诊断”点一次“开始诊断”，报告可见通知或失败。若遇 `recovery_authority_required`，先保留证据，再要求分别显式清理诊断 outbox 和新开始。未收到操作结果前不替用户清理。

H3/H4 在原生终态后、资源操作前后分别保存两个 source 的 owner/state/anchor/journal/gate 存在性和哈希。只读读取 Android FD/锁的聚合证据；不能主动另开 gate FD 作为探针。App 的 lease 布尔与实际 OS 机制证据分开；专用加密 backing 文件 hash 不等于独立读取 Keystore key。H4 需要“服务已停、旧 store lease 仍持有”的拒绝负例，运行中拒绝不能替代。

现场收据：`tmp/a3f-r3-device-gate-854f341e/preinstall.json`、`rollback/signature.log`、`install-receipt.json`、`install.log`、`launch.log`、`h0-initial-ui.xml`。原始本机材料不提交；不导出 owner 身份、内部 token、key 或原始使用内容。
## 首次开始：恢复门拒绝（19:43 +08:00）

用户原话：“点击开始诊断后没有活动观察正在运行”。UI 实读 `recovery_authority_required`，Activity/BLE 服务均不存在、Bluetooth=1；并非已启动后的通知失证。两个 source 的 owner/journal 均不存在，旧 state/anchor/gate 保留。当前页面 sequence0 不代表旧持久 sequence 已清零。

开始在建立 store/原生采集前被非空目录恢复门拒绝，符合 fail-closed。已向用户要求分别显式清理诊断 outbox 和重新开始，尚未收到完成回执，没有替用户执行清理。清理限诊断队列，专用密钥/完整 App 数据保持。

收据：`h0-start-no-notification-ui.xml`、`h0-start-no-notification.json`、`h0-recovery-gate-files.txt`，均位于本轮手机证据目录。只读观察器 `capture-safe.ps1` 已语法检查并执行，`h0-recovery-held.json` 观察两 gate FD 为0但有1个不可读/竞态FD，`/proc/locks` 不可读；不将该快照提升为完整 OS 锁证明。专用加密 backing 文件只保存哈希，不解密或输出 key。

独审核对现有 BLE BootReceiver 只处理 BOOT_COMPLETED，诊断入口没有产品心率设置页或 BLE 恢复调用；MY_PACKAGE_REPLACED 属于通知插件。安装后 BLE 未恢复的唯一原因尚未证明；活跃共存 Gate 仍未建立，正式包恢复后也须实核而非预判会自动启动。
## 清理误拒绝已定位；失败候选已回退（19:49–20:03 +08:00）

- 用户确认清理后再开始仍无通知；`h0-after-explicit-reset-start.json` 仍为恢复门、持久文件及密钥 backing hash 未变。要求只点清理后，用户确认执行；`h0-reset-only-ui.xml` 得到 `diagnostic_reset_scope_invalid`。
- 目录元数据无额外文件或链接，两种系统路径 spelling 的设备号/inode相同。shell realpath 各自保留 spelling，不能代表 Dart 的解析结果。
- 当前 APK 的 Debug VM 只读诊断直接核对原生 root `/data/user/0/.../no_backup/mda2_activity`、scope正确；对已编译的纯只读 `_validatedRoot` 临时断点956读取：Dart resolved 为 `/data/data/.../no_backup/mda2_activity`，strict比较拒绝。收据 `h0-dart-scope-read.json`。未调用reset/start/注入或删除，断点及本轮端口转发已撤销；这些调试停顿不参与UI收敛时限验收。最初表达式检查因无编译服务失败、无状态改变，随后以对象/已编译方法只读检查定位；不把空实例列表当作根不存在。
- 最窄返修由 D 原工作包负责：真实 MethodChannel 返回处以 Dart 规范化可信 no-backup 父边界，再拼固定诊断根；保持父节点、诊断根、source和文件反链接、精确目标和broker门。先取得别名正例 RED，再做修复/回归/独审/组合和新唯一候选；不手动删除手机目录绕过错误。
- 20:02:03–20:02:40 恢复安装前备份正式 APK；安装及冷启动exit0，设备 SHA-256 `E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37`。Activity服务不存在、Bluetooth=1；立即及20:03稍后实读 BLE 服务均不存在，不声称完整 BLE 运行态已恢复。
- 回退未清App数据、未force-stop、未改权限/蓝牙。`failed-candidate-restore.json`、`formal-restore-later-services.json` 保留实际结果。旧APK另保全为 `failed-candidate.apk`，仍为854F341E…BAD8658；新构建不能覆盖这份失败候选证据。

上述本机收据位于 `tmp/a3f-r3-device-gate-854f341e/`；返修输入与验证另存 `tmp/a3f-r3-pathfix/`。本轮候选失败，不继承或宣称通知/H1–H5通过，Goal未完成。后续新APK需重新安装及真人Gate，BLE活跃共存及最终运行态恢复仍单独待验。
## 原绑定 BLE 恢复（20:07 +08:00）

用户明确允许“按原绑定恢复心率服务”，范围含正式包及后续诊断候选。调用既有 START 入口；首次命令默认用户-2被系统拒绝（exit255，无启动），改为App所属user0后exit0，BLE服务真实存在，Activity仍不存在，Bluetooth=1。未提升手机权限、未改绑定/配置/蓝牙；没有读取心率内容，也不以service存在宣称GATT连接或数据已恢复。

收据 `formal-ble-resume.json` 保留初次失败；`formal-ble-resume-same-user.json` 与 `formal-ble-resume-confirmed.json` 为后续真实结果。本轮正式APK回退及BLE服务运行态已恢复；不代填新候选的共存或H1–H5。

## 路径修复新候选安装（20:23 +08:00）

- 精确APK SHA-256 `A684CDBFB5F627164EDA558B681AB7C84F4DB6738F1B4265B754F81205807C7F`，409244236字节，hereIAmV3 Debug诊断入口；运行输入1223文件集合 `4D4667AFC0E39D5AB17E942241CA76ECF3BC9F47156940E899B2BD8E45044C4E`，见 [新候选manifest](CANDIDATE_MANIFEST_PATHFIX.json)。没有新commit。
- 平台可信父边界规范化修复：D66/66、组合192/192、分析和独审通过，critical3/3、构建与签名exit0。原生77/77保留在未变源码上，不冒称新做设备验证。实现和反链接边界见 [修复说明](PATH_CANONICALIZATION_FIX.md)。
- 主线选择性更新4个已有R3源码/测试/脚本文件；23候选路径逐hash匹配，72个其他已修改tracked文件和Git index在集成前后不变。并行P6工作保留。
- 安装前实读仍为E1B39E9B正式包，BLE存在、Activity不存在、Bluetooth=1。20:22:40–20:23:17安装/冷启动exit0，设备实际APK完整hash匹配；未全包force-stop、未清数据。
- 20:23:42按既有原绑定授权调用BLE START（user0），exit0；BLE真实前台、通知id6157，Activity不存在、Bluetooth=1。没有更改绑定或读取心率内容；不以service存在宣称GATT/数据已恢复。
- 初始诊断页面为 `diagnostic_not_started`，开始/清理可用，查询/普通停止/两注入禁用。已要求用户仅点显式清理，尚未取得本候选的清理成功或真人通知结论。

新现场收据位于 `tmp/a3f-r3-device-gate-a684cdbf/`：`preinstall.json`、`install-receipt.json`、`ble-resume.json`、`h0-initial.json`。两gate FD计数0但存在2个瞬时不可读FD且全局锁信息不可读，不提升为完整OS锁证明。H1–H5及最后正式包恢复仍待。

## 新候选 H0 通过（20:24–20:28 +08:00）

- 用户明确只清理、未开始；页面实读 `diagnostic_reset_complete`，旧诊断state/anchor/gate被清理，三个专用key backing hash逐一不变。Activity未开始、BLE仍存在，Bluetooth1。`h0-reset-result.json`保存比较结果。
- 用户随后单独点击开始，并真人确认“活动观察正在运行”。之后按要求锁屏约10秒、解锁并查询；页面实读ready、同步verified、native running/ready，usage/screen fresh，sequence分别2/3。
- `h0-query-counts-ui.xml`实读screen_interactive/non_interactive/user_present各1、collection_gaps0、usage_queries1。H0正常路径通过，不扩展为系统事件完整性保证。
- Activity和BLE同时存在、Bluetooth1。两source各有1个真实gate FD；已有FD的fdinfo分别显示同App PID的POSIX ADVISORY WRITE锁（0 EOF），未另开gate文件；全局/proc/locks仍不可读，瞬时FD枚举可能有竞态，不能据单次快照证明所有时间点。
- 3秒同步观察器只读调用独立getObservationStatus并读取controller现有投影，已独审。首次初始化180ms超时保留为观察器失败；只将初始化上限调至1500ms，第二次6秒校准17样本、unknown0。它不暂停App、不刷新controller、不调用控制动作；投影证据仍须与真人/屏幕核对。

当前正在等待用户点击通知自身“停止活动观察”，H1–H6尚未通过。上述新收据均位于tmp/a3f-r3-device-gate-a684cdbf。
## H1首次停止及H4前态（20:30–20:31 +08:00）

用户确认从通知点停止，但不知ready含义；当时系统面板仍展开，W0仅收起面板再读取诊断页，未代点停止。页面真实为notification_stop、查询禁用；Activity服务不存在、BLE仍存在、Bluetooth1。与H0查询后比较13行文件元数据完全相同，两source原gate FD190/214仍各有POSIX WRITE锁；满足“native停而旧store仍持有”负例前态，不等同资源释放。

H1计时观察共368样本：前45个有效running/ready，随后323个unknown，工具将RPC失败统一归码，无法据此证明失效原因或3秒收敛。App同PID24166仍存活；页面正确终态及BLE保持已有独立证据，≤3秒必须补测，H1整体暂不通过。辅助工具排查对象ID寿命；不得把观察器失败归为App失败。误取的系统面板文字已排除，不作为诊断证据保留。

下一步用户只点“无损释放已核实的孤立owner”，先验活lease拒绝，再普通关闭。见h1-partial-result.json及h1-returned-page.json。

## H4显示缺陷与本轮恢复（20:32–20:38 +08:00）

- 两次用户显式无损释放后，第一次独立文件/FD读数证明13行哈希元数据不变、原FD190/214与POSIX锁保持；不声称连续监测每一瞬间的FD数量。页面数秒后只见notification_stop，没有稳定拒绝提示。
- 独审定位：releaseOrphanOwners的catch写入动作拒绝，下一秒前台同步经collector状态通知及controller两处赋值覆盖_readiness。本次在逐source循环前失败，ownerReleaseCodes没有稳定兜底。活store的native beginRelease拒绝实际为diagnostic_owner_release_refused，不必然为diagnostic_outbox_lease_held。现有测试只有即时断言，缺少下一轮、手动刷新和resume。资源安全拒绝与显示失败分开：H4页面要求不通过。
- U仅返修controller/screen及专项测试：独立保留最近显式资源动作结果，自动生命周期同步保持；下一明确动作更新，新代重置，不改broker/文件/wire/通知/BLE契约。当前未取得返修验证或新APK。
- 第二版辅助见证167个有效样本后在55.9秒采样超时停止，后续用户回执已在窗口之外；未捕获瞬间拒绝，不伪造动态证明。辅助脚本另修独立ID区域并扩展有界读取时限，不属于APK变更；旧unknown日志全部保留。
- 用户点击“停止并释放本次资源”后，h3-normal-close文件对照仅两个owner由存在变为不存在；state/anchor/journal/gate及三个key backing不变。当前App两gate FD均0、不可读FD0；这是实际FD关闭证据，进程lease结果未取得完整UI投影，H3整体不单独写通过。
- h3 UI读取时系统面板在前，诊断UI集合为空，未用于页面结果。另一次H4滚动后的uiautomator idle失败导致旧XML被取回，相关UI已明确排除；观察脚本已改为逐次唯一文件且必须确认dump成功，不得接受旧UI。
- 20:38:00–20:38:34恢复原正式包，安装/设备hash/冷启动exit0；按原绑定授权启动BLEexit0。立即读数尚未成为前台，20:38:57后续实读前台true/id6157、Activity不存在、Bluetooth1。调试转发已撤销，无全包force-stop、全数据清理、绑定/蓝牙更改。

精确A684CDBF APK保全为本机tmp/a3f-r3-device-gate-a684cdbf/candidate.apk，manifest已更新路径；没有被后续构建覆盖。恢复收据formal-restore-result.json、formal-restore-ble-confirmed.json保留先后读数。H2、H4正例和H5未完成，最终新候选H6仍待，Goal保持开放。

## 资源动作结果返修与第三候选（20:44–20:51 +08:00）

- UI-only不可变动作结果使用本次局部actionCode，stop/孤立释放/reset结束时保留，自动核对不覆盖；下一显式动作更新，新begin清除旧代结果。中文动作/结果附既有公开码，不改变wire、原生、store或授权。见U_HANDOFF与W0_CONTROL_CONTRACT第7节。
- 同一大视口旧版widget在1100ms前台tick后取得真实RED exit1；最终UI31/31、分析exit0。早期小视口导致新行未构建的失败已保留，未放宽断言。独审核对11inputs和3日志及迟到Future不覆盖新回执断言，最终接受。
- W0完整组合193/193、7测试文件/17输入逐字节一致，分析无问题。4路径选择性集成，23候选源码/测试/脚本hash一致，70个其他dirty tracked和index保持。无commit/push。
- 1223运行输入SHA256 `C1EC9F4646D1363B90C893D815FB00399074D8A6C53997528225EAC8A02BFC9D`；JNI188未变。critical3/3后构建actual0，113.717秒；构建后再次逐输入核对。
- 唯一APK SHA256 `9A099611F08763B2A73C962557D65970864FB9D4775001D3EE5AB2791ACBB6C3`，409243922字节，hereIAmV3 Debug诊断入口；包名/签名核对exit0。见 [本候选清单](CANDIDATE_MANIFEST_UI_ACTION.json)。
- 20:50:04–20:50:40安装与冷启动exit0，实际手机APK完整hash相同。按原绑定授权恢复BLE；20:51:17前台true/id6157、Activity不存在、Bluetooth1。初始页面diagnostic_not_started、sequence0，所有采集/注入默认未开始。
- 新本机证据目录为tmp/a3f-r3-device-gate-9a099611；构建/组合/集成证据为tmp/a3f-r3-ui-actionfix/w0，U原始RED/GREEN为同层evidence。只读计时器独立根/采样ID区，采样RPC750ms、初始化1500ms、总时长最多180秒，真实时间窗/unknown均保留，不放宽3秒验收定义。

已要求用户仅显式清理、未要求开始；尚未给本候选任何真人通过结论。

## 第三候选显式清理已确认（20:57–20:58 +08:00）

用户回复“已清理”。当前9A099611页面为diagnostic_reset_complete，start_requests0、usage_queries0、两sequence0；滚动实读“最近资源动作：显式清理 · 已完成”，结果在后续读取仍保留。三个专用key backing hash逐一不变；Activity未开始，BLE真实前台6157、Bluetooth1。两gate FD快照0，存在瞬时不可读FD时仍不宣称全局锁证明。h0-reset-result.json绑定当前APK；用户下一步单独开始、真人确认通知、锁解并查询，H0尚未完整通过。
25秒只读见证共76样本，73个running/ready；3个初始target_unavailable保持未知，不计通过。正常结束，无RPC超时。此为运行状态辅助证据，不替代真人通知和锁解查询回执，见h0-running-observed.json。

## 第三候选锁解查询已获用户回执，页面计数待核（21:22–21:24 +08:00）

用户针对通知确认、锁屏约10秒、解锁并显式查询回复“已完成”。两次只读快照均确认Activity前台及BLE前台6157、Bluetooth1；两个source原gate FD各1，现有FD的fdinfo锁行保持。后一次不可读FD为0，但全局锁仍不可读，不扩大证明边界。

两次新UI dump均成功，但过滤其他App后诊断UI为空；原因未判定，不把空页面当作查询失败，也不推定事件计数。已请求用户回“完整本地诊断”并保持亮屏，不需再开始或查询。H0仍待本候选事件计数/页面投影，尚未请求H1通知停止。只读计时器当前未运行；H1须待页面就绪后新开时间窗。

收据：本机tmp/a3f-r3-device-gate-9a099611/h0-completion-reported.json、h0-lock-unlock-query.json、h0-return-page-check.json。独审再次核对见证hash及保守时限：连续前台用最后非终态native读取起点至确定非ready的UI读取终点；resume另分段，不能从首次stopped读完才开始计时。无源码、APK或设备配置修改。

## 第三候选H0通过，H1计时通道故障另列（21:39 +08:00 起）

- 用户回诊断页后，h0-user-returned.json实读collector ready、native running/ready、同步verified；usage/screen sequence均3，usage_queries1、start_requests1、reset_requests1。screen_interactive/non_interactive/user_present各1、collection_gaps0；与本候选显式开始、真人通知和锁解查询回执合并，H0正常路径通过。当前usage为fresh、screen为stale，保留实值；不倒填过去fresh或系统事件完整性。
- Activity及BLE均前台，Bluetooth1；双source原gate FD/锁仍持有。两个先前UI空快照不参与页面验收。结果绑定h0-result.json与本候选9A099611。
- H1只读见证三次均在初始化前后极短时间报observer_failure、samples0；独立握手只输出HttpException，TCP连接成功不等于VM握手成功。同端口重建和新本地端口均无效；本App socket/proc端口表安全读取被拒绝，没有扩大权限或扫描端口。失败不归因于App功能，也不冒称已取得3秒证据。
- 尚未停止或重启App。已告知用户先执行通知停止与资源保护检查，严格3秒同步继续单列待验。新APK未产生，H1功能部分/H2–H6和最终正式包恢复继续。

本机失败证据：h1-notification-stop-witness{,-v2,-v3}.jsonl、h1-connection-probe.json、h1-forward-refresh.json、h1-fresh-forward.json。只读端口定位辅助脚本位于tmp/a3f-r3-pathfix/list-app-loopback-listeners.ps1，hash 7DA75B46253782B60D87693E6B3A3987BFCA83A776D721FBDF14F57BDAC39321；独立于APK输入，语法检查通过，执行仅得到table denied。

## 用户清除通知后的实际失证现场与H4拒绝负例（22:04–22:07 +08:00）

- 用户原话“我不小心把通知清除了”，并未执行预定H1通知停止按钮。实读native stopped/notification_not_visible、同步verified、collector非ready、查询禁用，Activity服务不存在；usage/screen sequence仍3/3、start1/query1/reset1。只记录实际通知失证补充现场，不替代H1、预定H2注入或3秒时限，也不归因三星OEM；具体清除范围未核。
- BLE仍真实前台6157、Bluetooth1。独立只读通知活动列表核对本包仅一条记录：BLE6157存在、Activity5102143不存在。首版严格标题解析失败，active_section_found=false，其false字段全部按unknown排除；v2标题匹配成功才作为存在性证据。没有输出通知正文或其他App记录。
- 失证前后13行文件元数据完全一致；两源owner/state/anchor/gate hash保持、journal仍不存在，三个专用key backing hash保持；服务终止未自动释放当前store资源。
- 用户按要求只点“无损释放已核实的孤立 owner”。22:05:51及22:06:55两次页面独立动作行均显示diagnostic_owner_release_refused，两个UI读取窗口间61.413秒；native仍notification_not_visible。两次读取跨过自动同步，拒绝提示未被覆盖。
- 操作前后13行元数据完全一致，原FD185/201及各自fdinfo POSIX WRITE锁保留，后快照不可读FD0。H4“已停但活lease”的拒绝负例通过；快照不独立证明从未短暂打开第二FD，该点结合已审拒绝链。H4正例仍待，不能把本项误写为成功回收。
- 已请求用户仅点“停止并释放本次资源”做H3，尚未取得该动作回执；不清理或重新开始。严格H1/H2时限和最后正式包恢复继续待验，Goal未完成。

本机证据：notification-dismissed-by-user.json、notification-dismissed-active-notifications-v2.json、h4-live-lease-refusal{,-stable}.json及对应-files.txt、h4-negative-result.json。均绑定9A099611唯一候选，没有源码/APK改变。

## H3正常关闭通过，H5刷新返回不自启已核（23:48–23:53 +08:00）

- 用户回复“已停止并释放”。两source逐项实读closed、文件租约已释放true、进程租约仍持有false、文件声明仍持有false；独立动作结果为停止并释放已完成，普通停止按钮禁用。未执行第二次停止，不冒称设备上的重复点击幂等。
- 两个owner变为不存在，其余11行元数据逐行保持，包括state/anchor/gate、journal不存在及三份key backing；usage/screen sequence保持3/3。Activity无、BLE前台6157与Bluetooth1保持。初两次FD扫描gate均0但有2个瞬时/不可读FD，保留限制。
- 用户对刷新/Home/返回操作回复“1”。23:52自然快照UI不在本App，但当前进程gate FD均0且不可读FD0，补足该时点进程FD枚举证据；全局锁仍不可读，不声称全局证明。此证据在后续覆盖安装前取得，不由进程替换补填。
- W0只用本App既有启动入口将原task带回前台（系统明确未新启Activity），随后滚动读取：manual_refreshes1、start_requests1、usage_queries1，序号3/3及两源关闭结果保持，13行元数据不变，没有自动采集。不将W0导航冒称用户已自行返回。
- H3本次正常关闭及无损保留通过；H5刷新/返回不自启通过，非空恢复门拒绝仍待。独审接受H3结论及上述FD边界。

收据：h3-user-stop-release.json、h3-release-source-details.json、h3-normal-close-result.json、h5-refresh-return.json、h5-w0-return-navigation.json、h5-refresh-return-counts.json、h5-refresh-return-result.json。W0滚动和带前台只属导航，没有代点开始/清理/释放按钮。

## 同一APK重装恢复只读观察环境（23:54–23:57 +08:00）

- 在显式资源关闭、H5返页证据保全后，正常覆盖安装同一9A099611 APK以恢复失效VM连接。安装前核对v3-lab@b2adc44b、候选完整hash、实际手机hash及正式回退E1B39E9B hash；23:54:36–23:55:11安装/冷启动exit0，设备base仍为9A099611。无新代码、构建、force-stop、数据清理或权限/绑定变更。
- 按既有原绑定授权调用BLE START user0；后续实读前台6157、Bluetooth1，Activity不存在。安装前后13行诊断持久元数据完全相同；新controller页面sequence0只表示初始投影，不能解释为持久序号被清零。
- 新进程30900的启动日志提供唯一新VM端点；建立新的专用只读转发并撤销旧27632，认证路径仅本机私有连接配置保留，不导出。12秒校准36样本正常结束，无握手或RPC失败；36个target_unavailable对应未开始诊断，无活动计时通过结论。
- 只读连接恢复与Gate结果分开；新进程从新观察时间段开始，不补填旧H1/H2时限。已请求用户仅点开始、不先清理，验证非空恢复门；尚待结果。

收据：vm-recovery-reinstall-receipt.json、vm-recovery-ble-resume-receipt.json、vm-recovery-postinstall.json、vm-forward-reconnected-receipt.json、vm-recovery-witness-calibration.jsonl、vm-recovery-result.json。当前连接配置为本机vm-local-connection-reconnected.json（敏感，禁止输出）；原配置只保留历史。

## 非空恢复门拒绝通过（2026-09-28 00:02 +08:00）

用户回复“已点开始”，未先清理。新进程页面明确recovery_authority_required，Activity服务仍不存在、BLE真实前台6157/Bluetooth1。对同包重装后基线逐行比较，13项持久元数据完全不变，没有新owner或采集；新页面序号0不解释为旧持久数据被重置。非空恢复门拒绝通过，见h5-nonempty-explicit-start.json及h5-nonempty-result.json。

已要求用户下一步只点显式清理诊断outbox，清理回执待核；尚未要求重新开始。H1通知按钮、H2可控失证及严格时限、H4正例和最终正式包恢复继续待验，不将恢复门通过提升为整个Goal完成。

00:05用户单独回复“已清理”。cycle2-explicit-reset.json实读diagnostic_reset_complete，诊断10个文件条目均不存在，三份key backing hash不变，Activity尚未开始、BLE前台保持；见cycle2-reset-result.json。随后才要求用户新开始、真人确认通知并显式查询，当前等待该回执；不合并清理与开始授权记录。

H2触发前只读复核：既有Debug注入设置失证标记后立即排队执行正常queryAndAccumulate，不是等待30秒周期，也不是直接stop。瞬态diagnostic_notification_loss_injected可能被状态同步覆盖；现有witness可记录原生终态和UI投影读取窗口，不能把用户回复时间或首次stopped读取完成时刻当作准确注入/终态发生时间。H1/H2分别开新观察段，先见同目标running/ready，再要求真人动作；严格3秒只计算可执行前台的终态收敛。

## 第二周期开始/查询已核，计时连接再次不可用（2026-09-28 00:09–00:18 +08:00）

- 用户回复“已开始并查询”。cycle2-start-query.json实读collector ready、native运行状态、Usage sequence2，Activity前台5102143和BLE前台6157、Bluetooth1。原Usage/Screen gate FD172/239各持POSIX WRITE锁。此为第二周期开始/查询证据，不重复提升H0或补填任何3秒时限。
- 新见证先因电脑专用转发缺失而连接拒绝；恢复同一24925→39191后仍零样本失败。诊断副本明确main_phase=connect_websocket、HttpException，尚未进入VM初始化。随后仅访问同App UID的既知设备回环端口39191，固定分类connection refused；不扫描其他端口，不输出认证路径或响应正文，不能据此判断远端监听消失的原因。独立代码审计未见见证正常关闭会删除adb转发或关闭远端VM服务。
- 00:17独立服务/FD快照仍确认Activity与BLE前台、原双FD锁保持，不可读FD0；本次诊断UI不在前台，过滤结果为空，不能拿空UI作状态同步证据。没有重装、重启、清理或重新开始，现有诊断持续运行。
- 停止重复连接探测；向用户发出明确通知按钮停止并返回的H1功能步骤。H1功能结果待回执和页面核对，严格3秒独立待验；随后可在本代已停止资源上执行H4正向注入/窄释放。H2和最终正式包恢复仍待。没有降低验收定义或完成Goal。

本机证据：cycle2-start-query.json、cycle2-h1-{witness,witness-v2,connect-diagnostic}.jsonl、cycle2-h1-connection-probe.json、cycle2-h1-forward-restored.json、cycle2-device-vm-probe.json、cycle2-pre-h1.json。辅助诊断见证只增加固定阶段/异常类别，SHA256为40DC6191D0E9A6C3AAD11F3F7D8963D191206682F69357ADA543D5FEBAEC6442；不属于APK输入，不改变当前9A099611候选。

## 第二周期通知已消失，转入H4正向现场（00:18–00:20 +08:00）

用户回复“通知被清理了”，不推断是谁清除或具体清除范围；未获得通知停止按钮动作回执，因此H1按钮场景仍未通过。00:19服务快照确认Activity不存在、BLE前台保持；W0仅将原有诊断task带回前台并滚动读取，页面为stopped / notification_not_visible、verified、collector非ready、查询禁用，Usage/Screen sequence2/0。开始到失证后13行元数据逐项相同，原gate FD172/239及锁保留。只读活动通知列表确认Activity5102143不存在、BLE6157存在，Bluetooth1。

上述是第二次实际通知失证后的功能收敛证据，非预定H2注入，亦无3秒证明。证据为cycle2-notification-gone{,-returned}.json、cycle2-pre-orphan-details.json、cycle2-w0-return-navigation.json、cycle2-notification-loss-result.json。已向用户发出唯一下一动作“注入 Usage owner 删除失败并关闭资源”；尚未获得回执，不提前记录关闭、孤立owner形成或窄释放成功。当前满足H4注入前同代stopped且store仍持租约的条件。

## H4正例：显式关闭失败形成冻结孤立owner（00:20–00:22 +08:00）

用户单独回复“已注入并关闭”。逐源实读Usage为owner_lock_cleanup_failed、Screen为closed，两源文件租约已释放true、进程租约仍持有false、文件声明仍持有false；独立动作结果诚实显示observation_stop_failed，未被自动状态同步覆盖。Usage原owner hash保持，Screen owner已消失，其余12行元数据逐一不变（含Usage owner），序号2/0与start2/query1/reset1保持，BLE前台6157/Bluetooth1持续。

三次FD枚举均gate0/0但有1个瞬时未读项，不能单独当成完备FD扫描。对原先已证持锁FD172/239定点只读复核，两者均已复用为非gate；额外未读项再次检查时已消失（VANISHED）。据此记录原gate句柄已不再占用原FD，并结合逐源close结果保留证据边界，不声称全局锁证明，不新开gate探针。

证据：h4-positive-injected-close.json、h4-positive-injected-details.json、h4-positive-pre-release.json及各-files.txt，h4-positive-orphan-formed-result.json、h4-positive-original-fd-recheck.json。已请求用户下一独立动作“无损释放已核实的孤立 owner”，结果待核；形成残留不等于回收成功。

## H4正例无损释放与重复操作通过（00:23–00:25 +08:00）

- 用户对唯一窄释放动作回复“1”；实际文件/UI收据确认Usage owner被删除、Screen owner仍不存在，其他12行元数据保持。独立动作结果diagnostic_owner_release_complete，Usage逐项owner_released、Screen closed，两source close结果均closed且file lease released=true/process lease=false/file claim=false。后续同步后的页面与元数据仍保持，序号2/0、start2/query1/reset1不变，Activity未启动，BLE前台6157/Bluetooth1。
- 用户对独立重复释放步骤再次回复“1”；页面诚实返回Usage target_absent、Screen closed、总动作complete，13行元数据全部不变，计数不变，没有重新采集。初次实质释放与后续幂等结果分开保存，不把第二次target_absent误记为再次删除。
- 本段gate FD扫描0/0，瞬时未读1仍保留；结合注入关闭前后原FD/逐源结果，不扩大为全局锁证明。H4活租约拒绝、孤立形成、显式窄释放、失败/成功提示保持和重复操作均取得本9A候选设备证据。H1通知按钮、H1/H2严格3秒、H2受控失证和最终正式包恢复仍待，Goal未完成。

证据：h4-positive-release-{return,stable-details,repeat}.json及-files.txt、h4-positive-release-result.json、h4-positive-repeat-result.json。已请求下一独立显式清理，为H2新周期准备；尚未获得回执，不提前记清理或新开始。

00:26独审接受H4正例及重复操作，仅覆盖H4并保留FD限定。用户对独立清理指令回复“1”；cycle3-explicit-reset.json实读diagnostic_reset_complete，两序号0、10项诊断文件不存在、3份key backing hash与清理前一致，Activity未启动、BLE前台/Bluetooth1。随后才请求用户仅开始并保持诊断页，尚待该回执。

观察工具补充只读审计：当前Flutter本地工具/Android embedding未发现可直接外部调用的io.flutter.view.DISCOVER入口；getVMServiceUri仅进程内缓存API，当前App无查询桥接。既有原生状态/MethodChannel/UI快照没有足以重建终态到前台收敛的连续时间记录，不能替代严格3秒证据。未执行猜测广播、完整flutter attach或新增APK埋点。

## H2受控失证功能部分接受，显式关闭已核（00:27–00:29 +08:00）

用户分别对新开始、唯一页面失证注入按钮指令回复“1”。注入前collector ready、Activity真实前台，原gate FD197/239持锁；注入后原生stopped / notification_not_visible、同步verified、collector非ready，Activity服务不存在而BLE前台/Bluetooth1保持，原gate锁继续持有。用户回执、前后实读与已审Debug注入走真实连续性检查的链条共同支持H2功能部分，独审接受；不声称物理通知被移除或OEM复现。

没有连续计时，也未捕获diagnostic_notification_loss_injected瞬态，不能给准确注入时刻、3秒上界或期间无短暂回弹。相较开始快照，只有Usage state/anchor改变，序号0→1、permission_changes1、usage_observations0；快照不能定位该写入准确时刻。页面usage_queries1为延续计数，不等于没有原生查询（注入本身会调度正常queryAndAccumulate）。两owner、其他source元数据与三份key backing保持。

随后用户单独停止并释放：两source closed，file lease released=true/process lease=false/file claim=false；两个owner消失，其他11行不变，序号保持1/0，Activity未重启、BLE仍前台。gate扫描0/0、瞬时未读1与全局锁不可读继续保留。证据：cycle3-{explicit-reset,start,explicit-close}.json、h2-controlled-loss.json及-files.txt、cycle3-pre-h2-result.json、h2-functional-and-close-result.json。

下一步仅补H1通知按钮功能场景后恢复正式包；严格3秒继续作为未验，不用功能通过替代。已请求独立清理为该场景准备，尚未获回执。

00:32用户对单独清理回复“1”，cycle4-explicit-reset.json确认diagnostic_reset_complete、10项诊断文件不存在、3份key backing保持、Activity未开始。用户再对单独开始回复“1”；00:33 cycle4-start.json实读ready、Activity/BLE均前台，原gate FD197/244及POSIX锁存在。随后立即给出通知自身文字按钮停止步骤，等待该动作回执，未要求查询或其他按钮。

## H1通知按钮功能部分接受，最后资源关闭已核（00:40–00:42 +08:00）

用户对通知自身“停止活动观察”指令回复“1”。页面明确stopped / notification_stop、verified、collector非ready和查询禁用，Activity服务不存在，BLE前台6157/Bluetooth1保持；原gate FD197/244及锁仍持有，后次扫描不可读FD0。相较开始只有Usage state/anchor改变、权限事件使sequence0→1；不能写成停止区间持久数据全部不变。独审接受H1功能部分，严格3秒、立即checking及连续无回弹仍未取得证据，不提升为完整H1通过。

随后用户单独点普通停止并释放并回复“1”：两source closed，file lease released=true/process lease=false/file claim=false，两个owner不存在，其他11行元数据不变，序号1/0保持。覆盖安装前仍在原进程30900定点复核原FD197/244，均已复用为非gate；全量扫描gate0/0有1个瞬时未读项，保留限制，不由后续安装替代资源关闭证据。

证据：h1-notification-button-{return,details}.json及-files.txt、h1-functional-result.json、cycle4-final-explicit-close.json及-files.txt、cycle4-close-original-fd-check.json。正式回退包E1B39E9B完整hash已再次核对，接下来按既有授权安装恢复，并分别确认实际包hash、冷启动和BLE前台；此段尚不提前记录恢复完成。

## 正式包恢复与本次设备收口（00:43–00:46 +08:00）

最后一轮资源关闭证据保全后，00:43:44–00:44:22覆盖安装验收前备份正式包；安装前实际设备为9A099611，安装后完整SHA256为E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37，与备份一致。安装、正式入口冷启动、原绑定BLE START user0均exit0。没有force-stop、清App数据、改绑定/权限/蓝牙；不从脏主目录重新构建替代。

00:44:40–00:44:51独立实读新PID4793，Activity诊断服务不存在，BLE前台true/id6157，Bluetooth1。与覆盖安装前对照，13行诊断持久元数据逐行相同，最后owner仍不存在；未读正式聊天页面或心率内容。独审接受H6恢复，不扩大为BLE实时测量/GATT、正式聊天体验或全局OS锁通过。后续仅移除本轮匹配的24925→39191调试转发；三个已知专用本地端口均无残留映射，其他映射不动。

本机证据：formal-final-restore-receipt.json、formal-final-state.json及-files.txt、final-device-gate-result.json、final-forward-cleanup.json。辅助restore-formal-final.ps1核对固定分支/HEAD、候选/备份/设备hash以及原进程显式关闭，安装请求与实际状态分别落证据。一次内联清理命令exit1且无收据，随后先只读确认映射仍在，再精确移除并实读无残留；不把失败请求当成已清理。

| Gate | 当前9A候选结论 | 边界 |
|---|---|---|
| H0 正常路径 | 通过 | 真人持续通知、锁解和查询事件已核 |
| H1 通知按钮停止 | 功能部分接受 | notification_stop及页面收敛已核；3秒、立即checking、连续无回弹未证 |
| H2 受控通知失证 | 功能部分接受 | 真实检查后的停止/页面收敛已核；注入瞬态、精确时刻及严格时限未证，不是OEM复现 |
| H3 正常关闭 | 通过 | 逐源结果、原句柄退出、只去owner、记录/序号保留；FD/global锁限制如上 |
| H4 孤立owner释放 | 通过 | 活租约拒绝、失败形成孤立、另行窄释放、提示保持、重复target_absent |
| H5 不自启/恢复门 | 通过 | 刷新返回不自启、非空恢复拒绝；W0导航与用户动作分开记录 |
| H6 正式包恢复 | 通过 | E1完整hash、冷启动、Activity无、BLE前台6157、持久元数据保持 |

**阶段结论：不关闭Goal。** 功能缺口修复、193/193组合验证与上述设备功能已取得各自证据，但调试端点失效导致H1/H2连续时序缺证；后续须先恢复稳定且不改变产品行为的只读时间见证，再对同一候选补验。若需要更换APK，按新hash重新定义设备证据，不继承本候选通过项。此次手机操作结束，正式包已恢复，无commit/push。

## 2026-09-28 01:22 自动补验最终收口

9A099611同包自动补验：H2受控通知失证前台同步保守上界515ms，返页核对419ms，经独审接受；397条样本/0读取未知、346条后续未见回弹仅证明采样范围。H1通知自身停止功能成立，但停止发生在有效窗口外，严格3秒仍缺证；立即checking及完整连续时序仍待，Goal未完成。01:21已恢复完整hash一致的E1正式包，稳定后BLE前台6157/Bluetooth1、Activity诊断服务无，13项持久元数据保持；原gate FD在安装前已释放，本轮转发已清理。23项源码pin一致，本轮无产品代码改动、无commit/push。本轮完整计算、失败窗口及收尾收据见[自动时序补验](AUTOMATED_TIMING_GATE.md)。此前真人功能Gate继续有效，自动操作单独标记。
