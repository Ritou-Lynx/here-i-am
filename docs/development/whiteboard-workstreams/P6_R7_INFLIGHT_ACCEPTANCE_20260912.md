# P6 R7 执行中 HTTP 与宿主退出验收

后续状态：本页保留 HTTP/native 阶段及其当时“App仅设计”的历史结论。独立 App 入口现已实现、构建并完成部分实测，新增启动失败清理未确认；当前待办以 [App验收](P6_R7_APP_ACCEPTANCE_20260912.md) 为准。不得把本页“当前无待清理实例”扩大到后来 App 的新失败实例。

2026-09-12。承接用户“继续下一步”；基线 `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`，索引为空。上轮已通过无模型 turn 的正常 HTTP 关闭及默认三 pipe 宿主强退，见[原始证据](P6_R7_HTTP_NATIVE_ACCEPTANCE_20260912.md)。本轮不继承旧组合的模型完成/取消结果。

## 当前范围

使用同一 native v7（exe SHA `73CBE6277FD4BF5B92BDC3189E00EEE5CE78F208D6037D8D16A14DF9BDE4BC4E`）、保留三 pipe 的 detached transport、已有专用账户和既有固定公开测试句。独立 loopback HTTP 宿主经真实 API/adapter/TaskSession 创建并执行；不切现役 Bridge、不操作真实队列、不启用生产 profile。

