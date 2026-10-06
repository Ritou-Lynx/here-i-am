# schema6 部署准备与现场切换边界（PR14 复核续作，2026-10-06）

继续 `codex/core-deploy-readiness-20261006`，base `v3-lab@90f23ce1d38628901e25b421d8f0f21c084f093b`。用户通过此前备份覆盖、真实检查还原及退回说明，要求 CI 修绿、日常自动运行与电脑外备份后更新同一草稿 PR 暂停。**本轮没有现场切换批准，不合主线、不碰现役 Core/MCP/隧道、原库、任务或手机。**

## 固定包与三条运行路径

Core、wrapper、恢复、备份与登录/关机工具从同一已提交 Git 树打包；Node 固定24.14.1，外部保管 manifest SHA。发行目录、state、control根、显式配置、密钥、custody 与备份各自 protected ACL、plain canonical路径。库存、链接、hardlink、owner/SYSTEM ACL检查不因 CI 或恢复变更放宽。生产 prepare 必须提供 MCP 会话配置；使用旧 MCP 固定同字节源码快照，server SHA256 保持 `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6`，不改其 CLI 程序字节。MCP 依赖和 Node 完整库存/hash纳入保护，源码快照与现有可变 `.state` 分离，状态/凭据不纳入源码重建或覆盖。该独立快照不冒充与新 Core 同一 Git 树。

| 路径 | 机制与限制 |
|---|---|
| 正常登录/关机 | 登录会话 launcher 每次新建空 control；Core ready 后由同一会话启动其拥有的 MCP Job；隐藏顶层窗口监听关机/注销，先停止备份派发，确认 MCP Job/树/句柄退出，再排空活动备份、认证 Core close 并等真实 Core/guardian/Job/锁回执。只在登录后运行，任务模板只写XML，不在本轮注册。 |
| 非正常退出 | 先关闭会话拥有的 MCP 树并确认 owned tree 句柄释放，排空/暂停未管理工具与脚本；SQLite 首开前真实离线租约排除 writer，原DB/WAL/SHM/journal流式加密并验证；在同一canonical绑定的隔离副本回放、完整性与独立custody/配置/schema检查。通过后记恢复事件、替换、推进head并正常启动。检查失败或迁移/提交中断停机等处理。 |
| 旧v4首次接管 | 未来现场获准冻结任务/结束绑定的进程树后，用相同保全/副本检查机制迁移4→5→6，全部通过才替换。旧进程终止不是clean close；获取真实offline lease与保全证据后才开始。无需单独不可重做adoption阶段链，独立最新custody仍不能回退。 |

新的自动恢复不激活备份副本，不由目标自己的历史签发已有5/6恢复floor。签名prefix保护已封存不可变操作/回执历史及单调序号；领域记录通过固定大小汇总绑定每条身份、revision和完整行HMAC，按已认证操作重建旧cut与当前物化行；下降或同revision改正文拒绝，递增须匹配完整已接受结果，见[大数据验收](SCHEMA6_SCALED_RECOVERY_20261006.md)。设备token合法重新配对不被固定为不可变。最后封存之后没有独立见证的每条ACK不在可证明范围，恢复后仍按原sync_id/op_id对账。

保持 `legacy_b3` 单一上传器、reply jobs/activity关闭、owner-managed领域策略；受限transcript/grant与exact72 replay保护保持。PR10开启另需源ID/队列与实际手机Gate，不能双开上传。captures真机增改删/用户改卡保护未过继续47862，切换时只一个消费者。

## 现场顺序（本轮未执行）

1. 审核精确源码提交、固定包manifest与CI/本机完整演练。复核完整九类备份：Core/副库/手机库；完整旧包；配置；任务；凭据（含MCP .state OAuth/writeback/前端与手机令牌）；owner policy和i_memory快照；transcript grant；外置与库内完整72 replay；独立custody/head。隧道/Tailscale配置按当次实际清单保全，机器私钥按用户决定排除。
2. 配置并实际验证口令包与电脑外密文副本。口令Lynx自己保管，固定工具安全提示输入，不放聊天/argv/env/仓库。外部目标后选，可配置；本机每天备份默认保留30天。对每份归档保留认证绑定回执，不能仅解密成功就声称恢复完成。
3. i提交现场停机窗口、任务动作、精确原包/Node/路径、原进程句柄/开始时间、端口及消费者清单，由Lynx批准。排除未知手动启动者；另行明确授权后停用 `\HereIAm-iRemoteMCP` 并禁用触发/失败重试，保存原任务设置。先停止旧 MCP 并确认完整进程树/句柄释放，再冻结旧 Core 的重试/触发并停止；未归新会话管理的工具/脚本须暂停排空。只读源码审计不等于全机无 reader。
4. 确认真进程退出、端口不再归旧PID、锁可真实独占、DB及sidecar无别的句柄。固定child与guardian/离线租约负责持锁；普通布尔JSON或“已Stop-ScheduledTask”不能代替。
5. 原文件流式加密保全并认证，保持原件。隔离副本用SQLite正常打开回放，4→5→6逐项核旧表/身份/设备/序号/grant/replay与默认关闭策略，checkpoint/关闭后再次immutable检查。准备期间原DB及sidecar摘要不变。
6. 通过后进入短提交区：原sidecar移入生成的受保护暂存区、合并后的单DB替换到原canonical路径、外置head推进。此多文件/目录过程不能成为一个SQLite事务；pending记录覆盖中断。替换开始后的中断保持停机并向前审查，不删pending自行重来。
7. 启动新固定包，核真实schema6/health、node/device/授权/72 replay行为、一个上传器、activity/jobs关闭；保留原桥。签发/注册新的登录任务前核InteractiveToken/LeastPrivilege/固定manifest与launcher config锚，不能默认开机无人登录运行。
8. MCP 由新 Core 交互式会话统一接管，Core ready 后才启动；旧独立任务保持禁用。手机安装/地址/上传配置各自另审；真机消费闭环后才退役47862。关机真人 Gate 前必须从 MCP 成功执行一次已授权 `i_recall` 或 `i_chat_turn`，使真实 read model 已开库；四项 Gate 的清停项包含 MCP 阶段回执，自动启动项包含新登录后 MCP 再成功处理请求。见[现场⑥.4与四项Gate](SCHEMA6_CUTOVER_FIELD_CHECKLIST_20261006.md)。

