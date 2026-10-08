# R03 真人关机/开机验收：正常清停未通过（2026-10-08）

截至北京时间约09:27：新Core/MCP在线，自动异常恢复及新会话自动备份均已运行成功；**正常关机clean-close未通过，完整切换验收未完成**。本人明确“直接正常关机，没出现提示”，没有点强制关闭。保留现役，原址/head已推进，只能向前修；本轮不重新关机、不启停服务、不改运行包、任务、ACL、配置或手机。

## 1. 现场时间线

|北京时间|证据|
|---|---|
|09:08:35.172|旧MCP真实i_recall HTTP200/success；同代PID1944|
|09:11:20.800|最终只读关机前preflight通过，旧六份终态回执均不存在，hook_ready=true|
|09:14:40.819|System/User32 1074，record884409|
|09:15:23.708|System/EventLog 6006，record884427|
|09:15:28.603|System/Kernel-Power 109，record884445|
|09:15:38.638|System/Kernel-General 13，record884447|
|09:16:12.500|Win32_OperatingSystem.LastBootUpTime|
|09:16:13.365|System/Kernel-General 12，record884448|
|09:16:35|HereIAm-CoreSchema6-Session.LastRun；新会话进程11204开始|
|09:17:02.410|新session-window.json，hook_ready=true|
|09:17:21.598|automatic_crash_recovery事件时间，随后head generation2|
|09:17:23.352|新MCP PID17944启动，绑定Core PID25840 ready|
|09:21:05之后|新backup-status显示backup_completed/success=true；下一尝试2026-10-09 09:21:05.606北京时间|

查询窗口09:10–09:18未发现System 6008或Kernel-Power 41。它与本人的正常关机观察相符；不把系统正常结束误写成应用已clean-close。

TaskScheduler Operational日志实际disabled，未更改/启用，不能提供独立的trigger事件证据。AtLogon已批准模板、任务LastRun、新会话时间及主窗没有手动Run共同支持本次登录自动启动；当前进程11204/25840/17944均SessionId=1，但不能将新实例SessionId回推旧实例。

## 2. 正常清停：不通过

旧session：session-c6034acb52324b2d93592a74a222f2ec；旧control：control-9264cfeeea12438e877b84b4f23b5f41。主窗与独立worker均只读确认：

|旧位置|终态回执|结果|
|---|---|---|
|control|mcp-stop.json|不存在|
|control|session-close.json|不存在|
|control|supervisor.json|不存在|
|control|child.json|不存在|
|control|guardian.json|不存在|
|session|session-exit.json|不存在|

旧session最后写入仍为00:25:09，没有本次关闭的新增终态。旧launch.json仍在、绑定批准固定候选，但其存在不能补证明结束过程。

因此无法确认：MCP停止方式/退出码/Job空/句柄释放；Core是否未强杀、child/guardian exit0、锁释放、DB独占打开；以及总耗时是否满足共同30秒预算。**不填写臆测的运行失败码，不把端口消失、Windows关机完成或下一次恢复成功补签clean-close。** 此次也无法实测正常关闭总耗时。

## 3. 自动恢复与当前服务：已恢复在线

新session：session-a72347032f7e4923b7220317a1116a5f；新control：control-60693dddc6df4f9ea8824e24ab8112cd。

- 新任务enabled/running；两旧Core/MCP任务仍disabled。未由主窗手动启动。
- Core schema6、node前缀9d634309未变；47841由25840监听；47860/47862由17944监听。
- MCP ready绑定Core PID与同代身份均匹配；固定manifest仍3b7e210b…147fa0，无未解决pending。
- 新恢复事件kind=automatic_crash_recovery，head generation2、直接前任为gen1。
- raw-d717291b-1747-4586-8277-728550df106c保存DB/WAL/SHM流式加密文件与manifest；manifest摘要977193cf…0591a等于恢复事件中的rawManifestSha256。未解密raw或读取正文。
- head→floor文件摘要→恢复事件→直接前任head及ready身份/config/manifest/node的元数据绑定全部通过。没有读取恢复密钥或独立重算MAC；不是另做一次全库恢复检查。

恢复事件SHA256：171e99e13769d660ed727735d53a5d0d9e7d88281abbd445276b827a332a4167。
current-head SHA256：db11d0e7d963fd690f29fb2f7c0237f45413a502e7378c55835d3932e389d047。
floor SHA256：7878222bdc007613b25ceab6d70db81ed703a6c2548736fd3ea757207508a5da。

## 4. 数据与自动备份边界

