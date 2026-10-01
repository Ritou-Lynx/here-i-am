# A3F-R3 W0 本地控制合同 v1

2026-09-27；已确认 Goal 的实现合同。固定源基线 `b2adc44b7c04983a931c39695b81491cd295084b`。仅本地 Debug Activity 控制面，不改变 MDA wire / 持久 schema。N、D、U 以本文件为共同接口；新增字段/码需主窗协调双方，不能静默漂移。

## 1. 状态、终态和交付关联

`getObservationStatus`（无参数）与 native `onObservationStatus` 返回同一 exact-key map：

| 字段 | 类型/含义 |
|---|---|
| version | 整数 `1` |
| session_id | 非空进程随机关联值；仅内部 |
| observation_id | 本次启动 token；无已知代的初态为空串 |
| revision | 非负、单调、安全整数；同 session 内排序 |
| state | `unknown / starting / running / stopping / stopped` |
| enabled | bool；只有 running 可为 true |
| reason | 下述固定码白名单 |

初态 `unknown / enabled=false / observation_id='' / activity_source_unavailable`。同 session/revision 回退拒绝，同 revision 内容不一致拒绝；新 session 不继承旧终态权威。状态核对无 Usage query/key provision/sequence/start 等采集副作用。opaque 关联值不得进入 UI、证据导出或 audit 文本。

固定 reason 白名单：`activity_source_unavailable`、`activity_starting`、`ready`、`collector_disabled`、`user_stop`、`notification_stop`、`service_destroyed`、`foreground_start_not_allowed`、`foreground_start_failed`、`foreground_state_lost`、`notification_not_visible`、`appops_watcher_unavailable`、`boot_marker_unavailable`、`boot_marker_changed`、`owner_fence_mismatch`、`service_instance_mismatch`、`usage_permission_denied`、`usage_permission_revoked`、`activity_opt_in_required`、`debug_diagnostic_required`、`activity_authority_invalid`、`epoch_state_corrupt`、`epoch_state_write_failed`、`device_locked`、`usage_events_expired`、`usage_query_failed`、`usage_query_null`、`observation_stop_failed`。运行中的控制状态不以查询结果覆盖其生命周期；更多 query readiness 仍留在既有 batch，不混入控制 reason。未知原因只归约为固定失败，不透传异常正文。

`stopObservation({session_id, observation_id})` 返回 exact `{outcome, status}`，outcome 为 `stopped / target_changed / unknown / failed`；status 为上表。仅目标相同、status=stopped、enabled=false、outcome=stopped 证明本代原生终止。旧目标不得关闭 successor。并发/重复同代 stop 可以返回同一终态；无身份 `deactivate` 不能绕过此门，只能使用当前 handler 已拥有的目标，否则拒绝。

终态必须封闭本代交付、使旧回调失效，并取得 query executor drain barrier 与 service destroy/清理完成证据；不能把请求已发送或 shutdownNow 当完成。未 claim 的启动可在证明零采集/占位取消后结束。cleanup/时间界限失证返回 unknown/failed，不启动后继绕过未知状态。

`activateObservation` 参数为既有 activation 字段加 `lease_tokens: {android_usage_events: token, android_screen_state: token}`（实际 source 字符串以 AndroidActivitySource.wireValue 两常量为准），须两个租约都当前有效且无恢复 permit，才复用 R2 启动链。旧 `activate` 返回 `observation_control_required`，不能成为无租约旁路。

activation 回执保留既有 readiness 映射，加 `observation_status`。该字段只代表本请求所属状态；若请求没有获得启动身份，则为 null 且 enabled=false，不能用别人的当前状态让调用者误绑定。新 production MethodChannel 必须使用新控制合同；旧 fake 能力只供本地合成测试兼容，不能成为真实平台降级路径。

上述 activation 的 exact keys 为七个：`enabled / readiness / usage_source / screen_source / usage_permission / counters / observation_status`，与 N 的真实 Channel 一致；不得用三键简化替身证明跨层接合。保留字段也须按两 source、既有 permission 与非负整数计数白名单验证。新状态字段为 null 的合法失败回执不以请求本身 enabled=true 判坏，只有回执 enabled=true 而无本次身份才拒绝。

