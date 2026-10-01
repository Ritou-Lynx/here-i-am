# P6 R7 产品候选文件封包脚本交接

日期：2026-09-14。本包只新增 `tmp/p6-r7-review/prepare-product-recovery-package-v1.mjs` 与本文。脚本已经语法和生成模板的只读检查，**尚未运行封包生成**；没有创建owned24/25、实际bootstrap或启动App/Node host/provider/UAC/native，没有修改旧封包和旧脚本。

脚本SHA-256：`93a661b3d226f017949d4a7229263c0076f4046214557bb2a2636a2b5b267f9b`（chunk `ffddc0`）。它只读取受审输入、核验哈希和生成新文件，不含child_process、HTTP调用或动态执行launcher的代码。

## 固定输入与主控接续

参数顺序保持旧v4的形状：`--build-sha256 <64hex> --host-review-sha256 <64hex> --first <两位编号> --successor <不同两位编号> --case normal|app-death`。24/25仅是主控拟用的新编号，目录已存在则拒绝；不提供覆盖、恢复半成品或自动清理选项。case只记录计划场景，不执行故障注入或启动。

- candidate及host源码均固定 `D:\memex\.worktrees\p6-r7-product`；App固定其 `build\windows\x64\runner\Debug\memex.exe`。
- App清单固定 `tmp/p6-r7-review/app-product-build-01/candidate-build.json`，要求schema `p6_r7_product_app_build_v1`、build_exit_code=0、40位baseline、非空goal及source_files/bundle_files；逐文件校验SHA-256及bundle size。相对路径拒绝越界、冒号、点段及文件链中的symlink，App本身必须出现在受审bundle清单中。
- host审查固定新worktree根的 `p6-r7-product-host-review.json`，要求baseline与App清单一致、testExit=0、`sourceHashes`为完整闭包basename→hash、`sharedClosure.sha256`为根目录 `p6-r7-product-union-closure.json` 的实际字节哈希。无旧witness-host-baseline硬编码pin。
- 从两代host真实递归解析静态本地mjs依赖；拒绝动态import和目录外/非相对非node依赖，≤64项。review sourceHashes与union closure必须分别与递归集合完全相等，且必须包含binding与Gateway transport。不会仅核对两个入口。
- 队列工具固定 `tmp/p6-r7-review/product-app-schema-export/queue-tool-definition.json`，SHA-256 `1d6883d52d165afb4923877571bc66cbcf9e7df8c22cbc972143fba613f797de`，名字必须为 `manage_long_task_queue`。未重新定义schema或改成零tools。
- Witness05固定exe SHA-256 `e60ab90477230a593563656d4c27c1bd4835b39655f9b90e3b29895cb818d8fc`；原Node、native-source-rebind-01、addon02固定路径与哈希原样保留，没有改WFP或CLI配置。

主控须先形成新App构建清单及包含最终binding/transport/Witness05 pin修改的host review，复核本脚本后使用其实际哈希参数运行。本包不把主控此前任何一次测试结论硬编码为新source已通过；输入review必须真实对应最后一版文件。

## 两代launcher与普通会话接线

两代均从owned22的修正版launcher源衍生，固定基底SHA-256 `e5d835e94be57cd5070c811f4be216046424dd82229539f62b9fd99a454f9b0d`。旧stdin、stdout丢失保护、closed后不再写日志、30分钟上限与process.argv/Node executable hash检查保留；第一代保留App EOF独立见证路径。第二代只还原为旧successor的shutdown/EOF分工，不调用其不存在的appStdinEof，不提升其见证范围。

生成的launcher分别静态import新worktree的candidate/successor host，另静态import该同一闭包中的binding与transport。第三参数为真实 `new WorkbenchProductHostBinding(...)`，第二参数undefined，不注入fake native factories。

每次封包产生新dataset UUID；conversationId为 `p6-r7-candidate-` 加dataset，scope按旧profile/conversation/title/goal形状计算。dataset、conversationId、scopeHash、固定dynamicTool及其来源哈希嵌入 `launcher-config.json` 的product字段。launcher只用这些已pin的值构造binding，并调用无配置参数的 `createWorkbenchProductGatewayTransport()`，没有接受模型提供URL、auth、command或测试requestImpl。

`owned-host-config.json`仍是原 `p6_r7_owned_host_v1` exact结构，仅三个pins：launch.mjs、launcher-config.json、closure.json。product没有添加为owned-host第四个pin，也没有修改BootstrapConfig authority/schema。普通会话不是新增text native owner；普通关闭unknown仍由真实host hook阻止host_closed/exit0，脚本没有覆盖关闭判定。

## 写入与证明边界

脚本先在内存构造两代closure/launch/launcher-config/owned-host-config/candidate-build副本及Witness05 bootstrap，全部pin总量≤512。所有外部输入及source在首次写入前再次校验；两代目录以非递归mkdir新建，输出文件均flag wx/CreateNew。生成最后的recovery-package报告包含bootstrap哈希、输入审查哈希、工具哈希、脚本自身哈希和started:false。失败半成品不自动重用，需主控检查后选择新编号；本包没有删除动作。

未复制旧observe-native-identities辅助脚本、日志、actual-runs、旧数据或运行收据。受信资源收尾仍来自正式host/Witness证明，文件封包不声明旧实际Gate可继承。App真实data目录仅检验不存在，不创建或读数据库。

## 本次验证

- chunk `fc5df3`：`node --check tmp/p6-r7-review/prepare-product-recovery-package-v1.mjs`，exit0。
- chunk `51a3be`：从新脚本读取模板转换段，以owned22源执行纯字符串替换；两代生成文本均通过未链接、未执行的 `vm.SourceTextModule` 语法解析，并断言精确替换次数、固定argv、stdout/closed保护、第一代独有EOF方法、三个新worktree import及第三参数品牌binding。exit0，未写文件、未import/evaluate任何产品模块。
- 脚本没有执行，所以本次没有build清单/host review最终内容的验收，也没有生成实际bootstrap、封包输出或真实启动结果。主控review与文件封包运行是下一步。
