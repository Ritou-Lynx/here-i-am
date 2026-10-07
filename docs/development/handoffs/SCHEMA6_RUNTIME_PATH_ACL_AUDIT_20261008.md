# Schema 6 runtime 路径与 ACL 只读审计（2026-10-08）

审计时点：2026-10-08 00:46:19 +08:00。基线 codex/core-preflight-readonly-20261007 / a1f5f70394e11f23d4f231e3483af2f7057c6b16。

结论：发现 **1 项确定 ACL 违例**：批准 settings 内 daily-backup-config.json。其他被现场核对的现役入口要求未发现新增违例。这不是启动、备份、关机或还原 Gate 通过；未运行这些入口，未执行 SQL，未读取凭据/数据库/备份正文，未改生产文件、ACL、任务或进程。动态文件可随运行新建/替换，本报告是时间点证据。

## 1. 规则与源码

源码均相对 tools/i_core/release_schema6/。现役 manifest SHA256 为 3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0；47/47文件现场 hash 匹配。46文本源与 checkout 做CRLF→LF规范后全同；Git换行差异不是部署漂移。

|代号|精确要求|实现|
|---|---|---|
|G|canonical本地绝对路径，目标及祖先无reparse；owner本人；Allow仅本人/SYSTEM/Admin；本人FullControl。普通文件/子目录不要求自身protected；函数不拒绝Deny ACE|lifecycle/protected_paths.ps1:2；login_schema6.ps1:17；session_window.ps1:117|
|GRoot|G加目标自身AreAccessRulesProtected=true|明确带-Root或root=true调用|
|B|plain路径；owner本人；目标自身protected；每条ACE必须Allow且精确FullControl，主体仅本人/SYSTEM，二者都必须存在。Admin不合规|key_custody.ps1:32|
|P|plain本地路径、类型正确、文件single-link；不把owner/ACL作为该入口的强制条件|backup_bundle.mjs:19–34 safe；package.mjs plainPath|
|Observe|已读元数据；没有所列现役入口对每个后代递归执行G/B的依据；不能把父目录保护推广成后代必须protected|MCP动态/旧memory状态/T9非日常输出顶层|

采集器只读属性、owner/DACL、Win32 FILE_READ_ATTRIBUTES（share R/W/Delete），不读credential、DPAPI、stop.key、数据库字节。存在文件nlink全为1，目标/祖先无reparse。随后补核505个存在的唯一路径，Win32最终路径全部与指定路径一致；T盘现场文件系统为NTFS。未实际独占开库/锁测试；不宣称元数据通过等于运行可用或内容认证通过。

## 2. 入口及全部路径类别

|入口/调用链|固定与动态路径|实际要求及边界|
|---|---|---|
|login_schema6.ps1:76–124|release根/全树/manifest/47文件；login及父settings；Core config；backup config；state根；control根；backup-key根|release根GRoot、全后代G；配置G；login父/state/control/key根GRoot。Open-BootstrapFile:68另查单链接/最终路径并持只读句柄。login对backup config仅G，所以目前可启动、后续备份B却拒绝|
|start_schema6.ps1:80–128 → configuration.mjs:40–60|release；Core state根及所有后代；当前control；Core config及父；grants/approvals/recovery-key/backup-key文件及父；runtime-backups根；recovery-custody根及既有custody.lock|根GRoot、文件G；state递归后代G；key加载进一步B；并非全部settings都要B|
|configuration.mjs loadKey → key_custody.ps1:66–74|backup-key/runtime-backup.dpapi；recovery-key/runtime-recovery.dpapi|目录与文件都B、DPAPI输入single-link。未调用密钥加载/解密|
|runtime_child.mjs:65–98 / job_guardian.ps1:6–19|control、launch.json、stop.key、Core s6-lifecycle.json|control GRoot、文件G；绑定与内容摘要不在本元数据审计范围|
|mcp_configuration.ps1:8–50|mcp.json父/文件；mcp-source根/递归后代/6源文件；固定Node；I_REMOTE_MCP_STATE_DIR、I_HOME；I_MEMORY_DB、I_MEMORY_POLICY|根GRoot、文件G；bootstrap文件single-link。state/home不递归强制后代G；memory父不在此处要求GRoot|
|MCP动态|oauth.json、core-frontend.json、phone-feed.json及tmp；writeback.sqlite及sidecar；配置日志目录/新日志；memory sidecar/identity后代|oauth.mjs:100–104、writeback.mjs:129–131,260–264用mode/chmod不等同Windows显式B。server.mjs:433–488选外部state/memory/log路径。六固定源码本次hash匹配；未开库|
|session_window.ps1关机/注销hook|ready.json、launch.json、supervisor.json、s6-lifecycle.json；control/stop.key/既有close；Core DB及runtime.lock|ReadProtected:127=G+single-link+最终路径+≤1MiB；close用control GRoot；ProbeClosedDatabase:250=G+single-link+最终路径及真正独占开库；runtime.lock:305=G。本次不执行关机/独占开库|
|会话新建与回执|session-GUID/control-GUID；launch.pending→launch.json、stop.key、manifest.id、guardian/ready/child/supervisor；mcp-start/stop、backup-status-GUID、session-window/close/exit、pending与close临时文件|login:123–126新空目录设置三主体GRoot；普通新文件可继承、protected=false属预期。WriteNew:141原子发布。未来尚不存在文件不是当前失败|
|scheduler_once_schema6.ps1:12 → backup_bundle_schema6.ps1:85–97|daily config、policy.outputRoot、.automatic.lock、backup-key目录/DPAPI|config B；输出根plain而非强制B/GRoot；既有lock B；不存在则真正备份运行创建并设置B。当前lock尚未创建，与config阶段拒绝一致|
|automatic_backup.mjs:66–106 → backup_bundle.mjs:24,126|118 spec来源、envelope；local/mirror daily-GUID；capture临时/sidecar；artifact/runtime.aes256gcm、portable-key/binding、receipt|来源及既有文件P/稳定性检查；新fresh输出目录代码设置本人/SYSTEM私有ACL；不是所有来源文件/父root都要B。保留期只处理认证managed目录；本次未读备份正文|
|recovery_adapter.mjs:94–115,377–407,448–460，下次启动|current-head.json、当前不可变hash.head.json、generation>1时直接前任head、custodySha.floor.json、custody.lock；异常恢复另生eventHash.recovery.json|custody根GRoot、既有lock G；内部文件plainPath/single-link并加MAC/hash/进度验证，普通子文件不要求B/GRoot。当前后代另做G观察全过，无内容/MAC/DB验证|
|raw_state_backup.mjs:73|runtime-backups根、raw-GUID下DB/WAL/SHM加密文件、manifest|父根GRoot；新子目录/文件可继承；元数据不等同可恢复|

