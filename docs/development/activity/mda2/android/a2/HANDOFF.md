# MDA-2 A2 — Android 持久 outbox 与恢复权威交接

> 日期：2026-09-13。状态：A2-R2 本地纯 Dart 候选已完成并冻结，等待 W0 独立审计与选择性集成。不是 Android 系统接线、APK、实机或一晚 Gate。

## A2-R2 — owner 删除异常释放 gate 返修

- W0 独立复跑通过但拒绝 R1 提交 `47adfbf69baecea40e60bbeb8c8659ed4af32b1b`：`_removeOwnLock` 在删除 `owner.json` 后才释放 gate；删除或解码抛错会让已关闭实例永久持有进程 lease。
- R2 将 `_removeOwnLock` 改为 `try/finally`：无论 owner 解码、精确身份核对或删除是否成功，`finally` 都调用 `_releaseLeaseOnly()`。owner 不可证明属于自身时绝不删除；删除异常固定归一为非敏感 `owner_lock_cleanup_failed`，并 poison 实例。
- 删除失败时保留原签名 owner。后继仍须对该 owner、source、binding、anchor generation/digest 提交精确恢复权威，持稳定 gate 复核后才能替换；没有放宽接管，也不删除不确定 owner。
- 新增确定性 owner 删除故障注入。close 路径证明旧实例已 closed、不可继续分配，gate 已释放且精确 authority 可恢复；open 已接管后发生初始化异常的 catch 清理路径也证明 owner 保留、gate 释放、只有针对该 replacement owner 的新 authority 可恢复。A2 专项由 28 项增至 30 项。
- `_createOwnerLock` 与 `_acquireForOpen` 自身的 Android/非 Android 异常分支均在重抛固定码前释放 gate；create/open 取得 owner 后的后续失败统一走上述 `_removeOwnLock` finally。

## A2-R1 — 恢复接管竞态返修

- W0 拒绝首个固定提交 `7d0494436d55578d6388b12e69080a7741e4dc9d`：旧实现校验 stale owner 后短暂 lock/unlock lease，再递归删除 owner 目录；两个持同一旧 inspection 的恢复者可让较晚者删除较新 owner。
- R1 改为稳定、永不随 owner 轮换删除的 `owner.gate`。恢复者取得同一 OS 独占 gate 后，在临界区内重新读取并精确校验 owner、source、binding、anchor generation/digest，保持锁不释放地再次复核并原子替换 `owner.json`；同一 gate 句柄随后直接成为新 owner 的生命周期锁。
- 不再递归删除 owner 目录。清洁 close 只在仍持 gate 且证明 `owner.json` 属于自身时删除该 owner 文件，然后释放 gate；crash 留下 owner 文件，由下一份精确恢复权威处理。
- 新增确定性嵌套双恢复者回归：loser 在 winner 持 gate 的临界区内得到 `owner_still_active`；winner 写入新 owner 后，即使释放模拟进程锁，旧 authority 也得到 `recovery_authority_invalid`，新 owner 文件字节不变。A2 专项由 27 项增至 28 项。

## 身份与边界

- 工作包：MDA-2 A2；主窗 `01a0917d-17fa-7bf3-a282-fd4c551d93b2` 派发。本 worker task ID 由 W0 的任务状态表持有。
- Worktree：`C:/Users/ExampleUser/.codex/worktrees/9a29/memex`；分支：`codex/mda2-a2-android-durable-20260913`。
- 精确起点：`b55386cfc896c98376a071009f349dcbc88dc84b`，启动时 detached HEAD、工作树干净；创建临时分支后才写入。
- 首个提交 `7d0494436d55578d6388b12e69080a7741e4dc9d` 与 R1 提交 `47adfbf69baecea40e60bbeb8c8659ed4af32b1b` 均已被 W0 拒绝，不得单独回收；R2 交付 commit 是包含本 handoff 的后续单一修复提交，完整 SHA 由本任务最终回报并由 W0 用 `git rev-parse HEAD` 独立核对。
- 只修改 `lib/data/services/activity/mda2_android/**`、`test/data/services/activity/mda2_android/**`、`docs/development/activity/mda2/android/a2/**`。共享 Core/validator、DB schema、根依赖、Android/Kotlin/Manifest/Channel/DI/UI/BLE/FGS、全局状态、Roadmap 与 DEVLOG 均未修改。
- 未读取或复制 `D:/memex` 的未提交工作；只从受审冻结树 `C:/Users/ExampleUser/.codex/worktrees/aa86/memex` 逐文件读取和导入 A1。

