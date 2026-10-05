# W2 通用引擎扩展交接（2026-10-05）

- 基线：`859b77b5f478d7bf09897c3eb96f00f1df779bed`；分支 `codex/w2-business-domains-20261005`。
- 本窗口只修改下列三个引擎/专项文件和本交接；未改 DB 表/marker、公共 HTTP kind、全局状态或 Git index；无 commit/push、真实数据库、生产服务动作。
- W1 已验收候选保持不变；这些能力属于 W2，不代表业务域已注册、授权或上线。

## 固定接口

- `DomainStore` trusted-host 构造参数：`domainHooks` 与 `verifyLegacyAdoption`。
- `registerDomain(..., {mode:'off', requiredHooksVersion, serverDerivedFields:[]})`；版本和派生白名单持久保存在既有 registry JSON。缺失/错版本 hooks 按域拒绝，不破坏全 Core/chat identity readiness。
- hooks bundle：`{version, authorizeOperation, validateTransition, deriveFields?}`。所有上下文深拷贝冻结；只读 lookup 按当前 read/object 权限及目标域 readiness 返回冻结当前副本；没有 DB/写接口。异常、Promise、非法返回 fail closed 503，无终态接受。
- authorize 阶段：`preflight` 不读对象，`submit` 获当前可见对象且在旧 op 查询前，`lookup` 获不可变原操作摘要。`matchesOperationValue` 仅比较已注册有限 enum 控制字段的 HMAC，不保存原话等逐字段指纹。
- validate 阶段：完整最终记录，包含 merge 的最终写集合只读视图。返回 true/false 或 `{valid:false,code}`（有限现有码）；合法 ack 可返回 `{valid:true,derived_refs:[{domain,id}]}`，不接受任意数据补丁。
- deriveFields 仅用于已验证用户 actor 的 status。显式白名单字段参与同一次 schema/业务校验、base 冲突、用户锁、field_meta、回执和 change。手机输入仍只能 status；完成于的 WI 语义是含时区 timestamp，业务实现取已授权 op.created_at，Core accepted_at 保持服务器时间。
- processor.input_revision 位于各自 disposition 对象，业务 hook 核对原话组 field_meta.rev；不使用整条记录 revision，保留两个处理者独立并发。

## 派生引用与删除

- 合法 ack 将最小 derived_refs 写入原 op 元数据；重处理覆盖当前 outputs 不会丢历史引用。
- 源删除/merge-source 在同一事务汇总历史引用为 cascade_pending，并在即时清正文前完成登记；拒绝或故障则一起回滚。普通 tombstone/receipt 不暴露这些引用。
- 不改变 wire outputs 的稳定 ID 列表；业务可信解析器负责把已知 outputs 映射为 domain/id，不能猜域。引用登记不证明目标存在或赋予目标权限，不执行跨域删除。
- 引用限长、去重采用无分隔歧义的 JSON tuple，排序不依赖系统区域设置。

## 本机 adoption

- `adoptLegacyRecord(principal, domain, record, options)`：默认 dryRun=true；无 HTTP 路由/新远程 kind。
- record：`{id,revision,deleted_at,origin:{principal_id,device_id},data?,provenance:{source,source_refs,import_batch_id}}`。
- options：`{dryRun,authorizationRef,sourceKind,sourceRecordId,sourceRevision,batchId,mappingVersion,opId?}`。
- 必须有本机 `domain:adopt`、import actor、当前来源白名单和同步 trusted-host verifier=true。验证器负责来源完整性与作者映射；普通请求不能自报该证明。受同一 required/version 业务 hooks 约束。
- 保留非 UUID 旧 ID、旧 revision、删除标记。已删源只能导入 purged 最小墓碑，拒绝携 data；不把 legacy plaintext/hash 写入永久元数据。旧活记录导入正文位于可清区域；只有完整请求 HMAC 用于精确幂等。
- 同一受控来源/批次/映射/版本精确重跑复用一份结果；同版本内容不同拒绝；Core revision 或控制身份改变、来源高/低版本再次覆盖都 needs_resolution。没有空更新凑 revision、upsert 或用户锁豁免。
- 默认 opId 是受控身份元组派生的稳定 UUID 格式；调用者也可显式传稳定 UUID。迁移入口自行落实源冻结、dry-run 审核和逐项部分完成报告。

## 实际验证

- 最终运行：`node --test --test-reporter=tap tools/i_core/domain_store.test.mjs tools/i_core/domain_adoption.test.mjs`。
- **77 tests / 77 pass / 0 fail / 0 skipped / exit 0**；10,372.7025 ms。均为内存或专用临时合成 SQLite。
- 覆盖既有 W1 51 项，以及 hooks 重启缺失/异常/异步/不可变上下文、权限缩小重播、离线派生时间、输入注入/缺用户证据、派生冲突、merge 最终视图、processor 输入版本、历史 cascade、故障回滚、本机干跑/墓碑/幂等/来源权限和提交后丢响应恢复。
- 前一组合失败来自测试 helper 一处误替换变量，已修正；引用专项发现 locale 排序差异后改确定性排序。以上问题均包含在最终 77 项通过结果中。
- 业务 schema/导入脚本窗口与 root 另验跨文件组合；本报告不冒称设备、真实来源迁移、生产授权或跨域删除执行通过。

## 冻结 SHA-256

| 文件 | SHA-256 |
|---|---|
| `tools/i_core/domain_store.mjs` | `600f0a32be0f5e66ac3c9e719e066f360055b0c1b28b4ee870bcb8ef157addb0` |
| `tools/i_core/domain_store.test.mjs` | `2e94222dd779acb6fb0cec673da31db60ca6d7652238bebb3912acbe8cf1ed85` |
| `tools/i_core/domain_adoption.test.mjs` | `313e5d0edab221e23afc75947207b167bf56fa571d7f70099990cb95e9cc9d33` |
