# W2 Windows 受保护实盘队列

独立工作包；不接现役、不采集 OS 活动、不配生产账户、不运行 HTTP。`WindowsQueueBroker` 是可运行的最小独立权威提供者，`WindowsDurableQueue` 在其启动的另一个进程中读写真正的 Windows 磁盘。默认 transport 为空，只有测试宿主注入真实内存 Core 的直接调用。

Windows、现有 Node v24.14.1，无新增依赖，从仓库根执行：

```powershell
node tools/mda2_windows_queue/fixtures/run_tests.mjs
```

测试在本包 `.scratch/test-*` 下创建随机资源，成功后删除本轮 scratch，并写入 `docs/development/activity/mda2/windows/w2/RESULT.json`。第二参数仅用于按场景名筛选故障定位；有 filter 的结果不是全套通过。Windows 沙箱可能禁止祖先目录原生句柄或 DPAPI；应由现有审批机制审查此限定测试，不能跳过保护检查。所有 PowerShell 辅助进程隐藏运行；秘密、原字节和绑定经继承的私有管道传递，不进入命令行。

## 适配边界

- `broker.mjs`：可信控制器显式 `registerFresh(binding, newRoot)`，只接受已经由授权配对流程产生的新绑定；随后 `start(...)`。这个调用不进行配对，也没有从旧文件自动注册的路径。默认最多 8 个存活 lineage，测试值并非生产配额。
- `authority.mjs`：独立 broker 内存中的 epoch、revision/sequence floor、owner fence、预留/提交状态、采集 proof 和送达 proof。没有快照导入/重建 epoch 方法。`WindowsAgeClock` 使用独立辅助进程直接调用 Win32 `GetTickCount64`，不使用重启后计零的 queue uptime。
- `capture()` 只供可信采集适配器在采集时调用。queue worker 的 IPC 允许集没有 capture 或注册操作。签名绑定原观测、原采集坐标、epoch、lineage、nonce。生产原生采集/回调缓冲尚未提供；fixture 中只有 broker 自造的严格粗信号。
- `queue.mjs` / `store.mjs`：先验证原采集年龄，再物化现有 validator 的规范事件；不可变原字节以 AES-256-GCM 加密，单行 SQLite 事务同时保存 next/revision/fence、lineage、年龄、attempt、receipt 和冻结。所有发送只能经过 broker 最后复核。单 source、单事件、单在途；每来源独立配对、队列和序号。
- `windows_guard.ps1`：随机队列密钥用 DPAPI CurrentUser 保护，和密文队列分别放在 `keys/` 与 `queue/`。AAD/DPAPI entropy 绑定规范根路径和配置摘要。仅当前用户与 SYSTEM 的 ACL、原生规范路径、reparse、硬链接和独占 owner 文件锁均校验；自建目录持有禁止删除共享的句柄。应用配置秘密不落队列。
- 内置独立 maintenance 定时执行清理；即使没有发送/新采集，也可以在 queue owner 退出后启动仅清理的 owner。它不是系统计划任务，不承诺 Windows 强停/休眠/关机时的准点执行。

## 恢复与拒绝

独立权威预留 proposal 后才写 SQLite；磁盘提交后再确认权威。磁盘与权威匹配的新 proposal 可以恢复；权威已经预留而磁盘仍是旧状态时，保留预留的高水位，清理并冻结为 `authority_reservation_gap`。此版本对这种窗口保守牺牲可用性，即使那是 receipt 事务且 Core 可能已经接受，也不推测可以继续。

broker 独立重新物化签名观测，验证新行的 sequence、digest、原年龄、rawDeadline 和 TTL；后续 prepare 保持这些字段不可变，并拒绝无 capture 新增、提前删除、复活、非法 attempt/receipt 转移。真实 Core receipt 还由 broker 的私有签名绑定原 owner/attempt。旧 owner 只有在实际 child exit 后失效，不能按超时抢占；文件锁另行阻止第二 OS owner。

TTL 等号可接受；仅 never_sent 在 TTL 严格过期时本地终结并冻结。attempted_unknown 可在原 raw horizon 内原字节重试；raw 年龄等号即删除每事件明细。冻结后的原在途回执只能结算自身；迟于 raw horizon 的回执不能复活条目。未知/畸形响应不当作成功，明确终态才冻结并提前去除 raw。

## 不支持的范围

仅证明独立 broker/年龄提供者存活的队列子进程恢复。broker 死亡、新 broker/cold boot、丢失年龄 epoch、整可信域一起回滚、恶意同账户进程/管理员、实际断电和磁盘控制器持久性都没有生产恢复承诺。DPAPI 可解密和自洽旧库均不能替代新鲜度权威。旧 lineage 无证明时停止出口；能安全解密并持有保护句柄时仅最小化本地状态，不自动配对。实际终止 broker 时队列子进程也退出，磁盘 raw 可能保留到拒绝式 reopen 才清理；disconnect 回调只是尽力清理，不是终止保证。

清理证明到 SQLite 当前逻辑视图和本包显式可控缓冲。AES 密文历史、WAL/备份、JS/IPC/GC 内存、pagefile、休眠文件、SSD 历史扇区不具备已验证的物理硬删除。测试明确验证旧密文在期限后仍可用原 DPAPI 队列密钥解密。因此本包不能用于声称“到点所有 raw 不可恢复”的生产 Gate。

没有 WTS/GetLastInputInfo/前台窗口/键盘钩子、真实 sender、异步网络生命周期、外部恢复服务、自启/后台系统调度、Android 移植、手机 UI 或真实部署。后续接口需要 W0 单独接包；本包不改共享 Core、validator、wire、schema 或配置权限。

详细交付见 [HANDOFF](../../docs/development/activity/mda2/windows/w2/HANDOFF.md)。
