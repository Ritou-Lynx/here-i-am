# i_core 42 项既有测试债修复（2026-10-05）

状态：42 条既有失败全部在最终默认并发与串行完整复验中通过；候选尚未提交、推送、合入或部署。

## 基线与范围

- 分支：`codex/i-core-test-debt-20261005`；精确基线 `f605d5017cbc0a8eb69983e00c25cd1bba08a0eb`；初始工作树干净。
- 输入清单来自 W0 的 `W0_BASELINE_FAILURES_20261005.json`：42 条报告项 = 41 个叶测试 + 1 个失败父测试汇总。
- 基线串行：260 tests / 217 pass / 42 fail / 1 skip；默认并发：260 / 216 / 43 / 1。额外并发失败为全局 TEMP 目录观察干扰。
- 只修复本独立工作树的源码、fixture 和验证文档；未修改 W0、运行副本、在线服务、手机、真实数据库、policy 或凭据。

## 根因与处理

1. M3 #1–15：断言仍有效，测试输入失效。缺失 `bbb8025d` 历史 Store；补公开静态 schema4 DDL 与八表代表性合成数据，固定生产 v4 guard 校验形状。保留前置拒绝、DDL/COMMIT、rollback、真实自有子进程中断、claim 与恢复拒绝、旧数据和游标读取断言。
2. Pin #16–21：断言仍有效，测试输入失效。用自建临时 Git 的真实合成 commit/blob 验证打包；明确改名标注合成来源。真实公开 server/relay 不改字节，Store 仅在临时包替换 activity schema 构造。保留 manifest、Node、source byte/blob/hash、tamper、完整 WAL 视图、HTTP auth、relay journal 与运行锁断言。生产 builder/launcher/guard 不变；新增缺历史及合成 provenance 的生产拒绝负例。
3. R3 #22–42：验证基建代码缺陷与失效历史输入。继承 PowerShell 7 的 PSModulePath 使 Windows PowerShell 5.1 Security 模块因 TypeData 冲突无法加载。cleanEnvironment 收敛到 Windows 内置模块，并补不可信继承值回归。六份固定 Core hash 不变，全部经公开 f605 Git blob 独立复核相等；源码来源重锚定到该公开 commit。所有完整 Job/guardian、ACL、锁、真实退出、clean receipt 与 crash-restart 拒绝断言保留。
4. 额外并发失败：测试以全局 activity-preflight-* 集合观察清理，误读其他文件并行创建的合法目录。改为受限 testOnlyTemporaryPrefix，只观察该调用拥有的 TEMP 前缀；保留清理和源主文件/sidecar 字节断言。非法路径前缀在创建前拒绝，allowMissing 不从 recovery API 下传。
5. 完整复验发现的夹具发布竞态：JS 直接写入 stop / descendant.json，.NET 在 File.Exists 后可能于写句柄尚未关闭时读取而报共享锁错误。stop 改为同目录关闭后 rename、重复调用幂等；descendant 改为同目录关闭后硬链接原子发布，以保留目标不覆盖语义。未改 native supervisor / witness / guardian，未加吞错、retry、skip 或删退出断言。

## 逐项矩阵

编号沿用原始 42 条清单，原始测试名称完整保留。以下每项均与两套最终日志中的真实 PASS 名称逐一匹配（含3个明确改名映射）。

