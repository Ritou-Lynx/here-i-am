# i_core 测试债：公开 schema4 fixture 交接（2026-10-05）

工作基线：`codex/i-core-test-debt-20261005` / `f605d5017cbc0a8eb69983e00c25cd1bba08a0eb`。本 worker 只改迁移 / runtime pin 测试输入；未修改生产 pin builder、launcher、guard，未读取私人旧谱系，未提交工作树。

## 根因与逐项分类

共同根因是测试直接 `git show bbb8025d:tools/i_core/...`，净化公开历史没有这些旧 blobs。测试尚未运行到其安全断言即失败，不能归类为断言过时。

| 原基线编号 | 分类与保留断言 | 修复路径 |
|---|---|---|
| 1 | node_id 非法在迁移 hook 前拒绝 | 合成 schema4 seed |
| 2 | schema_version 非法在 hook 前拒绝 | 同上 |
| 3 | after_ddl 抛错回滚 | 同上 + fixture reader |
| 4 | before_commit 抛错回滚 | 同上 + fixture reader |
| 5 | 真正事务中 DDL / metadata / COMMIT 时序 | 同上 |
| 6 | COMMIT 后抛错保持 v5、无激活 | 同上 |
| 7 | owned Store 子进程 after_ddl 中断 | 同上 |
| 8 | owned Store 子进程 before_commit 中断 | 同上 |
| 9 | owned Store 子进程 after_commit 中断 | 同上 |
| 10 | DELETE journal before_commit 中断、热日志恢复 | 同上，reader 允许 SQLite 恢复自己的现有文件 |
| 11 | DELETE journal after_commit 中断 | 同上 |
| 12 | claim 后中断，不允许 busy / expired takeover | 同上 |
| 13 | 观察真实 clean close 后同路径重启 | 同上 |
| 14 | ledger 损坏状态不明，拒绝两个入口 | 同上 |
| 15 | 无 main 的 orphan sidecar 保留 | 同上 |
| 16 | 每个源 blob ID / SHA-256 / 字节绑定 | 明示真实合成 Git commit；不冒称旧 bbb blob |
| 17 | verify-only / 内容篡改 / manifest 错配无状态写入 | 隔离测试 builder / launcher 副本 |
| 18 | 缺失 / v5 DB guard 拒绝、字节不变 | 原生产 guard |
| 19 | WAL 中 v5 写入被拒绝、全部 sidecar 字节不变 | 原生产 guard |
| 20 | schema4 列变更被拒绝 | 原生产 guard |
| 21 | 环境清理、HTTP auth、真实 relay / journal、排他锁 | 原公开 server / relay 字节不改，显式 schema4 store adapter |

新增负向测试：原生产 builder 在合成仓库找不到固定 bbb blobs 时 fail-closed，且不生成 release；原生产 launcher 拒绝合成 commit manifest。缺失历史仍然禁止生成 / 接受真实旧版 pin。

## 改动与边界

- `tools/i_core/test_fixtures/schema4/synthetic_schema4.mjs`：静态八旧表 SQL、每表代表性合成数据、合法身份和 FK；独立固定 shape digest 仍由原 guard 校验。`seedSchema4(filename)` 可供 R3 使用；device token 为 `synthetic-token`，消息为 `M3 synthetic migration fixture`。
- `Schema4Reader` 仅校验 rollback 后聊天 / cursor 可读和逻辑不变；允许现有自建 DB 的 SQLite 热日志恢复。结果明确 `old_constructor_called:false` / `synthetic_reader_called:true`，不冒称执行旧历史 constructor。
- `tools/i_core/test_fixtures/schema4/runtime_pin_lab.mjs`：各测试临时 Git 仓库中保存真实公开源 bytes，store 只替换 activity constructor 为 dormant adapter，以保持 schema4。完整 server 路由 / auth、relay、PowerShell 与依赖保留真实公开源码。
- 临时 builder / launcher 副本仅重锚定该真实合成 commit、补齐 activity dependency inventory、明确 release 名为 `synthetic-public-schema4-test-only`。生产 BASELINE / Node hash / inventory / guard 全不改。
- `migration_m3/lab.mjs` 不再读取历史 commit；迁移证据字段更名为 `fixture_source_sha256` 并注明 `public_synthetic_schema4`。
- schema4 README 明示：自动验证的是公开代码与合成输入契约，不是缺失历史 executable 的兼容性接受，也不授予部署权限。

## 验证

专项命令：`node --test --test-concurrency=1 tools/i_core/migration_m3/migration.test.mjs tools/i_core/runtime_pin/runtime_pin.test.mjs`。

最终复验退出码 0：22 tests / 22 pass / 0 fail / 0 skip，含 15 原迁移项、6 原 pin 项和 1 新负向测试，耗时 82.2 秒。已包含公开源未改写断言与正确事件 kind；临时日志 `hereiam-fixture-worker-final-20261005.log`。`git diff --check` 对本 worker 路径通过。

仅测试自己的临时 DB、进程和 loopback listener；没有真实 state、在线服务、运行目录、部署或真人 Gate。R3 helper 由主窗单独持有并接入 seed，worker 没有改该路径。