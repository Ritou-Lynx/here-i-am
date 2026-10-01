# P6 R7 独立 HTTP 候选真实验收

2026-09-12；基线 `v3-lab@1b6a2961`。本轮使用独立 `127.0.0.1:0` HTTP 宿主，没有替换现役 Bridge，也没有操作真实队列。生产 `workbench_text_only_v1` 继续 `available=false/fail_closed=true`。

## 冻结组合与范围

三次验收均使用 probe SHA `5349A89EC54C58EBB287E963B75B219DE99D86277D64FCE2AC03F62140FC508E`、native v6 exe SHA `166637F47E38348CB33B715A0A666CC8A664667BBC5110F2BADF002843F456C9`、Node SHA `58E74BF02FC5BBACC41DCB8BEF089961CD5BDDD37830B87784E4FC624D145D1F`。每次在启动前冻结 25 项输入，结束后逐项核对相符；包括当前 HTTP/API、adapter、TaskSession、broker/native transport、六项 C# 编译输入与 exe。

使用真实 native 执行器、CLI、专用账户的非刷新状态查询与实际 `thread/start`，全程禁止 `turn/start` 和 broker arm。模型请求、真实上游请求、输出放行均为零。CLI 的两次模型目录查询由本地 broker 返回 404。Node 保留既有 `--use-env-proxy`，测试 HTTP 使用独立无代理 Agent；未修改全局网络设置。

| 场景 | 精确 attempt | 实际结果 |
| --- | --- | --- |
| 创建后 DELETE | `31f6c1eb-9a5f-4ca1-8fba-1ec72509801e` | create/DELETE 均 200；v2 execution 与完整 `closed_without_turn` 回执精确匹配 |
| 创建途中断线 | `7bfed735-5459-4d8f-b705-9d9fed2823a8` | 真实 thread 返回后暂缓交付，销毁客户端；观察到服务器 abort 后释放；回收同 owner，未签发 execution/stop 成功回执 |
| 候选宿主正常关闭 | `de1d1ddd-b5eb-44a2-bb28-41575385e76e` | create 200 后走真实 shutdown 模块；无 DELETE；保留并核验同 session 的 no-turn tombstone |

三个 probe 实际 exit0，native owner 实际 exit0；进程关闭、Job 空、stdio EOF、精确规则缺席、句柄关闭、helper 实际退出六项均成立，`cleanup_pending=false`。broker 排空、HTTP socket 关闭与 handler settle 均已观察。

## 原始证据

- 创建关闭：[报告](../../../tmp/p6-r7-review/native-http-session-close-01.json)，SHA `E71E29B118A61A6F18D6E813FA88F422ECCC6F03D51B00B6D476C76E3F652583`；[独立复核](../../../tmp/p6-r7-review/native-http-session-close-01-verification.json)，SHA `CEDF7B66EC0278E6C2B18E2C388ADF7330B0CC0964D484732C700CFABFDCC043`。
- 创建断连：[报告](../../../tmp/p6-r7-review/native-http-create-disconnect-01.json)，SHA `77863AA02A47D7339646EC023F792E5660EE2A680C70241776712BF8D4F3FD6F`；[独立复核](../../../tmp/p6-r7-review/native-http-create-disconnect-01-verification.json)，SHA `336A23DDAA80CE6D023EAFBDB22532554AB52D02C613EADA18553813C572414D`。
- 正常退出：[报告](../../../tmp/p6-r7-review/native-http-host-graceful-01.json)，SHA `4DE158910F3BA1D02F7E9D64F899E42693A4E812D41C256B021163B0E25E0128`；[独立复核](../../../tmp/p6-r7-review/native-http-host-graceful-01-verification.json)，SHA `2B67CEEADA562EE5C1E6332E39C2F54C3CCB49C68A0A32B0C451AD372D53F18D`。

每份复核链接其运行前 inventory 的 SHA 与完整输入清单。三者都是无模型的真实 HTTP/native 验收，不继承 actual09/10 的模型完成/取消结论，也不证明执行中 turn 断连、宿主强制终止、App 界面退出或真人 Gate。

## 宿主强制终止的凭据修复

默认 Node 宿主死亡会同时失去 native stdin 写端和 stdout 读端；v6 即使内部清理完成，也无法交付最后 stdout 回执，实际 exit4 不能视为清理证明。没有通过持有额外管道端或重定向 native stdout 改变被测拓扑。

v7 在同一受保护 attempt 目录写入固定 `final-receipt.json`：精确绑定、六项事实与 pending 字段；CreateNew、写入、刷新、读回哈希、输出句柄和独立证据 pins 全部关闭后，才允许实际 exit0/3。文件标记 `pending_actual_exit_commit`，必须与独立持有的精确进程实际退出联合核验；文件单独不是完成凭据。原 v6 source/exe 与上述三个结果保留。

