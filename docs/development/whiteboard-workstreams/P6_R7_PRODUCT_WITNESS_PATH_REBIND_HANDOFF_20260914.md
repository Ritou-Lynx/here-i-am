# P6 R7 产品候选 Witness05 路径重绑定交接

日期：2026-09-14。Witness05 已从04的明确源文件新建并重新编译，原合成测试10/10通过，原Core包含553项检查全部通过。本包仅替换固定路径，不增加ordinary会话的native owner身份，不改变authority或验收定义；真实产品App/provider/native Gate尚未运行。

## 边界与唯一差异

新目录：`tmp/p6-r7-review/owned-recovery-witness-05`。只复制以下10个明确文件：`OwnedRecoveryCore.cs`、`OwnedRecoveryWindows.cs`、`OwnedRecoveryBootstrapConfig.cs`、`OwnedRecoveryControlClient.cs`、`OwnedRecoveryWitnessProgram.cs`、`OwnedRecoverySyntheticClient.cs`、`OwnedRecoveryTests.cs`、`owned-recovery-bootstrap.test.mjs`、`run-tests.mjs`、`README.md`。没有复制04的runs、actual-runs、bootstrap配置、日志、凭据或旧exe/dll。05内exe/dll和合成输入、runs、日志、收据均由本次原runner新生成；旧04文件未修改。

`OwnedRecoveryBootstrapConfig.cs`只替换三条常量，README同步同三处路径引用：

| 常量 | 04 | 05 |
| --- | --- | --- |
| Root | `D:\memex\tmp\p6-r7-review\owned-recovery-witness-04` | `D:\memex\tmp\p6-r7-review\owned-recovery-witness-05` |
| Candidate | `D:\memex\.worktrees\p6-r7-owned-recovery` | `D:\memex\.worktrees\p6-r7-product` |
| HostSource | `D:\memex\.worktrees\p6-r7-witness-host\tools\dev_agent_bridge` | `D:\memex\.worktrees\p6-r7-product\tools\dev_agent_bridge` |

因此固定App路径为 `D:\memex\.worktrees\p6-r7-product\build\windows\x64\runner\Debug\memex.exe`。只读确认新worktree分支为 `codex/p6-r7-product`（chunk `0cb97d`）；其建立基线和App编译由主控负责，本包没有编译或启动该App。

差异检查（chunk `b2b948`）对每个新文件执行与旧文件经上述三次精确替换后的全文相等断言，全部通过。其余8个文件与04 SHA-256逐字节相同。Core为 `44b140928e0cf51b05100d66667ed3563e0127dcae51d215de60ab73b72ee9f9`；没有新增角色、放宽owner/held进程/六项资源证明、修改schema、provider、费用或认证配置。

保留固定依赖：Native仍为 `native-source-rebind-01/windows_text_gate_task_executor.source-rebind-01.exe`，SHA-256 `674f159148f47c9702a360bfb4d32fd7b37604cd453a3104a3db08dd83fd02fc`；Node仍为 `D:\Nodejs\node.exe`，SHA-256 `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`；addon仍为 `owned-recovery-node-addon-02/witness_addon.node`，SHA-256 `7a80151fa467f296237c03f0cfacdfbda5a5447712041799053174666f8756fc`。这里只核对未改变的源码常量，没有再次启动或验收这些生产依赖。

## 本次真实编译与合成结果

命令：`node tmp/p6-r7-review/owned-recovery-witness-05/run-tests.mjs`。首次启动chunk `9c251e`，完成chunk `a2e22c`；2026-09-14 02:14:26.646至02:14:41.363 UTC。原runner自身及其子测试均实际exit0，**10 tests / 10 pass / 0 fail / 0 cancelled**。没有force-exit或手工修改结果。

- 原standalone witness、Core DLL、Core harness以原固定csc编译参数完成，warnaserror不变。
- 原Core `--self-test`实际553 checks通过。
- 合成first App/Node关闭、独立claim/consume及一次successor许可通过，审计链21项；重放同配置拒绝。
- 原flush/close故障、连接/帧期限、错误配置/hash/固定exe、已有data路径、缺失stdin EOF/未绑定task/Node crash拒绝覆盖保持通过。
- 原App death合成观察为synthetic App实际exit197、synthetic Node实际exit0；不等于真实Flutter App死亡恢复。

新收据：[build-and-test.json](../../../tmp/p6-r7-review/owned-recovery-witness-05/build-and-test.json)；日志：`tmp/p6-r7-review/owned-recovery-witness-05/test-run-2026-09-14T02-14-26-646Z.log`。原runner未修改，包含的03历史base hash与测试中04阶段名仅作既有历史标签；不能解释为05继承了03/04的实际Gate。

| 新产物 | SHA-256 |
| --- | --- |
| `OwnedRecoveryWitness.exe` | `e60ab90477230a593563656d4c27c1bd4835b39655f9b90e3b29895cb818d8fc` |
| `OwnedRecoveryCore.dll` | `ea8cbad1e3d90178a03a963c060ec21a5e7ff989f6afe21ad9a45017706ae8b6` |
| `OwnedRecoveryTests.exe` | `da87eb7df7bc94f4d76ed6ffd8977d0fb806edf048c306fe0b387b5e7a05d491` |
| `OwnedRecoveryBootstrapConfig.cs` | `240e89e875772d21ac13b89f2f85f1222d56088cbd84ccef7508596ea6df2008` |

完整10源/doc及3产物哈希见本次收据（读取chunk `984c45`）。本包无需修改核心功能即可通过。

## 主控接续范围

主控在新App/Node受审封包中固定05 witness路径与上述exe哈希，不能将discovery环境变量提升为信任来源。实际运行前仍需独立封包、最新App/Host/ordinary guardian完整source closure及bootstrap pins；本次没有生成实际bootstrap或替代主控的封包校验。

普通会话继续由独立guardian按本次exact session/turn及真实provider终态收据关闭；它没有被伪列为text native owner。Node在ordinary关闭与queue/native关闭任一unknown时仍不能发布host_closed/exit0。这是产品host接线的先决，不是本次三路径修改扩大了Witness Core证明范围。

没有连接47831/47841、请求真实provider、触及auth/生产DB或启动真实App/UAC/text native executor。合成测试确实启动了本次新编译的synthetic子进程并使用其原有Win32句柄/命名管道核验；这是明确授权的原合成测试，不能写成真实产品运行。未提交，旧04验收资料保持原样。
