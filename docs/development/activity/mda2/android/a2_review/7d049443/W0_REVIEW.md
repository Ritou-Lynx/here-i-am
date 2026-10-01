# A2 `7d049443` W0 独立审计

日期：2026-09-13
结论：**拒绝选择性集成，退回原 A2 任务修订。**

## 固定对象

- 候选：`7d0494436d55578d6388b12e69080a7741e4dc9d`
- 父项：`b55386cfc896c98376a071009f349dcbc88dc84b`
- 分支：`codex/mda2-a2-android-durable-20260913`
- 独立任务：`01a09933-d22f-7b53-9144-395a7a7ae6e8`
- 审计时工作树干净；diff 仅 12 个新增拥有路径，`git diff --check` 通过。

## 阻断项

`FileActivityOutboxStore._acquireForOpen` 先读取和验证 stale owner/anchor，随后只短暂取得并释放旧 `lease` 的 OS 独占锁，再无持锁、无二次 owner/anchor 核对地递归删除整个 owner 目录并创建新 owner。

两个恢复者可以同时持有同一旧 inspection。A 释放旧 lease 后，B 可先删除旧目录并创建新 owner；A 随后仍会删除 B 的新 owner 并接管。后续 `_verifyOwner` 可能使较早的新 owner fail closed，但这不能满足“旧 authority 只能替换它核准的精确 stale owner”的契约。

该缺陷为 P1，阻断 W0 独立复跑和集成。修订需要让稳定 OS 独占句柄覆盖二次 owner/anchor 核对与替换全过程，并用确定性双恢复者竞态测试证明较新 owner 不会被旧 authority 删除。

## 其余范围证据

- A1 manifest 的 8 个来源路径与冻结 `aa86` 实体 SHA 匹配。
- 9 个被测 owned 文件的 Git 原始字节与首版 post-final manifest 匹配。
- 未发现 HTTP、socket、真实设备、真实凭据或真实 Core 调用。
- 首版收据中共享 `activity_control_plane.test.mjs` 的 SHA 对应 CRLF 工作区字节；候选与基线的 Git LF blob 相同。后续收据须分开记录这两种哈希口径。

因为已存在语义阻断项，W0 没有把首版自报的测试结果提升为接收证据，也没有把该提交写入主线。
