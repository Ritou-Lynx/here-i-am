## 2026-10-07 21:29（上海）最新结果：r02 Prepare 拒绝，已完整退回

单目录 settings 已按新授权加固成功，新只读演练零失败；六项批准外锚及实时父 SD 均未变，故按有条件预授权进入正式 r02。144项 Apply 成功后，正式 Prepare 在读取 ACL 回执时因 owner 为 Administrators 而非本人，报 `prepare_owner_rejected`。没有现场改 owner 重试。已真实恢复全144项原 owner/DACL/继承，复核原 raw 身份/字节、grant/replay、旧固定包和库存，再恢复旧任务原定义/权限，按 Core→MCP 启动并绑定完整树、schema4及三个端口。21:28:57退回签收通过。

**未完成切换，暂停待审。** 新任务不存在，候选从未启动，原库未迁移/替换，head未推进；四项真人Gate未执行。r02已消费，旧锁/回执全部保留，不得复用；下一轮须新的正式ID。单 settings 获批前置保留（f88d49ec…），生产 settings **不可清理**。完整证据和下一轮源码建议见[本轮授权及实录](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)。以下旧阶段的“r02未使用/零停机/尚未加固”均仅为当时历史，不覆盖本节。

## 2026-10-07 新授权：单目录前置及有条件 r02（优先于历史记录）

用户已授权先将单目录 settings DACL 执行入口/测试纳入 PR20、CI 全绿后，仅关闭继承并保留既有ACE；加固成功后新ID完整只读重演，包含模板逐字、PR16在线副本和结束全套复核。全套零失败且 manifest/XML/双SDDL/父SD/login 原批准hash全部不变，可直接按预授权用r02执行④–⑥；任何现场失败或偏差就停审，不进场。实际管理员/U盘/口令/关机及手机、claude.ai节点仍叫本人。此刻尚未执行加固或新演练。[本轮精确门槛和恢复判据](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)。下方“禁止改ACL/需另请进场”等为旧轮历史。

## 只读演练阻断，当前不得进场（2026-10-07）

维护源码62104abd/PR20 CI15绿，但最新只读演练因获批login父task-approval…\\settings仍继承ACL拒绝，固定生产Prepare同样要求protected；该目录不在原144项计划。本轮禁止改生产ACL，补齐方案未执行。精确目录/方案hash/回退及三次回执见[演练交接](SCHEMA6_READONLY_PREFLIGHT_20261007.md)。正式r02未用，旧Core/MCP schema4、零停机。先另审此目录前置处理并完整重演通过，才可另请正式进场授权；下文为历史阶段记录。

# 当前进展：方案已接受，源码修订中

用户已接受显式Unified=true、input/expected分开绑定的非保护DACL及外主体仅纯读条件。本轮已进入源码/CI/新候选阶段；下面“待用户接受/未改固定包”等为当时历史快照。新模板使旧包不可复用，最终精确审批待新候选完成。A继续冻结前暂停，B独立继续。详见[任务权限修订](SCHEMA6_TASK_SECURITY_REVISION_20261007.md)。

# Core 切换再次授权：只读首关停止记录（2026-10-07）

## 结果与执行边界

用户授权主窗合并PR16并按现场清单④–⑥切换，先启动独立B源码窗口；生产XML/SDDL的本机兼容性先只读核实，通过才可冻结。本人口令、U盘、XML、管理员及真人设备步骤逐项叫人。

PR16已普通合并到v3-lab，提交72905f6f9bf5753de68b31b8f89d6ec7427db30a，受审head为09ea2914562edcf2b4f3dbba37cedb009d4a3219（15/15检查绿）。远端返回merged=true；没有把私人D目录Git历史带入主线。

**A未切换，停在冻结之前的兼容性门槛。** 没有调用新窗口入口，cutover-retry-20261007-r02仍未使用；没有冻结/停用旧任务、停止服务、Apply ACL、生产Prepare、注册新任务、迁移/替换原库、推进head或启动候选。没有操作手机、隧道、PR10、47862配置及邮件。旧锁和回执均原样保留。本轮人为引入的服务停机为0，无需执行恢复旧任务的mutation；不是已经完成切换或关机验收。本轮正常关机清停、登录自启、手机同步、claude.ai写入四项真人Gate均未执行。