| # | 原始测试名称 | 判定 | 处理与保留断言 | 复验 |
|---|---|---|---|---|
| 1 | `constructor preflight rejects node_id before any migration hook` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 2 | `constructor preflight rejects schema_version before any migration hook` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 3 | `formal Store constructor throw at after_ddl rolls back` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 4 | `formal Store constructor throw at before_commit rolls back` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 5 | `ControlPlane callback stages observe actual uncommitted DDL, metadata and committed transaction` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 6 | `throw after COMMIT stays v5 without attempting ROLLBACK or activation` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 7 | `actual owned child interruption: store/after_ddl` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 8 | `actual owned child interruption: store/before_commit` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 9 | `actual owned child interruption: store/after_commit` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 10 | `actual owned child interruption: control-delete/before_commit` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 11 | `actual owned child interruption: control-delete/after_commit` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 12 | `actual child death after active claim refuses busy and expired takeover` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 13 | `observed clean close permits normal same-canonical-path Core restart` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 14 | `damaged ledger is indeterminate and neither entry is permitted` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 15 | `orphan sidecar without main is indeterminate and preserved` | 测试输入失效；行为断言有效 | 公开 schema4 合成种子；原迁移/拒绝/中断/保留断言不变 | 默认 PASS；串行 PASS |
| 16 | `runtime pin freezes every packaged source blob at bbb8025d` | 测试输入失效；安全断言有效 | 真实合成 Git fixture + 公开 server/relay；生产 pin 固定拒绝不变 | 默认 PASS；串行 PASS |
| 17 | `verify-only, content tamper, and manifest mismatch never open or create external state` | 测试输入失效；安全断言有效 | 真实合成 Git fixture + 公开 server/relay；生产 pin 固定拒绝不变 | 默认 PASS；串行 PASS |
| 18 | `schema-v4 guard rejects missing and schema-v5 state without modifying either` | 测试输入失效；安全断言有效 | 真实合成 Git fixture + 公开 server/relay；生产 pin 固定拒绝不变 | 默认 PASS；串行 PASS |
| 19 | `guard rejects a schema-v5 write still resident in WAL and leaves all source bytes untouched` | 测试输入失效；安全断言有效 | 真实合成 Git fixture + 公开 server/relay；生产 pin 固定拒绝不变 | 默认 PASS；串行 PASS |
| 20 | `guard rejects a schema-4 database whose table columns were changed` | 测试输入失效；安全断言有效 | 真实合成 Git fixture + 公开 server/relay；生产 pin 固定拒绝不变 | 默认 PASS；串行 PASS |
| 21 | `pinned v4 start clears inherited enablement and holds its external runtime lock` | 测试输入失效；安全断言有效 | 真实合成 Git fixture + 公开 server/relay；生产 pin 固定拒绝不变 | 默认 PASS；串行 PASS |
| 22 | `combined release binds frozen M3 source bytes and fixed source table rejects a baseline-restored blob` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 23 | `post-COMMIT M3 hook throw leaves v5 with empty claim but no R3 clean receipt, so R3 refuses restart before Store construction` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 24 | `invalid v4 shape rejects without starting migration; open sidecar and missing DB reject without constructor` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 25 | `crash after schema5 listener creates real missing-close evidence and refuses automatic original-path restart` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 26 | `accepted migration followed by listen failure closes the same store and supports normal original-path restart` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 27 | `cancel with a live incomplete HTTP request forces actual child exit and keeps shutdown unconfirmed` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 28 | `fixed PS entry defaults verify-only and rejects unknown/runtime flags before database mutation` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 29 | `explicit migration preserves eight old tables, dormant HTTP and clean original-path restart; lock prevents second instance` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 30 | `fingerprint, inventory and canonical/link path rejections precede store construction` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 31 | `occupied loopback rejects before migration; absent or forged receipts cannot prove exit` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 32 | `continuous configured service exceeds 120 seconds, public APIs work, protected operator close confirms complete Job` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 33 | `authenticated close removed after both observers have checked it does not stop the service` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 34 | `non-ENOENT control read failure remains fail closed` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 35 | `explicit disabled configuration rejects all enablement routes and inherited environment; cancellation is clean` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 36 | `parent process death reaps actual Job members but cannot mint a clean receipt or authorize crash restart` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 37 | `config path ACL, binding, unknown fields, overlap and unsupported relay reject before store construction` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 38 | `guardian process alone dies: live parent fails closed and reaps its root and descendants without clean receipt` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 39 | `CREATED` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 40 | `DUPLICATED` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 41 | `PUBLISHED` | 验证基建缺陷 + 历史输入失效 | PS5 内置模块；同哈希公开来源；原真实进程/锁/receipt 断言保留 | 默认 PASS；串行 PASS |
| 42 | `parent death at each real guardian bootstrap barrier cannot leave suspended processes or a held runtime lock` | 父测试汇总；非独立产品缺陷 | 三个真实 bootstrap 子场景全部复验；父汇总随之通过 | 默认 PASS；串行 PASS |

原 #16 当前名为 `runtime pin test package binds every source byte to its explicit synthetic Git commit`；#21 当前名为 `synthetic schema4 pin with public server clears inherited enablement and holds its external runtime lock`；#22 的负例改为 rehashed substituted blob。名称修改明确真实覆盖范围，原安全谓词仍在。

## 验证证据

