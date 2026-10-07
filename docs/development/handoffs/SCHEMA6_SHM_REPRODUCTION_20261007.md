# Schema 6 在线只读捕获 SHM 合成复现（2026-10-07）

## 结论与授权边界

固定发布版 `captureConsistentSqlite` 在独立写进程保持 WAL 库打开、提交后不再执行任何 SQL 的条件下，仍会改变 SHM。三个全新根均仅改变 offset 104 的一个字节 `02 → 03`，原生小端 `aReadMark[1]` 从 2 变成 `mxFrame=3`。DB/WAL 的存在、大小、SHA-256、dev/ino 全部不变；SHM 的身份、大小、0..95 头、其余字节均不变。此证据足以否定“在线只读捕获前后整个 SHM 必须同哈希”的比较前提。

仅创建、读取、关闭/强杀和清理合成进程/合成库；未打开、停止、配置或复制现役数据库，未修改固定 release、guard 或私有执行器，未 commit/push。主窗负责 guard 决策和全局状态交接。

## 固定实现与复核

- 基线 Git commit：`1552e251c18c4554d425a0051ea7452e4904bb40`。
- Node `v24.14.1`，内置 SQLite `3.51.2`，Windows / LE；Node SHA-256 `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`。
- 固定 release manifest SHA-256 `6ae8f970a08ee8f21f8c78ba8846273144101cbdd8d3a2cb0530d5a3daf6b1ff`；`verifyRelease` 47 文件通过。
- 实际导入固定 release 捕获模块 SHA-256 `bff29b4a0e28c8ab84b0ba353889d435c03d15966395c2d06fd14c21de850d7f`，与基线 Git blob 精确相等。工作树 SHA `fc55bda5df8a6ef2faa75e7d5541b50d8fad7d691261cf16f62705f47c0f3936` 仅因 CRLF 不同，LF 规范化后完全一致。
- 默认测试调用仓库模块；固定发布复验通过显式 `ONLINE_SHM_OPTIONS` 指定模块/发布根/manifest/Node pin，CI 不硬编码本机盘符。

## 实验设计与结果

每个场景使用 `syntheticRoot` 创建全新库；独立 writer 在 `wal_autocheckpoint=0` 后创建表并提交两行合成值，随后封住 SQL 入口，只用 IPC 保活和应答。ready 后没有计时器、SELECT、PRAGMA 或 checkpoint。捕获前后 IPC 回报一致且 writer 存活；正常关闭及强杀对照则先等待合成 writer 退出。SELECT 对照为另一个独立进程，使用 `readOnly:true` 和 `mode=ro`，只执行一次 SELECT。

| 场景，每组新根 3 次 | 捕获/读取前后 DB/WAL | SHM 变化 | 验证 |
| --- | --- | --- | --- |
| 独立空闲 writer + 固定 capture | DB 4096、WAL 12392 字节；全部身份/哈希稳定 | 仅 offset 104，`aReadMark[1] 2→3` | writer 存活、零后台 SQL、3/3 复制含两条正确记录 |
| 正常关闭 writer，再 capture | 关闭动作已 checkpoint，使 DB 8192；capture 本身 DB 不变，WAL 从无到 0 字节 | capture 从无创建 32768 字节 SHM，`mxFrame=0` | 3/3 复制正确；此条件不是活动 WAL 的等价对照 |
| 强杀合成 writer，保留 WAL，再 capture | DB/WAL 存在、大小、哈希、身份稳定 | offset 8/40/44/56/88/92/104/128；含双份头及 checksum、读标记、`nBackfillAttempted 0→3` | 3/3 复制正确；更符合静止库重新接入时 SHM 恢复，不能只称读标记变化 |
| 独立空闲 writer + 独立只读 SELECT | DB/WAL 全部稳定 | 仅 offset 104，`aReadMark[1] 2→3` | 3/3 两条结果正确、writer 存活且零后台 SQL |

逐字节 diff 比较整个文件，JSON 保留各文件存在/大小/SHA-256/dev/ino、SHM 前 136 原始字节、双份 48 字节头、原生序读标记、全部 changed offsets 及前后 byte 值。Windows 120..127 是文件锁保留位置；本次这些字节未变，不能把读标记变化叫作“锁页变化”。[SQLite WAL format](https://www.sqlite.org/walformat.html) 说明了 SHM 原生字节序、read-mark 字段、锁位置及重新连接/关闭时的生命周期。[WAL 文档](https://www.sqlite.org/wal.html) 与[临时文件文档](https://www.sqlite.org/tempfiles.html#shared_memory_files) 提供 WAL 和共享内存文件的作用及生命周期背景。SQLite明确SHM不存持久数据、可从WAL重建；普通可写wal-index下读连接也会写read-mark，readOnly数据库并不承诺SHM字节不变。

## 文件与复跑

- `tools/i_core/release_schema6/online_shm_reproduction.test.mjs`：Node test 入口；默认四场景各一次。
- `tools/i_core/test_fixtures/release_schema6/online_shm_probe.mjs`：采样、精确 diff、固定发布可选验证、复制正确性和独立 writer 状态断言。
- `tools/i_core/test_fixtures/release_schema6/online_shm_worker.mjs`：独立 writer 与只 SELECT 一次的 reader；只能使用明确新建合成根。
- `tools/i_core/test_fixtures/release_schema6/online_shm_result_20261007.json`：最终固定发布的 12 场景纯合成结果，SHA-256 `acfbdc7ec53f1bf3ea449f3683d72861eef8a43a2c566fae98f58fcc9e6111e1`。

默认：`node --test tools/i_core/release_schema6/online_shm_reproduction.test.mjs`。
固定发布：在相同命令前将 `ONLINE_SHM_OPTIONS` 设置为 JSON，字段为 `captureModule`、`releaseRoot`、`manifestSha256`、`nodeSha256`、`repeats:3`；两个路径由执行者显式指定已授权 release。runner 将参数经 CLI 传给净化环境子进程，不传入 Core、代理、模型或账户配置。Windows 创建进程可能自动补入 OS 账户/PATH 字段，probe/worker 在任何数据库工作前将非 allowlist 字段删除；不输出环境值。所有合成根清理前验证绝对路径、前缀和原始目录身份。

首版夹具在任何库创建前因 Windows 自动补入环境字段而失败；修正清理后源树默认 4 场景通过。固定发布四组各三次预设独立复验通过；增加前 136 原始字节保存及所有场景 DB 稳定断言后，最终同样 12 场景全部通过。没有以重试筛除负复现或修改合成 WAL/SHM 字节迎合预期。

## 限制

这些结果只证明该固定 Node/SQLite/Windows、明确 WAL 状态与连接生命周期下的合成行为；不证明真实库发生过同一变化，也不授权现役重跑。SHM 是可变协调状态，但不能因此容许 DB/WAL、配置、密钥、release 的变化；更不能把所有未知 SHM 变化归为这次证实的 read-mark 更新。只读并非整个文件集合物理零变化。三次重复使用新根且遇负结果立即失败，未调用真实库；尚未得到跨 OS / SQLite 版本的同等证据。
