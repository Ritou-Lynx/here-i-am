# W0 与 v3-lab 共同的 42 项既有失败

基线 `v3-lab@f605d5017cbc0a8eb69983e00c25cd1bba08a0eb` 串行复测：260 tests、217 pass、42 fail、1 skip。W0 原集成源码候选 `9b23d511fc28d588c3d1fe2c73014901e4824070` 的全目录测试：368 tests、325 pass、42 fail、1 skip。两者失败名称集合双向一致，说明这 42 项原本已在 v3-lab 中存在，并非本次合并引入。

这里是 Node 测试报告的 42 条失败条目：41 条终端失败，以及 1 条因 3 个失败子测试而失败的父测试汇总；不能解释成 42 个独立叶测试。一次默认并发基线测试另有 1 项共享临时目录观察失败；该项单测与串行复测均通过，不计入此清单。诊断线索涉及脱敏历史中缺失的冻结旧版 Core fixture，以及 Windows PowerShell 安全模块自动加载失败；后续修复任务必须逐项核实，不能统一判为过时测试或跳过。

机器可读清单：[W0_BASELINE_FAILURES_20261005.json](W0_BASELINE_FAILURES_20261005.json)。

| # | 分组 | 测试位置 | 失败名称 | 类型 |
|---|---|---|---|---|
| 1 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:95` | constructor preflight rejects node_id before any migration hook | 终端失败 |
| 2 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:95` | constructor preflight rejects schema_version before any migration hook | 终端失败 |
| 3 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:115` | formal Store constructor throw at after_ddl rolls back | 终端失败 |
| 4 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:115` | formal Store constructor throw at before_commit rolls back | 终端失败 |
| 5 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:126` | ControlPlane callback stages observe actual uncommitted DDL, metadata and committed transaction | 终端失败 |
| 6 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:147` | throw after COMMIT stays v5 without attempting ROLLBACK or activation | 终端失败 |
| 7 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:161` | actual owned child interruption: store/after_ddl | 终端失败 |
| 8 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:161` | actual owned child interruption: store/before_commit | 终端失败 |
| 9 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:161` | actual owned child interruption: store/after_commit | 终端失败 |
| 10 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:161` | actual owned child interruption: control-delete/before_commit | 终端失败 |
| 11 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:161` | actual owned child interruption: control-delete/after_commit | 终端失败 |
| 12 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:187` | actual child death after active claim refuses busy and expired takeover | 终端失败 |
| 13 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:202` | observed clean close permits normal same-canonical-path Core restart | 终端失败 |
| 14 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:219` | damaged ledger is indeterminate and neither entry is permitted | 终端失败 |
| 15 | M3 migration | `tools/i_core/migration_m3/migration.test.mjs:231` | orphan sidecar without main is indeterminate and preserved | 终端失败 |
| 16 | Runtime pin | `tools/i_core/runtime_pin/runtime_pin.test.mjs:142` | runtime pin freezes every packaged source blob at bbb8025d | 终端失败 |
| 17 | Runtime pin | `tools/i_core/runtime_pin/runtime_pin.test.mjs:166` | verify-only, content tamper, and manifest mismatch never open or create external state | 终端失败 |
| 18 | Runtime pin | `tools/i_core/runtime_pin/runtime_pin.test.mjs:188` | schema-v4 guard rejects missing and schema-v5 state without modifying either | 终端失败 |
| 19 | Runtime pin | `tools/i_core/runtime_pin/runtime_pin.test.mjs:209` | guard rejects a schema-v5 write still resident in WAL and leaves all source bytes untouched | 终端失败 |
| 20 | Runtime pin | `tools/i_core/runtime_pin/runtime_pin.test.mjs:241` | guard rejects a schema-4 database whose table columns were changed | 终端失败 |
| 21 | Runtime pin | `tools/i_core/runtime_pin/runtime_pin.test.mjs:261` | pinned v4 start clears inherited enablement and holds its external runtime lock | 终端失败 |
| 22 | R3 guardian | `tools/i_core/runtime_upgrade/r3/combination.test.mjs:66` | combined release binds frozen M3 source bytes and fixed source table rejects a baseline-restored blob | 终端失败 |
| 23 | R3 guardian | `tools/i_core/runtime_upgrade/r3/combination.test.mjs:91` | post-COMMIT M3 hook throw leaves v5 with empty claim but no R3 clean receipt, so R3 refuses restart before Store construction | 终端失败 |
| 24 | R3 guardian | `tools/i_core/runtime_upgrade/r3/faults.test.mjs:14` | invalid v4 shape rejects without starting migration; open sidecar and missing DB reject without constructor | 终端失败 |
| 25 | R3 guardian | `tools/i_core/runtime_upgrade/r3/faults.test.mjs:30` | crash after schema5 listener creates real missing-close evidence and refuses automatic original-path restart | 终端失败 |
| 26 | R3 guardian | `tools/i_core/runtime_upgrade/r3/faults.test.mjs:50` | accepted migration followed by listen failure closes the same store and supports normal original-path restart | 终端失败 |
| 27 | R3 guardian | `tools/i_core/runtime_upgrade/r3/faults.test.mjs:68` | cancel with a live incomplete HTTP request forces actual child exit and keeps shutdown unconfirmed | 终端失败 |
| 28 | R3 guardian | `tools/i_core/runtime_upgrade/r3/lifecycle.test.mjs:9` | fixed PS entry defaults verify-only and rejects unknown/runtime flags before database mutation | 终端失败 |
| 29 | R3 guardian | `tools/i_core/runtime_upgrade/r3/lifecycle.test.mjs:24` | explicit migration preserves eight old tables, dormant HTTP and clean original-path restart; lock prevents second instance | 终端失败 |
| 30 | R3 guardian | `tools/i_core/runtime_upgrade/r3/lifecycle.test.mjs:54` | fingerprint, inventory and canonical/link path rejections precede store construction | 终端失败 |
| 31 | R3 guardian | `tools/i_core/runtime_upgrade/r3/lifecycle.test.mjs:82` | occupied loopback rejects before migration; absent or forged receipts cannot prove exit | 终端失败 |
| 32 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:60` | continuous configured service exceeds 120 seconds, public APIs work, protected operator close confirms complete Job | 终端失败 |
| 33 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:120` | authenticated close removed after both observers have checked it does not stop the service | 终端失败 |
| 34 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:192` | non-ENOENT control read failure remains fail closed | 终端失败 |
| 35 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:202` | explicit disabled configuration rejects all enablement routes and inherited environment; cancellation is clean | 终端失败 |
| 36 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:216` | parent process death reaps actual Job members but cannot mint a clean receipt or authorize crash restart | 终端失败 |
| 37 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:236` | config path ACL, binding, unknown fields, overlap and unsupported relay reject before store construction | 终端失败 |
| 38 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:251` | guardian process alone dies: live parent fails closed and reaps its root and descendants without clean receipt | 终端失败 |
| 39 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:266` | CREATED | 终端失败 |
| 40 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:266` | DUPLICATED | 终端失败 |
| 41 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:266` | PUBLISHED | 终端失败 |
| 42 | R3 guardian | `tools/i_core/runtime_upgrade/r3/service.test.mjs:264` | parent death at each real guardian bootstrap barrier cannot leave suspended processes or a held runtime lock | 父测试汇总 |
