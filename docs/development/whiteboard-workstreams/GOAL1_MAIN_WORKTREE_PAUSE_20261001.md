# Goal 1 主 worktree 核验与后续暂停（2026-10-01）

## 当前落点

用户要求到此暂停，并将本轮成果与主 worktree 合并。主 worktree 为 `D:/memex`，分支 `v3-lab`，HEAD `b2adc44b7c04983a931c39695b81491cd295084b`。Goal 1 本地验收已按 [最终判定](GOAL1_FINAL_LOCAL_ACCEPTANCE_20261001.md) 完成；生产启用与减弹窗改造尚未开始，按用户指令暂停。

本轮核验确认源码已经落在主 worktree：[接线记录](GOAL1_P6_PRODUCT_WIRING_20260930.md) 中的 14 个差异文件与 7 个新增文件已在先前选择性集成，保留了主树 `AppDatabase.openCandidate` 等并行增量。`source-manifest-runtime-v3.json` 的 104 个受控路径现在仍全部同哈希，0 缺失、0 漂移。

`codex/goal1-p6-product-wiring` 与 `v3-lab` 同 HEAD，没有本任务独有提交可供 Git merge；不再整枝覆盖主树。源码以主 worktree 的未提交修改保存，Git 索引在此次核验前后均为空。未创建 commit、未 push、未发布；其他并行修改和两个附属验收 worktree 原样保留。

## 可恢复快照

- 源码清单：`tmp/goal1-p6-combined-20261001/source-manifest-runtime-v3.json`，SHA-256 `D612BC5668D64AF8EC1341D398DBF50A250A3F3C8E1FDFF6A21A7CD152B88509`。
- 本地源码归档：`tmp/goal1-pause-checkpoint-20261001/source-104.zip`，566225 字节，SHA-256 `44BB09919258523FE5D31D00F60D6013BB87220EC4D278F38E8FD99EA04B1087`。
- 归档含 104 个受控源码文件和上述清单；ZIP 完整性、逐文件解压哈希均通过。它仅覆盖这 104 个路径，不是整个仓库或全部原生构建输入的备份；不含数据库、凭据、CLI、App 包或原生二进制。
- 核验元数据：`tmp/goal1-pause-checkpoint-20261001/checkpoint.json`。既有验收包和脱敏回执继续留在原目录，未清理。

## 恢复入口

恢复时先核对主 worktree 的分支、HEAD、现有改动与 104 路径源码哈希，再读最终本地验收判定。生产启用评估与减少系统确认的原生执行器改造属于后续工作，必须保留默认拒绝，并以新候选完成对应验证；不继承旧原生哈希的真人结果。此次暂停没有启动应用、队列任务或新的系统提权程序。