## 固定候选复用：47项逐字相同

| 核验 | 结果 |
|---|---|
| 原候选来源 | 1552e251c18c4554d425a0051ea7452e4904bb40 |
| manifest SHA256 | 6ae8f970a08ee8f21f8c78ba8846273144101cbdd8d3a2cb0530d5a3daf6b1ff |
| 库存 | 47项，含固定Node |
| 候选现有字节/大小对manifest | 47项全部相同 |
| 合并提交的各源码字节对原manifest | 全部相同，变化清单为空 |
| 决定 | 可以沿用已构建候选；没有为了改变source_commit重写manifest或重建 |

维护源码在固定47项之外。库存一致不代替配置、XML、权限和现场Gate。

## 只读Windows检查

只读取原批准记录、审阅XML、登录配置的owner绑定和任务目录元数据；未输出XML全文、SID、凭据、业务内容或库内容。使用Windows PowerShell5.1，真实Schedule.Service连接只做NewTask内存定义、GetTasks枚举和GetSecurityDescriptor；未调用RegisterTask、Run、DeleteTask或Enabled setter。

| 检查 | 结果 |
|---|---|
| 批准XML SHA256 | 7de2a122a782c509cad3a89304bce5ba88e03c607583eb62a17d9b57ee183a05，与原审批一致 |
| XML显式UseUnifiedSchedulingEngine | 缺省 |
| 本机NewTask读取 | false；再次内存roundtrip仍false，规范化XML稳定 |
| Principal | InteractiveToken=3、LeastPrivilege=0；COM返回账户表示经SID归一后与当前用户及login配置一致 |
| 动作/触发 | 各1 |
| 新生产任务 | 未发现同名任务 |
| 原批准记录的SDDL绑定 | 没有approved_sddl/approvedSddl/task_sddl/taskSddl字段 |
| Task Scheduler根目录安全描述 | 前后完全相同；存在ADMIN/SYSTEM的OI继承ACE和CREATOR_OWNER继承ACE |
| 实际注册后的定义/SDDL | 本轮未注册，未验证 |

首次检查直接比较COM账户文本与SID曾得到false；立即改为只读SID归一重核，结果true。最终身份判断只使用归一后的回执，不将表示差异写成权限或身份错配。

原私有RegisterOnly草稿只以null SDDL交给Scheduler默认构造，不包含批准SDDL或严格SDDL回读；它没有执行。本轮仓库受审RegisterOnly要求明确的approvedSddl及批准绑定，不能把旧XML审批自动充当该新权限锚。

历史同机合成已观测省略Unified在注册时false→true、D:P丢失；Hosted合成也观测父目录继承ACE。当前生产比较保留Unified、P位和继承flags的严格检查。内存NewTask解析只能证明定义层接受，不能排除注册后的变化；TASK_VALIDATE_ONLY语法检查也不能证明该项。**本次缺少SDDL审批锚，同时注册规范化风险未排除，故首关不放行。** 不宣称生产注册必然失败，不借用显式true合成任务的绿灯。

## 停止后的现役只读签收

2026-10-07本轮停止后查询：HereIAm-iCore与HereIAm-iRemoteMCP均Enabled=true、State=4（Running）、各1实例；47841监听属Core原进程，47860/47862同属原MCP进程。只查询元数据，不操作任务/进程，不把此结果当新Core健康或真人Gate。未查询原库schema，不能将历史schema4快照当本轮原库检查。

## 14:36上海：已授权的四组真实COM演练

用户在本主窗明确回复“授权”。仅执行先前列明的最多4组：原缺省/显式Unified=false × protected/unprotected DACL。Windows PowerShell5.1；每组随机名称、禁用、无触发、安全cmd空动作，从未Run。输入hash持柄、全部预构造、CREATE硬上限、nonce绑定清理均先经独立源码复核；纯内存验证2组安全构造、6种危险形状拒绝，0次任务创建。