- M3 + pin 最终专项：22/22 pass，0 fail，0 skip；日志 `%TEMP%/hereiam-fixture-worker-final-20261005.log`。
- 当前 activity 全文件：108 tests / 107 pass / 0 fail / 1 skip；前缀窄化后的受影响专项：1 pass / 0 fail / 0 skip。
- R3 combination + lifecycle 首轮：6/6 pass；补继承模块路径断言后会由两种完整模式复验。
- R3 faults + service 首轮：17 tests / 16 pass / 1 fail / 0 skip；失败为新 seed 中 M3 的 stale job 被真实 reclaim 领取，返回 m3-message 而非 r3-turn。已恢复原 R3 chat-only 输入（worker/job/shadow 为空），未改领取断言；日志 `%TEMP%/i-core-debt-r3-service-20261005.log` 与 `i-core-debt-r3-continuous-diagnosis-20261005.log` 保留。持续服务专项修后 1/1 pass，实际监听 125030 ms，完整 Job 退出与原路径重启确认；日志 `%TEMP%/i-core-debt-r3-continuous-fixed-20261005.log`。
- 默认并发首轮：261 tests / 258 pass / 2 fail / 1 skip，退出 1，265.1 秒。新增 pin 负例使总数从 260 到 261；两红分别为 server restart 的 fetch failed、R3 startup 的 fixture_wait_timeout。原日志 `%TEMP%/i-core-debt-full-default-20261005.log` 保留；第二轮默认并发：261 / 259 / 1 / 1，388.4秒；唯一失败为取消场景 timeout=4500 被误用于启动等待（本轮实现错误），已明确分开为独立60s启动预算，关闭/退出预算保持原值。第二轮日志 `%TEMP%/i-core-debt-full-default-final-20261005.log` 保留。上述为诊断轮次；最终两种模式均已通过。
- 上一候选完整串行：261 tests / 260 pass / 0 fail / 1 skip，exit 0，1049.3秒；日志 `%TEMP%/i-core-debt-full-serial-final-r2-20261005.log`。同候选默认并发：261 / 258 / 2 / 1，exit 1，406.8秒，失败为自有 stop 与 descendant.json 的写句柄共享锁竞态，日志 `%TEMP%/i-core-debt-full-default-final-r2-20261005.log`。
- 发布竞态修后：M3 supervision 7/7 pass，0 fail/skip；guardian 死亡专项 1/1 pass，全部退出与 Job 清空断言通过，clean_receipt:false 保留。日志 `%TEMP%/i-core-debt-m3-supervision-atomic-20261005.log`、`i-core-descendant-guardian-targeted-20261005.log`。独立持有写句柄实验确认旧模式读取失败、新模式在关句柄前 final 不存在、发布后完整读取、重复 descendant 发布报 EEXIST 且原内容不变。
- 最终同一候选、相同递归16文件：默认并发 **261 tests / 260 pass / 0 fail / 1 skip**，exit 0，391.5秒；串行 **261 / 260 / 0 / 1**，exit 0，910.7秒。两个 runner 外部并行、内部各自保持指定模式，耗时不作性能比较。完整日志 `%TEMP%/i-core-debt-accepted-default-20261005.log`、`%TEMP%/i-core-debt-accepted-serial-20261005.log` 的 SHA-256、42项逐条匹配、持续服务证据及源码复核见[机器可核对验证摘要](I_CORE_TEST_DEBT_VALIDATION_20261005.json)。

## 覆盖边界与后续

- 原唯一 skip 由大小写不敏感的测试卷触发：该卷无法创建两个仅大小写不同但实体不同的文件。条件保留；不新增 skip、todo、屏蔽或删断言。
- 合成 schema4 reader 和 pin 包不能证明缺失历史构造器、历史旧服务器字节或现役运行时兼容。记录 `old_constructor_called:false`，不冒称恢复历史接受证据。
- R3 Core 仍严格固定公开 f605 的六份原接受字节；当前 Store 的临时前缀改动由当前 Store 测试覆盖，没有偷偷进入冻结包。包中保留的旧 M3 patch / verification hash 属于历史来源元数据，不能作为本候选已应用旧 patch 的证明。
- 历史 seal_delivery 仍固定旧基线与旧任务分支，本次未运行或重写它；本候选使用本交接与新的源码绑定摘要，不沿用旧 VERIFICATION 接受结论。
- W0 合入后的三处安全/读取补丁须按实际集成基线做针对性接线复验；本次未自行同步。W1 继续暂缓。
- 本次授权仅修复与测试；主窗之后确认集成，无源码仓库 commit/push/PR、部署或在线重启。

worker 细节见 [fixture 专项交接](I_CORE_TEST_DEBT_FIXTURE_WORKER_20261005.md)。

## 完整复验暴露的额外测试可靠性问题

- 首轮默认并发的 server restart TAP 未记录底层 cause，不能确证该次网络错误原因。独立重放普通随机端口 300/300 通过；同端口旧客户端 10/10 ECONNRESET（复用刚关闭服务的旧 socket）；仅加 Connection: close 又实际捕获 fetch 的 bad-port 失败，独立 6000 端口场景可复现。
- 测试 JSON 客户端改用 Node http.request 的 agent:false，每个请求独立连接；同一个原 restart 场景固定重用端口，保留节点身份、配对 token、cursor、持久化事件断言。未改生产 server，未增加 retry/sleep/skip。server 全文件 21/21、同端口修后 50/50、6000 修前失败修后通过。证据 `%TEMP%/i-core-restart-review-438227fd7a834fb4accc64e6357e4868/`。
- 首轮 R3 continuous 的失败在启动 ready 之前，为夹具固定 15s 等待；同项独立实际 125s 已通过。ready 等待使用独立60s启动预算，不再复用短取消场景的关闭/退出等待预算；仍有限失败，生产服务没有新增或放宽运行期限，实际持续监听、真实退出、锁和 clean receipt 断言不变。

