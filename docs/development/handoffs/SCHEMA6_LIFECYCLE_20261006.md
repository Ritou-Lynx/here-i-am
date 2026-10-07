# Schema6 固定候选生命周期交接（2026-10-06）

基线：`90f23ce1d38628901e25b421d8f0f21c084f093b`。本工作包仅拥有 `tools/i_core/release_schema6/lifecycle/` 和本交接；package/CLI、恢复适配器、完整备份及全局状态由主窗集成。未运行现役任务、旧库、Remote MCP 或手机操作。

## 真实入口及边界

- `lifecycle/start_schema6.ps1 -ManifestSha256 <外锚> -Start -StateDirectory <原址> -ControlDirectory <新空目录> -ConfigurationFile <受保护配置>` 启动长期 loopback 服务。端口默认 0；不存在服务运行时限。
- 所有源码、Node、manifest、完整库存先校验；Node 固定 24.14.1 及包内既定 SHA256。拒绝 inherited `I_CORE_*`、`NODE_*` 及列明的 TLS/OpenSSL 配置。固定 `PATHEXT=.EXE`；首次 Node 调用清空退出码并要求实际 0。
- `schema6-config-v1` 明确绑定 manifest、原数据库路径、node_id、owner SID；仅 `legacy_b3`、jobs/activity=false、owner_managed。grant/replay 为外部固定文件及摘要；配置与外部文件在整个父进程生命周期保持只读句柄。
- recovery/backup key 仅接受各独立目录内 `runtime-recovery.dpapi` / `runtime-backup.dpapi`。固定包 key helper 以当前用户 DPAPI 解密，原始 32 字节 stdout 只捕获于内存；无明文密钥临时文件、argv 或环境传输。relay 保持关闭，不能据此声称现役邮件功能兼容。
- 普通重启要求 schema6、live role、无残留活动 claim/SQLite sidecar、原 canonical 路径与 node、同包/同配置、上次 clean-close 的数据库与完整状态树摘要一致，并由恢复适配器检查独立 custody 当前头。旧 R3/旧 v4 回执不被接受。
- `-InitializeEmpty` 只用于全空新状态目录：真实 Core 初始化 schema5，关闭并封存空库 genesis，使用真实离线迁移到6，再校验并监听。首批写入之前已有独立 floor；没有旧库接管含义。此入口必需 backup_directory/backup_key_path。配置 node_id=new 的后续使用只能由原已绑定的 provisioned_empty 清停谱系证明。
- `-OfflineOperation verify|rollback|migrate` 使用同一真实 Job/锁/guardian。它能验证既有原址、空 schema6→5 回退及该谱系5→6迁回；不接受无 supervisor 谱系的旧 v4 作为首次迁入。

## 托管和清停证明

`owned_job.ps1` 从 R3 的已审计实现派生，使用独立 `ICoreSchema6-` Job 命名空间：暂停创建真实 child，先入禁止 breakaway、kill-on-close 的 Job，再恢复。guardian 保存独立运行锁句柄并核原父 PID/开始时间，父进程也通过原生持柄核 guardian PID/开始时间。Core 真实 writer 与所派生的校验进程都在该 Job 内。

`request_stop.ps1` 以 ACL 保护控制目录中的独立 stop key 对 run id / manifest / close 或 stop 做 HMAC；密钥不在命令行。重复同一已认证请求幂等。清停至多排空 60 秒，超时强杀绝不写 clean receipt。Core 关闭 listener/store 后只写 close_prepared；父进程需核实际 child exit 0、guardian 正常退出、Job 空且没有强杀后才能写 clean_closed，再释放并实际探测锁。父/guardian/child 非正常消失写 recovery_required，不能普通重启。

`offline_lease.mjs` 的能力对象由模块私有 WeakMap 品牌保护。固定子进程才可创建，并反复检查原父/guardian 开始时间、实际 Job 成员和运行锁占用；事务外还用原生独占 DB 句柄确认无开放数据库。只有固定 Core 迁移的六个已审计事务 checkpoint 跳过与自身 SQLite 句柄冲突的重复试开，仍核 OS 身份、Job 与持续锁；不接受 JSON writersStopped 或任意回调作为租约。

## 验证记录

最终源码的真实合成 Git 固定候选专项 **10/10 通过，0 失败、0 跳过**（三组独立合成根并行）：

| 分组 | 结果 | 实测用时 |
| --- | --- | --- |
| 便携配置/WeakMap/完整树 + 实际写入后125秒持续服务、认证幂等清停、原址重启、状态新增文件拒绝 | 4/4 | 269.8秒 |
| 环境/未绑定配置/发行额外文件拒绝 + guardian/父进程/Core子进程分别死亡、recovery_required及重启拒绝 | 4/4 | 266.7秒 |
| 真实Windows持锁6→5→6、schema5服务拒绝 + backup角色/旧schema4拒绝 | 2/2 | 319.0秒 |

持续HTTP窗口实际125108毫秒；配对/聊天写入在其前完成，并在两次清停后验证原消息保留。真实6↔5场景232.1秒，核每次child/guardian退出、Job空与锁释放。成功根均在证据闭合后清理。早期一次测试自身普通只读查询产生SQLite边文件，曾导致末尾断言失败；修正为immutable后上述最终4/4已完整重跑通过。

对先前由真实合成Git提交生成的固定候选另跑 `smoke.mjs` 通过，75.6秒，返回HTTP/认证停止/原生退出/Job空/锁释放/发行不变全部true。该smoke测试候选manifest为 `7954de54ebc440d8a56f017c035d3d7662e7c493b4486ee5baff14aa3dc22e33`，合成来源提交 `873ae9bdaa1055b02be7d909bd67e8b6d4eb884b`；不等于root最终集成包，主窗仍应按下一节重跑精确集成包。

测试脚本 `lifecycle.test.mjs` 的便携配置/WeakMap/完整树测试不会在 Linux 全跳；Windows 分支使用实际固定生产入口。候选来自新合成 Git 的真实提交，runtime 全库存通过 `readCommittedSources` 提取。Git 从当前安装动态定位单链接 bin/git.exe。成功场景确认本 lab 的 Job 空后，核实解析后的 Temp 自有根、所有路径无链接再清理；失败证据保留。

## 主窗最终包烟测

```powershell
& $Node tools/i_core/release_schema6/lifecycle/smoke.mjs $Release $ManifestSha256
```

`smoke.mjs` 不进入生产库存。它不改候选、不重算外锚、不替换校验器；完整验证传入候选，随后只新建自己的合成状态/配置/DPAPI/备份/custody，运行真实空5→6准备、schema6 HTTP、认证清停，核原生退出与 Job 空、锁释放和候选不变，输出不含密钥的 JSON 回执后仅清自己的已核 Temp 根。不再等待125秒。

## 未完成与接受范围

- 真实现役旧固定 v4 没有本 supervisor 的清停回执。单独获得本锁不能证明旧 writer 停；首次迁入仍明确拒绝，需要独立 legacy cutover adapter、现役任务/action/进程树/监听者/包哈希的当次核实与生产停启授权。
- Windows 真实性覆盖新空5→6、6↔5、真实服务生命周期。4→5→6 算法/加密专项属于恢复 worker 的合成验证，不等于现役4首接验证。
- 没有生产可部署接受、真实账号/配置兼容确认、设备 Gate、部署或发布。root 需从最终集成提交 prepareRelease，再运行上述固定包 smoke。
- worker 提交仅上述拥有路径；该次提交按授权临时使用 `SKIP_PROJECT_STATE=1`，finally 恢复，主窗负责 DEVLOG / 当前态和最终 closeout。