| Unified输入 | DACL输入 | 注册后Unified | P位实际 | 严格定义比较 | 严格SDDL比较 |
|---|---|---|---|---|---|
| 缺省false | protected | true | false | 拒绝 | 拒绝 |
| 缺省false | unprotected | true | false | 拒绝 | 与CREATE前独立期望一致 |
| 显式false | protected | true | false | 拒绝 | 拒绝 |
| 显式false | unprotected | true | false | 拒绝 | 与CREATE前独立期望一致 |

**4次CREATE、4次回读、4次绑定删除，最终枚举4名全不存在；没有第5次。** 主回执2026-10-07T06:36:51.1448833Z至06:36:52.2661007Z，约1.121秒。所有safeReadback/deleted为true，无清理失败、结果不确定或父SD漂移。旧两任务完整XML/SDDL/Enabled/状态/实例快照前后一致；独立复核旧两任务仍Enabled/Running各1实例，三端口仍绑定原进程。本轮人为停机0。completed=true仅表示安全执行和清理闭合，**不表示兼容性通过**。

主匿名回执SHA256：27b701feaa20866495dd47d32dfca9a7044bd72c8810260e215313db4001d252。诊断fixture SHA256：945928b71fcfc6094c8c077e6d1ab62fba044970f38e3a018de4a5d1664c4b21。回执在忽略的build/ci合成根；诊断源码为tools/i_core/test_fixtures/release_schema6/maintenance_compatibility_probe.ps1。没有改固定47项或生产维护比较，源码/记录仅本机未提交、未推送。

protected输入预期保持P位，不用actual反向改期望。unprotected由CREATE前本机父SD独立推导6条ACE，actual含7条，其中额外OWNER FR与同SID/flags的FA由现有严格规则合并，比较一致；没有忽略Inherited flags。独审已复核回执hash及解释。

## 最小修订提案（待用户接受，未改固定包）

1. 固定Prepare模板显式UseUnifiedSchedulingEngine=true；本机明确false也会变true，补false无法解决受测冲突。只读内存验证表明，拟议XML相对原批准定义仅该设置改变，Actions/Principals/Triggers和其余Settings相同。新模板会改变47项中的文件字节，需源码专项/CI、新候选与新manifest及配置/XML外锚，不能继续沿用今天“不变库存”的复用结论。
2. 提议采用非protected的最小OWNER/SYSTEM/ADMIN显式DACL，并将registrationSddl、expectedRegisteredSddl、批准父SD哈希、继承算法版本分别纳入配置/本人审批。CREATE前从批准输入和匹配批准哈希的实时父SD重算期望，必须等于已批准expected；CREATE只用input，严格回读只用expected，父SD前后漂移即拒绝。actual不构造期望；P位、owner/group、ACE SID/flags/mask比较保持。当前生产代码尚未实现该输入/期望分离。
3. 本机拟议继承结果只包含OWNER、SYSTEM、ADMIN，未包含其他主体。输入3条显式FA，期望另含3条ID权限：ADMIN/SYSTEM各001F019F，OWNER为001F01FF。原审批没有SDDL锚，不能把此新权限方案当已批准；protected差异也不能被悄悄豁免。
4. 已在新的私有review-only目录准备完整XML预览、input/expected SDDL和绑定元数据，未改原批准文件/生产配置。预览XML SHA256 b42af2fcbc363382ea547127a0b6f07f4ff8fa697b53e5f57986ee5f4b1b7988；input SDDL SHA256 50398e9fe2ff2b2cbf62ee4ed31b703ddc21aff6339a0595963e2cb859915feb；expected SDDL SHA256 9d1a0c172a55d1ac6ee5a8a831793abde4cd6b7252258329688283f3bc593580；父SD UTF8 SHA256 330eb3abb433de72e6efae43075cd7440976dae310f7d55da2717626b38b880d，算法windows-file-oi-v1。不在仓库保存真实SID/SDDL/XML。
5. 该预览仍引用旧候选/manifest，明确reviewOnly=true、registrationAllowed=false、productionApproved=false、finalCandidateRebindingRequired=true；不是可批准后直接注册的最终XML。接受修订方向后再准备代码、测试和新候选，交本人批准最终精确XML/SDDL。四次本机创建额度已用完，不再创建新测试任务；后续本机只做纯验证，新的真实任务创建须另有授权。

