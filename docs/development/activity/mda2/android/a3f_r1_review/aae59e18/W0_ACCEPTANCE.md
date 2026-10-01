# A3F-R1 W0 独立源码验收

2026-09-17；决定：接受 `aae59e18f142e0854c033a0b2e31c65bc3fd0e88` 的19路径本地源码候选，parent为 `6b7546715acea81948874809daf67a32c208b238`。本页不表示 APK、部署或真人 Gate 已通过。

- worker提交/工作树真实核对，clean；Git archive独立副本的19路径逐提交blob绑定并记录SHA-256。Windows换行转换单独核对，测试镜像与独立源码逐字一致。
- W0独立 Android **31/31**，真实编译+22任务执行、2m31s；A3 **25/25**、A3-D **15/15**；对应source/test analyze、mirror均通过。
- W0自有 `W0LatePublicationContractTest` **2/2**：最初EMPTY后迟到反例保留原断言；另测无关raw后前移UI cursor仍可找到同ms的15/16/18，每类一次、ACK后重扫不重复。Gradle exit0、1m2s，不复用worker断言替代。
- 相邻 A1 **56/56**、A2 **31/31**；source/test analyze、mirror通过。实际Dart生成wire/Core内存演练 **20/20**、隐私负例7项、duplicate/TTL边界通过；没有生产Core或网络收集。
- R1/A3/A3-D/A3-F四项最终commit静态守门、保护路径零diff、隐私与diff检查通过。Manifest、Gradle、pubspec/lock、共享outbox、Core、生产入口、BLE/check-in及全局状态未由worker修改。

## 接受的行为与限制

授权epoch与发布完整性分开；重扫仍有效的300000ms尾部，不以EMPTY或无关raw推进不可回访水位。native有界ledger、单在途batch和epoch绑定逐项ACK，仅在Dart durable成功/已确认duplicate/显式终止拒收后退休。storage/bridge/ACK失败保留重试，原occurrence和TTL不变。

较早于durable顺序边界的晚发布事件明确计作late_out_of_order；超龄、overflow、断连、epoch遗弃等遗漏本地累计可见，fresh不清零。有效同批成员先入库，再标记本地delivery gap；不生成now时间错误事件阻挡本批。诊断固定 `publication_completeness=unknown`，没有系统无损watermark声明。

真正满容量没有原地释放API，保留retry到原TTL后显式超龄遗漏；瞬时拒写解除专项仅证明可解除故障后的恢复，不能替代满容量恢复。原生内存pending不承诺进程死亡尾部无损，新epoch不回填死亡/撤销区间。当前仍为synthetic local diagnostic，生产接线未启用。

## 后续 Gate

按19路径选择性本地集成，独立核对主线并行dirty/index保护；正式App构建与源集检查另记。构建前critical须3/3，从干净已接受提交构建新唯一hereIAmV3诊断APK，重新核对签名/hash和原包回退。

旧B34B设备三事件Gate为未完成：23:21屏幕occurrence在23:34人工query时已超5分钟TTL，缺失设备原因未单独证明；旧A3-D2 FAIL不提升。原正式APK E1B已恢复。本轮新APK尚未构建/安装。

真人在完整授权epoch中锁屏约10秒、解锁立刻query/refresh，交付短于5分钟；分别核对原始occurrence、native拒收与durable结果，再跑持续通知/停止、权限edge、死亡/重启及隔离/耗电矩阵。缺项保留unknown，不能用固定等待伪造完整性。

证据：worker [HANDOFF](../../a3f_r1/HANDOFF.md)；W0冻结副本 `tmp/a3f-r1-w0-review-aae59e18f142` 的 `W0_ARCHIVE_BINDING.json` 与专项XML；自有反例 `tmp/W0LatePublicationContractTest.kt`。无push/publish。
