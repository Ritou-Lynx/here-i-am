# P6 Task Executor 重复副本清理（2026-09-29）

## 结果

- 清理根：`D:\HereIAm-P6-R7-Task-Executor`。
- 仅删除 18 个已闭合历史 attempt 中的精确文件 `codex.exe`；保留 attempt 目录、全部 JSON 收据、日志和诊断。
- 删除逻辑大小与物理分配大小均为 `5,317,360,992` bytes（4.952 GiB）。
- 删除瞬间 D 盘可用空间为 `24,362,799,104` → `29,680,209,920` bytes（22.690 → 27.642 GiB），净变化 `5,317,410,816` bytes；比目标物理占用多 `49,824` bytes，说明同窗仍有其他磁盘活动，不能把净变化完全归因于本次清理。
- 删除后 18 个目标均不存在；根下仍保留 124 份 `codex.exe`。

## 删除资格

每个目标都在删除前再次满足：

1. 路径位于精确根目录内，根、attempt 目录、目标文件和必需收据均不是重解析点；目标只有一个硬链接。
2. `prepared/bound/closed/cleanup/final` 身份字段一致，cleanup 收据 closed、rules/helper handles 为 true；final 的 operation/stdout 与六项清理事实为 true，`cleanup_pending=false`。
3. final 自身的 `pending_actual_exit_commit` 不单独作为完成证据；另有对应 `app-lifecycle-owned-*` 外层真实关闭、原 native `exit_code=0`、六项清理事实，以及 `native-identities.jsonl` 的 PID / creation FILETIME / image hash / parent 观测匹配。
4. `codex.exe` 大小均为 `295,408,944` bytes，SHA-256 均为 `3D6CA7085C932B62EF4EE4877E92F15B050FB94B2EB8E6C10A346A06248C6004`，与受保护固定源一致；删除前逐项通过只读独占打开。
5. 删除前复核当前进程没有从该根启动的可执行文件；删除在单个 PowerShell 流程中以 `-LiteralPath` 对下列精确文件执行。

## 精确删除清单

```text
D:\HereIAm-P6-R7-Task-Executor\01dbcdc59f64481c8acfe7db8ddb7572\codex.exe
D:\HereIAm-P6-R7-Task-Executor\0a0014e4b74e442b87524f147cd60566\codex.exe
D:\HereIAm-P6-R7-Task-Executor\1fbce7d2517b4979bf4f8c13cfb725fa\codex.exe
D:\HereIAm-P6-R7-Task-Executor\38a13bfcf8f7414c814d3e7b327a76d1\codex.exe
D:\HereIAm-P6-R7-Task-Executor\454f5b6cf92d4d669365e6f96f5a23f6\codex.exe
D:\HereIAm-P6-R7-Task-Executor\4f2e98c182b147d0a667ea00f68b4509\codex.exe
D:\HereIAm-P6-R7-Task-Executor\78ed23b55bdf4ccb8fdc5b4cf0e80b8c\codex.exe
D:\HereIAm-P6-R7-Task-Executor\792ecdbc61a644a7be899fe355032db9\codex.exe
D:\HereIAm-P6-R7-Task-Executor\7af78a0628ad4e77a2e35f685f6da6a0\codex.exe
D:\HereIAm-P6-R7-Task-Executor\87e097c7da9b426f84c875cc822f20c1\codex.exe
D:\HereIAm-P6-R7-Task-Executor\a42653de39c94376a6d38a37fe21f57f\codex.exe
D:\HereIAm-P6-R7-Task-Executor\a624746eac754e4bb4caf8a41d259e88\codex.exe
D:\HereIAm-P6-R7-Task-Executor\ae4b79c8fa1145da853b2345f258e41e\codex.exe
D:\HereIAm-P6-R7-Task-Executor\aee65246f5284bd3a0253b4db9009382\codex.exe
D:\HereIAm-P6-R7-Task-Executor\b2cc9512759242eab441f1761a0da60b\codex.exe
D:\HereIAm-P6-R7-Task-Executor\e33bbd9ad4dc49bb9c8ad26fc03b7a9d\codex.exe
D:\HereIAm-P6-R7-Task-Executor\ebb0580a2fe14393977f0ee7df0f0341\codex.exe
D:\HereIAm-P6-R7-Task-Executor\f3bcf4c59ff7460995cef1c8d4b00835\codex.exe
```

## 明确保留

- 固定源 `52572f7de2d14177888bcc8e66cfc553\codex.exe`：当前 P6 恢复/调用链仍直接引用；删除前后 SHA-256 均与上值一致。
- 2026-09-27 当前/最新失败链的 17 份 attempt：`089ca522...`、`2674c073...`、`28dfa163...`、`2916e002...`、`587a6b42...`、`73115fa4...`、`78e87d79...`、`802c5fa4...`、`85387866...`、`8fb88570...`、`9acf90e8...`、`c3a51d76...`、`c677e6a5...`、`c81ce6d9...`、`d1e6101c...`、`e933a857...`、`f83e95de...`。
- 其余 106 份 `codex.exe`：收据缺失/失败/cleanup pending、异常关窗、没有独立 native identity，或没有合格外层真实关闭证据；全部保守保护。
- `tmp/p6-r7-review/retry-20260927`、最新 C3 失败证据、所有 executor 收据与诊断、目录本身；未操作设备、生产状态、Git 索引、commit 或 push。

## P6 状态边界

本清理只处理已闭合历史 attempt 的重复二进制，不改变当前 P6 判断。最新 C3 仍是启动握手失败：原 Node 实际退出缺证、App 异常退休、正常双关闭 Gate 未过；当前修复工作继续使用受保护固定源与最新证据链。