冻结 v7 source SHA `47D3DA743598E17F92F2B3B7764226376097D015A7E337C3F27A9E7D8FBD5F92`，exe SHA `73CBE6277FD4BF5B92BDC3189E00EEE5CE78F208D6037D8D16A14DF9BDE4BC4E`。[编译清单](../../../tmp/p6-r7-review/native-task-executor-07-build.json) SHA `1BED3BFD4E07AE1275E1453B96926A661800BCB25227D2A5170CB4C6E772D553`。主控已独立审 diff、运行 native/probe 12/12，本地 native self95、harness712；这些仅为本地验证。

同一 v7 已独立完成无模型 HTTP 创建/DELETE：attempt `ea73769b-82ed-4204-9792-a297ea54b891`，HTTP 与 native 均 exit0、六项回收成立、25 项输入前后相符。[报告](../../../tmp/p6-r7-review/native-http-v7-session-close-01.json) SHA `EB7779B78F451F34989E510BF438F000C93166B707BDF9136A8FD8B7002D17EC`；[复核](../../../tmp/p6-r7-review/native-http-v7-session-close-01-verification.json) SHA `385292B31BDB6AEB295ADFA52F9F9152A7CD773CC402404CC551BB60F6612C7B`。受保护目录中的最终文件只读回查为 `close_command`、stdout 成功、六项 true/pending false，文件 SHA `9CB7C6714541EA3FAA33BA736383DDAD32161C818A2CE1EDC1ED262BFB2ACD73`；它仍带 pending_actual_exit_commit，实际 exit0 由 native transport 在原运行中取得。

## 默认宿主强制终止 actual02：失败，保留原始结果

固定 witness02 source `6E222B9F8695C90A68EB23A40521F2B52067A570B09F9D5889BA1DA48030D6A7` / exe `759EA33B244E4B7A57816C17DD129EB54DD585CDD4584918CCD2CF843D064D0A`，target `B30F2916F36DBF92F3A2E73353351652BF29221677CA7250F6A8BE746E8EF368`；19 模块闭包及共30项输入冻结。修复控制 CRLF/失败重试与通知输出异常后，主控5/5、37项C#自测、独立定点审计通过，才执行 actual。

实例 `796e21fa-e29f-45c6-a856-bae0b8e6e6c3`：见证器通过精确 held handle 终止自己启动的 Node；原生 owner 实际退出码为0，随后在 `native_exit` 检查阶段失败。原报告 `passed=false/cleanup_pending=true`，没有最终停止证明。受保护目录的限定只读检查确认只存在 prepared/spawning/bound 和 install ready/ack/receipt，未生成 closed/cleanup/final 文件；不能把 owner 退出码0解释成清理成功。

[失败报告](../../../tmp/p6-r7-review/native-host-fault-actual-02.json) SHA `42498F1032A8803212EC7DC52D15243EC0DAEAC3E57660FBA8902846C1961BBE`；[失败结果与30项输入复核](../../../tmp/p6-r7-review/native-host-fault-actual-02-verification.json) SHA `7688CB9D9F3054DD277D02BE0BAB6930CE6B072E6F7696750E7E0FBFDC078A7C`。输入均未变，外层命令 exit1 保留；未捕获精确 witness 非零码，不将它编造为2。原native exit0来自见证器持有的真实进程句柄。