三个 HTTP 场景分别验证固定文字完成、精确中断、turn 启动响应交付前的客户端断连。中断请求的 ACK 不作为结束凭据；须匹配 thread/turn 的 `turn/completed`，回收凭据另须精确本地关闭、broker 排空和原生六项事实。[官方中断协议](https://learn.chatgpt.com/docs/app-server#interrupt-a-turn)亦将成功请求与最终 interrupted 状态分别描述。

`broker.upstream_attempts` 表示调用本地 exchange 的一次尝试，不能单独证明远端已接收或开始计算。强退后的本地进程与网络资源回收也不能推出远端停止计费。冻结输入、实际退出码、有限结构报告逐实例保存；失败保留，不自动换题目、放宽终态或复用旧成功结论。

## App 入口核查

现役 App 的 coordinator 固定创建默认 runtime，默认 Bridge 为 `127.0.0.1:47831`；任务生产组合加载真实 TaskRoomService。虽然 task queue factory 有 runtime 注入参数，实际 App composition 尚未提供独立 host、隔离数据源的调试入口。现役 Node Bridge 也未注入 text adapter factory；仅启用 experimental API 的环境变量不能开启 text profile。

因此当前可验独立 HTTP/native 生命周期，不能将它声称为真实 App 界面通过。App 阶段需要显式候选 host/runtime 注入和隔离测试数据入口；缺少这些接线时不改现役端口或真实队列。页面离开及后台保持执行、明确取消、detached 尽力回收、重启不自动执行分别验收。

## 当前验收结论（本次“现在可以”之后）

本阶段四项独立 HTTP/native 候选实测全部通过，当前无待清理实例。分支 `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`、空索引、43项既有改动保持。生产仍 `available=false/fail_closed=true`；这不是 P6/Goal1、真实 App 或真人 Gate 完成。

| 场景 | 精确实例 | 实际退出 | 证据 | 报告 SHA-256 |
| --- | --- | --- | --- | --- |
| completed-05 | `83b3e4fc-7269-4244-b160-e497bf5664bf` | Node0 / native0 | [报告](../../../tmp/p6-r7-review/inflight-http-completed-05.json) / [核验](../../../tmp/p6-r7-review/inflight-http-completed-05-verification.json) / [实际退出采集](../../../tmp/p6-r7-review/inflight-http-completed-05-capture.json) | `B82458A20D7A7431514EC5E186B8BA4D268180C7BE9A2D5D8EF91CABCA8A493E` |
| interrupt-05 | `beb6207d-fd8a-45c2-bd3e-76f05e5d501f` | Node0 / native0 | [报告](../../../tmp/p6-r7-review/inflight-http-interrupt-05.json) / [核验](../../../tmp/p6-r7-review/inflight-http-interrupt-05-verification.json) / [实际退出采集](../../../tmp/p6-r7-review/inflight-http-interrupt-05-capture.json) | `72150E025416128DD46BA8A37B0FCF19634E835F3F13F790EEC90D16D4D56E15` |
| turn-disconnect-03 | `e46bd31e-8136-44cd-85b2-73e2bc9e1242` | Node0 / native0 | [报告](../../../tmp/p6-r7-review/inflight-http-turn-disconnect-03.json) / [核验](../../../tmp/p6-r7-review/inflight-http-turn-disconnect-03-verification.json) / [实际退出采集](../../../tmp/p6-r7-review/inflight-http-turn-disconnect-03-capture.json) | `C9B6C246983165BA06AD81684DCC1F04FE92EA984D7F969B8CB111549B835A8A` |
| inflight host-fault actual03 | `0aa4eba7-6c86-4bf2-883c-e169c20746f7` | witness0 / held Node77 / native3 | [报告](../../../tmp/p6-r7-review/native-inflight-host-fault-actual-03.json) / [核验](../../../tmp/p6-r7-review/native-inflight-host-fault-actual-03-verification.json) / [实际退出采集](../../../tmp/p6-r7-review/native-inflight-host-fault-actual-03-capture.json) | `7AD6146421315795272C687C1FBD33B2D83D99B56464C397BAD047C53294DD58` |

三个 HTTP 场景均一次 start、一次 exchange，原生 process/Job/stdio/rules/handles/helper 六项 true，broker drained、宿主关闭、pending false。完成场景收到固定文字及匹配 completed；取消和断连须真实中断 dispatch/ACK 后匹配 interrupted，空文字、未释放响应。断连另确认真实 AbortSignal 和唯一 API-origin 同绑定 close，finally 回收不能补造通过。主控逐实例核验输入各26项；新增启动器采集 Node 实际退出码及显式 `--use-env-proxy`，最终另将 Node/launcher/manifest 后置哈希与冻结值比较。

强退在本地 exchange 已进入且未结束、无文字/终态/响应释放的 ready 后，仅终止持有的同一 Node。ready接收到kill调用为0ms；该窗口仍非原子。Node实际77、native实际3、stdin EOF、stdout最终发送失败、同绑定持久凭据及六项回收均成立，pending false；witness原本就显式使用代理。31项输入/20模块闭包匹配，独立221项断言通过。远端在kill瞬间是否仍运行、是否停算/停费、broker在kill后的drain及provider terminal均保留null；重启恢复未验。

### 此次修复与启动条件

- adapter 原先先撤销 exchange 再调用 TaskSession.close，导致断连01收到failed而非interrupted。最小修复交由已有TaskSession先等待中断RPC，再撤销和回收；无task、创建取消和故障路径仍立即撤销，严格终态、相同owner和未知关闭重试保持。源码 SHA `6B4DF3357077E0080972623B0FED3D4C309183284468D4BBB73ED2187661654C`，测试 SHA `B45910A3E6F21AF05B712A6DD3C59AAFDA34D1FA5F7DC3DA712A2D0719A67374`。主控 HTTP/adapter/TaskSession 专项45/45、独立34/34及代码复核通过。
- HTTP完成03/04的有限报告均为transport_failed；该通用码也可能涵盖读流失败，不能单凭它断言没有HTTP响应。另行无凭据HEAD对照显示当前启动未启用环境代理时UND_ERR_CONNECT_TIMEOUT约10.7秒，显式已有代理返回405约868ms。随后不改源码或机器配置，在固定[启动器](../../../tmp/p6-r7-review/run-inflight-http-env-proxy-01.ps1)中补 `--use-env-proxy`，完成05通过。405只证明连接可达，认证/模型完成由后续actual05另证。
- 启动器 SHA `2FFC85EB00E8344D63A8E5AD3A04310DB5D7BAC742D8BEFC12DED70F5CC25FF9`；native v7和HTTP probe保持本页固定pin。host-fault当前witness exe SHA `1768612715960AA76B506E0C4C1B4E47E176843A34841249E60C00F76B255D77`，[31项冻结输入](../../../tmp/p6-r7-review/native-inflight-host-fault-03-inputs.json) SHA `60D10BC62454E830E177DD3FBA8EB98F37D1FFAFDDE2B0D840BE675918C13DB3`。

### 当前恢复与历史失败

6946c568 精确恢复v2已实际完成：inspect/cleanup各exit0，仅删除其3个filter和1个sublayer，事务提交后当前规则缺席、资源关闭、recovery_pending false；原interrupt02失败/pending/停止回执未验证保持。v1本次已启动但因ClosedHash字面量第14/15字符互换在stage1失败，零删除；修正后新增8项独立输入对照测试，主控2/2、C#260及最终9项pin复核通过。较早UAC取消是独立历史事件。完整pin与实际报告见[精确恢复交接](P6_R7_INFLIGHT_HTTP_INTERRUPT_RETIRED_HANDOFF.md)，不再重跑已完成清理。

- interrupt03/e6bd14c5通过旧adapter；turn-disconnect01/b47fb1a9因提前revoke失败，但native0/六项true、当前已回收。均保留原报告，不提升为新adapter证据。
- 新adapter但未显式启用代理的completed03/91c73d97及completed04/6fefd7b3均失败，本地回收完整；interrupt04/0adac4c2、turn-disconnect02/c6a06a57各自通过。最终统一采用本页表格中的显式代理启动组合。

### 后续边界

下一步是实现[隔离 App 候选入口](P6_R7_APP_CANDIDATE_ENTRY_DESIGN.md)，使用独立host及新建空测试数据，再验页面离开/后台继续、取消、detached尽力回收和重启不自动执行。当前仅设计，不构建或运行该入口，不触碰真实队列。现役47831/47841仍是原PID28396/32704及原启动时间；本任务未提交推送、构建安装App、切换服务或改变API/费用/权限定义。

[最终范围、输入与退出核验](../../../tmp/p6-r7-review/inflight-resume-closeout-verification-02.json) SHA `E00B0687B4F155457BB2C481CF053501E26648E1F2E92A980567D5A1D210AD71`。下方保留较早尝试及其当时结论，当前下一步只以本节为准。

## 较早尝试与当时状态（历史）

较早暂停点：Windows确认曾返回用户取消、当时管理员未启动；此后用户“现在可以”触发的恢复v1检查失败及v2精确成功均见上节。原取消时点的记录保留，不能再作为当前未启动结论。

旧v1启动器及当时范围记录仅供追溯：[启动状态](../../../tmp/p6-r7-review/inflight-retired-launch-cancelled-01.json)、[旧范围核验](../../../tmp/p6-r7-review/inflight-closeout-verification-01.json)。恢复v2已完成，禁止按旧入口再次清理。

HTTP 探针已经独立审阅，修复 JSON 停止回执校验、绝对超时栅栏和断连观测顺序。最终源码 SHA `A6118B5F2C0D3DEBD9B873FB900CA61D61067D97DDEB4E320926291523BE1EF7`，测试 SHA `6A4552189C150CF5395BD828F826EC8E2D90A95CD0F1448B81C8DD43B6C0A9EE`；主控专项 **11/11**，worker 相邻 **43/43**。真实 API 发起的 close 与实际 AbortSignal、同一 promise 回执共同作为断连证据；finally 清理不能补造成功。

宿主强退探针经过两阶段握手：先绑定持有的 Node/native/CLI 句柄，再发唯一固定 start；仅当本地 exchange 已进入且未结束、没有 terminal/text/响应释放时提供 ready。witness 在接到 ready 后 1000ms 内复核身份并只终止 held Node，要求实际 exit77、native exit3、EOF、stdout 最终发送失败、同绑定最终文件及六项关闭事实。ready 到 kill 非原子，远端是否仍运行、是否停算/停费、broker drain 和 provider terminal 均保持未知。主控专项 **8/8**，其中 C# **66** 项 self-test；BOM 修订和 held Node 实际退出码已独立复核。

### 逐实例记录（保留失败）

- 最终 HTTP `completed-02` / `26199414-8c84-4b75-9ed7-4d1479c61b1a` 已通过：固定文字与匹配 completed，HTTP create/turn/delete 200，native0、六项 true、pending false，26 项输入前后相符。报告 SHA `07592C224C99251277EDBC6C36DDE95327894927AB332182B9F217F534C76E1B`；[独立核验](../../../tmp/p6-r7-review/inflight-http-completed-02-verification.json) SHA `80C4B29E52E9577A4C1F00296A12A847FF346FBA2677636A648CCA6E471F5538`。
- 最终 HTTP `interrupt-02` / `6946c568-0440-4574-8fbc-2d069b071c6c` **失败**：精确中断已 dispatched/ACK，匹配 interrupted、exchange abort、broker drained、空文字/未释放响应均观测到；但 native 实际 exit4，rules/helper 两项 false，pending true，DELETE503、停止回执未验证。没有 cleanup-ready/ack/receipt，具体助手失败原因未确认，不推定用户取消。原报告 SHA `F697DF1BD14F3555B94DA90CBFD09B026ECE6FA7541F516AD79C58DD140B5F99`；[失败核验](../../../tmp/p6-r7-review/inflight-http-interrupt-02-verification.json)。精确恢复单独记录，不能改写为该次通过。
- 宿主强退 `actual-01` / `427b4805-2bb9-40b0-9c01-d25b3ea66676` **失败且未强杀**：未收到 inflight ready，随后 graceful 完成、native0。原 witness report SHA `F89412DE1AECB399028215B83E03F2020490F08FFDF48ADA61B9D7D2E6EB3FF5` 保留 pending/失败。另行核验同绑定 final 为 close_command/stdout true/六项 true/pending false，确认本次正常清理；[独立正常清理核验](../../../tmp/p6-r7-review/native-inflight-host-fault-actual-01-graceful-verification.json) SHA `B6E5DC7B17D8FC9F387262523632A57376E5D7353DB4E6D65339759BDBDAF736`，不补造 host-fault 成功。
- 该强退失败的控制流原因已在**同实际启动壳**的无账户 dummy 中复现：Framework StreamWriter 首帧为 `EF-BB-BF` + 固定 start LF，原严格 parser 拒绝。仅修订 contract 接受整个流起点的一次 BOM，拒绝帧中/后帧/重复 BOM 和前导空白，真实 C#→Node 管道回归通过。target/witness/native 未改，contract SHA `7A5FA9370A7704798A204F558C8551BFA84F16F82E81646CBBA4BC3B4EBF7785`，候选02重新冻结31项输入。
- 早期探针 SHA `0F0DBAB8…89CE9C` 下的 `completed-01` / `277819d3` 和 `interrupt-01` / `38be7d2b` 各自通过；只保留各自原清单和核验，不提升为最终 HTTP 源码的证据。

### 历史恢复v1与强退candidate02

6946c568 恢复仅针对其三条 filter/一个 sublayer，固定8记录文件、owner/child/install-helper 创建时间、native/CLI映像、AppId摘要、目录ACL及精确顶层清单。独立审阅发现并修复 closed phase/child 比较、原 pending=true 与 operation_failed=false 三处校验问题；主控专项1/1（含 C#260、自身 plan/拒绝参数及 History/CaptureHistory 合成正反例）通过。source SHA `EF9FB5A49AD83E1DB04BC9CB3442EF7C3E3361384E0D0DAD2ADB47D9038DE742`，exe SHA `6DF591F4B17A3ACD2B0DFB704A4EAF57BA67201D96ABC80B78CF35D4B67BC3F4`；[冻结构建](../../../tmp/p6-r7-review/native-inflight-retired-01-build.json) SHA `C05B7492B9C0E23548D2964AA7C42907DFAB14DBB97784E0B8D8E12FB2132DA0`。该v1当时没有成功恢复结论，后续v2实际成功见上节。恢复通过也只能关闭当前规则遗留，原 interrupt-02 的失败/停止回执未验证保留。

宿主 candidate02 复用 target SHA `D4E92AAA236888C076BC6AD7C2D5330E1A29F2091A27836091B295FB40881C72` 与 witness source SHA `10514755B6D9612423299C30C6646A4A8AED359C2CDB14817412AFBDB25E160F`，仅控制 contract BOM 修订；新 exe SHA `D8E02A741BB4DBEBFDB843673A74B1AF720B6831CD5E244F00631B3C865212ED`，[31项冻结输入](../../../tmp/p6-r7-review/native-inflight-host-fault-02-inputs.json) SHA `ABB6A36CCF236BCC3F6D3CA82245E84CF44315FC5D29ED3F34A969475D320B96`。该candidate02未执行，adapter修复后重新冻结candidate03并实测通过，见上节。

生产继续 `available=false/fail_closed=true`，P6/Goal1 未完成。[App 候选入口设计](P6_R7_APP_CANDIDATE_ENTRY_DESIGN.md) 已完成只读核查和方案，尚未实现、构建或运行该入口。
