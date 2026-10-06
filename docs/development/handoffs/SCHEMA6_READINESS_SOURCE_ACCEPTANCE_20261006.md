# schema6 生命周期/恢复/完整备份主窗验收（2026-10-06）

## 范围与基线

从已授权合入PR13的`v3-lab@90f23ce1d38628901e25b421d8f0f21c084f093b`隔离到`codex/core-deploy-readiness-20261006`。本轮推进D4源码、同提交固定候选、合成验证及明确授权的九类私有备份与隔离恢复检查；不停止/重启现役Core或MCP、不改任务/线上配置、不升级原库、不切47862、不装手机或改上传器。D1/D2/Drift62等先前源码和真实副本证据仍按PR13交接，不由本轮新增测试替代。

| 工作包 | 已复核提交 | 接受范围 |
|---|---|---|
| 恢复适配器 | `bd6f03ceab6c79bf311ec53204500f932de0a2c0` | 原canonical live路径，真实租约入口，schema4完整备份认证后genesis、已有5/6既存可信floor，库外最新head防回退 |
| 完整运行备份 | `44b9d4976a415e0ad00f280c79638f679bac66d7`、fixture修复`9c6c34d6f7897114d1f65dff0205bbcd895597be` | 九类显式库存、完整旧包、流式AES256GCM逐项认证、CurrentUser DPAPI purpose/path绑定、固定包/真实退出码/内存密钥管道 |
| Windows生命周期 | `7e66311e4608bff1c828e9ae38f7b185cc221938` | 固定Windows Job/guardian、受保护显式配置、认证清停、实际原生退出/Job空/锁释放、新空5→6及同谱系6↔5 |
| 主窗共享接线 | 本分支最终提交 | 34项同树库存/固定策略、CLI verify、PATHEXT/实际Node退出检查、Linux便携+Windows专项CI、全局状态与部署方案 |

## 主窗组合验证

新增还原接线前的主窗Windows组合已完成：**203/203，0失败、0跳过，退出0，686854.793ms**。包含完整备份23、恢复23、发布32、生命周期10及相邻Core/MCP115；持续HTTP窗口125015ms。用户新增实际还原要求后仍需对新增源代码及最终整包复验，不能把这个结果提前覆盖新增只读入口。

三个worker均以合成数据验证：恢复23/23、原domain_migrate22/22；备份最终23/23；生命周期最终10/10（便携3+Windows7），新增非空断言所在case另1/1，真实合成Git候选smoke通过。生命周期实测持续125108ms，真实Windows6→5→6确认每次原生退出/Job空/锁释放。算法测试中的synthetic lease与生产OS租约分开，生产模块拒绝JSON/任意回调/测试capability；已有真实schema4副本结果属于前轮PR13，不能视为本轮现役4首次迁入已验。

最初主窗提前组合159/161，两项失败分别缺尚未集成的lifecycle/common.mjs与offline_lease.mjs；不是业务断言失败。完整包集成后整组复跑。独立二审指出必须补真实固定入口offline迁移，已由最终Windows6↔5场景闭合；备份旧手造manifest测试改为真实新Git提交+prepareRelease。生命周期早期自身只读查询产生sidecar导致末尾拒绝，修正为immutable后原完整场景重跑通过。更早fixture/环境失败和重跑保留在各worker handoff，不屏蔽或修改生产校验使测试变绿。

Node/PowerShell语法及diff检查无错误；无需构建Flutter App，因为本轮不改lib/android或schema生成定义。源码验证、固定包烟测、远端CI、生产Gate分别绑定，不能沿用PR13的CI或APK结果覆盖新增代码。新Windows专职job验证生命周期与DPAPI，Linux仍负责便携路径。

## 最终固定候选

主窗最终同树固定候选、真实授权还原与完整复验尚在进行，完成后将回填精确摘要与回执。

候选仅固定源码和Node；没有DB/配置/任务/密钥/grant/replay内容。外部manifest摘要用于每次校验，候选不覆盖旧包。smoke只在全新合成Temp根建受保护配置和DPAPI密钥，调用候选真实入口；成功后确认进程/Job/锁并安全清自己的根，不操作现役状态。

## 生产未接受项及下一步

1. 旧固定v4没有可验证外部清停接线，普通入口拒绝无本监督谱系首次迁入。独立“非优雅停止后恢复”的adoption能力、先于任何SQLite打开的原始DB/WAL/SHM/journal加密保全、原址恢复验证、不可重做genesis的阶段链及断电演练尚待实现；不能把获得锁/PID消失/健康返回当作旧实例clean_close。方案见[部署runbook](SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)。
2. 监督配置固定relay关闭，旧Shortcut邮件运行配置尚未兼容验收；完整清单需保全其依赖，不能据本候选覆盖现役邮件功能。已有5/6跨包/跨配置交接也不由同包清停重开测试授权。
3. `inventory_only`不证明生产依赖全部发现或writer停止。原任务/所有writer、完整现役配置与凭据保管、原址/独立最新floor均需当次核实。备份仅有新私有目录的检查提取，无生产激活/原址覆盖路径，非空domain拒绝降级。
4. 来源adoption和captures真机新增/改版/删除/用户改卡保护闭环通过前保留47862，切换时只留一个消费者。MCP切换、手机安装和PR10上传启用分别获得具体授权，保持同一时间单一上传器。

D4生产切换未完成；现役服务和主力手机保持此前候选。用户要求本轮补全备份覆盖、真实隔离还原、停启/电源事件/退回说明与本人操作单，推送并开草稿PR后暂停审核；不继续新legacy接管开发。邮件调试可按用户决定在切换时暂时关闭，其生产影响须明确。

## 证据入口

- [恢复worker](SCHEMA6_RECOVERY_ADAPTER_20261006.md)
- [完整备份worker](SCHEMA6_FULL_BACKUP_20261006.md)
- [生命周期worker](SCHEMA6_LIFECYCLE_20261006.md)
- [部署方案](SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)
- [前轮PR13验收](POST_AUDIT_SOURCE_ACCEPTANCE_20261006.md)
