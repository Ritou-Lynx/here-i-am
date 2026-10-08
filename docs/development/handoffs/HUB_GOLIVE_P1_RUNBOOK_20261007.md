# P1 独立上线清单与退回边界

本清单属于 B 线源码交付，不是已批准执行的现场操作单。A 线原现场清单、Core 生命周期、会话启动器和 release 库存保持主窗口所有权。所有日期按上海时区：目标 10/09 前完成源码测试；可单独选择 10/09 上线 P1，默认窗口为 10/17–18。P2/P3 未开启不妨碍 P1。

## 先决阻断：不能以组件测试替代完整上线

当前审核已发现以下真实接线缺口；必须在主窗口复核关闭之后才能执行生产切换。

1. Core 正式 CLI/受管宿主需显式装配 `createPersonalDataHooks`、dedup、用户授权 verifier、legacy adoption verifier；当前基础入口仅支持注入，并不自行启用这些配置。新组件不能靠环境猜测或测试的 `() => true` verifier 上线。
2. 网页 `i_remember`/`capture_add` 只转发 `authorization_ref`，尚无可上线的可信授权签发入口。OAuth 登录、模型自报、聊天存在或 UUID 均不能代替本轮动作授权。主窗口需确认受信入口政策，完成精确请求绑定的签发/持久化后再开放；不得为了闭环放宽 Core 检查。
3. 手机独立领域 credential、UI 签名和连接装配属于本候选源码；owner 的实际签发、安装实例绑定与显式 route 迁移仍要完成。兼容可选配对字段不代表现役 Core 已发出该字段。旧聊天 bearer 不能作为领域 bearer。
4. 47862→Core 的 production Gate verifier、旧 note→capture→卡/账本 ownership adoption、可执行切换入口仍需完成并证明。现有 `selectCore` 严格准入检查没有自动生成这些凭证。不得伪造 generated baseline、通过 UI 开关或仅凭相同 ID 接管。

这些是源码/授权入口缺口，不标为“只待真人点一下”。在关闭前保留旧桥与旧 MCP，P1 状态为未完成。

## 阶段顺序

| 步骤 | 具体动作与接受证据 | 执行前授权 | 失败/退回 |
|---|---|---|---|
| 0 源码候选 | 审查 P1 独立提交；Node、widget、Linux 全套、Windows 构建绑定精确 PR head；构建前执行 `scripts/verify_critical_fixes.ps1` | 源码/合成 CI 已授权；合并另批 | 保持草稿，不合并、不部署 |
| 1 A/B 包衔接 | 主窗口在获批合入后，从同一提交重建 Core/MCP 固定包，审查新增/变更模块库存、mcp_reader/legacy/hash、托管 MCP 入口与私有状态目录分离 | 主窗口合并/候选打包边界 | 库存不一致或遗漏 hooks 即停止；不替换现役 |
| 2 保全与 off | 经窄授权保全当前 Core、MCP notes/OAuth/配置及手机凭据/队列；captures 初始 off，legacy_b3 上传器与 47862 继续 | 真实数据/凭据读取与保全另批；只在本机保留 | 任何备份或可恢复性证据缺失均停止 |
| 3 notes dry-run | 停旧 notes 写入口并取得一致关闭副本；用显式路径、source/batch/target ID、origin map、host adapter 执行 `import_personal_notes.mjs`，默认不带 `--apply` | 冻结旧写入、真实副本读取另批 | 缺来源映射、冲突或源侧 WAL/SHM 未关闭则停止；原数据不动 |
| 4 captures shadow | owner 显式注册 captures，配置只用于影子的 importer；按相同映射 apply 到 shadow，对账数量、原 note_id/revision/墓碑和 planner skipped | 真实影子写入另批 | shadow_staged 不显示 accepted；可退回 off，手机数据与旧路径保持 |
| 5 frozen 最终对账 | 冻结影子与旧写入口；排空在途、重新取得最终一致副本；核来源映射、卡/账本 ownership、用户改卡保护与 tombstone，保存可恢复回执 | 冻结、真实投影迁移另批 | 对账不一致不切权威；回旧入口需确认没有产生新权威写入 |
| 6 authoritative | 仅 captures 转正式接受者，通过受控领域导入生成新 production receipt/snapshot/cursor，不能把 shadow receipt 升级或复制整表 | captures 权威切换单独批准 | 首次权威接受后不降 schema、不整库覆盖、不简单改回 phone；先 frozen，保留新写，优先向前修 |
| 7 新 MCP 与会话启动器 | 新 MCP 使用 Core captures 配置与独立最小 scopes；确认 `i_chat_turn/i_context/i_recall` 兼容；同一笔记录不同时写新旧 notes。由主窗口更新启动器库存和包锚 | MCP 包替换/会话启动器接入单独批准 | 未发生新 captures 接受前可恢复旧包与配置；已有接受后需先对账，禁止双写退回 |
| 8 App 候选 | 安装固定 hereIAmV3/com.memexlab.hereiam.v3 包；保存旧队列/凭据/卡来源；仅经独立领域授予附加连接 | 主力手机安装和配置另批 | 不清手机库/secure storage、不换 deviceUUID；配置缺失保持原路径，不能冒称已连接 |
| 9 真机闭环 | 侧键新建/改版、网页新建/改版/显式删除、断网重试、丢响应后同 op 重试、用户改卡保护、来源不可见/权限撤销不当删除；确认无重复卡和账本行 | 真实测试数据写入/删除、必要本人主观 Gate另批 | 保留失败首证据；有冲突标待解决，不清 outbox或用户改卡 |
| 10 47862 单消费者交接 | 只有完整 Gate 与来源/adoption proof 验证通过，持有同一安装 DB 的单消费者 lease/fence后 `selectCore`；保留旧配置与回执到验收结束 | 消费者交接独立批准 | 未成功接管仍由 legacy；失败不并开；已有 Core 消费后回切须逐记录映射/队列对账，不声称现有代码已提供 production 回切 |
| 11 47862 退役 | 完整真机增改删、离线恢复与用户保护通过后，再批准停止旧桥；记录来源、队列、cursor 与 owner 证据 | 退役另批 | 保留可恢复配置/来源映射；恢复旧桥仍需证明只有一个消费者 |