机制调查：固定 [Node v24.14.1 的 libuv Windows 源码](https://raw.githubusercontent.com/nodejs/node/v24.14.1/deps/uv/src/win/process.c) 将未指定 detached 的子进程加入父进程持有的 KILL_ON_JOB_CLOSE Job；actual02 的 native owner 启动正缺此选项。这与原生 owner 直接退出而完全缺失最终清理文件高度吻合，但本次未直接采集该 Job membership，保留因果推断限定。后续最小修复仅为原生 owner 加 detached，保留三 pipe、进程引用和所有身份及关闭检查；没有 unref，也不能继承旧 pin 的实际结果。

## actual02 遗留规则的独立恢复

固定 retired-only 候选仅接受上述 `796e21fa` 实例，源码 SHA `9C9DA837E2F50F6152EEF606C264B26B4CC03F1A0E3CB49E10B05BAC799CDBC3`，exe SHA `DEB245A56FEB52360D5193B7F264FE95472C173AD777BE32DFEF5C90416B6BE5`。主控及独立审计复核后，主控纯测试4/4（self260、harness356），再实际执行固定 inspect 与 cleanup。

inspect 实际 exit0：确认精确三 filter/一 sublayer 全部存在，原 owner/child/helper 身份已不活跃，指定映像无活实例，文件与 ACL 绑定成立。cleanup 实际 exit0：同一事务内重新验证、精确删除3+1，提交后四项全无，检查器资源关闭，`recovery_pending=false`。无进程终止、目录改写或模型请求。原历史 `cleanup_pending=true/host_fault_passed=false`、原 Job/child-close unknown 保留；当前恢复不能改写 actual02 失败。

- [inspect 报告](../../../tmp/p6-r7-review/native-host-fault-retired-inspect-actual-01.json) SHA `8F27B9BDA83D65B2A70F390F0FBBF5A7A29418BB0CCF172210593012871FDD54`；[真实退出捕获](../../../tmp/p6-r7-review/native-host-fault-retired-inspect-capture-01.json) SHA `348FA7E8CF16F0578B36D6E1B4CDBD857DC4A6E5E2B899A269440CABC1953063`。
- [cleanup 报告](../../../tmp/p6-r7-review/native-host-fault-retired-cleanup-actual-01.json) SHA `2E441C47215566FAEE47FF96F96601ACA1B10A641B82C526569D2CD0F600D35A`；[真实退出捕获](../../../tmp/p6-r7-review/native-host-fault-retired-cleanup-capture-01.json) SHA `CDA894489C0525C5B2839008766823BA64035E28427E8C7A3B5A6F13C8D79EDF`。

## 默认三 pipe 宿主强制终止 actual03：通过

Windows 上独立自退出 dummy 复现实例显示：持有原进程句柄时，退出前 image 查询成功，退出后查询返回错误31，但 PID、creation、wait-signaled、GetExit 均有效。witness03 因此保留退出前 canonical image 与持有文件 pin；退出后严格要求同一句柄 PID/creation、wait0、GetExit 和持有文件的再次哈希核对。未放宽最终文件、EOF、stdout失败或六项回收要求。dummy 不是 native/模型验收。

冻结 witness03 source SHA `A931E876F8FA4C198946E867BA0A24BC7C142A32CF3738C693BA34D920246C8F`，exe SHA `0FBF4016FFADAB959D746D11AFF513481C715FF15299B5330AEEFCB104946999`；native 仍为上述 v7。新 transport SHA `8C4F80FC616BAB9EF96EA0117EE3B54D57A70E06BB2794C5677FED42BA5A8A98`。worker组合47/47、主控witness/transport18/18（含44项C#自测），独立审计与额外transport13/13通过。19模块闭包、共30项输入在本次运行前冻结，事后全部吻合。

实际 attempt `4e8a1205-fc25-4289-b6fd-4273bad3b8c0`：完成真实 HTTP create/no-turn 后，见证器持有并核验自己启动的 Node、native owner 与 CLI 身份，只终止该 Node，实际 exit77。默认三 pipe 没有额外写端/读端维持。native 因 stdin EOF 自行清理并实际 exit3，child 实际 exit0；受保护最终文件精确匹配、`input_eof`、`operation_failed=true`、stdout最终发送失败，六项回收均 true，pending false。witness 自身所有持有句柄、文件和读取任务关闭，实际 exit0。实际退出码同时有外层固定 capture，不能由报告自称替代。

- [actual03 报告](../../../tmp/p6-r7-review/native-host-fault-actual-03.json) SHA `5C2506A3BDFAC08419253007182C58BAAA597406D1C06C1584C9C6674C5BFF72`。
- [witness 真实退出捕获](../../../tmp/p6-r7-review/native-host-fault-actual-03-capture.json) SHA `32CB44740AA649A57B1F069C18DA067924881DE7FA1984CBC5481F74AFEC22AA`。
- [输入清单](../../../tmp/p6-r7-review/native-host-fault-03-inputs.json) SHA `3AF347F876AA90CC4794A38972906E8603B67071E9EF1FA0316A1D49220E6D55`；[主控复核](../../../tmp/p6-r7-review/native-host-fault-actual-03-verification.json) SHA `3C460F6CE3D0B609189F305E56FB744276E167A04076A39B7D6BBCD090981C7B`。
- 最终文件在受保护的同 attempt 目录内，主控另行只读核验 SHA `78C3D68E5585C8EC9F748939201BF1B93962D8AE959BF8516A898A523D3B3FA5`。它仍是 pending_actual_exit_commit，联合见证器取得的实际 native exit3 才构成本次证明。

独立审计随后通过154项产物断言：30/30输入、19/19闭包绑定、恢复工具6/6依赖和两个实际退出 capture 均匹配；原 actual02 文件未改。

同一最终 `detached` transport 与 native v7 另行通过正常 HTTP create/DELETE：attempt `c9bd148a-804b-4fa5-9fd7-19d1ab273581`，probe/native实际exit0、两次HTTP200、精确v2 no-turn停止凭据、六项回收true/pending false，25项输入前后相符、模型与上游请求0。[报告](../../../tmp/p6-r7-review/native-http-v7-detached-session-close-01.json) SHA `24EF2842DAA89F5B8A97428E686F721D35B7304699FA4E4A1AA908281CAEDDDC`；[复核](../../../tmp/p6-r7-review/native-http-v7-detached-session-close-01-verification.json) SHA `103A1CAA1353AF78863C988F127E1537F6CE5DB389A41819D7E4593B468D831C`。这补充了新组合的正常关闭证据；前面旧 transport 的断连/正常宿主退出仍是各自原 pin 的证据。

本次证明固定候选在无模型 turn 的正常关闭及默认三 pipe 宿主死亡时完成回收。运行中模型请求、provider 停止、App 界面操作和真人 Gate 不由此推出；生产继续拒绝，P6/Goal1 未完成。
