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
- 真实 Windows 固定包 child death→下一次登录自动恢复→监听→正常关闭单项通过（约 168 秒），Job 空后清理隔离根；固定包普通写入/连续 125 秒监听/关闭/重启场景通过。完整 lifecycle suite 正在独立运行，最终结果由后续证据追加/主窗接收，不能把当前运行中状态计为全部通过。
- 共享 `lifecycle/test-fixture.mjs` 从当前源码制作独立 synthetic Git 提交，调用生产 `prepareRelease`，逐字复制完整库存到预先保护的空 release 根。所有新测试根走 canonical `syntheticRoot`，Node 使用独立固定文件。测试不手造 manifest，不放宽生产 ACL/link 检查。
- Windows `process.kill` 场景是强制结束证据，不是 POSIX SIGINT/SIGTERM handler 的优雅关闭实测；handler 已走既有 shutdown 路径，SessionEnding 独立由主窗/CI worker 验证。
- 当前 profile 强制 activity=false；未来若启用活动保留策略并裁剪已签 activity_changes 旧前缀，本包保守停止检查，不声称已实现任意活动保留历史的自动恢复。
- 自动审批曾拒绝删除新增的冗余 cursor-secret hash 条件，理由为可能削弱身份验证；已原样保留，不绕过，不影响本包功能。

## 集成入口

- Runtime inventory 增加 `automatic_recovery.mjs`、`raw_state_backup.mjs`；保留现有固定包安全检查。主窗需与登录包装/SessionEnding 工作包新增库存合并。
- 测试入口：`node --test tools/i_core/release_schema6/automatic_recovery.test.mjs tools/i_core/release_schema6/recovery_adapter.test.mjs`；Windows 集成入口：`node --test tools/i_core/release_schema6/lifecycle/lifecycle.test.mjs`。
- 未来真实 v4 接管仍由主窗执行已授权的停止任务/结束旧进程树，并持有 native 锁后调用固定 `start`；本包未代替真实停机证据，也未执行任何真实接管。
