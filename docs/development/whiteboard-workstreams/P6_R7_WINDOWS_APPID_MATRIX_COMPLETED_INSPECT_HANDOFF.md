# P6-R7 v3 固定实例只读复查候选

主控已于本轮实际执行：source/snapshot `tmp/p6-r7-review/native-appid-matrix-completed-inspect-01.cs` SHA `E18F1090EF6F421D4D51FD7956702929C0CD2CCFC618FF0FCB930D348E214B64`，冻结 exe `tmp/p6-r7-helper/windows_text_gate_appid_matrix_completed_inspect.v1.exe` SHA `E84E46E3583C1777A653825D608C3A0AEEBCB4159C1DE86B70A14AB71E615D20`。主控5/5、1027+189纯断言及绑定该source的独立复核通过。固定runner SHA `2083D0567592CC44500B66E0E6AF11AF0EF0C96F2397009604139BC890E1C3FF`；held runner36612与native均实际exit0。

实际报告 `tmp/p6-r7-review/native-appid-matrix-completed-inspect-actual-01.json` SHA `A72B3CCAFE8A2F01804FE2419AE083A97BEA91DF181F8829B4D2A6D421B403EB`；采集回执 SHA `38DBC3D0F7288B76FC3432C6AA93B225FF58C9F937AF719453608CA3788F5CDB`。历史关系、前后pins/ACL、目标进程当前不活跃、只读事务结束及资源关闭均true，固定三filter/一sublayer全absent，inspection_complete=true、cleanup_pending=false。无规则删除，不回填原v3 actual stdout/exit；原矩阵不因此通过。以下为冻结前实现说明。

2026-09-12；基线 `v3-lab@bbb8025d99fc0acaa846d58b4e5a94cef90f8756`。本工作包仅新增独立检查器、专项测试和本交接；未修改旧 `162de…` 检查器、Runtime、全局状态或历史报告，未提交。

## 目标与证据边界

- 固定实例：`70ea3573-f6cf-4c5c-b680-8a21288ea5fb`；owner PID `44532`，creation `134336608542776034`，broker port `45541`。
- 原 v3 外层报告校验失败；原 stdout / actual exit 未保存。本候选不重建这些证据；历史 `closed.json` 或 receipt 不等于原 helper 实际关闭。
- 唯一实际入口：`--inspect-completed-fixed-elevated-readonly`；仅接受当前 primary / High / elevated / Non-AppContainer token，且当前 SID 必须拥有两个精确、受保护 ACL 目录。不会自动提权。
- 输出 schema：`p6_r7_matrix_fixed_completed_inspection_v1`；实际 mode：`inspect_completed_fixed_elevated_readonly`。无参数、`--plan`、`--self-test` 均不进入 native inspection；其他参数拒绝。
- `historical_records_consistent` 只证明固定文件的关系一致；`exact_child_closed=null`、`job_active0=null`、`helper_actual_exit_verified=false` 始终不提升。矩阵、生产、真人 Gate 仍为 false；真实上游和模型请求均为 0。

## 只读范围

逐层 held directory handles 验证路径和 no-reparse；原 v3 exe、实例副本以及 prepared / bound / closed / cleanup receipt 的文件句柄全程 held，读前及读后验证固定 hash。MatrixRecords 检查四文件 schema、scope、nonce、owner / image / token / port 一致，bound 与 closed 的 child 三字段一致，cleanup receipt 与 closed 完整绑定。

固定目录只允许 17 项：prepared、spawning、bound、closed；install 和 cleanup 各 ready / ack / receipt / report；event-binding / event-probes / event-receipt；probe-report；matrix-probe.exe。名称集合、文件类型和无 reparse 在前后复查；其余文件不读取内容、不推断 actual exit。

只打开只读 BFE transaction，按固定 attempt 派生的 3 个 filter key 和 1 个 sublayer key Get；Abort 后关 engine。不会枚举/修改策略，不 Add / Delete / Set / Commit，不启动或终止进程，不打开 socket、不运行 CLI。进程快照最多 8192 项，仅对两个固定 image basename 候选核对 image path、PID、creation 与非阻塞 wait，并检查固定 owner PID / creation；无法确定时拒绝。

只有固定四对象全 absent、前后目标进程不活跃、前后 pins / ACL 合格、transaction 已结束且所有本轮资源成功关闭，才输出 `inspection_complete=true` / `cleanup_pending=false`。这只解除本实例当前策略残留待查；不会声明原 Job、child 或 helper actual close。资源关闭失败保留句柄并有限重试，但即使重试清空也保持本次检查不成功。

## 固定输入 SHA-256

| 输入 | SHA-256 |
| --- | --- |
| 原 `tmp/p6-r7-helper/windows_text_gate_appid_matrix_runtime.v3.exe` 与实例 `matrix-probe.exe` | `07FA499C4922B80D531C09FA23F053C7982AD28718F9BA6089297ECBA34B77F3` |
| prepared.json | `0F93F5DCAEFFEF802BE3084AE434768FBB1C2D58783A1147DAAB58D765616E23` |
| bound.json | `BDCFEAA09202984D9257011CFAAEFF9ECB92549E9614B5135D4F2A8760B3D625` |
| closed.json | `705D143E3410426BF506DD757E8BC373F1A760A675A50AB1742C23DD5BAA8073` |
| cleanup-receipt.json | `D412A74B166770AB9F62D6F302BB625CE8CBEC20705E82585515AF2EF8C5F47B` |

## 本地验证与交付

- `node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_completed_inspect.test.mjs`：5/5，1027 self-test assertions、189 合成 pure assertions。
- 两个 C# x64 入口 warnings-as-errors 编译通过；SDK C++ 仅编译验证 snapshot ABI 与 `FWPM_TXN_READ_ONLY=1`。依赖编译前后 SHA pins 不变。测试临时目录仅清理本轮创建且已核对绝对路径的目录。
- 测试覆盖历史字段缺失/错误/多余、跨记录 child 不一致、非法 phase / weight、caller 身份、17 文件集合替换/重复/路径穿越，以及资源失败保留与重试。测试不运行实际检查入口、UAC、BFE、socket 或目标进程操作。
- 真实目录在 worker 沙箱内读取返回 access denied；未提权。真实输入 hashes 采用主控现场提供的固定值；四文件关系在本轮仅用合成记录验证，现场结果由主控执行固定入口确认。
- source SHA-256：`E18F1090EF6F421D4D51FD7956702929C0CD2CCFC618FF0FCB930D348E214B64`。
- test SHA-256：`FB995A9417D576E5A0BCCA0ECA668F98E233C5CBAE76C4ABA6D98CD71EB71D55`。
- 独立类入口 `/main:HereIAm.R7.MatrixCompletedInspectProgram`；编译依赖与固定 hashes 见专项测试。未冻结发布 exe；主控复核后编译冻结，并负责实际 Windows 确认、新报告与检查器实际退出证据。
