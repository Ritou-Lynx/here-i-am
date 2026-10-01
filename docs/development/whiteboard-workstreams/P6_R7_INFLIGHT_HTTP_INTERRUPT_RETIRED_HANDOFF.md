# P6 R7 HTTP interrupt 精确退役恢复

2026-09-12 当前状态：主控已实际执行恢复 v2 的只读检查和精确清理，两次恢复程序均退出 `0`。目标仅为失败实例 `6946c568-0440-4574-8fbc-2d069b071c6c`，scope `b313153a-b5bb-2fe8-cbe1-ba150d3de67c`。当前规则已移除、恢复资源已关闭，`recovery_pending=false`；原 HTTP interrupt02 仍然失败。

## 固定边界与原失败

恢复源码固定八份实例记录、复制 CLI、冻结 v7 源码/程序及原实际报告。prepared/spawning/bound/install、closed 和 final 必须属于同一绑定；目录 ACL、完整路径及各祖先不含 reparse，文件由持有句柄及哈希复核。当前 owner/child/helper 的 PID 与创建时间、同映像活动进程、AppID、权重及规则身份均须验证。

只有显式 `--apply-cleanup` 可在写事务内删除固定三个过滤器和一个子层；`--inspect` 只读。规则部分存在或身份不符时拒绝删除，关闭失败保持失败状态并保留资源责任。恢复不启动模型、不读取凭据、不修改旧报告，也不查询或重建原 Job 会话。

原 [inflight-http-interrupt-02.json](../../../tmp/p6-r7-review/inflight-http-interrupt-02.json) SHA-256 为 `F697DF1BD14F3555B94DA90CBFD09B026ECE6FA7541F516AD79C58DD140B5F99`：提供方已出现匹配 `interrupted`，但 native 实际退出 `4`；process/job/stdio/handles 为 true，rules/helpers 为 false，待清理为 true，stop receipt 未验证。其 final 的 `operation_failed=false` 与退出 `4` 并不矛盾：关闭不完整也会退出 `4`。恢复成功不能补成历史正常退出或取消回执。

## 取消、v1 校验失败与 v2 成功分别保留

- 较早的 [inflight-retired-launch-cancelled-01.json](../../../tmp/p6-r7-review/inflight-retired-launch-cancelled-01.json) 仅记录当时 UAC 启动被取消：administrator process 未启动、未检查或清理。记录中“报告不存在”是该时点事实，不能覆盖后续运行。
- 本轮 v1 管理员程序确已启动。[inspect-actual-01](../../../tmp/p6-r7-review/native-inflight-retired-inspect-actual-01.json) 与 [capture-01](../../../tmp/p6-r7-review/native-inflight-retired-inspect-capture-01.json) 记录实际退出 `2`、`failure_stage=1`、零删除、`resources_closed=true`。这是 `ClosedHash` 字面量零基索引 13/14（第 14/15 个字符）抄写互换导致的固定文件校验失败，不是系统授权取消。
- v2 将 `ClosedHash` 改为原独立清单中的 `186E914B57CFFEFC6BB830F5843FD15F5753B37BB78EC898D394ACB284C19517`。程序化比较确认：归一化换行后，v1/v2 源码仅此字面量不同；原字节另有该行一处 CRLF→LF 变化。

## v2 实际结果与证据

只读检查完整匹配三个过滤器和子层，未删除，仍 `recovery_pending=true`。随后清理在事务内精确删除 **3 filters + 1 sublayer**；提交后确认 `current_rules_absent_verified=true`、`resources_closed=true`、`transaction_ended=true`、`recovery_pending=false`，两次 `failure_stage=0`。历史字段仍是 `cleanup_pending=true`、`historical_cleanup_pending=true`、`historical_http_interrupt_passed=false`、`historical_stop_receipt_verified=false`；`exact_child_closed`/`job_active0` 仍 null，未捏造 helper 原退出证明。

| 文件 | SHA-256 |
| --- | --- |
| [inspect-actual-02](../../../tmp/p6-r7-review/native-inflight-retired-inspect-actual-02.json) | `2678B62C0440FDABAE201FA72591B9A929E0BF283922DEF253EB0DAB363DAB09` |
| [inspect-capture-02](../../../tmp/p6-r7-review/native-inflight-retired-inspect-capture-02.json) | `BD9B219AD66CC4EF0C85C1746F5B79CE73947662A2EF08513BC165D30A07CD7C` |
| [cleanup-actual-02](../../../tmp/p6-r7-review/native-inflight-retired-cleanup-actual-02.json) | `EEFA0B104AAD0F4BC39C584E3AB5FF255099B4EA8D53B6D72E34727F3EC2BA15` |
| [cleanup-capture-02](../../../tmp/p6-r7-review/native-inflight-retired-cleanup-capture-02.json) | `EABBBC18A75CFAA42294EF097A8884CC1D477632B1F0AEAD3AB185FDAE645FF4` |
| [verification](../../../tmp/p6-r7-review/native-inflight-retired-02-verification.json) | `DFA19B35E16C1648F5B41B5F7C81508D5497FAF8596F9E4CF37079CA6173B890` |
| [build](../../../tmp/p6-r7-review/native-inflight-retired-02-build.json) | `ED65B08227F6B7569C1FB418EBABA7A86BD299E10BC9A66E42443FB7C0241C87` |

本次文档更新独立重新计算以上哈希、capture 所记 stdout 摘要与实际退出 `0`、程序后置 pin，以及 verification 的 **9/9** 当前输入；均匹配。

## 固定候选与纯验证

- 当前源码及冻结 `native-inflight-retired-02.cs`：`31B82E0A8AB5E9AB08B8E1F6E69B36290D833E1B472E0C301A1E94C4EE67B9D5`。
- 当前测试：`1BC56664CD9A13079FF91FE72827BF22155A02C7420F074447F9ECA187653173`。
- 实际 v2 程序 `windows_text_gate_task_inflight_retired.v2.exe`：`729BAC6E909758F12E522D3D6F7F1B06F980F51C4309E63C561E4D29EACF31A9`。

主控专项 **2/2** 通过，新增源码八份记录常量与 [独立输入清单](../../../tmp/p6-r7-review/inflight-interrupt-retired-inputs-01.json) 的逐项比对回归；编译开启 `/warnaserror+`，build 记录编译/自测均退出 `0`、**260 项纯自测**。本轮文档 worker 仅只读核对并更新本文件，没有重跑清理、启动实际程序、修改源码或读取凭据。生产和真人 Gate 均未启用。
