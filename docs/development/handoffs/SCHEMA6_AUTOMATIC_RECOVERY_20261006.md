# Schema 6 自动恢复与 v4 副本接管工作包

- 基线：`0e04e1fb1d9ca0d1a15b457bc79b66f3f8c8243d`；分支 `codex/schema6-autorecovery-20261006`。已先接入 CI canonical TEMP 修复（本分支 `9631b7c5`，等价上游工作包 `99147e`）。本包不推送，不操作现役服务、原库、真实配置、手机或真实计划任务。
- 主窗负责最终集成、DEVLOG/当前态、SessionEnding/登录任务与最终精确候选回归；worker 只提交本包和本文，提交单次使用 `SKIP_PROJECT_STATE=1`，finally 恢复环境值。

## 实现与权威边界

- `lifecycle/runtime_child.mjs` 的普通 `start` 在任何 SQLite 打开前读取受保护配置/marker，并取得真实固定子进程 offline lease。缺 marker 进入 v4 候选；非 `clean_closed` 或 DB sidecar 残留进入异常恢复。已标记 inspection 的路径在最早入口拒绝。
- `raw_state_backup.mjs` 按 DB/WAL/SHM/journal 四项记录缺失状态，逐块 AES-256-GCM 加密、签名 manifest 并流式解密验证。保全期间及提交前重新核验源文件。生产没有 JSON 布尔 proof 或可注入 verifier；native probe 验证原父/guardian 进程身份、Job 成员、被持有的锁，并同时探测 DB 与存在的 sidecar 独占打开。
- 仅副本进行普通 SQLite 打开、WAL 回放、完整性/外键/身份/配置/路径绑定与 custody 验证。activity 仍绑定原 canonical live path；不把 backup role 改为 live，不把 stage 路径写进 binding。v4 副本在相同流程内完成 4→5→6 与 legacy digest 校验。
- 外置 `current-head.json` 仍是唯一最新权威。新 floor 保存 bounded immutable-prefix 摘要、Core identity/设备 ack、全局 sequence、domain principal generation 与 domain watermarks/highwaters。Core `change_events`/`chat_messages`、domain ops/receipts 的旧前缀不能被新的更大 MAX 掩盖；正常 domain_records 编辑、设备重新配对可继续。
- 旧 floor 若没有 progress witness，仅活动表一致不能证明 Core 未回退，因此必须满足副本 checkpoint 后的完整 DB hash 与旧已签 hash 一致；否则 `old_custody_progress_unverifiable` 停止。此兼容限制不影响无旧 floor 的 v4 首次接管，也不假称两次 seal 间所有尚未封存的权限变动都已有独立证据。
- 校验通过后写带时间与原始 manifest 摘要的恢复事件和新 floor，再移开旧 sidecar、原子替换单个 DB、推进外置 head。随后回到 opening/listening；这不伪造旧进程 clean close。最终 clean_closed 仍依赖真实关闭与 supervisor 回执。
- `s6-recovery-pending.json` 是单个中断锁存记录，不是不可重做阶段链。包含操作类型、commitStarted、开始/失败时间、脱敏错误码。提交开始前失败或中断，原 DB/sidecar 原字节不变；提交窗口中断则锁存阻止下一次启动，等待向前核验，不自动回退 head。异常抛出前的私有 stage 会清理；进程强杀留下的 stage 保持受保护并停止后续启动，供检查。
- `restoreRawStateForInspection` 只接受 fresh 且与原 state 分离的目标，Windows 要求受保护父目录，POSIX 要求当前用户私有父目录。全部四文件验证后才创建并最终发布检查副本；副本附现有 `.i-core-inspection.json` 标记，自动恢复入口在 raw/SQLite/迁移前拒绝它。没有 live activation/覆盖原路径/回退 head 的接口。

## 验证

- 自动恢复与既有 recovery adapter 专项：40/40 通过，包含真实 Node 强杀后的 committed/uncommitted WAL、v4 copy migration 中断原文件不变、坏库、head 回退、角色/路径拒绝、旧 floor 限制、domain 可变编辑、旧 immutable op 篡改、Core 同 ID 重新配对、raw 四文件精确还原与末项密文篡改不发布输出。
- 第一提交真实 Windows 完整 lifecycle suite 10/10 通过（850225 ms），包括普通写入/连续 125 秒监听/关闭/重启、guardian/parent/child 强杀后的下一次启动恢复、offline 6→5→6、拒绝错误配置/角色；所有合成根在 Job 空后清理。这是第一提交证据，不替代下述追加修复的精确候选回归。
- 共享 `lifecycle/test-fixture.mjs` 从当前源码制作独立 synthetic Git 提交，调用生产 `prepareRelease`，逐字复制完整库存到预先保护的空 release 根。所有新测试根走 canonical `syntheticRoot`，Node 使用独立固定文件。测试不手造 manifest，不放宽生产 ACL/link 检查。
- Windows `process.kill` 场景是强制结束证据，不是 POSIX SIGINT/SIGTERM handler 的优雅关闭实测；handler 已走既有 shutdown 路径，SessionEnding 独立由主窗/CI worker 验证。
- 当前 profile 强制 activity=false；未来若启用活动保留策略并裁剪已签 activity_changes 旧前缀，本包保守停止检查，不声称已实现任意活动保留历史的自动恢复。
- 自动审批曾拒绝删除新增的冗余 cursor-secret hash 条件，理由为可能削弱身份验证；已原样保留，不绕过，不影响本包功能。