Prepare/注册/维护不是会话反复执行的入口，本次未调用；任务对象安全由主窗另审计，不以此文件证明Task Scheduler DACL。MCP实际immutable目录为维护根mcp-source，固定Node仍指schema6-20261007-1552e251/runtime/node.exe，符合批准配置且hash匹配，不能误判漂移。

## 3. 现场计数

599条“路径×检查类别”、506唯一路径：321 PASS，1 FAIL，1 NOT_CREATED，276 OBSERVED。类别重叠，不把599当文件数。UNKNOWN=0（默认沙箱拒读后获准只读访问成功）。文件nlink>1=0，reparse/祖先异常=0。

release：47清单文件+manifest=48文件、含根6目录，合计54。MCP源：6文件+4目录=10。Core state全树61。当前session树38，额外对control目录做1次GRoot。Core custody/runtime-backups联合12。

|类别与状态|条数|
|---|---:|
|automatic-lock, NOT_CREATED|1|
|automatic-mirror, PASS|1|
|automatic-output, PASS|1|
|backup-config, FAIL|1|
|backup-envelope, PASS|1|
|backup-source, PASS|118|
|control-root, PASS|1|
|core-config, PASS|2|
|core-custody, PASS|12|
|core-external, PASS|7|
|core-state, PASS|61|
|current-session, PASS|38|
|current-session-root, PASS|1|
|dpapi, PASS|4|
|login-config, PASS|2|
|mcp-config, PASS|2|
|mcp-data-files, PASS|2|
|mcp-data-roots, PASS|2|
|mcp-dynamic, OBSERVED|190|
|mcp-executable, PASS|1|
|mcp-source, PASS|10|
|memory-dynamic, OBSERVED|83|
|memory-parent, OBSERVED|1|
|release, PASS|54|
|t9-root, PASS|1|
|t9-top-level, OBSERVED|2|

## 4. 唯一违例与已批准最小方案

$APPROVAL/settings/daily-backup-config.json：owner本人，protected=false，3条inherited Allow FullControl（SYSTEM/Admin/本人），nlink=1，68662字节。SHA256仍为d33106d26cf4c6e7c7f54e007e84bda869c0ce9c7b75a1377d98b321e4387cb5。

B违例有两点：自身未protected、存在Admin。它通过login的G，却不能通过自动备份的B。

本人已批准的最小方案仅针对这一个文件：owner本人；DACL protected；仅本人/SYSTEM两条Allow FullControl。保持内容、父settings、兄弟配置、运行包、任务不变；前后验证批准hash、file identity/nlink、owner/DACL。当前未修；须新增源码精确HEAD完整CI绿后才执行。不能用保护父目录替代文件B，也没有依据批量修改整个settings。

影响：现役Core/MCP/关机hook没有此文件B断言，不因该违例单独停止；下一次备份（interval=86400秒）继续在automatic_config失败；下次登录对应G可过、备份仍失败。整体关机/重登仍需真实Gate、内容认证和当时时点状态，不由ACL审计保证。

## 5. 恢复链覆盖不等于ACL违例

当前recovery-custody中的current-head、不可变head副本、8871…floor、d5d3…recovery事件、custody.lock均存在，owner本人、single-link、无reparse。根protected=true；普通文件继承、protected=false是合法的G状态。

118项daily清单不是递归捕获recovery-custody；路径核对确认8871…floor与d5d3…recovery事件没有直接列入。head引用关系依主窗已有白名单证据，本worker未读正文。常规重启读取当前head、不可变副本/必要前任、floor；recovery事件是恢复历史证据，不应误称verifyCanonicalRestart必读。

新增手动完整备份/本机+T9/真实还原由主窗执行，独立手动清单应覆盖当前实际恢复链；这里元数据通过不证明备份完整性。若变更批准daily配置内容和绑定hash，需另提方案，本worker未改。

## 6. 逐项索引与本机证据

本机详细收据 %TEMP%/schema6-runtime-acl-audit-20261008.json，599条逐項实际路径、去SID的owner/DACL、identity、nlink、大小。仅本机临时目录，不在公开Git；没有保存完整SID/SDDL或秘密正文。采集脚本同目录.ps1。

公开索引中Observe后代/无关旧Core后代以row ID显示，避免传播历史路径名；与本机收据相同行序逐项对应。G补充观察不表示runtime对每个输出都递归重检。P内容稳定hash/MAC及SQL检查未执行。路径代号：APPROVAL=批准task-approval；MAINT=cutover维护根；SESSION=当前session-c6034…；RELEASE=固定c9662439；CORESTATE=原Core .state；MCPREPO=continuity-b0-b2-20261002；T9=指定恢复根。精确绝对路径保存在本机收据。

|配置锚点|SHA256|
|---|---|
|$APPROVAL\settings\login.json|28c5b700b98815b57b57e4cc9430f16ee8ef5ba8bdc3a1a08f854873965e1e00|
|$APPROVAL\settings\core.json|cc5f8a42f31a18b72d8dba28559d1a4a01300ea875e117d61e9928deb9f4722c|
|$APPROVAL\settings\daily-backup-config.json|d33106d26cf4c6e7c7f54e007e84bda869c0ce9c7b75a1377d98b321e4387cb5|
|$MAINT\settings\mcp.json|1c2ec2597190734c3632b0a7709a302c03c416193c32f405a457248d2b689522|
|$RELEASE\manifest.json|3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0|

