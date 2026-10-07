# D4 schema6 离线恢复适配器（2026-10-06）

- 基线：`90f23ce1d38628901e25b421d8f0f21c084f093b`；只修改 `recovery_adapter.mjs`、其专项测试与独立 recovery 合成夹具。本文件由 worker 持有，主窗统一整合全局状态。
- 固定依赖 `lifecycle/offline_lease.mjs` 的 `assertOfflineLease`；拒绝 JSON writersStopped、普通回调与未品牌化对象。每个迁移阶段与 custody 写入前后重复核验能力；真实 OS 锁、Job、旧写入者清停的真实性由固定生命周期模块承担。
- API：`migrateToSchema6` / `rollbackEmptySchema6` / `sealClosedRecovery` / `verifyCanonicalRestart`，均同步；参数为 `databasePath,supervisorLease,custodyDirectory,custodyKey`，迁移另需 `backupKey,backupDirectory`，schema4 另需 `initialBackup:{artifactPath,artifactSha256}`。
- `assertOfflineLease` 返回 `databasePath,checkedAt,allCoreWritersStopped,cleanCloseReceipt`；后者为 `receiptId,databasePath,nodeId,databaseSha256,custodySha256`。hash pin 属于独立生命周期回执，不能从待验证数据库或可替换的旧 custody 自动推导。seal 后必须由 supervisor 将其返回 hash 写入独立 durable receipt。
- schema4 仅接受完全不存在 activity/domain 的原址数据库；先固定调用完整 runtime bundle 验证器并核对当前摘要，再使用既有 `migrateActivitySchema`，在事务提交前复核锁与旧业务摘要。首次 activity genesis 在此之后独立封存；它不能为已有 schema5/6 历史补签授权。
- schema5/6 必须已有独立 hash pin 的认证 custody。custody 包含原路径、node、完整数据库摘要、schema、真实 clean receipt ID 与 activity floor，以独立 32 字节 HMAC 密钥认证。与数据库目录及备份目录不可互相嵌套，密钥不能复用 cursor secret 或 backup key。
- `migrateDomainSchema` / `rollbackEmptyDomainSchema` 收到由真实 lease 派生的同步 offlineProof、独立 backupKey 与已验证 floor。库既有 AES-GCM 备份/回读验证、非空新域拒绝回滚保持不变。不存在整库覆盖、跨路径激活或旧数据库恢复路径。
- 原址启动先调用 `verifyCanonicalRestart`，通过后普通 `createICoreServer` 不传 `activityRecoveryFloor`；库的 `backup_activation_unsupported` 不修改。floor 参数不是绕过备份拒绝的开关。
- 分阶段失败保持 fail-closed：若4→5已提交而后续丢锁/写custody失败，不宣称6完成，不自动覆盖恢复；保留加密备份与已写的独立工件，需 supervisor 重新取得可信恢复证据。
- 测试只使用临时合成根。独立 fixture 显式替换测试实例的单一 OS lease import；生产模块没有测试开关/可注入验真器。实际迁移、SQLite、加密、摘要、floor/role校验与HTTP关闭重开不替换。
- 独立 custody 当前 head 追加 generation/previous head SHA、floor SHA、receipt/node/path 认证链；当前 head 与数据库/state 分开，不支持 restore CLI。旧 DB + 旧生命周期回执 + 旧 floor 一起回退仍被拒绝。wx 排他锁贯穿操作，原子替换/flush/回读当前 head；缺失、篡改、并发、未完成 pending 均不自动修复。
- 首次 seal 仅允许真实 supervisor 的 empty_provision 且数据库业务/活动为空，或内部已验证 schema4 迁移 genesis。已有5/6只能延续外部当前 head，不能现场自捕获补签。关闭后新 receiptId 可更新，但必须携带上一轮 custody pin；迁移返回新pin后再关闭seal时先更新该pin。
- 验证结果：恢复专项 **23/23 passed，0 skip**；包括真实9role加密 bundle 的4→5→6链、已存在活动历史的5→6、72条replay/grants/原业务摘要、原址HTTP关闭重开、错误floor/node/path/key/head、活动claim、备份角色、全部sidecars、提交前丢锁、备份中断、迁移后写域禁止回滚、旧DB/receipt/floor共同回退、第二个真实Node进程持custody锁，以及未改动生产adapter拒绝JSON与合成capability。既有 domain_migrate 回归 **22/22 passed，0 skip**；合计45项通过。语法检查通过。
- 测试边界：只有OS supervisor能力为显式synthetic WeakMap替身，23项通过**不证明**Windows Job/旧writer清停/生产入口跨模块链。主窗须另跑该组合。首轮沙箱路径父目录检查EPERM后，以已授权合成测试提权重跑；没有放宽路径检查。
- 无现役数据库、配置、进程、手机操作；无 push/PR/merge。worker 提交仅自身路径，使用本次已有 `SKIP_PROJECT_STATE=1` 例外并在 finally 恢复；主窗整合提交需正常状态检查。