## 正常关闭与下一次登录

认证停止入口 `lifecycle/request_stop.ps1` 只发请求，`stop_requested`不是完成。实际listener/store关闭、child exit0、guardian exit0、Job空、无强杀、marker clean_closed、锁释放全部成立才是清停。可处理SIGINT/SIGTERM按实际关闭结果记账。Windows强制结束、超时、断电由下一登录的副本恢复处理，不要求Lynx每晚手动停。

关机hook在同一个 **30秒总预算**内先停止备份派发，确认 MCP Job/完整进程树退出及 owned tree 句柄释放，再结束活动备份托管Job，之后才请求Coreclose；三个阶段不能各自获得30秒。Windows `CREATE_NO_WINDOW` 下无法可靠投递 SIGTERM，MCP 当前方案是有限 grace（不超过3000毫秒）后必要时 force 会话拥有的 MCP Job，并明确记录 force，不能称为 MCP graceful。Core 自身 child/guardian 仍要求 exit0、无强杀、`clean_closed` 和锁释放；MCP 强杀许可不延伸到 Core。MCP 未完全退出或句柄未释放时不得继续 Core 离线恢复/替换；保留失败回执。隐藏窗口不能承诺无限阻止关机。纯睡眠不生成第二实例。关机取消而Core已经关闭时，先确认旧 MCP 树已清理，再由同会话用新control重开，Core ready 后重启 MCP；不得另启旧独立任务。具体OS界限和客户端停机表现见[运行说明](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)。

## 备份和只读恢复

普通完整备份仍拒绝sidecar；它与原始raw文件保全格式分开，不能放宽普通检查来冒充恢复。在线每天备份在私有目录制作SQLite一致副本，保存真实独立custody文件；归档检查上下文只供只读检查，不作为现役floor。多个库不是全局原子快照，工具仍标 `inventory_only` / `production_completeness_not_attested:true`。

backup/recovery键独立，CurrentUser DPAPI便利本机自启；backup键另有scrypt/AES-GCM口令包。口令-only入口完整认证后提取新检查目录、实际启动不可变只读Core，核node/schema/devices/全部用户表数量和指纹、整库字节哈希、业务403、关闭无sidecar/字节改变。备份里的launcher不运行，source_path不覆盖。不同用户/机器无法解开的其他组件DPAPI凭据需重新绑定/认证，不承诺复制密文即恢复所有服务。

[电脑外恢复](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)写口令、保留与镜像、新用户检查恢复、Tailscale重新登录/同名、47862/Serve/手机配置步骤。不同标准Windows SID的合成口令恢复已在一次性hosted CI实际通过两次，见结构化回执；本机未创建账号，另一实体电脑和生产激活未验，不用同用户子进程冒充跨账号证明。

## 退回

- 副本检查/迁移**替换前**失败：原DB/sidecar未动；保留原始密文、失败回执，先确认会话拥有的 MCP 树/句柄释放、候选writer全停及原schema4兼容后，按当次获准退回范围重开旧v4和旧MCP。副本迁移失败不是原库已经升级。
- 原位替换已开始、独立head已推进或新Core已经接受任何写入：不把旧库/旧v4覆盖回来，不恢复旧current-head。先清理会话拥有的 MCP 树并确认句柄释放，保持受影响writer停、其他工具/脚本暂停排空，保全新增内容和提交证据，向前修复。
- 既有空domain的6→5受限rollback不等于6→4；无整库激活、翻backup角色或重新签基线捷径。
- 调试Shortcut邮件接受先关闭：发送与回执查询503/`shortcut_mail_disabled`，SMTP配置/凭据/journal保全，不自动重发；普通聊天/MCP/手机验收独立。

MCP 生命周期静态依据见[读者审计](SCHEMA6_MCP_READER_AUDIT_20261006.md)；本轮新增候选实测、固定源与精确回执由主窗统一落在[MCP 会话验收](SCHEMA6_MCP_SESSION_ACCEPTANCE_20261006.md)，本手册不填写尚未取得的数字或新 CI 成功结论。现场依旧遵循 merge → 合并提交重建 → 另授权 switch；U 盘先核 NTFS，不自行格式化，邮件关闭、47862 和 `legacy_b3` 保持。

## 本轮交付与暂停

[原九类52文件真实恢复](SCHEMA6_REAL_BACKUP_RESTORE_20261006.md)是此前已被用户接受的副本证据；本轮不重新读取这些真实数据。新合成六类演练、测试数量、固定包hash、CI精确head及限制统一见[主窗验收](SCHEMA6_AUTOMATIC_MAIN_ACCEPTANCE_20261006.md)。仅在本机整组与新演练、PR14所有检查绿后推同分支并暂停等审核。
