# 维护源码闭合主窗验收（2026-10-07）

基线为PR16分支codex/schema6-online-shm-preflight-20261007@d4b71a92。用户批准仅整理维护源码、合成演练、更新同PR并等待全部CI；不合并、不进场。本轮没有读取真实JSON/快照/库/正文/凭据，也没有查询或操作现役Core/MCP/隧道/生产任务/手机。只读指定私有脚本源码，所有执行限本分支和新合成根。真实COM只操作本次随机合成任务。

## 已闭合的源码范围

版本化ACL、owner wrapper、foreign-owner probe、冻结helper、新窗口入口、固定Prepare和CREATE-only注册，以及它们的共享锁/完整回执/输出范围辅助模块。实际部署路径、SID、批准锚均来自私有配置。合成测试一并位于release_schema6及test_fixtures/release_schema6，并由Windows job必跑。固定runtime47项未变；新维护代码不自动进入release库存。

窗口计划ID为cutover-retry-20261007-r02，入口enter-maintenance-window.ps1；现场目录尚未创建。旧锁、旧回执、旧guard不删除、不复用；新窗口可以在旧文件存在且无独占句柄时进入，同窗口即使失败也拒绝重入。所有WindowId统一8–80字符、字母数字开头、后续仅字母数字下划线连字符。

## 主窗复核与修正

- 统一taskPath为文件夹、name为任务名；读取COM时按folder+name，避免冻结成功后注册必拒。
- 所有代码/配置hash默认必需，准备回执只有显式只读持柄例外，随后完整语义/字节验证。最终独审发现Register只瞬时验候选库存、随后按路径执行脚本的TOCTOU；已补父进程pin manifest及全部候选文件至finally，跨进程改写/替换拒绝、释放后可写的合成回归随改动补齐。
- entry从同一受保护句柄hash/parse并pin源码后执行；冻结失败恢复disabled定义后实际回读四节/SDDL/Enabled，兼容原XML省略Enabled。
- 输出只能是本轮窗口直属新文件、彼此互斥、与raw/external/输入及ACL目标树分离；包括失败回执，不能误写缺失journal。
- 独立Prepare共享guard并实时重核冻结，Register验证子调用由父锁保护；没有Internal/SkipGuard生产开关。
- PR16在线SHM例外不扩大：冻结初次闭合和65秒观察仍四件全hash，raw加密/NativeLease/strictClosedPath/ACL/plainPath保持。
- ACL只改owner/DACL/继承，不读目标内容；raw_external_verified=false明确要求外层持锁重核。pending库存漂移拒绝盲退，保全后再审；接管四证据任一出现/未知即向前修。

## 合成证据

主窗初次合并专项33项：31通过、0失败、2未执行；4.537秒。两个未执行分别为本机非管理员foreign-owner探针和避免重复CREATE的opt-in COM测试。不能称本机全通过；Windows CI显式启用两项，缺令牌或实际回读失败即job失败。

本机真实COM由工作包独立执行，只有一次CREATE：随机禁用、无触发、零实例任务。首轮严格比较发现真实默认值/SDDL变化后拒绝；没有再CREATE，对同一nonce对象完成回读、同名/XML差异拒绝和DELETE，最终不存在且从未运行。首轮中间遗留和恢复过程如实记录在注册交接；生产不享有规范化豁免。

ACL合成覆盖Owner/DACL/继承全项往返、父级中断后全清单恢复、pending保留/禁止盲退、窗口相互排斥和硬链接拒绝；foreign-owner特权往返由CI真跑。冻结合成覆盖旧锁/回执字节保持、新ID通过/同ID拒绝、四件每件内容变化、首次SHM变化及进程句柄身份错误拒绝。

整合首轮108项为104通过、2失败、2未执行，119.690秒；失败均属新夹具：统一8字符下限后仍用旧短ID，以及新pin夹具继承了PS7模块路径。已修夹具、固定PS5.1模块根，并要求跨进程拒绝实际sharing-violation而非任意异常，未放宽生产检查。最终复验108项：106通过、0失败、0取消、2未执行，168.206秒（其中维护41项+前轮相邻67项）。未执行仍仅本机无管理员foreign-owner与不重复CREATE的COM opt-in，Windows CI强制执行；远端精确提交CI回执统一在同PR正文/Checks登记，不继承旧head绿色。

最终Register全库存持柄修正后，主窗复验全部维护41项：39通过、0失败、0取消、2本机未执行，11.530秒；含真实跨进程4次改写/替换sharing violation及释放后可写。前述相邻67项源码未再变化，保留108项整组证据，不冒称在新修正后重复执行完整108项。Windows CI在最终精确head强制两项特权/COM，不沿用被后续push取消的旧head。

## 明确的剩余现场门槛

未执行真实旧任务冻结/65秒观察/恢复、现役144项Apply、生产Prepare/注册/Start、迁移替换或真人关机/手机/claude.ai四Gate。源码函数及合成任务不能代替这些证据。

固定Prepare模版省略UseUnifiedSchedulingEngine；官方schema默认false，但本机同版本合成注册曾变为true，SDDL protected也曾被Scheduler移除。检查保持严格拒绝；进入现场前须证明批准XML语义兼容或审阅必要变更。未访问生产XML，不能声称已验证它可注册。

合并PR16与再次进场都需另行授权；本轮完成推送、全部检查绿后暂停。

微软依据：[TASK_CREATION](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_creation)、[UseUnifiedSchedulingEngine默认值](https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-useunifiedschedulingengine-settingstype-element)。实际规范化差异仅据本机合成证据，不能推断目标生产XML已通过。

最终静态检查：10个维护PowerShell文件PS5.1解析通过，维护Node模块语法通过；版本化源码无现场路径/真实SID/现场凭据，Git差异与文档链接检查通过。新固定47项runtime源码没有变化。远端结果按精确head登记在同PR正文/Checks，全部绿后才结束。

主线PR15后续已合入v3-lab@0a24cac2b7db812f34fb845325e27b77d16139dd，导致PR16仅DEVLOG与项目状态冲突。本轮把该精确主线提交整合进隔离分支，保留双方新增记录；维护源码及固定runtime未因此改变，未运行Relay脚本或任务。PR16仍为草稿且未合入主线；最终CI以整合后精确head为准。

最终d07be5b2两组Windows整组均272项271过/1失败/0跳过；唯一失败真实COM的registered_sddl_changed，foreign-owner往返实际通过，合成任务已安全删除。没有把失败改跳过或重跑掩盖。新增快速Windows维护job和匿名SD形状诊断（OWNER/SYSTEM/ADMIN/OTHER、flags/mask；无真实SID/SDDL），定位差异；生产安全描述符比较不改，不用actual覆盖expected。最终完整CI仍以修正后的精确head为准。