## notes 导入的固定语义

复用 `tools/i_core/import_personal_notes.mjs`，不另造导入器。源必须是显式绝对路径的关闭副本；拒绝符号链接/硬链接、活动 sidecar、超量数据、错误目标 Core。默认 dry-run；`--apply` 必须有受信 host adapter、授权引用与逐 note 作者映射。

- 保留原 note_id、revision、创建时间和删除标记。墓碑不携正文，即使旧行异常残留正文也不迁入。
- 旧记录 planner 始终 skipped；旧手机 delivered_revision 不等于 Organizer 已处理，不伪造 done。
- 重复相同内容返回 duplicate，不新增 revision/change；同版本内容冲突、旧/新源版本或 Core 用户修改均停止，不覆盖。
- CLI 只输出汇总；来源映射、凭据、实际正文与 private receipt 不进入 Git/PR。dry-run 通过不是 apply 授权。

## legacy_b3 → PR10 单一上传器（仅方案）

本候选不启用 PR10、不更改 grant 或服务器 capability。保留每轮 capability 的三选一 `legacy_b3 / pr10 / disabled`，不得在某一路失败后自动改走另一路。

1. 经授权安装后先保持 legacy_b3，复核旧设备 ID、全局 origin sequence、companion marker、outbox、外置 grant 和历史 replay 绑定不变。
2. 在合成场景与授权设备证据中证明 legacy 在途已结束、队列载荷/ID/序号可恢复，再由 owner 独立授予 PR10；legacy 的 enabled 不等于 PR10 授权。
3. 单个受控点切 capability=pr10，并启用既有手机 owner 入队配置；同一轮只能提交一次 companion 路径。保留 user/feed 能力。
4. 需要退回时先停止新 PR10 派发并排空在途；核未知结果、以相同 sync_id/sequence/正文查重；单点恢复 legacy_b3。无法证明单入口或不可变载荷时停在 disabled，保留队列供处理。
5. 真机核无重复气泡、重试只得同一回执、serverSequence 归档及授权撤销后队列不丢。此项独立于 captures 的 47862 消费者切换，不共用“切换成功”结论。

## 主窗口统一联系用户的事项

优先确认网页动作授权入口的政策与实现范围；其后依次是源码合并、固定 MCP/主窗口启动器库存更新、真实 notes 副本导入、App 安装与领域授予、captures 权威切换、真机 Gate、上传器切换、47862 接管和最终退役。每项均以完成的可复核候选作为审批输入；本窗口没有执行这些生产动作。
