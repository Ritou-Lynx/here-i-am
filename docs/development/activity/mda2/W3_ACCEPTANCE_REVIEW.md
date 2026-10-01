# W3 主窗验收

2026-09-13；W0 task `01a0917d-17fa-7bf3-a282-fd4c551d93b2`。

## 当前裁决

修订 `af3cb5764546ebd2c1191214ea90f850d92d2815` **通过主窗本地接线候选验收**。独立干净归档复跑W3 **44/44**、W2兼容 **35/35**、主窗新增退出负例 **5/5**；实际Node/包装器exit0、scratch与兼容镜像清理确认，109份导出文件先与Git blob对应，复跑后除4份预期结果文件外无变化。固定源码二审无P1/P2，初交付退出误判、提前退休和HTTP启动异常假退出均关闭。[机器收据与证据索引](windows/w3_review/af3cb576/ACCEPTANCE.json)。

本地源码已选择性合入 `v3-lab@63acaaf80bdb14d5fe1418b683a5afd289df3ca4`（父提交 `68307c9e`），65条路径逐项核对、54份并行修改受保护，源码提交后index为空，正常项目状态守门提交完成。见[实际合入收据](windows/w3_review/af3cb576/LOCAL_LANDING.md)。运行态切换、真实采集、生产端点/配对/自启、Android及真人Gate仍未执行。W2差异为4个生产执行文件加1个同步fixture适配，原W2树与历史证据保持。

## 初交付裁决（历史）

初交付 `7bdf72b7622a8d5418b42d4ac45a01a7af4924e2` **退回原任务限定返修，未接受、未合入**。W3 task `01a09699-5a54-7fb0-8b05-f69972c3b118`，独立分支 `codex/mda2-w3-windows-wiring-20260913`；源码基线 `68307c9e`。worker原37/37与35/35仅为该版本历史证据。

主窗从固定commit导出干净归档，15项执行/依赖与声明SHA匹配。采集器边界独立审查无P1/P2；发送生命周期仍有可复现阻断。既有主目录HEAD/空index已只读确认，未修改生产或运行态。

## 初交付发现

1. **退出失败被当作成功**：broker `trackAsyncDispatch` 将rejected `exited`也标记为`transportExited=true`。主窗纯内存负例中，`exited=Promise.reject(no_exit_proof)`、completion保持pending，随后`broker.close()`成功。这是实际复现，不能以原通过测试覆盖。修订必须保持未知/失败，并检查completion先完成时仍未退出的出口不能被并发、stop/close或记录清理遗漏。
2. **异步契约在副作用后检查**：当前直接调用transport再验证返回handle；裸Promise没有独立可取消/退出能力。要求在首次派发前验证异步契约，实际取消与退出分开，异常handle不能留下未追踪请求。
3. **结果字节的逐文件更正**：默认git archive受core.autocrlf影响，将结果导出为CRLF，初核不能据此直接推定Git blob失配。完整二进制git show复核确认RESULT和W2_COMPAT_RESULT两份完整结果的blob/工作区/声明均一致，撤回这两项缺陷归因；只有W2_COMPAT_SUMMARY仍因混合换行与Git blob不同（工作区291字节/声明`19b84447…1085`，blob282字节/`caf2e999fcc3ef630b099784b0db950c0c0abcfa33a3f7ce3d5ec6f985416f40`），JSON语义相同。原任务只需规范新汇总并重算SHA。主窗改用`git -c core.autocrlf=false archive`，并对所有导出文件逐一核对Git blob；15项执行源原先一致，第1项复现仍有效。完整更正见[导出诊断](windows/w3_review/7bdf72b7/EXPORT_CORRECTION.json)。

| 结果文件 | 初次默认归档的CRLF字节SHA256（不是Git blob） |
|---|---|
| RESULT.json | `54f4c49787d9aa3c2d30a05e5d1ddb53625fd637c41ee9e89850efcf941cb306` |
| W2_COMPAT_RESULT.json | `48373d77c0fe9ab12795ebbe7dedf438cf9869dd4f856b79234de616251c4b7f` |
| W2_COMPAT_SUMMARY.json | `3b9b332f03281e026a3156c02d43f0948077eac0af4071d6e9602bdbe79828c4` |

主窗原始复现和18项清单结果见[初交付核验](windows/w3_review/7bdf72b7/PRECHECK.json)。没有重跑已知存在阻断的旧全套；新执行源码交付后再统一完整复验。

主窗还独立复现[completion先完成但出口未退出](windows/w3_review/7bdf72b7/COMPLETION_BEFORE_EXIT.json)：记录已为complete、transportExited=false、cancelRequested=false，broker.close仍成功。已在首条返修中要求同类覆盖；不得只改exited rejection而留下退休记录绕过停止证明。该负例首次仅证据输出路径写错而未保存，改为工作区内绝对路径后重跑exit0；没有真实网络或辅助进程。

修订中快照：worker新W3结果42/42、W2兼容35/35及清理已产出，新commit和主窗复跑仍待，不用这份进行中的结果提前接受。主窗将使用[干净复验准备器](../../../../tools/mda2_acceptance/w3_clean_review.mjs)，关闭归档自动换行并对每个导出文件核对Git blob；原任务证据不被覆盖。

修订中又确认同类异常分支：HTTP适配SHA `255237b8ddcd93ad95719cb22e2fc671b18a6926cb6f04038798d1d3a84f7710` 的start catch无条件给closed收据。主窗使用自建随机loopback和真实request，仅注入write同步抛错；exited已成功而request尚未destroy/close，随后主窗实际destroy并等待close清理，测试exit0。见[定向证据](windows/w3_review/7bdf72b7/REPAIR_HTTP_START_THROW.json)；该文件明确绑定修订快照SHA，不属于7bdf源。已返同一任务修复创建request前/后失败的退出证明区别，待固定候选再复验。

## 修订验收顺序

1. 固定新commit并确认干净；从Git归档提取自有测试镜像，核对执行源、依赖、原W2历史和结果字节。
2. 独立复核注册/准备期拒绝、退出失败/非法收据、completion先完成、真实loopback socket关闭和late owner；无请求或取消ACK不能替代出口退出证据。
3. 主窗运行默认disabled状态、完整W3合成/原生编译、W2兼容35场景，保留实际进程退出、scratch清理与新测试结果；不覆盖worker证据。
4. 无阻断且同字节复跑通过后才形成接受裁决及具体选择性本地合入载荷，保护主目录并行修改。真实采集、生产端点、配对、自启、运行态切换及Android工作不随本包验收启动。