## A1 输入核验

冻结树 HEAD 为 `1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`，分支 `codex/mda2-a1-android-20260912`，恰有 8 个未跟踪交付文件。核验 SHA-256：

| A1 文件 | SHA-256 |
|---|---|
| `docs/development/activity/mda2/android/HANDOFF.md` | `cf01a03138cd3913eb5f9505eacade5a38e630e1ed86c1f867537a6ee7f8c59d` |
| `docs/development/activity/mda2/android/synthetic_events.json` | `0844dd7d7c556b8ca81083e8a6f6e3a25b0c60687dd51312427cfc85bf8becb2` |
| `lib/data/services/activity/mda2_android/android_activity_normalizer.dart` | `01ae905afe456ba854e3297802021f9698b5683842f0736d0db1a6fb9abc5e3e` |
| `test/data/services/activity/mda2_android/.gitignore` | `68bdb5952b09a333f93f08d4e1b992d5f1e208bd9389324c869c803b7c696e88` |
| `test/data/services/activity/mda2_android/android_activity_normalizer_test.dart` | `20df565a6e3998e628657abb2b1f45d582d4c1d847d7f4d6585cdcce1b96cd5d` |
| `test/data/services/activity/mda2_android/generate_synthetic_events.dart` | `1b16d111fd1ed1d73f4b06cc5f4c2b5912f7ce2600be3d3024f03482cd464636` |
| `test/data/services/activity/mda2_android/verify_flutter_synthetic.ps1` | `aab4df182d83a06c5af359e9588d0034d872baf988efcddf8daf2e8296755878` |
| `test/data/services/activity/mda2_android/verify_wire.mjs` | `8ff9d0c3f058d6eed7e0e484fac2f8cf4af9f83696990bdd5474a456ec3171cf` |

A1 的 56 项测试文件和 generator 保持原 SHA。原 fixture 因本包唯一文档拥有路径只允许 `a2/**`，被逐字放到测试拥有路径 `fixtures/synthetic_events.json`，SHA 不变；验证脚本只改为引用该路径并加入 A2 store/test。Normalizer 为注入 `ActivityOutboxStore` 做了最小接口抽取，实际 Dart 输出仍与冻结 fixture 深度相等，并继续通过当前主线 validator/Core。

## 实现结果

1. `ActivityOutboxStore` 成为 normalizer 的注入边界；A1 内存 store 继续用于 56 项兼容测试，生产候选由 `FileActivityOutboxStore` 提供。每个目录只绑定一个 source/binding/lineage，Usage 与 Screen 独立从 sequence 1 开始。
2. 每次 allocate 先验证 scope、固定输入形状、HMAC 年龄证明、24 小时上限、wall-clock floor、容量和 source/binding，再生成一次完整 `device.activity.v1/schema_version:1` JSON 字节。journal → state → anchor 三阶段均持久完成后才返回；中断恢复只有“未分配”或“完整已分配”，不补号、转绑或重造字节。
3. state、anchor、journal、owner 都是格式版本固定、HMAC 完整性保护的本地文件。anchor 可发现旧 state 回滚；未知版本、缺失、截断、MAC 损坏、sequence/attempt/age/source/binding 不变量异常均 fail closed。
4. owner 由签名 `owner.json` + 稳定 `owner.gate` 的 Windows 实际独占锁组成。第二 owner 即使带精确恢复对象，在活 owner 持锁时也得到 `owner_still_active`；进程锁释放后，恢复对象还必须在持 gate 临界区内精确匹配旧 owner、source、binding、anchor generation/digest 才能替换。旧 authority 不能删除或替换较新 owner。close/create/open 清理即使 owner 解码或删除失败也在 finally 释放 gate；留下的 owner 仍只能凭精确 authority 恢复。缺恢复权威保持冻结，不会发送或分配。
5. sender 仅收到 `Uint8List fixedWireBytes`。每次调用 transport 前，store 已把该记录原子持久为 `attempted_unknown` 并增加 attempt；因此 transport 异常/丢回执不会回退为 `never_sent`。accepted、duplicate、retryable、terminal rejection 沿用现有 Core 语义，没有新 response wire。
6. 单 source 单 owner、单 flush、FIFO。在途期间冻结时，只允许匹配 owner + attempt token + event ID 的真实回执结算；后续记录保持 `never_sent/attempts=0`。旧 owner 的晚回执无法越过 OS owner 证据。
7. 满载在 sequence 分配前拒绝并暴露 `outbox_full`。发送资格以签名年龄证明的原观测 deadline 为上限：精确 24 小时边界可发，一毫秒后冻结为 `raw_release_deadline_expired`。TTL 后但原观测 deadline 前保留相同字节供 Core duplicate/terminal reconciliation。
8. normalizer/store 严格拒绝包名、应用名、正文、位置、BLE/健康 raw、客户端 `received_at_ms` 和任意 payload 扩展。持久文件只含固定 wire、绑定元数据、年龄证明、attempt/receipt/freeze 与非敏感计数；audit 只接收固定错误码和整数计数，transport 异常正文不落盘、不入日志。

