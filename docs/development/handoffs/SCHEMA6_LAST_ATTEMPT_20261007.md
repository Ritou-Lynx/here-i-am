# 最后一次切换与 10/09 晚间备份（2026-10-07）

本轮最后一次正式尝试使用新的窗口 ID，r02 及其锁、回执、日志原样保留。截止 **北京时间 2026-10-09 18:00**；此前必须完成四项真人验收，缺一项即“切换未完成”。源修复、CI 或合成通过不延长截止。

## 进入顺序

1. 完整系统修复提升 writer 的新工件 owner；既有证据只核验、不修写。见[完整工件库存](SCHEMA6_ELEVATED_ARTIFACT_INVENTORY_20261007.md)。
2. Hosted Windows 必跑真实提升 ACL Apply（合成144项）→ 同SID普通消费者 → 固定 Prepare → 安全派生的禁用无触发任务 CREATE/真实 COM 回读/删除。核实际token，生产XML仍待现场注册，测试不能冒充已执行。
3. 准确源码提交全部 CI 成功后，以新只读 ID 完整执行首个改动前检查，包括 PR16 在线判据、模板逐字相同、结束全套复核。
4. 六批准 hash、实时父SD、固定47项字节未变，演练零失败，才使用已有条件预授权。管理员操作、口令安全输入、真人关机/登录、手机与claude.ai测试仍由主窗叫本人。
5. 生产 settings 不可清理且保持原位置；不重复加固已经通过的单目录，不复用旧Apply回执。当次重核原144库存、两旧任务/完整树/端口。

## 截止与安全退回

- 到点或错过触发，停止新现场尝试、冻结、注册或切换写入，上海再继续；已经完成四Gate的现场不反向操作。
- 未产生pending或库存漂移、未跨提交且原件/外锚与144项完全吻合时，按受审次序恢复原owner/DACL、旧任务定义/权限，Core→MCP启动并核schema4、单实例、完整树、端口。
- pending或临时副本造成库存变化，即使尚未替换，也不能盲跑144项Rollback或删除新项；保全现场并报审。
- commitStarted、替换、head推进、新接受写入任一发生或无法排除，只向前修；不降库、退head或盲启v4。截止不授权破坏安全边界。
- 冻结前留足当次30分钟窗口及真人响应时间；不足就不开始，不能为赶时间省略检查。

## 四项真人验收

| 项目 | 完成判据 |
|---|---|
| MCP处理真实请求后正常关机 | read model确实开过；同次安全关闭回执、Core/guardian正常退出、所属Job空、clean_closed及文件释放全齐，MCP+Core计入30秒 |
| 本人开机登录后自动启动 | 批准登录任务自动触发，新的session/control、schema6 ready、Core/MCP单实例，不手动启动代替 |
| 手机同步 | 原App/原配置实际同步耐久接受、队列不丢，不启PR10、不装手机 |
| claude.ai写入 | 真实客户端成功与Core耐久接受；health/metadata或waiting_for_retry不算 |

逐步骤未验证部分及失败边界见[Prepare后16阶段表](SCHEMA6_POST_PREPARE_GATES_20261007.md)。

## 10/09 晚间完整备份与实际恢复

本线程已安排一次性 **10/09 18:00截止检查、20:00备份执行**。这是未来操作安排，不是备份或验收已完成。本机需开机且Codex在运行；离线时不能保证准时触发。错过截止不补开切换尝试，备份按实际时间报告。

无论切换成功、退回或停审，先确认真正现役的包/schema/数据库，再用已受审工具创建新的一套完整加密备份。不在原址替换/提交期间并行备份，不按旧盘符或旧schema推断。

1. 重核Samsung PSSD T9（F211007Y0LNUK7S）、卷身份、NTFS及批准镜像目的地。非NTFS或身份不同停下告知本人，不格式化。
2. 九类逐项覆盖：数据库及一致性信息、发行包、配置、任务定义/权限、凭据与MCP .state、i_memory policy/快照、transcript grant、72 replay审批、恢复custody/独立head。隧道/Tailscale配置和已授权手机库副本纳入相应清单；Tailscale机器私钥按本人决定不备份。实际数量/缺项原因逐项记录，不沿用旧116文件数字。
3. 固定backup_bundle_schema6.ps1的Create/Verify或批准Automatic流程，spec/config新hash绑定。核DPAPI与恢复口令envelope；需要口令只开安全窗口叫本人，不进聊天、仓库、日志、命令行。
4. 新隔离目录执行RestoreInspection，或RestorePortable口令还原；不覆盖现役、不启动writer/注册任务/改手机。实际只读检查恢复库的node_id、schema、设备、每表计数/指纹、写入拒绝与检查前后库字节；只有密文hash不算恢复。
5. 签收本机密文、T9镜像、envelope/binding、实际恢复回执与耗时。关键提交或USB离线则明确延后，不伪报成功。

本地运行前提参考[OpenAI Automations文档](https://learn.chatgpt.com/docs/automations)。口令备份在新电脑建立新现役Core（重绑DPAPI、独立恢复密钥/current-head/配置路径）仍为下一轮缺口，不在本次只读还原内执行。