## 二审修复与补充证据

- 生产 custody 锁改为固定 PowerShell 父进程整个 Core 生命周期持有的 `FileShare.None` 系统句柄。offline lease 仍要求真实父/guardian/Job 身份和持锁探测；普通 JSON 或合成 capability 不能进入生产。载体文件保留，进程死亡后系统释放句柄，下一次固定启动重新持有同一文件，不依赖删除残留锁。仅 test-only lease 保留独立 wx 互斥模拟。
- 每个 domain materialized record 增加已签 revision/hash 见证（最多 16384 条，完整 floor 上限 4 MiB）。已封存版本不得消失、降 revision 或同 revision 改正文/删除标志。DomainStore 在内部 `domain_ops.op_meta_json` 保存完整目标行 HMAC 与绑定 namespace/domain/principal/op_id/request_digest/result 的 metadata HMAC；生产另外核验原 receipt_auth。create/patch/status/delete/restore/merge/purge 走统一 persist，legacy adoption 与生产/shadow retention 也保存承诺。恢复前进必须与认证结果中的完整行一致，不能仅抬版本或追加裸 accepted targets；公开 receipt 字段、权限规则、schema 列均不变。domain_op_payloads 仍可正常删除。
- 既有无内部结果承诺的旧候选域记录，仅允许与外置已封存 revision/hash 相同；无法证明的未封存前进以 `domain_record_advance_unproven` 停止，原件已 raw 保全且未替换，需人工向前核验。这是尚未部署候选的兼容边界，不描述为现役日常故障；v4 首次迁移为空 domain 不受影响。
- 启动配置预读与 PowerShell JSON 解析固定返回 `config_json_rejected`；child 回执只允许静态白名单错误码，任意异常正文不写入回执。随机合成 pairing secret 的坏 JSON 已有直接 redaction 测试及 fixed Windows 入口测试。
- 新增 next-fixed-start 中断锁存测试：在合成 schema4 上分别提供 precommit/commit-started latch，要求下一次未修改的 Windows 固定入口拒绝并保持四文件 hash。此原生部分模拟便携 adapter 故障注入留下的 latch，不声称真实 OS 在迁移指令中强杀；`commitStarted:false` 保持可用旧 v4 字节，`true` 只允许向前人工核验。
- 最新 portable 恢复/adapter/redaction 回归：51/51 通过（16428 ms），含 authoritative/shadow 的真实 patch r2 保留真实 receipt 却恢复 r1 正文，以及追加伪 accepted metadata 两类攻击；两种 namespace 的真实编辑→删除→retention 均成功。DomainStore 本身 65/65 通过。首次合并运行中的两个新攻击 fixture 因只读测试连接遗留 WAL 导致 seal 前失败，已改测试读取为可正常收尾的合成连接，51 项重跑通过；生产检查未放宽。
- Windows 三项 3/3 通过（168439 ms）：坏配置随机 secret 未泄露、child death 后保留 custody.lock 载体并复用 OS 锁自动恢复、schema4 两种 pending 在 next fixed start 拒绝且四文件 hash 不变；均在 Job 空后清理。该 Windows 包含 native lock/redaction 修复，尚未包含最后内部 domain HMAC 增补；精确完整集成候选由主窗回归，不借前一快照替代。

## 集成入口

- Runtime inventory 增加 `automatic_recovery.mjs`、`raw_state_backup.mjs`；保留现有固定包安全检查。主窗需与登录包装/SessionEnding 工作包新增库存合并。
- 测试入口：`node --test tools/i_core/release_schema6/automatic_recovery.test.mjs tools/i_core/release_schema6/recovery_adapter.test.mjs`；Windows 集成入口：`node --test tools/i_core/release_schema6/lifecycle/lifecycle.test.mjs`。
- 未来真实 v4 接管仍由主窗执行已授权的停止任务/结束旧进程树，并持有 native 锁后调用固定 `start`；本包未代替真实停机证据，也未执行任何真实接管。
