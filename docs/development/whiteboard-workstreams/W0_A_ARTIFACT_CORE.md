# W0-A — Artifact Core 最小执行器

**状态**：隔离窗口实现完成，待 W0 审核与选择性集成
**分支**：`codex/whiteboard-w0a-artifact-executor`
**基线**：`v3-lab@96f4e95a`
**范围**：provider-neutral executor / port / fake recovery tests；无 schema、migration、provider、renderer 或 UI

## 本轮闭环

- 新增 `ArtifactBundleExecutor`，在进入任何产品写入前执行 P3 契约预算、路径、关系与 operation/inverse 校验；
- 通过单次流读取核对 staging MIME、实际字节数与 SHA-256，再执行 content-addressed final object commit；
- 通过 `ArtifactDomainBatchRepository` 对 conflict hash、领域 operation 与 Artifact binding 做原子提交，生成确定性 `OperationReceipt`；
- 通过 `ArtifactExecutionLedger.open(plan)` 原子认领完整 plan 的幂等键；重启 replay 返回原 receipt，不重复 final object 或领域写入；
- `planned / staged / hashes_verified / committed / recovery_required / rolled_back` 均为显式 resume 分支，不覆盖已有 journal 从头执行；`hashes_verified` 后不再读取可能已被原子移动的 staging；
- `ArtifactDomainBatchRepository.lookupCommit(plan)` 是领域提交 crash boundary：非空证明写入与结果同事务耐久，空值证明零写入；无法证明时只返回 `ArtifactExecutionPending`，绝不误标 rejected、rollback 或 GC；
- 领域部分失败只对已报告成功的 operation 逆序执行声明的 inverse；final object 只进入引用感知延迟 GC；
- staging/hash/conflict/事务失败先落 `recovery_required` journal，再清理、回滚并落 `rolled_back`；清理暂时失败可在新 executor 实例中继续恢复。

## 新增端口

- `ArtifactObjectStore`：受控 staging stream、幂等 final commit、staging cleanup、延迟 GC；已移动 staging 时必须校验同 manifest 的 final object 并成功 replay；
- `ArtifactExecutionLedger`：完整 plan 原子认领、journal 与 receipt 耐久化；
- `ArtifactDomainBatchRepository`：conflict hash、可查询 durable commit result、领域批次 + binding 原子提交、幂等 inverse rollback。

端口没有 import Drift、现有 Repository、provider、renderer、UI 或 `MemexRouter`。P3 `ContentBundlePlan / ArtifactManifest / ArtifactCommitJournal / OperationReceipt` wire contract 未修改；只在原 artifact barrel 导出 executor。

## 验证

- executor fake 驱动：16/16；除正常/失败链外，逐一覆盖已有 planned/staged、两个对象各自 commit 后、domain commit 后、committed journal 后、receipt 后/cleanup 前的崩溃恢复，以及 committed/result 不可证明和 adapter outcome pending；
- executor + 原 P3 契约组合：46/46；故障恢复均断言 domain/final object 只写一次、无错误 rollback/GC、重启与后续 replay 返回同一 receipt；
- 再叠加 W0 白板共享契约组合：72/72；
- changed-file analyze：3 文件，零 issue；
- `git diff --check`：通过；生成文件、依赖、schema、migration 无实质 diff。

## W0 接入请求与风险

1. **Ledger/schema（需要 W0 决定）**：生产 adapter 必须以 `idempotency_key` 唯一约束原子认领，并保存 canonical plan digest、journal 与 receipt；同 key 不同 plan 必须 fail closed。可用新的执行记录表或现有任务存储的私有 envelope，但不得只按 batch ID 做非原子查询后写入。
2. **跨进程 plan 恢复（需要 W0 决定）**：当前最小 executor 由调用者在重启后重新提交同一 `ContentBundlePlan`；若后台启动需无调用者自动扫描恢复，durable adapter 还必须保留可重建的 exact plan。无需改 P3 wire，可作为 persistence envelope；若 W0 不接受 envelope，再另提共享契约变更。
3. **领域事务与结果查询（硬 Gate）**：生产 adapter 必须把 exact-plan 幂等 claim、expected-state guard、operations、Artifact binding 与 `ArtifactDomainCommitResult` 放在同一事务；`lookupCommit(plan)` 非空即完整提交、空即零副作用。无法提供这一证明的 adapter 必须抛 `ArtifactExecutionPending`，不得让 core 猜测失败。正常实现不得报告 partial commit；`ArtifactDomainCommitException.committedOperationIds` 只为旧/外部 adapter 已知逃逸提供补偿。
4. **对象存储**：`commitVerified` 必须在受控真实路径内做内容寻址、幂等原子 rename；若 staging 已移动但 final object 与 manifest 一致，replay 必须成功。延迟 GC 必须再次查引用，不能在错误路径直接删除 final object。
5. **未完成**：没有生产 adapter、Repository 注册、schema/migration、后台恢复扫描器，也没有 P7/P8/P9 provider、Canvas renderer 或 UI；这些不能因 fake 闭环通过而宣称上线。

## 集成建议

W0 先审核三个端口的事务语义，再决定 persistence/object-store adapter 与 schema。选择性集成本窗口功能 commit 后，复跑 artifact + 白板共享契约 72/72；生产 adapter 未落地前保持 executor 未注册状态。
