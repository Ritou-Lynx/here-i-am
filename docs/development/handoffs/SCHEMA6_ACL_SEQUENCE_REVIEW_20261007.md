# schema6 ACL现场顺序复核（2026-10-07，文档工作包）

## 范围与结果

- 基线：`1552e251c18c4554d425a0051ea7452e4904bb40`；本工作包仅更新[现场清单](SCHEMA6_CUTOVER_FIELD_CHECKLIST_20261006.md)并新增本交接。不改源码、DEVLOG、I_PROJECT_STATE、现场执行记录；不commit/push。
- 只读[现场执行记录](SCHEMA6_CUTOVER_EXECUTION_20261007.md)、原清单、固定Prepare/recovery源码，以及指定四个私有维护脚本。私有目录默认沙箱拒绝后，限定这四个源码文件的提升只读调用获准；没有执行脚本、访问实际进程/任务/原库/凭据/正文/JSON快照，也没有手机或配置操作。
- 已核私有 `acl-cutover-maintenance.ps1` SHA256为 `0abde623fdbd0685cffecc59e89a4d84893eaa1bcd112562be681e7194a373a2`。144项、16旧SID、实际外SID演练以及上次退回状态引用既有报告及主窗提供输入，不声称本轮重新查询现场。
- 更新顺序：重核批准/NTFS/备份/原ACL清单 → 冻结两旧任务及触发重试 → 停MCP → 在线只读预检 → 停Core、树/端口/65秒观察及冻结原件证明 → Apply前复核 → 全144项parent→child ACL → 完整回执/内容metadata复核 → 固定PrepareOnly及批准XML逐字比较 → 仅CREATE新任务 → 固定Start/Native raw保全/adoption → 真人Gate。
- ACL工作包未实现SHM判据；主窗随后已完成[固定release合成复现](SCHEMA6_SHM_REPRODUCTION_20261007.md)及在线比较源码/验证，详见[执行交接增补](SCHEMA6_CUTOVER_EXECUTION_20261007.md)。不改为停Core后复制；新source PR待审核，私有新窗口入口仍须闭合。现役ACL Apply未发生。

## 源码支持与必须闭合的缺口

| 依据 | 已核支持 | 清单限制／缺口 |
|---|---|---|
| 私有ACL脚本62–73、153–186、194–247 | 原生SetSecurityInfo仅Owner/Access及Protected/Unprotected DACL，Group/SACL参数为空；144项按路径深度排序；Apply基线比较；Apply失败及显式Rollback均调用全清单Restore-Snapshot，再全项readback。 | 不能只退回已写项；不能称SACL完整恢复。普通token不能替代同SID管理员及SeRestore。 |
| 私有ACL脚本23、164–165、234–247 | 句柄固定路径并核volume/file_id/size/mtime；不读取目标内容。 | 文件SHA保全由窗口主控的独立只读检查负责；脚本不证明内容hash不变。自动恢复catch仅核metadata，不能替代全inventory/冻结状态及完整回执复核。 |
| 私有ACL脚本153–163；owner wrapper15–16 | ACL脚本核旧两任务Disabled与三端口空；wrapper读取frozen passed/database_replaced。 | 不等于当前完整树退出、65秒观察或frozen时效/本轮绑定。Apply前必须重新闭合这些证据。 |
| owner wrapper44–54；prepare-production-login.mjs15–26 | wrapper核新成功Apply回执并仅校正该新回执owner、hash不变；prepare依赖一份mode/passed/snapshotHash匹配回执、固定PrepareOnly及XML hash比较。 | 两处都未复核144逐项完整记录/当前ACL及本轮完整frozen绑定；绿色窗口、单个passed字段不足以放行Prepare。旧成功回执也不可重用。 |
| freeze-legacy-runtime.ps1181–226、235、291–306、311–320 | 冻结helper内部catch有原任务恢复分支；有65秒观察、冻结raw复核、单次CreateNew锁及追加回执。 | 没有ACL执行后的独立Rollback入口；保留的锁/回执阻止原样重跑。新在线判据及新的窗口入口尚待主窗闭合，不能删锁/旧回执绕guard。 |
| [recovery_adapter.mjs](../../../tools/i_core/release_schema6/recovery_adapter.mjs)508–532、583–605 | replacement前即创建pending，raw先保全认证，再打开副本；commitStarted先于sidecar移动/主库替换；随后推进head。失败留下pending，中断需要审核。 | 即使commitStarted=false，state新增pending也会使硬钉144的ACL Rollback拒绝inventory。此时保持writers停，补受审恢复方案；不删pending/改常量。commitStarted、replacement、head或新写入任一出现即只向前修复。 |
| [prepare_login_schema6.ps1](../../../tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1)75–115 | 固定release自校验、配置ValidateOnly、managed MCP、非零端口及CreateNew输出；仅prepared，registered/started均false。 | 注册工具未在本工作包源码范围内；仅CREATE及真实COM readback仍是待执行放行条件，不能把审阅XML或mock检查当注册完成。 |

## 退回解释

ACL曾Apply的替换前退回：先排除commitStarted/replacement/head/新写入 → 冻结新任务并停新candidate/owned writers、旧任务保持禁用且portsfree → 同脚本 `-Mode Rollback -ConfirmFrozen` 实际恢复144项并全项readback → 内容hash/identity/size/mtime与原包原库兼容性安全 → 恢复原任务定义/触发/retry/Enabled/SDDL → 先旧Core schema4再同字节MCP健康。任何核验失败保持停写并报告原因，不把退回尝试说成恢复完成。

在在线预检阶段拒绝、Core仍在线且ACL未触及的分支，沿原冻结阶段回退，不另停Core来执行不必要的ACL Rollback。历史备份摘要或合成演练不代替新窗口实际恢复回执。

## 验证

- 对照固定源码和四个私有源码的相应分支复核以上边界；未运行现场脚本、库检查、合成运行或App构建。
- 指定文档的 `git diff --check` 通过；Markdown本地链接存在性检查通过。主窗已有DEVLOG/I_PROJECT_STATE及其他并行改动保留。
- 两个交付文档以UTF-8无BOM写入；主窗负责最终diff审核、全局状态及项目closeout。
