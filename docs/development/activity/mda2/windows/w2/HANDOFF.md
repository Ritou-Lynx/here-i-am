# MDA-2 W2 — Windows 受保护实盘队列交接

**候选：`W2-protected-disk-r1-20260912`；代码已冻结，未提交，待 W0 审查。**

task `01a09504-2fbf-7963-82a5-d9940f635d70` / local；Worktree `C:/Users/ExampleUser/.codex/worktrees/4dd2/memex`；分支 `codex/mda2-w2-20260912`。基线与最终 HEAD 均为 `1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`。

## 交付

新增仅在 `tools/mda2_windows_queue/**` 与本目录。真实 Windows DPAPI/ACL/规范路径/独占锁保护的 SQLite AES-GCM 实盘队列；独立 broker、原生年龄提供者与队列子进程；原子 sequence/lineage/bytes/age/attempt/receipt/freeze；独立清理；跨进程故障与回滚测试。默认无 transport；测试只把自建合成事件直接交给内存 Core，零真实 HTTP/OS 活动钩子。

- 使用入口和适配器说明：[README](../../../../../../tools/mda2_windows_queue/README.md)。
- 可重现全套：`node tools/mda2_windows_queue/fixtures/run_tests.mjs`；Windows 现有 Node v24.14.1；必要时通过现有审批机制允许此限定测试访问 Windows 原生保护能力。
- 最终 **35/35 场景通过、exit 0**，含 **14 个直接 broker 伪造投影拒绝**。覆盖分配/attempt/receipt 崩溃屏障、Core 已收丢回执、重复原字节/原 receipt、freeze/owner 交错、旧 snapshot、坏密钥/篡改/版本/绑定/ACL/reparse/硬链接、原采集年龄、TTL/raw 等号、容量、未知/终态、独立清理及实际 broker/helper 死亡。
- [RESULT.json](RESULT.json) 保存本次场景与进程事实；[SOURCE_MANIFEST.json](SOURCE_MANIFEST.json) 绑定 9 份本包执行源和 2 份只读 Core 源；[PROVENANCE.md](PROVENANCE.md) 记录 Node/输入/证据 hash 与 W0 P2 修正；[RECOVERY_MATRIX.md](RECOVERY_MATRIX.md) 给出允许动作。
- `W2.patch` 是所有新源码与交付正文的最小新增 diff，排除 patch 自身和其外层 `VERIFICATION.json`；后者记录完整文件指纹、patch hash 和范围/索引检查。原工作树没有 stage/commit，补丁反向 check 只检查、不应用。

## 真实支持范围

同一独立 broker 和年龄 provider 存活时，queue 子进程退出/终止后可恢复。broker 保持不可随队列 snapshot 回滚的 version/sequence/fence 权威；原生 GetTickCount64 提供本 epoch 年龄。恢复原 bytes，先持久化新 attempt，真实内存 Core 返回 duplicate 并沿用原 receipt。禁止只凭 DPAPI、mtime、自洽 snapshot、重启 uptime 或摘要猜新鲜度。

权威预留而磁盘未提交的窗口，保留外部 sequence/revision floor，逻辑清理并永久冻结 `authority_reservation_gap`。receipt 事务内中断也采用这条保守规则；本包没有推测式撤销预留或自动补号。

原采集 proof 绑定规范观测、lineage、epoch、原年龄与 nonce；新行及后续行在 broker 独立核对，不允许 worker 延长期限/换摘要/序号/复活。所有出口同时受 owner/fence、单次 attempt、不可逆 freeze、raw horizon 和存活的保护句柄约束。

## 未实现/不能据此放行

1. **跨 broker/cold boot/整可信域回滚不恢复旧 lineage**。实际终止 broker 时 queue 也退出，raw 曾保留到新 broker 拒绝式 reopen 才清理；无即时删除保证。新配对仍由另行授权流程负责。
2. **不支持物理硬删除 Gate**。期限后当前 SQLite rows 没有 bytes/digest/receipt/每事件时间；broker 年龄丢失时每事件 proof/dispatch 时间缓存也清空。但实际负例证明历史密文仍可解密。WAL/备份/JS/IPC/pagefile/休眠/SSD 历史未获不可恢复销毁证明；客户端采集起算与 Core received_at 起算仍是不同口径。
3. 无真实 WTS/LastInput/窗口/键盘采集，无生产配对/秘密配置，无异步或真实网络 sender，无系统后台调度/自启/卸载保障，无 Android 适配或手机 UI。实际休眠、关机、断电与磁盘损坏未测试；所有 TTL/容量/轮询值是 fixture/适配默认值，不是生产测量 SLO。
4. 不承诺对抗恶意同账户进程、管理员或整个 OS/VM 回滚。保护/完整性失败时停止；无法安全解密或持有句柄时不越权清理。

本轮没有共享 Core/validator/根依赖改动，无 stage、commit、集成、push、现役切换、设备安装、真实数据/凭据访问、计划任务修改或外部发送。未修改全局 DEVLOG/状态页；未派生任务或子 Agent。当前工作区 bootstrap 为 ephemeral，未写跨项目 closeout。

下一步仅由 W0 审查本冻结候选与复跑证据；源码停止修改，等待具体返修意见。生产采集/sender/Android/硬删除能力需要后续独立范围与授权，本包不替 W0 接受整个 MDA-2。