query/onBatch 结果加 `observation_status`，绑定产生该结果的原代，而不是回调送达时的 successor；D 在接受事件之前比较本代与失活 generation，旧 query/batch/ack 不能写 ready 或新 sequence。原生 delivery epoch/id 的确认门继续保留。

## 2. 进程租约与恢复 permit

Dart 3.12.0 本机 SDK 已核实。官方 [lockSync 契约](https://api.dart.dev/dart-io/RandomAccessFile/lockSync.html) 说明 Linux advisory lock 为进程级；[3.12.0 Linux/Android 实现](https://raw.githubusercontent.com/dart-lang/sdk/3.12.0/runtime/bin/file_linux.cc) 使用 F_SETLK/F_SETLKW。因此同进程其他 FD 的操作可能破坏旧锁，Windows 的同进程测试不构成 Android 证明。

N 提供静态、跨 Flutter engine 共用的 Activity 专用两 source broker。所有受支持 Android store create/open/reset/释放路径必须先取进程租约，才可打开 owner.gate；租约持有至文件句柄已确认关闭。OS gate 仍负责跨进程互斥。不得用 isolate-local static set 代替原生门；不得在 engine detach 时无条件释放。

| 方法 | exact 参数 | exact 成功结果 |
|---|---|---|
| acquireDiagnosticOutboxLease | `{source, permit_token}`；普通 writer/reset 传空 permit | `{source, lease_token}` |
| releaseDiagnosticOutboxLease | `{source, lease_token}` | `{released: bool}`；旧 token 不释放后继 |
| beginDiagnosticOwnerRelease | `{session_id, observation_id}` | `{permit_token, status}` |
| endDiagnosticOwnerRelease | `{permit_token}` | `{released: bool}` |

begin 仅允许精确 stopped 目标、无 startup、两 source 都无租约，建立单个恢复 permit。permit 存活期间拒绝 activation、其他 begin 及空 permit acquire；持同 permit 才可按 usage→screen 顺序取租约。end 要求相关租约已全部释放且 token 匹配。无自动过期/超时清除 permit；失败保留可重试身份，不清掉可能仍持有文件的 owner。原生只接受两个固定 source，不接受任意路径。

为处理“原生释放成功、回执丢失”的显式重试，broker 仅在本进程保存每 source 最近已成功释放 token 和最近已结束 permit。相同已证实 token 且当前无后继 lease/permit 才可重复回 true；获取后继使旧成功记录失效，旧 token 永远不移除后继。end 仍要求所有 lease 已释放。该成功记录不授权未知 acquire/begin 的恢复，不增加 TTL 或自动清理。

D 拥有新纯 Dart `activity_outbox_process_lease.dart`，不依赖 store/platform：

```dart
abstract interface class ActivityOutboxProcessLease {
  String get source;
  bool get isHeld;
  bool get hasFileClaim;
  void claimFileAccess(Object claimant, String source);
  void verifyFileAccess(Object claimant, String source);
  void releaseFileAccess(Object claimant);
}
```

真实 lease 由 platform 私有实现持 native token；同一 lease 不能重复认领多个 store/FD。native release 前须无 file claim，native 确认后才置 isHeld=false。对象不跨 isolate 传递/复制；每个参与者经同一 native broker 取得自己的租约，静态检查所有 Android 调用点，不能只凭 Dart 对象自报 token 代替原生排他。测试替身不进入实际 MethodChannel 路径。

U 为 FileStore create/open 添加可选 processLease；Android 上缺失即拒绝，其他平台可选，但传入时必须执行验证。create/open/窄释放在 gate FD 打开前 claim；FD 确认关闭后才 releaseFileAccess；不确定时保留 claim。既有 reset 同样先取得两 source broker 租约，不能通过 `_proveGateIsFree` 打开竞争 FD。

## 3. 无损释放与 D/U 接点

U 拥有 FileStore 的 `ActivityOutboxReleaseTarget`：内部不可变精确根/source/binding/owner/anchor 和 state/journal 字节关联，不出 UI/日志。提出的 API：

- `inspectOwnReleaseTarget()`：当前 store 在自己门内冻结目标，供 close 失败后使用。
- `ownerLeaseReleased` getter：只有 OS 文件句柄释放已证实时为 true。
- `inspectReleaseTarget({required Directory directory, required List<int> integrityKey, required SyntheticProbeBinding binding})` 静态只读路径，不打开 gate；`releaseExactOwner({required Directory directory, required List<int> integrityKey, required ActivityOutboxReleaseTarget target, required ActivityOutboxProcessLease processLease, ActivityOutboxRecoveryCriticalSectionHook? recoveryCriticalSectionHook})` 返回 `ActivityOutboxOwnerReleaseOutcome.released / targetAbsent`。不得经过 open、journal 恢复或建立新 owner；journal 存在时首版固定拒绝并保留原字节。

D close 前冻结目标；逐 source 返回结果。正常 close 成功后释放 native lease。删除失败但 gate 已确认关闭且 claim 已放时，可以释放 native lease，保留原冻结目标与失败结果；未知关闭保留对象/lease。不能对已 closed/poisoned 对象再 close 假装可重试。U 后续明确操作在 native terminal permit、两 source process lease 和 OS gate 内重新核对目标，仅删除 owner，保留 state/anchor/journal/sequence/key；successor 变化拒绝，不重新取“最新目标”自动继续。

D→U 接口：collector `addStatusListener/removeStatusListener`、`synchronizeObservationStatus()`、`stop()`；stop result 含 nativeOutcome/nativeStatus/sourceReleases/completed，各 source 含 closeCode、ownerLeaseReleased、processLeaseHeld、fileClaimHeld、retryable。`releaseTargets` 只内部使用；U 获窄释放结果后才可 `confirmReleasedOwner(source,target)` 退休同一已冻结且无文件/进程租约的失败对象，不读“最新 owner”替换目标。即使 store 引用已清除，process lease 释放失败也必须保留并可显式重试，不能因 store==null 漏掉。

`status.canQuery` 默认 false，只在本代仍接受且 owned/current 均精确 running 时为 true；页面可据此允许用户显式查询重核权限，不由 running 自动恢复 ready。`status.canRetireWithoutObservation` / `stopResult.noNativeAttempt` 只表达完整初始化已结束且从未进入原生 attempt 的证据；前者另须两个 source 的 close/FD/claim/process lease 都已证实释放。尚未完成的 acquire/activation 不授予退休权，空结果集合不算全部释放；nativeOutcome/status 保持真实值，不伪造 stopped。

已知 lease/permit token 的释放回执超时后，保留原身份并允许下一次显式操作幂等重试；晚回执只能确认原对象，不清后继身份。未知 token 的 begin/acquire 必须保留原 Future 与迟到身份，不能超时丢弃后重发。UI 等待有界结束并呈现 unknown/部分失败，资源证明分别保留；不以 busy 永久锁住所有恢复动作。

新增 store 固定码：`owner_release_target_changed`、`owner_release_journal_present`、`owner_release_path_invalid`、`owner_release_failed`。N 补充拥有路径仅限 `AndroidActivitySignalCollector.kt` 内 `DynamicScreenSignalReceiver.stop()` 的注销结果确认：失败保留 registered 并阻止发布 stopped，其他 collector 逻辑不扩大。

正常关闭失败仍保留已持有资源；service stopped、owner removed、file lease closed、process lease released 分别表达。两 source 部分成功必须可见。任何资源或许可释放结果不明，不能报全完成。

## 4. H2 / H4 与页面收敛

- H2：`debugInvalidateObservationNotification({session_id, observation_id})` 为明确 Debug/v3-only、当前运行代限定的操作，成功返回 `{accepted: true}`。给 Activity 自己的通知可见性证据一次失证注入，然后经既有 queryEvidence/epoch/continuity 函数自然 fail closed；不得直接 stop 或伪造终态。标注“注入通知可见性失证”，不声称物理通知移除或三星 OEM 根因复现。状态读取不会触发此故障。
- H4：在同一已确认终止代，给指定 source 的 close 显式注入一次 owner 删除失败；原 owner 字节保留、OS FD 与 process lease 的释放分别取得证据，形成可验证残留。用户另点释放后使用冻结目标。另验 service 已停但 store 活租约仍在时，恢复在打开第二个 gate FD 前拒绝。禁止全包 kill 或伪造冷启动终态。
- UI 同步状态 checking/unknown 与 native reason 分开；前台终止确认后≤3秒退出ready，resume/刷新立即checking，≤3秒无有效证明即unknown。状态监听只降级、不自动关闭持久owner或采集；资源释放由显式动作触发。
- H4 注入由 U 的 Debug诊断调用与 FileStore 的既有删除测试 seam 承载；D 只提供必要的明确测试注入参数/collector操作，不在正常路径默认开启。

U 只读 `verifyReleaseTarget({directory, integrityKey, target}) -> bool` 可供双 source 全量预检，复用窄释放的字节/签名校验，不打开 gate 或写文件；实际删除仍在 gate 内复核。FileStore `create/open` 可选 `beforeOwnerDeleteForTesting: void Function()?`（默认 null），在核对自己 owner 后、删除前调用，失败沿既有 finally 真实释放句柄。D `debugFailNextOwnerDelete(source)` 只在 Debug、已知自身代且持有该 source store 时设置一次性注入；U 显式 H4 按钮调用，正常流程不启用。

UI 本地固定码另为 `diagnostic_status_checking`、`diagnostic_status_unknown`、`owner_released`、`target_absent`、`diagnostic_owner_release_complete`、`diagnostic_owner_release_partial`、`diagnostic_notification_loss_injected`。它们只投影同步、逐源资源结果或故障已注入，不加入原生 reason，不替代 native terminal / FD / process lease 各自的证明；故障已注入不等于服务已停。

固定控制错误码：`observation_control_required`、`observation_status_invalid`、`observation_target_changed`、`observation_stop_failed`、`diagnostic_outbox_lease_held`、`diagnostic_outbox_lease_invalid`、`diagnostic_owner_release_refused`、`diagnostic_owner_release_active`；store 另沿用现有固定错误与 U 精确新增白名单。任何新增码先同步，未知错误只映射固定失败，不回传异常正文。

## 5. 验证与限制

须补纯原生多handler/租约竞争与失效测试、Dart严格解析和代际测试、store真实锁与不变字节测试、候选Android上的同进程竞争验证；这些层次分别报告。新 native broker 只是同进程排他，不代替 OS 跨进程锁或原生终态证明。没有真实第二engine/第二进程现场时如实标限制，不把mock当设备证据。

本合同允许为已确认安全目标作上述最小控制面实现调整；无新后台采集、持久 schema、BLE 或生产入口范围。主窗串行维护本文件和共享验证脚本，worker 不自行改另一包路径。


## 6. 设备返修：统一 Dart 规范目录

真实 getOutboxRoot 的 wire 字段不变；Dart 桥接在返回模型前，以本运行时解析可信 appData/no_backup 父边界并拼固定 mda2_activity，既有根仍严格反链接与目标等值。不同系统 spelling 不形成不同 owner 身份；规范根改变固定拒绝。此步骤仅读取目录元数据，不创建根/lease/key/sequence，不启动采集。具体算法、反例及本机/真人证明边界见 [路径窄修复](PATH_CANONICALIZATION_FIX.md)。

## 7. 设备返修：显式资源动作结果独立显示

原生生命周期状态与最近显式资源动作结果分别投影。普通stop、孤立owner释放、显式诊断清理的结果只使用既有公开固定码；自动状态订阅、前台定时核对、手动刷新和resume不得抹除动作的拒绝、失败、部分完成或未知回执。下一显式资源动作更新自己的结果，新一次已接受的开始请求清除旧代结果。繁忙时未接受的动作不能覆盖正在执行动作的结果。

动作结果是UI-only只读展示，不加入原生reason或共享证据schema，不授权start/query/删除，不作为FD、process lease或原生终态的替代证明。异步动作以本次局部结果记录，不能因finally等待期间的自动同步错误宣称成功；旧回执不能覆盖新代/后继动作。屏幕以中文动作名和结果说明显示，可附公开诊断码；既有逐source关闭/释放详情保持。

返修须取得旧版前台tick后提示消失的RED，并验证前台下一轮、手动刷新、后台返回、未知回执及后续成功/新代重置。手机新APK需重新验收，旧候选H0及安全拒绝证据不能替代该新显示行为的真人证明。
