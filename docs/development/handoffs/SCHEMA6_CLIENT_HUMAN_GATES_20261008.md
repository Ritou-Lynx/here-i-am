# R03 客户端真人验收（2026-10-08）

截至北京时间 08:59，手机同步及 claude.ai 公网写入两项已通过；正常关机 clean-close 与开机登录自动启动尚未执行。**切换未完成，只能向前修复。**

## 基线与范围

- 正式 checkout：codex/core-preflight-readonly-20261007 / 25e4b4fd3adf12d99ece3088966080f54bd34b9b。该提交 CI 八项与 PR Policy 共九项均 completed/success；[CI 37661468625](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37661468625)、[Policy 37661463008](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37661463008)。
- 固定候选 manifest 仍为 3b7e210b…147fa0。Core health schema6、原 node 前缀 9d634309；47841/PID46896、47860及47862/PID1944。两旧任务 disabled，新会话任务 enabled/running，仍是00:24手动Run的一代，不能算已验证登录自动触发。
- 实际 MCP server SHA256 adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6，与批准字节一致；MCP PID1944自00:25:07以来未换进程。
- 仅用固定 captureConsistentSqlite 制作短时只读一致副本，查询 ID/时间/序号/状态及计数；没有 SELECT content、payload_json、凭据字段。副本连接均已关闭，本次临时副本已删除；只保留本人/SYSTEM保护目录中的元数据证据。不修改原库、生产配置、服务、任务或手机。

## 已通过的两项

|项|本人结果|主机耐久证据|结论|
|---|---|---|---|
|claude.ai 写入|本人报约08:52同步成功|用户/回复对应Core序号7064/7065；MCP账本两条committed、error_code为空，全部pending/rejected为0；逐条完整sync_id、origin_sequence、server_sequence及event.entity_id匹配，Core恰好一行|通过|
|手机同步|本人报约08:54发送成功，随后明确“已看到回复，无异常”|现装1.0.30+113的Android设备前缀962d78a6-6db，origin_sequence644/645，对应Core7066/7067；设备last_ack_sequence=7067|通过|

claude.ai Core入库时间为08:52:37.410和08:52:57.741；手机用户/回复Core入库为08:53:41.478和08:54:03.964。仅据元数据记录时间，不保存消息正文。Core同期总消息/变更各7066，设备7；序号存在历史间隙，不能把最大序号误作数量。

两条claude.ai写回的sync_id仅公开SHA256前缀：96288c81abe52026、3127bc97c2126738。此次证据证明指定消息耐久落库和同ID关联；没有为了测试主动重发真实消息，不能扩大为全体消息的语义去重证明。

## MCP开库前置

08:52:39.925、08:52:57.754各有一次成功 i_chat_turn；08:52:46.980和08:52:48.936各有一次成功 i_recall，均为HTTP200。真实客户端来源由本人操作确认；ua_family=claude只是自报字段，不单独当身份认证。

固定MCP的工具处理调用lazy read model；成功i_recall实际查询该read model。结合进程未更换及固定实现直到shutdown才close缓存，已满足本代MCP实际开过Core库的前置；并未声称直接枚举过文件句柄。

08:52:02.215另有一条HTTP400，随后上述调用成功且写回耐久完成；现有诊断无该400的详细原因，不猜测为重初始化或鉴权故障。它不替代后续成功证据，也不被隐去。

若真实关机留至今晚，须在临近关机时再从本人claude.ai执行一次已授权 i_recall 或 i_chat_turn，核无正文成功回执后再关机，不能将早晨证据充作“立即关机前”证据。

## 本机证据与恢复读取入口

维护根使用现场清单中同一cutover维护根；相对目录：

manual-backups/human-gates-8803c4bd30ba495e8c213bc04456e655/

- metadata.json：08:56短时副本的投影、MCP诊断，bodyFieldsSelected=false，snapshotFilesRemoved=true。
- exact-links.json：SHA256 01b1bb55e2f1fd0d6659339ccb283c4fb922035b31fb5938ff1de62ae28807cd；08:59精确ID/事件关联全true，临时副本已删除。
- client-gates-confirmed.json：SHA256 cfde19177d0fad4c84dfc8ef30c89bc33dae14cee7070a5b56ddc6acc562e547；两客户端passed=true，其余Gate pending，cutoverCompleted=false。
- before-shutdown.json：SHA256 21b5f8776921e6d52321fb5c9ac5209722ce75eaea091112e754c9eeb738d865；保存旧session/control、任务及PID基线。它是关机前状态，不是关机终态证明。
- MCP mcp-start.json在当前control目录内，SHA256 014202b297bcd3266e0558fb782a04d9dae41c7f60a2dde240454903edfbf2ba；guardian-ready.json为4d429204ddcfb0e5ad62148b1627d7464894d7f2de6ea896d69c3b1b03197c55；ready.json为eb1f7b84cea465fad4b8e30fd85f82e078af81bcb3b78252303cfaddad6371a4。首个基线只收存在的白名单文件，不用缺席路径冒充新回执。

旧代session/control仍按[R03执行记录](SCHEMA6_R03_EXECUTION_20261008.md)保留；关机后核对应session-close/exit、MCP stop、Core clean_closed/guardian退出/30秒总预算，再核新登录任务触发及新代RunId/control。不得手动Run冒充自动触发，不删旧锁/回执或原head。

## 本人已选现在，待关机前最终MCP请求

本人已明确“现在做”。09:01–09:04只读复核：同代hook_ready=true、Core schema6健康、MCP/guardian等进程未更换；T9同设备且NTFS；六批准锚及固定47项大小/字节全部匹配。主窗已请本人在claude.ai紧接关机前再做一次i_recall，成功回执仍待。尚未叫本人正式关机，不能预写clean_closed或登录成功。接到本人结果并核无正文诊断后，保存最终基线，再由本人正常关机→开机→登录；主窗不代按关机、不发送模拟SessionEnding、不停止现役服务。四项全部通过后才签切换完成；10/09晚既定全量T9加密备份及实际还原另做。

## 09:11最终关机前签收
本人报告新i_recall成功；实际诊断09:08:35.172为HTTP200/success，同代MCP1944。09:11:20.800最终只读preflight通过，hook_ready、Core schema6/原node、进程、任务与T9绑定全部正确，旧终态回执尚不存在。final-shutdown-preflight.json SHA256 0b0887ca4a6bd399e1292ede6ea55df5b0c74dab05256f6c98fd009249d8efb9，保存在上述受保护证据目录。它明确shutdownExecuted=false/cutoverCompleted=false，不是关机验收结果。
前两次元数据筛选因PS7.6.5 ConvertFrom-Json把ISO时间解析为UTC DateTime，再经Parse(string)丢失时区，误报fresh_recall_success_missing；只读确认实际时间类型后改用DateTimeOffset直接转换，正确匹配09:08成功。只修正本轮核对脚本，未修改固定运行包/生产检查，不隐藏早先误判。
本人另报记忆卡快照停在10/2；仅列待查，未读取快照正文，不把本次Core切换及聊天同步通过称作新记忆卡检索上线。
下一步由本人Windows正常关机→待完全关机后开机→登录同一账户，保持T9连接；不手工启动Core/MCP或旧任务。返回本会话后核旧control终态与新自动会话，仍需开机后真实客户端复测。

## 关机后结果覆盖说明
本人已正常关机并开机登录；正常清停因旧六终态缺失未通过，新登录完成自动异常恢复及备份。此前两客户端通过仅是关机前阶段，不构成完整切换成功。详见[真人关机验收](SCHEMA6_REAL_SHUTDOWN_ACCEPTANCE_20261008.md)。