最终两套 runner 并行运行，各 runner 内分别保持默认并发与 --test-concurrency=1。所有可写 fixture/服务状态都是独立 TEMP root；M3 matrix/supervision 证据亦改为各进程自有目录，消除跨 runner 的共享报告覆盖。无需改变任何业务/退出断言。

R3 candidate_id、source_mode 与 source_commit 使用独立固定字面量断言；六份固定源码 hash 保留，不能只靠 producer 导出的常量与自身相等。

## 候选源码绑定

HEAD 未移动；以下 16 个改变或新增的可执行源码/测试字节集合 SHA-256 为 `ce014db22d31e983d190e0bcdcf584fca6dfab16a6b4a60096829d77bdb8d587`。最终两套复验使用同一集合，运行中无可执行源码写入；文档更新不进入该集合。绑定规则与相同16个测试文件清单见[验证摘要](I_CORE_TEST_DEBT_VALIDATION_20261005.json)。

| 路径 | SHA-256 |
|---|---|
| `tools/i_core/activity_control_plane.test.mjs` | `b4ac0c1fd52ae82987873d022a0654189e0de33dda948774f3c8b49dca48bca1` |
| `tools/i_core/i_core_server.test.mjs` | `a1731b18ca104619a93c91d72f9a0faf12df581271647a35fda88425fa178dc7` |
| `tools/i_core/i_core_store.mjs` | `f433c8e77de2ec4d2b1cbe3ba6bb94a4edc1f1024bd3bcb06f93a2a74cfb0f3f` |
| `tools/i_core/migration_m3/migration.test.mjs` | `7f14a71ffe17219b47b71c5d3063fb5d017fa59e5717864cbe952d30fb461b45` |
| `tools/i_core/migration_m3/supervision.mjs` | `f3ebcdc36f0a0e1bbcaccae8793812670763159da5c0766afa1378e07cc58db4` |
| `tools/i_core/migration_m3/supervision.test.mjs` | `d73e82cca9f45fd0ec1f169092df051d5ae53860b82dbef7b3fed1769c3fd56f` |
| `tools/i_core/runtime_pin/runtime_pin.test.mjs` | `8cbf40b14376eeacb7cf321ee5b82a66c0f6a4458a8f5750d2830eb4105f813d` |
| `tools/i_core/runtime_upgrade/r3/combination.test.mjs` | `a03567761196fcaf84bee3fd02362f8b752de79d7e06a7dcfa27f55098171b8e` |
| `tools/i_core/runtime_upgrade/r3/lifecycle.test.mjs` | `493c19a90689ec3a3342c35871df7fa5224866e3c0279a90ccf93d1f91766205` |
| `tools/i_core/runtime_upgrade/r3/package.mjs` | `71b59942886a73c36c24eb8e7ce3d7e3f8f0b86bae6693ff3fe1c08e567e444d` |
| `tools/i_core/runtime_upgrade/r3/start_schema5.ps1` | `af607571e505017848ff98903695c6deaba70a3e2d5be33a2039c09bf6a44e30` |
| `tools/i_core/test_fixtures/migration_m3/lab.mjs` | `f4da8e54969e8b2287d1c77ee5832a84b0171dc75b3aeed9260f958a7907ead1` |
| `tools/i_core/test_fixtures/runtime_upgrade/r3/descendant_fixture.mjs` | `de8116b3bb4c382f1dcfc4b2e31c4e408a3e2327ac1e5a1275c30d0d9153b857` |
| `tools/i_core/test_fixtures/runtime_upgrade/r3/lab.mjs` | `718ae505105ad6ae20310e208541317922e744e334a71f2d23839cc79f52ebb9` |
| `tools/i_core/test_fixtures/schema4/runtime_pin_lab.mjs` | `747508d2126511771b3cb3a4c180cb0f0a6a77c3e1fbfbea6a412cb90c1ebe5f` |
| `tools/i_core/test_fixtures/schema4/synthetic_schema4.mjs` | `9c6a939024bf421a9fc886415ceac82d0d7321cdfde0e69c23edd2653c863eee` |

原生产 runtime_pin 的 builder、launcher 和 verify_v4_state 的 Git diff 均为空；未改其固定来源、Node hash 或 guard。