## 故障与隐私矩阵

| 场景 | 本地行为 | 验证 |
|---|---|---|
| allocate 在 journal/state/anchor 后中断 | 恢复为 sequence 未分配或完整已分配；无半记录 | 3/3 |
| receipt commit 在三点中断 | 恢复为 `attempted_unknown` 或完整 settled | 3/3 |
| 活 owner / 双 owner | OS 锁阻止接管 | 通过 |
| 两个恢复者持同一旧 authority | gate 临界区至多一个 winner；旧 authority 不影响新 owner | 通过 |
| close 删除 owner 失败 | 固定 `owner_lock_cleanup_failed`；finally 释放 gate；旧实例不可写；精确 authority 可恢复 | 通过 |
| open 接管后的清理删除失败 | replacement owner 保留；finally 释放 gate；须针对它的新精确 authority | 通过 |
| stale owner 无/错恢复权威 | `recovery_authority_required/invalid` | 通过 |
| 旧 owner 晚回执 | `sequence_authority_required`，不结算 | 通过 |
| 丢回执/模糊异常 | 原字节保留，`attempted_unknown` | 通过 |
| accepted/duplicate/retryable/terminal | 分态持久；terminal 冻结，后续不 attempt | 通过 |
| 冻结时 inflight | 只结算真实匹配回执 | 通过 |
| TTL 边界/之后 duplicate reconciliation | 相同固定字节 | 通过 |
| wall-clock 回退 | 持久 `clock_regression` 冻结 | 通过 |
| 原观测 24h 边界/超 1ms | 边界接受，超限 `age_proof_invalid` | 通过 |
| raw release deadline 超 1ms | 不调用 transport，持久冻结 | 通过 |
| 容量满 | sequence 前拒绝，gap 可见 | 通过 |
| 权限 revoke/recover | Usage 停止；重建为 unknown/gap，须新 gap + 权限/观测 | 通过 |
| 缺失/截断/未知版本/MAC 损坏 | fail closed | 通过 |
| 旧 state + 新 anchor | `outbox_rollback_detected` | 通过 |
| source/binding 交换 | `source_binding_mismatch` | 通过 |
| 伪造年龄/source/binding proof | sequence 前拒绝 | 通过 |
| 私密字段/异常正文 | 不进入 wire、持久文件或 audit | 通过 |

## 验证证据

