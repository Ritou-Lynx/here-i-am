# W2 captures / planning 业务实现交接（2026-10-05）

## 范围与证据

- 基线：859b77b5f478d7bf09897c3eb96f00f1df779bed。独立 W2 工区，未修改 W1 原工区、schema 6 DDL、数据库版本或运行配置。
- 本 worker 新增：personal_data_domains.mjs / .test.mjs、import_personal_notes.mjs / .test.mjs、import_local_plan.mjs / .test.mjs。
- 通用引擎 required hooks、派生字段、受控 adoption 和最小派生引用账本由并行 domain_http worker 拥有。
- 2026-10-05 本 worker 专项：node --test tools/i_core/personal_data_domains.test.mjs tools/i_core/import_personal_notes.test.mjs tools/i_core/import_local_plan.test.mjs，31 过 / 0 失败 / 0 跳过。
- 所有测试仅内存 Core、临时合成 SQLite/JSON/Markdown。没有读取真实资料、升级真库、启用服务、创建生产凭据、commit 或 push。合成通过不等于手机、线上或迁移验收。

## 显式注册及宿主边界

模块导出 createPersonalDataHooks、personalDedupHooks、registerPersonalDataDomains。宿主须把 hooks/dedupHooks 注入 DomainStore，再显式注册；注册默认 mode=off。不会在 import、构造或服务启动时自动注册、开启或迁移业务。

requiredHooksVersion=personal-data-v1 持久化；缺失/版本不符 hook 的行为由通用引擎 fail closed。trusted-host policy 使用明确 principal 映射：
- captureSourcesByPrincipal：每个原话入口能声明的来源。
- plannerPrincipalIds：规划结构写入者。
- processorPrincipals：principal → organizer/planner。
- resolveDerivedReferences：从处理结果 ID 得到可信 {domain,id}；不提供就不能登记有输出的处理完成。

本 worker 未改 ICoreStore/server。将来宿主启用仍需显式提供 hooks、用户授权验证器、来源与 principal 映射；没有这些配置不构成可用的生产写入口。普通 HTTP 不开放 legacy_adopt。

## 固定字段与客户端视图

统一 envelope、revision、actor、receipt、cursor 继续采用 I_CORE_DOMAIN_CONTRACT.md。业务 schema_version=1 与 DB schema 6 分开。

| domain | data |
|---|---|
| captures | text, source, recorded_at；可选 organizer、planner 独立对象 |
| plan_items | title, level, area, parent_id, depends_on, status, replaced_by, block_kind, blocks, scheduled_at, planned_date, due_date, completed_at, energy, defer_count, source, source_url, note, remind_at |
| plan_weeks | week_key, expected_capacity, actual_capacity, daily_capacities, area_quotas, debt |
| plan_days | date, display_version, generated_at, change_summary, pending_decisions, capacity, queues, noted, lights_out_at |

plan_items 逐项对应 WI 中文字段，额外 remind_at=null 表示未设提醒。WI 状态保留：想法、待办、进行中、等待、完成、放弃、被替代；层级主线/目的/行动；块型深块/长块/语音块/零碎；来源语音/手打/邮件/复盘/拆分。原 ID 不因重命名或状态变化而更换。

- effort 原子组为 block_kind+blocks。日期真实校验，时间须带时区；块数为正有限数（允许小数），推迟为非负整数；完成于与完成状态、替代为与被替代状态严格对应。
- parent_id、depends_on、replaced_by 引用现存事项；分别检查自指与循环。日队列保留 ordered IDs 并验证目标存在。
- 容量对象固定 deep/long/voice；未知为 null，不能填零。周配额按 area+block_kind 唯一，保留下限/目标/上限/完成/本周还排了/状态及欠账来源。
- 日 queues 固定 fixed/deep/long/voice/extra/errands，不能重复放同一事项；pending_decisions 为 item_id/reason/suggestion；noted 为 capture_id/text；lights_out_at 未确认为 null。
- 日 edition 原子组含展示版本、生成时间、变更说明、待拍板、容量、队列、记下了与关灯时间。有效更新展示版本+1；展示版本不等于 envelope revision。没有排期算法。

## capture 与权限

capture 来源固定 phone_quick / claude_web / dot / codex。普通 create 的 data.source 必须等于 provenance.source，并匹配认证入口配置；作者 patch 仅 text，不能改来源、时间或 processor 分支。作者编辑/删除仍需普通 actor 证据与对象归属检查。

wire 采用两个独立顶层对象，UI 可映射为 ADR 的 dispositions 视图：
- organizer：{status, outputs, input_revision}
- planner：{status, outputs, input_revision, note}
- status 为 pending/done/skipped；outputs 保持 ID 列表。
- 普通 create 不允许提交这两个字段，缺省由 effectiveDisposition 投影视为 pending，避免用户创建把默认值锁死。
- input_revision 绑定 text 的 field_meta.rev，不是整个记录 revision；两个处理者可并发确认同一原话。作者编辑后旧处理结果投影视为 pending，旧原话的 ack 拒绝。
- 迁入 i_remember 的 planner 始终 skipped；不能重新分类成一批待办。作者编辑仍不改变这一迁入语义。旧传输 delivered_revision/card_id 不等于 organizer 已处理证明，不能伪造 done。
- claude_web/i_remember 删除采用即时在线正文清理；源删除事务登记最小 cascade_pending，输出目标不自动删除。物理页/WAL/离线备份不被本模块宣称已擦除。
- derived_refs 仅由可信 host resolver 给出，不能从 outputs 字符串猜目标域；这些引用不授予目标域读写权限。