|行ID|类别|目标代号|规则|owner|protected|DACL|nlink|结果|
|---|---|---|---|---|---|---|---|---|
|1|memory-parent|本机收据 row-1|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|2|memory-dynamic|本机收据 row-2|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|3|memory-dynamic|本机收据 row-3|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|4|backup-source|$MCPREPO\tools\i_memory\.state\backups\policy-before-b3-20261003.json|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|5|mcp-data-files|$MCPREPO\tools\i_memory\.state\i-memory.sqlite|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|6|memory-dynamic|本机收据 row-6|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|7|backup-source|$MCPREPO\tools\i_memory\.state\i-memory.sqlite|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|8|memory-dynamic|本机收据 row-8|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|9|backup-source|$MCPREPO\tools\i_memory\.state\policy-decisions.pending.json|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|10|mcp-data-files|$MCPREPO\tools\i_memory\.state\policy.json|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|11|memory-dynamic|本机收据 row-11|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|12|backup-source|$MCPREPO\tools\i_memory\.state\policy.json|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|13|memory-dynamic|本机收据 row-13|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|14|memory-dynamic|本机收据 row-14|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|15|memory-dynamic|本机收据 row-15|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|16|memory-dynamic|本机收据 row-16|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|17|memory-dynamic|本机收据 row-17|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|18|memory-dynamic|本机收据 row-18|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|19|memory-dynamic|本机收据 row-19|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|20|memory-dynamic|本机收据 row-20|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|21|memory-dynamic|本机收据 row-21|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|22|memory-dynamic|本机收据 row-22|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|23|memory-dynamic|本机收据 row-23|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|24|memory-dynamic|本机收据 row-24|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|25|memory-dynamic|本机收据 row-25|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|26|memory-dynamic|本机收据 row-26|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|27|memory-dynamic|本机收据 row-27|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|28|memory-dynamic|本机收据 row-28|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|29|memory-dynamic|本机收据 row-29|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|30|memory-dynamic|本机收据 row-30|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|31|memory-dynamic|本机收据 row-31|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|32|memory-dynamic|本机收据 row-32|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|33|memory-dynamic|本机收据 row-33|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|34|memory-dynamic|本机收据 row-34|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|35|memory-dynamic|本机收据 row-35|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|36|memory-dynamic|本机收据 row-36|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|37|memory-dynamic|本机收据 row-37|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|38|memory-dynamic|本机收据 row-38|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|39|memory-dynamic|本机收据 row-39|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|40|memory-dynamic|本机收据 row-40|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|41|memory-dynamic|本机收据 row-41|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|42|memory-dynamic|本机收据 row-42|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|43|memory-dynamic|本机收据 row-43|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|44|memory-dynamic|本机收据 row-44|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|45|memory-dynamic|本机收据 row-45|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|46|memory-dynamic|本机收据 row-46|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|47|memory-dynamic|本机收据 row-47|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|48|memory-dynamic|本机收据 row-48|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|49|memory-dynamic|本机收据 row-49|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|50|memory-dynamic|本机收据 row-50|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|51|memory-dynamic|本机收据 row-51|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|52|memory-dynamic|本机收据 row-52|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|53|memory-dynamic|本机收据 row-53|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|54|memory-dynamic|本机收据 row-54|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|55|memory-dynamic|本机收据 row-55|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|56|memory-dynamic|本机收据 row-56|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|57|memory-dynamic|本机收据 row-57|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|58|memory-dynamic|本机收据 row-58|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|59|memory-dynamic|本机收据 row-59|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|60|memory-dynamic|本机收据 row-60|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|61|memory-dynamic|本机收据 row-61|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|62|memory-dynamic|本机收据 row-62|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|63|memory-dynamic|本机收据 row-63|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|64|memory-dynamic|本机收据 row-64|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|65|memory-dynamic|本机收据 row-65|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|66|memory-dynamic|本机收据 row-66|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|67|memory-dynamic|本机收据 row-67|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|68|memory-dynamic|本机收据 row-68|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|69|memory-dynamic|本机收据 row-69|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|70|memory-dynamic|本机收据 row-70|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|71|memory-dynamic|本机收据 row-71|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|72|memory-dynamic|本机收据 row-72|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|73|memory-dynamic|本机收据 row-73|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|74|memory-dynamic|本机收据 row-74|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|75|memory-dynamic|本机收据 row-75|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|76|memory-dynamic|本机收据 row-76|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|77|memory-dynamic|本机收据 row-77|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|78|memory-dynamic|本机收据 row-78|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|79|memory-dynamic|本机收据 row-79|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|80|memory-dynamic|本机收据 row-80|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|81|memory-dynamic|本机收据 row-81|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|82|memory-dynamic|本机收据 row-82|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|83|backup-source|$MCPREPO\tools\i_memory\.state\v3-export\export-2026-10-02T16-43-19-893Z-ZkFPQ1\snapshot.sqlite|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|84|memory-dynamic|本机收据 row-84|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|85|memory-dynamic|本机收据 row-85|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|86|memory-dynamic|本机收据 row-86|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|87|memory-dynamic|本机收据 row-87|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|88|memory-dynamic|本机收据 row-88|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|89|memory-dynamic|本机收据 row-89|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|90|memory-dynamic|本机收据 row-90|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|91|memory-dynamic|本机收据 row-91|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|92|backup-source|$MCPREPO\tools\i_memory\i_memory_read.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True|1|PASS|
|93|mcp-data-roots|$MCPREPO\tools\i_remote_mcp\.state|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|94|mcp-dynamic|本机收据 row-94|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|95|mcp-dynamic|本机收据 row-95|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|96|mcp-dynamic|本机收据 row-96|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|97|mcp-dynamic|本机收据 row-97|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|98|backup-source|$MCPREPO\tools\i_remote_mcp\.state\core-frontend.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|99|mcp-dynamic|本机收据 row-99|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|100|mcp-dynamic|本机收据 row-100|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|101|mcp-dynamic|本机收据 row-101|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|102|mcp-dynamic|本机收据 row-102|Observe|Admin|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|103|mcp-dynamic|本机收据 row-103|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|104|mcp-dynamic|本机收据 row-104|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|105|mcp-dynamic|本机收据 row-105|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|106|mcp-dynamic|本机收据 row-106|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|107|mcp-dynamic|本机收据 row-107|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|108|mcp-dynamic|本机收据 row-108|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|109|mcp-dynamic|本机收据 row-109|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|110|mcp-dynamic|本机收据 row-110|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|111|mcp-dynamic|本机收据 row-111|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|112|mcp-dynamic|本机收据 row-112|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|113|mcp-dynamic|本机收据 row-113|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|114|mcp-dynamic|本机收据 row-114|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|115|mcp-dynamic|本机收据 row-115|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|116|mcp-dynamic|本机收据 row-116|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|117|mcp-dynamic|本机收据 row-117|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|118|mcp-dynamic|本机收据 row-118|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|119|mcp-dynamic|本机收据 row-119|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|120|mcp-dynamic|本机收据 row-120|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|121|mcp-dynamic|本机收据 row-121|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|122|mcp-dynamic|本机收据 row-122|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|123|mcp-dynamic|本机收据 row-123|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|124|mcp-dynamic|本机收据 row-124|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|125|mcp-dynamic|本机收据 row-125|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|126|mcp-dynamic|本机收据 row-126|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|127|mcp-dynamic|本机收据 row-127|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|128|mcp-dynamic|本机收据 row-128|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|129|backup-source|$MCPREPO\tools\i_remote_mcp\.state\oauth.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|130|mcp-dynamic|本机收据 row-130|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|131|mcp-dynamic|本机收据 row-131|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|132|backup-source|$MCPREPO\tools\i_remote_mcp\.state\phone-feed.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|133|mcp-dynamic|本机收据 row-133|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|134|mcp-dynamic|本机收据 row-134|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|135|mcp-dynamic|本机收据 row-135|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|136|mcp-dynamic|本机收据 row-136|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|137|mcp-dynamic|本机收据 row-137|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|138|mcp-dynamic|本机收据 row-138|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|139|mcp-dynamic|本机收据 row-139|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|140|mcp-dynamic|本机收据 row-140|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|141|mcp-dynamic|本机收据 row-141|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|142|mcp-dynamic|本机收据 row-142|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|143|mcp-dynamic|本机收据 row-143|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|144|mcp-dynamic|本机收据 row-144|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|145|mcp-dynamic|本机收据 row-145|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|146|mcp-dynamic|本机收据 row-146|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|147|mcp-dynamic|本机收据 row-147|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|148|mcp-dynamic|本机收据 row-148|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|149|mcp-dynamic|本机收据 row-149|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|150|mcp-dynamic|本机收据 row-150|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|151|mcp-dynamic|本机收据 row-151|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|152|mcp-dynamic|本机收据 row-152|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|153|mcp-dynamic|本机收据 row-153|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|154|mcp-dynamic|本机收据 row-154|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|155|mcp-dynamic|本机收据 row-155|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|156|mcp-dynamic|本机收据 row-156|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|157|mcp-dynamic|本机收据 row-157|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|158|mcp-dynamic|本机收据 row-158|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|159|mcp-dynamic|本机收据 row-159|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|160|mcp-dynamic|本机收据 row-160|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|161|mcp-dynamic|本机收据 row-161|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|162|mcp-dynamic|本机收据 row-162|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|163|mcp-dynamic|本机收据 row-163|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|164|mcp-dynamic|本机收据 row-164|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|165|mcp-dynamic|本机收据 row-165|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|166|mcp-dynamic|本机收据 row-166|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|167|mcp-dynamic|本机收据 row-167|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|168|mcp-dynamic|本机收据 row-168|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|169|mcp-dynamic|本机收据 row-169|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|170|mcp-dynamic|本机收据 row-170|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|171|mcp-dynamic|本机收据 row-171|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|172|mcp-dynamic|本机收据 row-172|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|173|mcp-dynamic|本机收据 row-173|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|174|mcp-dynamic|本机收据 row-174|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|175|mcp-dynamic|本机收据 row-175|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|176|mcp-dynamic|本机收据 row-176|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|177|mcp-dynamic|本机收据 row-177|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|178|mcp-dynamic|本机收据 row-178|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|179|mcp-dynamic|本机收据 row-179|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|180|mcp-dynamic|本机收据 row-180|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|181|mcp-dynamic|本机收据 row-181|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|182|mcp-dynamic|本机收据 row-182|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|183|mcp-dynamic|本机收据 row-183|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|184|mcp-dynamic|本机收据 row-184|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|185|mcp-dynamic|本机收据 row-185|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|186|mcp-dynamic|本机收据 row-186|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|187|mcp-dynamic|本机收据 row-187|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|188|mcp-dynamic|本机收据 row-188|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|189|mcp-dynamic|本机收据 row-189|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|190|mcp-dynamic|本机收据 row-190|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|191|mcp-dynamic|本机收据 row-191|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|192|mcp-dynamic|本机收据 row-192|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|193|mcp-dynamic|本机收据 row-193|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|194|mcp-dynamic|本机收据 row-194|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|195|mcp-dynamic|本机收据 row-195|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|196|mcp-dynamic|本机收据 row-196|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|197|mcp-dynamic|本机收据 row-197|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|198|mcp-dynamic|本机收据 row-198|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|199|mcp-dynamic|本机收据 row-199|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|200|mcp-dynamic|本机收据 row-200|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|201|mcp-dynamic|本机收据 row-201|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|202|mcp-dynamic|本机收据 row-202|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|203|mcp-dynamic|本机收据 row-203|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|204|mcp-dynamic|本机收据 row-204|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|205|mcp-dynamic|本机收据 row-205|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|206|mcp-dynamic|本机收据 row-206|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|207|mcp-dynamic|本机收据 row-207|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|208|mcp-dynamic|本机收据 row-208|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|209|mcp-dynamic|本机收据 row-209|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|210|mcp-dynamic|本机收据 row-210|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|211|mcp-dynamic|本机收据 row-211|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|212|mcp-dynamic|本机收据 row-212|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|213|mcp-dynamic|本机收据 row-213|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|214|mcp-dynamic|本机收据 row-214|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|215|mcp-dynamic|本机收据 row-215|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|216|mcp-dynamic|本机收据 row-216|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|217|mcp-dynamic|本机收据 row-217|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|218|mcp-dynamic|本机收据 row-218|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|219|mcp-dynamic|本机收据 row-219|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|220|mcp-dynamic|本机收据 row-220|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|221|mcp-dynamic|本机收据 row-221|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|222|mcp-dynamic|本机收据 row-222|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|223|mcp-dynamic|本机收据 row-223|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|224|mcp-dynamic|本机收据 row-224|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|225|mcp-dynamic|本机收据 row-225|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|226|mcp-dynamic|本机收据 row-226|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|227|mcp-dynamic|本机收据 row-227|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|228|mcp-dynamic|本机收据 row-228|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|229|mcp-dynamic|本机收据 row-229|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|230|mcp-dynamic|本机收据 row-230|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|231|mcp-dynamic|本机收据 row-231|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|232|mcp-dynamic|本机收据 row-232|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|233|mcp-dynamic|本机收据 row-233|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|234|mcp-dynamic|本机收据 row-234|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|235|mcp-dynamic|本机收据 row-235|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|236|mcp-dynamic|本机收据 row-236|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|237|mcp-dynamic|本机收据 row-237|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|238|mcp-dynamic|本机收据 row-238|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|239|mcp-dynamic|本机收据 row-239|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|240|mcp-dynamic|本机收据 row-240|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|241|mcp-dynamic|本机收据 row-241|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|242|mcp-dynamic|本机收据 row-242|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|243|mcp-dynamic|本机收据 row-243|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|244|mcp-dynamic|本机收据 row-244|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|245|mcp-dynamic|本机收据 row-245|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|246|mcp-dynamic|本机收据 row-246|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|247|mcp-dynamic|本机收据 row-247|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|248|mcp-dynamic|本机收据 row-248|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|249|mcp-dynamic|本机收据 row-249|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|250|mcp-dynamic|本机收据 row-250|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|251|mcp-dynamic|本机收据 row-251|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|252|mcp-dynamic|本机收据 row-252|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|253|mcp-dynamic|本机收据 row-253|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|254|mcp-dynamic|本机收据 row-254|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|255|mcp-dynamic|本机收据 row-255|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|256|mcp-dynamic|本机收据 row-256|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|257|mcp-dynamic|本机收据 row-257|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|258|mcp-dynamic|本机收据 row-258|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|259|mcp-dynamic|本机收据 row-259|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|260|mcp-dynamic|本机收据 row-260|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|261|mcp-dynamic|本机收据 row-261|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|262|mcp-dynamic|本机收据 row-262|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|263|mcp-dynamic|本机收据 row-263|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|264|mcp-dynamic|本机收据 row-264|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|265|mcp-dynamic|本机收据 row-265|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|266|mcp-dynamic|本机收据 row-266|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|267|mcp-dynamic|本机收据 row-267|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|268|mcp-dynamic|本机收据 row-268|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|269|mcp-dynamic|本机收据 row-269|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|270|mcp-dynamic|本机收据 row-270|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|271|mcp-dynamic|本机收据 row-271|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|272|mcp-dynamic|本机收据 row-272|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|273|mcp-dynamic|本机收据 row-273|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|274|mcp-dynamic|本机收据 row-274|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|275|mcp-dynamic|本机收据 row-275|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|276|backup-source|$MCPREPO\tools\i_remote_mcp\.state\runtime\remote-launch.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|277|mcp-dynamic|本机收据 row-277|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|278|mcp-dynamic|本机收据 row-278|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|279|mcp-dynamic|本机收据 row-279|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|280|backup-source|$MCPREPO\tools\i_remote_mcp\.state\runtime\start-remote.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|281|mcp-dynamic|本机收据 row-281|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|282|mcp-dynamic|本机收据 row-282|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|283|mcp-dynamic|本机收据 row-283|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|284|backup-source|$MCPREPO\tools\i_remote_mcp\.state\tailscale-cert-check\funnel.crt|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|285|mcp-dynamic|本机收据 row-285|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|286|backup-source|$MCPREPO\tools\i_remote_mcp\.state\tailscale-cert-check\funnel.key|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|287|mcp-dynamic|本机收据 row-287|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|288|backup-source|$MCPREPO\tools\i_remote_mcp\.state\writeback.sqlite|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|289|mcp-dynamic|本机收据 row-289|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|290|mcp-dynamic|本机收据 row-290|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|291|backup-source|$MCPREPO\tools\i_remote_mcp\diagnostics.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True|1|PASS|
|292|backup-source|$MCPREPO\tools\i_remote_mcp\mcp.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True|1|PASS|
|293|backup-source|$MCPREPO\tools\i_remote_mcp\oauth.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True|1|PASS|
|294|backup-source|$MCPREPO\tools\i_remote_mcp\server.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True|1|PASS|
|295|backup-source|$MCPREPO\tools\i_remote_mcp\writeback.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True|1|PASS|
|296|backup-source|$PROGRAMDATA\cloudflared\i-mcp\config.yml|P|Admin|False|本人:Allow:Read, Synchronize:inherited=True; Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True|1|PASS|
|297|backup-source|$PROGRAMDATA\cloudflared\i-mcp\i-mcp.json|P|Admin|False|本人:Allow:Read, Synchronize:inherited=True; Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True|1|PASS|
|298|backup-source|$USERPROFILE\.cloudflared\cert.pem|P|本人|False|其他主体:Allow:ReadAndExecute, Synchronize:inherited=True; SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|299|backup-source|$USERPROFILE\AppData\Local\Temp\hereiam-post-audit-private-20261006\core-backup.key.dpapi|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|300|backup-source|$USERPROFILE\AppData\Local\Temp\hereiam-post-audit-private-20261006\core-encrypted-backups\ae4cf1b2-5870-42be-a1dd-358539927f34.manifest.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|301|backup-source|$USERPROFILE\AppData\Local\Temp\hereiam-post-audit-private-20261006\core-encrypted-backups\ae4cf1b2-5870-42be-a1dd-358539927f34.sqlite.aes256gcm|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|302|backup-source|$USERPROFILE\AppData\Local\Temp\hereiam-post-audit-private-20261006\original-backup.aes256gcm|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|303|backup-source|$USERPROFILE\AppData\Local\Temp\hereiam-post-audit-private-20261006\original-backup.key.dpapi|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|304|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\manifest.json|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|305|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\runtime\node.exe|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|306|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\start_pinned_i_core.ps1|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|307|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\tools\i_core\i_core_server.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|308|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\tools\i_core\i_core_store.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|309|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\tools\i_core\send_shortcut_mail.ps1|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|310|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\tools\i_core\shortcut_mail_relay.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|311|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\tools\i_core\start_i_core_service.ps1|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|312|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\tools\i_core\strict_smtp_tls_validation.ps1|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|313|backup-source|$RUNTIME\candidates\b3-v4-phone-transcripts-20261003\verify_v4_state.mjs|P|本人|False|Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True; AuthenticatedUsers:Allow:Modify, Synchronize:inherited=True; Users:Allow:ReadAndExecute, Synchronize:inherited=True|1|PASS|
|314|dpapi|$MAINT\backup-key|B|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|315|core-external|$MAINT\backup-key|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|316|dpapi|$MAINT\backup-key\runtime-backup.dpapi|B|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|317|core-external|$MAINT\backup-key\runtime-backup.dpapi|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|318|backup-source|$MAINT\backup-key\runtime-backup.dpapi|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|319|backup-source|$MAINT\baseline-inputs\acl\precutover-acl.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|320|backup-source|$MAINT\baseline-inputs\components\phone-retained-20261006.sqlite|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|321|backup-source|$MAINT\baseline-inputs\initial-context.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|322|backup-source|$MAINT\baseline-inputs\operations\Cloudflared-failure-policy.txt|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|323|backup-source|$MAINT\baseline-inputs\operations\service-configurations.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|324|backup-source|$MAINT\baseline-inputs\operations\Tailscale-failure-policy.txt|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|325|backup-source|$MAINT\baseline-inputs\operations\tailscale-serve-status.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|326|backup-source|$MAINT\baseline-inputs\tasks\HereIAm-iCore.xml|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|327|backup-source|$MAINT\baseline-inputs\tasks\HereIAm-iRemoteMCP.xml|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|328|control-root|$MAINT\control-root|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|329|current-session|$SESSION|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|330|current-session|$SESSION\backup-status-fb0f3a63304744fc8a5db5c228f39260.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|331|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|332|current-session-root|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|333|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\guardian-lock.id|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|334|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\guardian-ready.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|335|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-1.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|336|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-10.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|337|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-11.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|338|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-12.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|339|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-13.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|340|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-14.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|341|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-15.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|342|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-16.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|343|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-17.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|344|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-18.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|345|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-19.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|346|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-2.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|347|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-20.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|348|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-21.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|349|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-22.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|350|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-23.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|351|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-24.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|352|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-25.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|353|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-26.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|354|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-3.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|355|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-4.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|356|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-5.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|357|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-6.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|358|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-7.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|359|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-8.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|360|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready-9.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|361|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ICoreSchema6Probe-da565566214c82a02a508517fece69a4.ready.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|362|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\launch.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|363|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\manifest.id|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|364|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\mcp-start.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|365|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\ready.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|366|current-session|$SESSION\control-9264cfeeea12438e877b84b4f23b5f41\stop.key|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|367|current-session|$SESSION\session-window.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|368|automatic-output|$MAINT\daily-backups|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|369|automatic-lock|$MAINT\daily-backups\.automatic.lock|OptionalB|||||NOT_CREATED|
|370|mcp-data-roots|$MAINT\mcp-identity|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|371|mcp-dynamic|本机收据 row-371|Observe|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|OBSERVED|
|372|backup-source|$MAINT\mcp-identity\identity.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|373|mcp-source|$MAINT\mcp-source|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|374|mcp-source|$MAINT\mcp-source\tools|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|375|mcp-source|$MAINT\mcp-source\tools\i_memory|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|376|mcp-source|$MAINT\mcp-source\tools\i_memory\i_memory_read.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|377|backup-source|$MAINT\mcp-source\tools\i_memory\i_memory_read.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|378|mcp-source|$MAINT\mcp-source\tools\i_remote_mcp|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|379|mcp-source|$MAINT\mcp-source\tools\i_remote_mcp\diagnostics.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|380|backup-source|$MAINT\mcp-source\tools\i_remote_mcp\diagnostics.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|381|mcp-source|$MAINT\mcp-source\tools\i_remote_mcp\mcp.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|382|backup-source|$MAINT\mcp-source\tools\i_remote_mcp\mcp.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|383|mcp-source|$MAINT\mcp-source\tools\i_remote_mcp\oauth.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|384|backup-source|$MAINT\mcp-source\tools\i_remote_mcp\oauth.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|385|mcp-source|$MAINT\mcp-source\tools\i_remote_mcp\server.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|386|backup-source|$MAINT\mcp-source\tools\i_remote_mcp\server.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|387|mcp-source|$MAINT\mcp-source\tools\i_remote_mcp\writeback.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|388|backup-source|$MAINT\mcp-source\tools\i_remote_mcp\writeback.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|389|backup-envelope|$MAINT\portable-key\portable-key.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|390|core-custody|$MAINT\recovery-custody|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|391|core-custody|$MAINT\recovery-custody\8871b93121a9b87dddf4b01832cafda785fe2ec684918e1bfea4146a2f7d0a69.floor.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|392|core-custody|$MAINT\recovery-custody\afe8d0842d57d1790df0dafbf81422327da5816ff9e6ec28b9ed0266e1d9bb35.head.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|393|core-custody|$MAINT\recovery-custody\current-head.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|394|backup-source|$MAINT\recovery-custody\current-head.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|395|core-custody|$MAINT\recovery-custody\custody.lock|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|396|core-custody|$MAINT\recovery-custody\d5d3a95f4a256b8a61a9c1e1d120bd6178474a7d7015afaf160c1435c14e5250.recovery.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|397|dpapi|$MAINT\recovery-key|B|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|398|core-external|$MAINT\recovery-key|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|399|dpapi|$MAINT\recovery-key\runtime-recovery.dpapi|B|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|400|core-external|$MAINT\recovery-key\runtime-recovery.dpapi|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|401|backup-source|$MAINT\recovery-key\runtime-recovery.dpapi|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|402|core-custody|$MAINT\runtime-backups|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|403|core-custody|$MAINT\runtime-backups\raw-d5c22d7c-909d-46da-b76b-7c8df9114961|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|404|core-custody|$MAINT\runtime-backups\raw-d5c22d7c-909d-46da-b76b-7c8df9114961\database-shm.aes256gcm|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|405|core-custody|$MAINT\runtime-backups\raw-d5c22d7c-909d-46da-b76b-7c8df9114961\database-wal.aes256gcm|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|406|core-custody|$MAINT\runtime-backups\raw-d5c22d7c-909d-46da-b76b-7c8df9114961\database.aes256gcm|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|407|core-custody|$MAINT\runtime-backups\raw-d5c22d7c-909d-46da-b76b-7c8df9114961\manifest.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|408|core-external|$MAINT\settings|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|409|mcp-config|$MAINT\settings|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|410|mcp-config|$MAINT\settings\mcp.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|411|backup-source|$MAINT\settings\mcp.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|412|core-external|$MAINT\settings\replay-approvals.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|413|backup-source|$MAINT\settings\replay-approvals.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|414|core-external|$MAINT\settings\transcript-grants.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|415|backup-source|$MAINT\settings\transcript-grants.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|416|backup-source|$APPROVAL\login-task.final-review.xml|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|417|core-config|$APPROVAL\settings|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|418|login-config|$APPROVAL\settings|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|419|core-config|$APPROVAL\settings\core.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|420|backup-source|$APPROVAL\settings\core.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|421|backup-config|$APPROVAL\settings\daily-backup-config.json|B|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|FAIL|
|422|backup-source|$APPROVAL\settings\daily-backup-config.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|423|login-config|$APPROVAL\settings\login.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|424|backup-source|$APPROVAL\settings\login.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|425|mcp-executable|$RUNTIME\releases\schema6-20261007-1552e251\runtime\node.exe|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|426|release|$RELEASE|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|427|release|$RELEASE\manifest.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|428|backup-source|$RELEASE\manifest.json|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|429|release|$RELEASE\runtime|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|430|release|$RELEASE\runtime\node.exe|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|431|backup-source|$RELEASE\runtime\node.exe|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|432|release|$RELEASE\tools|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|433|release|$RELEASE\tools\i_core|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|434|release|$RELEASE\tools\i_core\activity_control_plane.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|435|backup-source|$RELEASE\tools\i_core\activity_control_plane.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|436|release|$RELEASE\tools\i_core\domain_http.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|437|backup-source|$RELEASE\tools\i_core\domain_http.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|438|release|$RELEASE\tools\i_core\domain_migrate.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|439|backup-source|$RELEASE\tools\i_core\domain_migrate.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|440|release|$RELEASE\tools\i_core\domain_schema.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|441|backup-source|$RELEASE\tools\i_core\domain_schema.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|442|release|$RELEASE\tools\i_core\domain_store.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|443|backup-source|$RELEASE\tools\i_core\domain_store.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|444|release|$RELEASE\tools\i_core\i_core_server.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|445|backup-source|$RELEASE\tools\i_core\i_core_server.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|446|release|$RELEASE\tools\i_core\i_core_store.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|447|backup-source|$RELEASE\tools\i_core\i_core_store.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|448|release|$RELEASE\tools\i_core\inspection_read_only.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|449|backup-source|$RELEASE\tools\i_core\inspection_read_only.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|450|release|$RELEASE\tools\i_core\personal_data_domains.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|451|backup-source|$RELEASE\tools\i_core\personal_data_domains.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|452|release|$RELEASE\tools\i_core\release_schema6|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|453|release|$RELEASE\tools\i_core\release_schema6\automatic_backup.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|454|backup-source|$RELEASE\tools\i_core\release_schema6\automatic_backup.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|455|release|$RELEASE\tools\i_core\release_schema6\automatic_recovery.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|456|backup-source|$RELEASE\tools\i_core\release_schema6\automatic_recovery.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|457|release|$RELEASE\tools\i_core\release_schema6\backup_bundle_schema6.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|458|backup-source|$RELEASE\tools\i_core\release_schema6\backup_bundle_schema6.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|459|release|$RELEASE\tools\i_core\release_schema6\backup_bundle.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|460|backup-source|$RELEASE\tools\i_core\release_schema6\backup_bundle.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|461|release|$RELEASE\tools\i_core\release_schema6\backup_key_child.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|462|backup-source|$RELEASE\tools\i_core\release_schema6\backup_key_child.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|463|release|$RELEASE\tools\i_core\release_schema6\cli.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|464|backup-source|$RELEASE\tools\i_core\release_schema6\cli.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|465|release|$RELEASE\tools\i_core\release_schema6\key_custody.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|466|backup-source|$RELEASE\tools\i_core\release_schema6\key_custody.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|467|release|$RELEASE\tools\i_core\release_schema6\lifecycle|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|468|release|$RELEASE\tools\i_core\release_schema6\lifecycle\common.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|469|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\common.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|470|release|$RELEASE\tools\i_core\release_schema6\lifecycle\configuration.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|471|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\configuration.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|472|release|$RELEASE\tools\i_core\release_schema6\lifecycle\job_guardian.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|473|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\job_guardian.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|474|release|$RELEASE\tools\i_core\release_schema6\lifecycle\login_schema6.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|475|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\login_schema6.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|476|release|$RELEASE\tools\i_core\release_schema6\lifecycle\mcp_configuration.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|477|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\mcp_configuration.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|478|release|$RELEASE\tools\i_core\release_schema6\lifecycle\offline_lease.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|479|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\offline_lease.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|480|release|$RELEASE\tools\i_core\release_schema6\lifecycle\offline_probe_client.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|481|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\offline_probe_client.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|482|release|$RELEASE\tools\i_core\release_schema6\lifecycle\owned_job.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|483|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\owned_job.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|484|release|$RELEASE\tools\i_core\release_schema6\lifecycle\prepare_login_schema6.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|485|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\prepare_login_schema6.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|486|release|$RELEASE\tools\i_core\release_schema6\lifecycle\probe_offline.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|487|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\probe_offline.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|488|release|$RELEASE\tools\i_core\release_schema6\lifecycle\protected_paths.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|489|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\protected_paths.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|490|release|$RELEASE\tools\i_core\release_schema6\lifecycle\request_stop.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|491|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\request_stop.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|492|release|$RELEASE\tools\i_core\release_schema6\lifecycle\runtime_child.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|493|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\runtime_child.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|494|release|$RELEASE\tools\i_core\release_schema6\lifecycle\session_window.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|495|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\session_window.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|496|release|$RELEASE\tools\i_core\release_schema6\lifecycle\start_schema6.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|497|backup-source|$RELEASE\tools\i_core\release_schema6\lifecycle\start_schema6.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|498|release|$RELEASE\tools\i_core\release_schema6\package.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|499|backup-source|$RELEASE\tools\i_core\release_schema6\package.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|500|release|$RELEASE\tools\i_core\release_schema6\portable_backup_schema6.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|501|backup-source|$RELEASE\tools\i_core\release_schema6\portable_backup_schema6.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|502|release|$RELEASE\tools\i_core\release_schema6\portable_key_custody.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|503|backup-source|$RELEASE\tools\i_core\release_schema6\portable_key_custody.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|504|release|$RELEASE\tools\i_core\release_schema6\preflight_schema6.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|505|backup-source|$RELEASE\tools\i_core\release_schema6\preflight_schema6.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|506|release|$RELEASE\tools\i_core\release_schema6\preflight.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|507|backup-source|$RELEASE\tools\i_core\release_schema6\preflight.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|508|release|$RELEASE\tools\i_core\release_schema6\raw_state_backup.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|509|backup-source|$RELEASE\tools\i_core\release_schema6\raw_state_backup.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|510|release|$RELEASE\tools\i_core\release_schema6\README.md|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|511|backup-source|$RELEASE\tools\i_core\release_schema6\README.md|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|512|release|$RELEASE\tools\i_core\release_schema6\readonly_witness.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|513|backup-source|$RELEASE\tools\i_core\release_schema6\readonly_witness.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|514|release|$RELEASE\tools\i_core\release_schema6\recovery_adapter.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|515|backup-source|$RELEASE\tools\i_core\release_schema6\recovery_adapter.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|516|release|$RELEASE\tools\i_core\release_schema6\recovery_witness_worker.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|517|backup-source|$RELEASE\tools\i_core\release_schema6\recovery_witness_worker.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|518|release|$RELEASE\tools\i_core\release_schema6\restore_inspection.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|519|backup-source|$RELEASE\tools\i_core\release_schema6\restore_inspection.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|520|release|$RELEASE\tools\i_core\release_schema6\scheduler_once_schema6.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|521|backup-source|$RELEASE\tools\i_core\release_schema6\scheduler_once_schema6.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|522|release|$RELEASE\tools\i_core\send_shortcut_mail.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|523|backup-source|$RELEASE\tools\i_core\send_shortcut_mail.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|524|release|$RELEASE\tools\i_core\shortcut_mail_relay.mjs|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|525|backup-source|$RELEASE\tools\i_core\shortcut_mail_relay.mjs|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|526|release|$RELEASE\tools\i_core\strict_smtp_tls_validation.ps1|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|527|backup-source|$RELEASE\tools\i_core\strict_smtp_tls_validation.ps1|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|528|core-state|$CORESTATE|GRoot|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|529|core-state|本机收据 row-529|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|530|core-state|本机收据 row-530|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|531|core-state|本机收据 row-531|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|532|core-state|本机收据 row-532|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|533|core-state|本机收据 row-533|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|534|core-state|本机收据 row-534|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|535|core-state|本机收据 row-535|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|536|core-state|本机收据 row-536|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|537|core-state|本机收据 row-537|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|538|core-state|本机收据 row-538|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|539|core-state|本机收据 row-539|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|540|core-state|本机收据 row-540|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|541|core-state|本机收据 row-541|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|542|core-state|本机收据 row-542|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|543|core-state|本机收据 row-543|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|544|core-state|本机收据 row-544|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|545|core-state|本机收据 row-545|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|546|core-state|$CORESTATE\backups\b3-writeback-20261003\i-core.sqlite|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|547|core-state|$CORESTATE\backups\b3-writeback-20261003\i-core.sqlite-shm|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|548|core-state|$CORESTATE\backups\b3-writeback-20261003\i-core.sqlite-wal|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|549|core-state|本机收据 row-549|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|550|core-state|本机收据 row-550|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|551|core-state|本机收据 row-551|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|552|core-state|本机收据 row-552|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|553|core-state|本机收据 row-553|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|554|core-state|本机收据 row-554|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|555|core-state|本机收据 row-555|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|556|core-state|本机收据 row-556|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|557|core-state|本机收据 row-557|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|558|core-state|本机收据 row-558|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|559|core-state|本机收据 row-559|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|560|core-state|本机收据 row-560|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|561|core-state|本机收据 row-561|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|562|core-state|本机收据 row-562|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|563|core-state|本机收据 row-563|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|564|core-state|本机收据 row-564|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|565|core-state|本机收据 row-565|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|566|core-state|本机收据 row-566|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|567|core-state|本机收据 row-567|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|568|core-state|本机收据 row-568|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|569|core-state|本机收据 row-569|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|570|backup-source|$CORESTATE\historical-replay-approvals.json|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|571|core-state|$CORESTATE\i-core.sqlite|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|572|backup-source|$CORESTATE\i-core.sqlite|P|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|573|core-state|$CORESTATE\i-core.sqlite-shm|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|574|core-state|$CORESTATE\i-core.sqlite-wal|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|575|core-state|本机收据 row-575|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|576|core-state|本机收据 row-576|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|577|core-state|本机收据 row-577|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|578|core-state|本机收据 row-578|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|579|core-state|本机收据 row-579|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|580|core-state|本机收据 row-580|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|581|core-state|本机收据 row-581|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|582|core-state|本机收据 row-582|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|583|backup-source|$CORESTATE\local-transcript-grants.json|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|584|core-state|本机收据 row-584|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|585|core-state|$CORESTATE\s6-lifecycle.json|G|本人|False|SYSTEM:Allow:FullControl:inherited=True; Admin:Allow:FullControl:inherited=True; 本人:Allow:FullControl:inherited=True|1|PASS|
|586|core-state|本机收据 row-586|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|587|backup-source|$CORESTATE\shortcut-mail-journal.sqlite|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|588|core-state|本机收据 row-588|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|589|core-state|本机收据 row-589|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|590|core-state|本机收据 row-590|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|591|backup-source|$CORESTATE\shortcut-mail-relay.json|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|592|core-state|$CORESTATE\shortcut-mail-relay.runtime.lock|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|593|core-state|本机收据 row-593|G|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|594|backup-source|$CORESTATE\shortcut-mail-smtp.credential.clixml|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|595|backup-source|$NODE\node.exe|P|SYSTEM|False|Users:Allow:ReadAndExecute, Synchronize:inherited=True; AuthenticatedUsers:Allow:ReadAndExecute, Synchronize:inherited=True; Admin:Allow:FullControl:inherited=True; SYSTEM:Allow:FullControl:inherited=True|1|PASS|
|596|t9-root|$T9|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; Admin:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|597|t9-top-level|本机收据 row-597|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
|598|automatic-mirror|$T9\daily|P|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|PASS|
|599|t9-top-level|本机收据 row-599|Observe|本人|True|SYSTEM:Allow:FullControl:inherited=False; 本人:Allow:FullControl:inherited=False|1|OBSERVED|