最终冻结字节与结果见 `SOURCE_MANIFEST.json`、`RESULT.json`。最终成功命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File test/data/services/activity/mda2_android/verify_flutter_synthetic.ps1 -FlutterSdk D:/flutter -NoResolve
node test/data/services/activity/mda2_android/verify_wire.mjs D:/flutter/bin/cache/dart-sdk/bin/dart.exe
git diff --check
```

- Flutter：A1 **56/56**，A2 **30/30**；lib 与 test 拥有目录 `dart analyze --fatal-infos` 均 `No issues found`；测试镜像和 5 个拥有 Dart 文件逐字一致。
- Node：真实 Dart 输出 **20/20** 通过当前 `normalizeActivityEvent`，全内存 `ActivityControlPlane` **20/20 accepted**，诊断后 unknown **6/6**，隐私负例 **7/7**，duplicate/TTL 边界通过。没有 HTTP、真实 Core、磁盘数据库或网络。
- 共享输入 `activity_control_plane.mjs` 的工作区前后 SHA 与 Git LF blob SHA 均为 `525295357490814c69fb204358e019f862e916c09efc5f5ff85b99043f83f222`。`activity_control_plane.test.mjs` 的 CRLF 工作区前后 SHA 为 `1d68831ef819461757b7636b5006190bc1758911d33058aa58907c37a84e35dd`，Git LF blob SHA 另为 `cb1794ed4a4bd426c022f5c6b71a9ec0c1a1f26dd53865c3429548b12167ea47`；两者未混称。
- 工具：Flutter 3.44.0、Dart 3.12.0、Node 24.14.1。专项进程均真实 exit 0。

开发过程中的非通过尝试也保留事实：首次 sandbox 内运行无法写 Flutter SDK lock；授权后的离线 resolve 已生成 package config，但因共享 Pub `active_roots` 路径错误 exit 1，随后按 A1 既有方式用 `-NoResolve`。早期两次 `-NoResolve` 分别暴露 7 条和 3 条 fatal-info；增加 OS 文件锁后的首轮测试又发现测试读取锁中文件导致单测失败；切换到仓库既有标准 `crypto` 后，首次验证暴露镜像把它误列为 dev dependency 的 1 条 fatal-info。它们均已针对性修正并由上述最终命令完整重跑，不计为通过证据。

## 支持与不支持

当前真实支持：注入目录、注入完整性密钥、注入 HMAC 年龄证明提供者条件下的单机本地持久序号/字节/attempt/receipt/freeze；Windows 实际 owner 文件锁；精确 stale-owner 恢复；anchor 存续条件下的 state 回滚检测；纯 Dart normalizer 接入；合成 transport/Core 验证。

明确不支持或未验证：

- A3 原生可信年龄证明签发、UsageEvents、屏幕广播、UsageAccess 系统查询、Channel/DI/后台调度/自启均未接线。`HmacActivityAgeProofProvider` 只是 A2 本地边界，不证明真实 Android 采集来源。
- 完整性密钥的 Android Keystore 托管、轮换和恢复授权 UI/政策未实现；调用者必须提供。没有此权威不得启用。
- anchor 与 state 位于同一注入目录；“仅回滚 state、anchor 仍新”可检测，连同 anchor 的整目录一致回滚需要外部单调 anchor，当前未支持，不得声称已防御。
- 本包从不接收或保存原始 UsageEvents/包名；因此没有原 raw 的物理删除实现或可证明擦除。超过 release deadline 后固定降敏 wire 仍保留为冻结审计证据但不会再发送。物理删除能力未支持。
- 没有已结算记录压缩；容量包含全部记录，满后 fail closed，需后续经授权的 retention/compaction 设计。
- 没有真实 response parser、HTTP、认证、backoff、批量、timer、WorkManager、Android 进程杀死/重启或掉电硬件 Gate。三提交点是确定性逻辑中断测试，不等同于手机存储掉电证明。
- 没有手机 reader/UI；手机含义继续是 `unknown`。没有 APK、实机、部署或一晚 Gate。

## 清理与副作用

- 测试只创建 `Directory.systemTemp` 下的 `mda2_a2_outbox_*`，每例 teardown 删除；验证镜像只在测试拥有路径 `.verification/`，最终提交前已删除。
- 未访问真实 Core、凭据、真实数据库、网络、手机、adb 或健康/BLE 数据；未构建/安装 APK，未创建调度/自启，未 push、merge 或部署。
- 最终提交仅在 commit 命令的进程环境内设置 `SKIP_PROJECT_STATE=1`，命令结束立即恢复/清除；原因是 worker 不拥有全局 `I_PROJECT_STATE.md`。其他命令未使用。

下一步：W0 以最终完整 commit SHA 回收，独立核对 manifest、diff、关键断言和组合回归。A3 平台接线仍未授权、未派发。