固定工具短时只读一致副本核对：消息7068、变更7068、设备7；关机前六条测试消息7064–7069及相应事件全部存在。claude两轮的四条ledger均committed，全部ledger268条committed，pending/rejected均0。这里只证明所核六条没有丢失，不扩大为全部业务数据逐行比对。临时副本已关闭删除；没有选择正文或凭据。

新会话backup-status-fee1af2740354cf3a66853d145375f46.json：
status=backup_completed、success=true，SHA256 b8230651359334bcebcec38af5b8cc66c630f9cf619766db9feb814bacd39782。这是新登录后的自动调度成功回执；本轮没有再做该新包的实际还原或签收T9镜像细节。

此前01:35本机/T9九类130文件手动备份与01:38实际T9还原结果仍有效于其原时点。日常静态清单的动态custody/任务快照覆盖缺口仍列原后续范围，不能因worker成功就宣称已补齐新gen2恢复链；换机激活缺口也仍在。

## 5. 已证实源码问题与根因边界

固定session_window.ps1第343行在WM_ENDSESSION等待finished后仅BeginInvoke(Close)，返回后才由OnFormClosed第359行发布session-exit。微软明确全部应用返回该消息后，会话可随时结束；把必需耐久回执留在返回后的UI回调有发布竞态。[WM_ENDSESSION官方说明](https://learn.microsoft.com/en-us/windows/win32/shutdown/wm-endsession)

**这只能解释session-exit丢失，不能单独解释本次更早的MCP-stop/session-close等六份回执全部不存在。真实根因尚未证实。**

隐藏窗口不能直接作为根因：固定实现已经成功登记ShutdownBlockReasonCreate后才写hook_ready，微软文档说明已登记理由的隐藏窗口可按可见窗口处理。[官方关机机制说明](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/mpc/application-shutdown-changes-in-windows-vista) AllowHardTerminate=false也不是操作系统关机豁免，不能据此认定任务引擎强杀。[属性官方说明](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-allowhardterminate)

旧回执没有记录SessionId/window station/desktop或关机消息入口，现有证据无法区分未收到消息、收到后被结束、或发布失败。窗口Message入口、阶段边界、退出发布与实际Session绑定是下一轮最窄调查范围。没有对现役HWND发送消息、模拟SessionEnding或启用诊断事件日志。

## 6. 后续复验建议（本轮不执行）

1. 在独立测试进程和临时目录复用相同隐藏窗/理由登记/消息处理，用假Core/MCP worker记录QUERY/ENDSESSION进入、每阶段结束、回执flush、handler返回和OnFormClosed。
2. 先实跑可证实的“ENDSESSION返回后、排队Close前结束测试进程”竞态，再验证消息泵、worker延迟及写回延迟；合成结果不能替代真实关机。
3. 源码修复须保留MCP先停、Core认证关闭、strictClosedPath/NativeLease/ACL/plainPath及共同30秒预算。允许MCP有界force要如实标记，Core强杀不算clean。
4. 修复、专项/完整CI及新候选审阅完成后，再申请精确新运行包批准和一次真人复验；本轮不私自覆盖已批准47项。
5. 新登录后的实际MCP请求及客户端复测尚未取得；此前两客户端Gate保留关机前通过阶段，不冒充本次开机后完整验收。**不宣布切换完成，不盲退v4。**

本人另报MCP记忆卡快照停在10/2，仅列后续待查；当前不更换MCP或读取快照正文。

## 7. 本机无正文证据索引

同一维护根下manual-backups/human-gates-8803c4bd30ba495e8c213bc04456e655：

- final-shutdown-preflight.json：0b0887ca4a6bd399e1292ede6ea55df5b0c74dab05256f6c98fd009249d8efb9。
- postboot-metadata.json：0a06393b877e8b07d5b25311a71c4123c5d0f8a0676002704c592fc484df0a6f。
- postboot-chain-bindings.json：7ce31cf7d1be04f1fc25b928f6a6b7ed8ef06576bc866c4ca1a37798a4f34cac。

原postboot投影的headCustodyMatches将custody JSON摘要误比为database摘要，属于不同对象类型；正确绑定是head.custodySha256等于floor文件SHA256。已按固定recovery_adapter第378–379行重新核对为true，并保存后者独立纠正回执，未改任何原恢复链文件。错误投影留证，不把它当运行故障。

独立worker复核旧六回执缺失，不能补签clean-close；普通沙箱初始化有registry拒绝，沙箱外授权只读成功。诊断工具的沙箱访问失败与现役恢复/库完整性不是一回事。
