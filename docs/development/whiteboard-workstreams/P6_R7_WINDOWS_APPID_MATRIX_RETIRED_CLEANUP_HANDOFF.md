# P6-R7 固定退役矩阵实例恢复候选

主控已实际完成固定28e6恢复。最终source/snapshot `tmp/p6-r7-review/native-appid-matrix-retired-cleanup-01.cs` SHA `CD751E502B72AB8F117EFAF3FFEF5682E56969BA85F50293722C7D9F8FCA5D41`；exe `tmp/p6-r7-helper/windows_text_gate_appid_matrix_retired_cleanup.v1.exe` SHA `220F4274F06C92FA7F324DA07DB91D1490EC824F8EFB3E5DB2BDE6EFEA7817E2`。主控5/5、259自测/279纯断言及绑定最终源码的独立复核通过；固定runner SHA `908235BE7CDE0E1DFC0E8B6BF3FED255B0E6FC57152FBCE2AC24D0976A4633C5`。

held runner56688与native均实际exit0。报告 `tmp/p6-r7-review/native-appid-matrix-retired-cleanup-actual-01.json` SHA `19CB6EE8CD812AD6150590A15ED25047BA8C419F11D4FA31926A69B97BCC4DE6`，capture SHA `47504595255A17DF213D6B7F982FFD2388F5A7D49201539A2724900F5C088B2E`。只读预检确认3条本实例规则；事务实际删除3 filter+1 sublayer并commit，postabsence、记录/pins/ACL、当前目标不活跃及真实资源关闭全部成立，cleanup_performed=true、cleanup_pending=false。原v4 rejected/exit2报告不改写，不补造原helper、child、Job或矩阵通过证据。

- 范围：仅 `28e6b32b-9ad0-4be3-b04b-b1c22767d943`，owner PID `52468` / creation `134336616095270930`，broker `59675`；基线 `v3-lab@bbb8025d`，保留其他工作。worker 未提交，未触发 native 或 Windows 管理员确认。
- 唯一实际入口：`--cleanup-fixed-retired-matrix-attempt`。无参数、`--plan`、`--self-test` 不调用 native；额外参数拒绝。无任意实例、路径、端口、权重参数。
- 准入沿用 completed-inspect：当前 primary / High / elevated / Non-AppContainer token，当前 SID 必须拥有两级严格保护目录；held no-reparse 路径、只读文件句柄和 SHA pin；目录恰为本次 15 文件集合。按 owner PID+creation 判定当前不活跃，并有限枚举原 v4 image 与 copied probe image；未知或活跃拒绝。
- 历史验证：prepared → bound → closed 绑定一致，install receipt 对 prepared 的完整关系和 assigned weight 验证；固定 actual04 + capture04 验证同 attempt、拒绝 stage99、actual native exit2、stdout pin 与 post candidate pin。只证明保存的历史记录一致；不声称原 helper actual exit、child actual close、原 Job0 或矩阵通过。
- 精确规则范围：`MatrixContract.Scope(Attempt)` 派生的三 filter + 一 sublayer；AppId 来自 held fixed copied image，digest 与 receipt 一致。复用冻结 v15 `ExactFilter` / `ExactSublayer` / `ReadbackAllowed`；只接受三个规则和分层全部严格匹配，或四对象全部 absent。foreign / mismatch / partial / unknown 拒绝。
- 先只读事务核对。已 absent 不进入写事务。全匹配时，按冻结 v15 `RemoveAfterZero` 的证明、回读、删除、commit、postabsence 顺序回收；使用本候选的显式 engine/transaction 资源账本，避免原 `Dispose` 忽略 engine-close 返回。每个证明回调重新验证 held pins、ACL、当前 owner/image inactivity；commit 前亦复核。实际删除仅固定三个 key 和固定分层。
- 失败保留真实事务状态：begin 成功才标 active；commit / abort 成功才清除。abort / engine / handle 关闭失败 sticky false，保留句柄并最多两轮 close-only 重试；不再重做删除。即使稍后关闭成功，仍 pending。真实 postabsence、事务结束、前后准入和全部首次关闭成功才允许 `cleanup_pending=false`。
- 报告仅脱敏固定字段、阶段、nullable native error、真实 commit/deletion 及当前 absence；未知保持 pending。历史 helper / child / Job 证明始终 false/null；生产隔离、矩阵、人类 Gate 始终 false，真实上游和模型请求始终 0。

## 验证与指纹

- `node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_retired_cleanup.test.mjs`：5/5，通过 C# x64 warnings-as-errors 编译、259 self-test 和 279 pure assertions、Windows SDK snapshot / read-only txn ABI 编译。仅纯入口执行。
- pure 覆盖逐字段 journal/receipt/capture 负例、同 child 历史关系、精确 15 文件名、High caller 拒绝矩阵、owner/image inactive 判定、完整事务调用顺序与九处失败注入、部分规则拒绝、commit 后 absence 不满足拒绝、abort/engine/handle close 失败保留与 sticky false。
- source SHA-256：`CD751E502B72AB8F117EFAF3FFEF5682E56969BA85F50293722C7D9F8FCA5D41`。
- test SHA-256：`2A36FBAE62155483D2C97461E5A4574C84A9C4140D8B8CA28429708500611749`。
- capture04 SHA-256：`B0B9B0D7D211407A7A62252EDE236FCBC120C25CD974D8E800EAF63F951122AB`；actual04：`7CB66B95999238DD71DF395778FE566DA6FDA3CBA3F5E4499145AA35404560F6`。
- 编译依赖与 SHA 列在测试 `deps` / `pins`；冻结 v15 / contract01 未修改。测试临时编译产物已释放；没有交付可当作已验收 native 的 exe。
- 主控下一步：独立审计、冻结新 source/exe、按已授权 Windows 确认运行固定恢复；保存真实 stdout/exit、后验 hash 并核对 absence/resources，再决定是否继续新矩阵。worker 结果不能替代实际规则状态。
