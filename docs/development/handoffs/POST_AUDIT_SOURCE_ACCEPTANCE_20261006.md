# PREDEPLOY 审计后源码与候选验收（2026-10-06）

本轮执行用户确认的 D1–D4 推荐。PR12 已合入；后续源码在 `codex/post-audit-integrate-20261006`，本报告随最终验证更新。生产 Core、MCP 配置及主力手机保持原样。

## 已完成的授权动作

- B3 备份分支已推送：`codex/b3-writeback-local-20261003@3a9336b122b2fda22ff65ed32d9cee263e8fc2da`，远端 SHA 一致。正式与 B3 根提交均 `b96d9961950e8c0d6cbd71e4eafdb735833b0f7f`；和 D 私人旧谱系 HEAD 可达集合交集为0；153 新 blob 的敏感路径/字面密钥筛查无命中。筛查不是所有内容绝对无隐私的数学证明；没有迁入 D 旧历史、运行数据或凭据。
- [PR #12](https://github.com/Ritou-Lynx/here-i-am/pull/12) 在 `d9a8498264d349f8593cd421e76db3e77ad102fd` 五类精确 head 检查成功后普通合入 `64aea69331ecd374d4365d6b6a87025f757eb160`，合并时间 2026-10-05 17:22:32Z。
- [PREDEPLOY 原审计](https://github.com/Ritou-Lynx/here-i-am/blob/codex/predeploy-audit-20261005/docs/development/handoffs/PREDEPLOY_AUDIT_20261005.md) 保留在已推送的独立审计分支，未合入 v3-lab。

## 兼容与下游行为

1. [Drift61/62](SCHEMA62_COMPAT_20261006.md)：两个表定义和完整迁移区段按行尾归一后与 B3 逐字一致，schema63起预留给之后的新迁移。毫秒/服务端序号排序与定位分页也恢复；真正新增 feed 按页/角色通知及调度一次，回声和重复不会重调度。
2. [D1/D2 transcript/replay](CORE_TRANSCRIPT_COMPAT_20261006.md)：当前 Android credential 绑定 grant，受限 transcript 与 PR10 共用不可变 digest/序号持久化；legacy_b3/pr10/disabled 三选一，旧 grant 不能授予 PR10。72 外置审批与 durable ledger 保留，alias/身份/载荷变更拒绝。
3. [单一上传器](B3_UPLOAD_COMPAT_20261006.md)：每轮 capabilities 只选一个入口；旧 companion outbox 的 sender 只在本机匹配后修复，不改 sync_id/origin sequence；拒绝的 companion 保留，403/404仍允许拉取，未知模式拒绝。
4. [PR12账本跟进](CAPTURE_LEDGER_FOLLOWUP_20261006.md)：记一下的收支卡进现有账本面板，同源修订复用稳定行；删 capture 清精确属主行，保护用户改卡且留提示，其他手工账本行不受影响。没有对全部既有已消费 capture 做自动回填，也没有把本机账本升级为 Core ledger 权威。
5. `claude.ai day_get` 保持 canonical queues 的事项 ID，额外返回 `item_titles` 的 title/revision。独立 `plan_items:read` 才可取标题；缺权限、删除、失败或超过500条有明确 issue。限4并发；标题是各项当前版本，不能称跨领域原子快照。
6. D3 保留 47862、既有安全存储和 note receipt；网页 Core 消费缺真实闭环 Gate/来源 adoption 时阻断，包括墓碑，手机 quick capture 继续。切换只留一个消费者，过期租约可回收且旧 worker 被 fence。主窗最终整合及验证在下一节补齐。
7. [D4候选包装](CORE_SCHEMA6_RELEASE_20261006.md) 固定同一提交的 Core/wrapper、Node24.14.1和17文件库存。现阶段只制作候选/只读预检，始终 `deployment_ready:false`；没有生产启动/停服/迁移/回滚动作或真实 recovery-floor 适配器。

## 真实一致副本（仅元数据）

- 主力手机仍为 B3 `versionName=1.0.30` / `versionCode=113`。通过 ADB run-as 读取主库与 WAL，设备前后及本机哈希一致，未停 App 或写设备。
- 原始副本 `user_version=62`：聊天6962、outbox11、记忆卡128、kv45。整合 AppDatabase 连开两次，完整140表的列和数据指纹前后一致，integrity_check=ok。SQLite本机副本正常合并 WAL 属隔离副本处理，不能声称 raw 副本字节从未变化。
- 原始 Core schema4 一致副本单独演练4→5→6，7张旧业务表数据指纹一致；身份/设备/序号未变，grant1仍对应当前Android凭据，72外置/durable完整集合相同，新领域记录0，integrity/FK检查通过。
- 4→5 输入产生全新空 activity，没有证明现役 activity 历史恢复或生产 writer clean-stop。演练中的 offline proof/floor 只适用于该隔离、从未运行服务的副本，不能复用到生产。
- 原始手机/Core/两份外置授权的加密备份解密与输入 hash 校验通过；AES256GCM 密钥由当前用户 DPAPI 保护。密文 SHA256 `3b7f9102229dea7d57d13bbbe1c2fcd6430a20b420d9bdd669ed182bdba1429c`。密钥、数据库、正文及授权内容不进入 Git。

## 最终验证回执

主窗组合验证、精确构建候选及固定包预检在本报告后续提交填入。已完成：MCP+transcript/replay+release167/167；真实手机62副本专项1/1、140表保全；Core隔离4→5→6演练。

## 发布边界与下一步

- 先完成本轮源码精确 head CI、构建候选复核，再决定源码合入。
- 生产 Core/MCP切换和主力手机安装需绑定实际产物、保全整个运行配置/身份、真实 supervisor clean-stop 与独立恢复 floor；当前离线包装没有这些启动能力。
- captures 必须验真实新增/改版/删除和用户改卡保护，再以显式来源映射切消费者/退休47862；没有双写或自动切换。
- 包含 PR12 的 App 在第1/2项完成前未安装主力手机；本轮没有手机安装、服务重启、原库升级或生产领域/回复上传开关操作。