手机 captures 与 planning 使用分 scope 凭据。captures 凭据的 origin_device_only 不扩散到规划读取；planning 凭据三域只读且仅 plan_items:status。planner 无 chat/cycle/ledger 明细权限。

## 手机状态与时间

手机公开 patch 只能有 status，值仅完成/放弃；标题、日期、容量、completed_at 等客户端夹带全部拒绝。被替代事项不通过手机两按钮隐式解除替代关系。

plan_items 注册 serverDerivedFields=[completed_at]。受控 deriveFields 仅在通用引擎已经验证用户 status 操作后运行：
- 首次完成取已授权 intent.created_at，即用户声明的动作时间；receipt.accepted_at 仍为 Core 接受时间。
- 已经完成再次声明完成，保留原 completed_at；放弃清空 completed_at。
- 派生字段参与相同 base、用户锁、元数据与事务检查；AI/import 不得覆盖手机用户锁。
- 离线时间是有来源的用户声明，不是独立物理时钟验收。

## 本机导入

两脚本默认 dry-run，要求显式 sourcePath、sourceId、batchId、targetInstanceId；不扫描目录、不打开任意真实默认路径、不初始化或升级 Core。source 路径必须绝对，沿途拒符号链接/目录联接，普通文件拒硬链接。

库函数可注入已准备的 target DomainStore、principal、authorizationRef、originMapping。apply 需显式 dryRun=false；独立 domain:adopt scope、import actor、指定 import_sources 和 verifyLegacyAdoption 均由引擎验证。originMapping 是每条记录的 principal_id/device_id，不默认使用导入账号。

CLI 参数：
- 通用：--source、--source-id、--batch-id、--target-instance、可选 --mapping-version / --origin-map。
- 默认不写目标。--apply 必须另外显式 --adapter；adapter 是受信宿主模块，导出 createImportContext，提供已准备目标和验证上下文。源数据不能作为代码适配器执行。
- WI 可显式 --week-source / --day-source；Markdown 只报告 mapping_required，严格 JSON 映射才可导入。
- CLI 只输出聚合计数、completion 和无正文限制原因；不输出原话、凭据、文件路径或逐条私密 ID。库函数的 mappings/receipts 供显式本机调用方保存。
- conflict/mapping_required/not_attempted 返回非零状态；顶层 week/day mapping_required 也返回 exit 2。明确有限的事项导入可执行，但 completion=partial；默认 dry-run 对应 completion=mapping_required。真实合成 CLI 已验证 totals.mapping_required=0 时这些顶层未决仍不会 exit 0。shadow_staged 独立计数，绝不显示为 production accepted。

notes：
- 仅显式关闭的一致 SQLite 副本；存在 WAL/journal/SHM 就停止，不猜文件拷贝一致性。以 readOnly+query_only+只读事务读取 notes 指定字段。
- 原 note_id/revision 精确保留；deleted 直接采用无正文墓碑，旧行即使残留 text 也不迁入。
- 活记录原创建时间进入 recorded_at，来源映射 i_remember → capture source claude_web；保留原身份的 provenance 用受控导入入口。`delivered_revision` / `phone_card_id` 仅校验，证据仍保留在字节不变的只读源账本；没有迁成目标 organizer 投影，也没有宣称旧传输已等于业务处理完成。
- 同批精确重复无新 revision/change；同版本不同内容、低/高新源版本或目标已有 Core 改动均不静默覆盖。墓碑不能被旧副本复活。

WI：
- 严格校验 plan.json 完整原字段、UUID v4、日期、引用、循环、processed_receipts 格式。items 原 UUID 保留；新 Core item revision=1，WI 全局 plan.revision 只作为来源快照版本报告。
- 不将源缺失行解释为删除；保留放弃/被替代状态。原 processed_receipts 留在不改动的源规划库，报告数量，不将指纹错误放入单事项 revision。
- week/day 接受显式严格 JSON 数组映射，按受控来源身份+域+周键/日期生成稳定 namespace UUIDv5；未知容量仍 null。
- 先检查全部源结构、作者映射，按组合引用依赖排序串行 adoption；每条有独立原子回执，发生冲突后其余 not_attempted，不声称跨记录批次原子。
- 各关系分别无环但组合依赖有环时，没有安全逐条导入顺序，明确 mapping_required；不暂时创建悬空引用。
- dry-run 的依赖项标 planned/dependency_requires_apply_order，不伪称尚不存在目标关系已完成在线验证。
- 无法从 Markdown 明确获得容量/队列/学习项映射时保留待映射项，不编造排程。

## 后续集成边界

- W3/W4/W5/W7-0 可复用业务字段、W1 receipt/outbox/cursor 形状；真实 token/授权签发、出站策略、真实本机导入与启用仍需相应范围的授权和证据。
- 原始业务资料与映射文件保持本机私密非 Git。W8 切换规划权威前应处理本交接列出的 Markdown/学习引用/已有本地 receipt 映射边界。
- 此处无自动 watcher、scheduler、聊天副作用、跨域自动删除或真实服务注册。