本次合成替换了动作、Enabled和触发器，仅证明受测Settings/SDDL行为；原生产XML仍未真实注册验证，四项真人Gate未执行，A继续停在冻结之前。下一步需要用户接受任务设置/权限修订方向；不要求现在输入口令、管理员操作或关机。

B 14:43上海快照：源码窗口仍active，规划监视器正补记录不可见保持pending、多实例互斥、Codex超时及回收，默认禁用，使用假进程/合成数据。notes/领域36项已过是局部证据，P1/P2/P3与整组CI尚未由主窗验收；A停止不取消B。

## 初始受限演练计划（历史，已由上节签收）



这是待批准方案，未执行。因为本轮首关明确只读，以下真实CREATE→回读→删除会超出首关限制，需要用户单独授权；现役始终保持运行。

- 最多4个合成任务（原缺省/显式false设置与受保护/非受保护DACL的组合），仅创建随机HereIAm-Synthetic-Compat-名称的任务，始终禁用、清空触发器，替换实际Action为系统cmd的/d /c exit 0；从不Run任务，不使用生产任务名，不触及旧任务。
- 先以原批准XML的Settings构造合成定义，再测显式Unified=false是否保留原语义；若不保留，记录并提出显式true的受审XML变更，不能自动接受。
- 独立审批SDDL前先核本机父folder的继承规则；合成对比受保护/非受保护的最小OWNER/SYSTEM/ADMIN权限，原输入与CREATE前独立期望分别固定，不从注册actual回填期望。
- 每个合成对象只CREATE一次，nonce/路径/owner/禁用/无触发/零实例绑定后删除并枚举确认缺席；所有失败回执保留，不触碰同名竞争者。测试期间不执行生产Prepare或进入现场窗口。合成通过只证明受测Settings/SDDL行为；由于动作、Enabled和触发器已改为安全形状，不能代替原生产XML完整兼容性核验或生产放行。
- 演练结果决定最小模板/XML/SDDL方案，生产严格比较不放宽。若需要改固定Prepare模板，47项库存会变化，须版本化、专项测试/CI、重新构建候选并交用户批准精确XML/SDDL，才重新进场。不能继续沿用今天的“不变库存”结论覆盖未来修订。

本轮尚不需要输入口令、插U盘、管理员操作或关机。上述门槛闭合前不叫用户执行后续动作。

## B：独立源码窗口当前进度（14:26上海快照）

任务“记一下与规划上线前源码准备”，thread 01a11502-ef12-7613-bb9c-60f2fddd6e5e，从当时最新origin/v3-lab@0a24cac2建codex/hub-golive-src-20261007独立worktree。用户已授权源码提交/推送/草稿PR，未授权部署或合并。主窗随后合入PR16；该变更不阻塞B。

B已拆MCP、手机捕获、规划监视器三个互斥工作包，主控负责notes导入/上线顺序/整合。notes→captures及领域相邻合成测试36项通过，覆盖原ID/revision/墓碑/planner skipped/幂等/拒绝。正在补手机正式启动的领域连接及用户操作签名接线；已有页面和HTTP适配器不等于生产启动接线完成。P1尚在实现，P2/P3与完整CI待整合，不写源码全完或上线可用。

B禁止改固定release、维护源码、生命周期/会话启动器及现场清单；新版MCP固定库存衔接只列待主窗处理。B不读真实数据库/凭据，不停启现役、不装手机、不注册任务、不合并。A停止不取消B，B继续优先完成可单独上线的P1。
