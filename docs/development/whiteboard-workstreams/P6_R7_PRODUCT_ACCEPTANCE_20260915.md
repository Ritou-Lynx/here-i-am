# P6 普通聊天候选：9 月 15 日现场接续

当前接续见[9月16日记录](P6_R7_PRODUCT_ACCEPTANCE_20260916.md)：34窗口已到期并完成精确失败收尾；36/37准备完成但未启动。本页开窗状态均为历史。

## 20:57 接续：251b实际检查通过，准备34/35

- 用户再次“继续”后，已审251b只读检查01实际启动（`608512`），外层执行及collector47488实际退出0（`88b8dd`）；inspector实际0，2026-09-15T12:56:54Z—12:57:05Z。[报告](../../../tmp/p6-r7-review/app-lifecycle-owned-33/251b-rule-inspect/app-native-rules-actual-01.json) SHA `cc9bcafc6da9fac746133d4f6bbec2c5689f815fbc914f9298676374e69608e9`。
- 固定3filter/1sublayer均缺席，inspection_complete/current_rules_absent_verified/transaction_ended/resources_closed均true，零删除及模型请求。主控读回及[实际独审](../../../tmp/p6-r7-review/app-lifecycle-owned-33/251b-rule-inspect/ACTUAL-INDEPENDENT-REVIEW-01.md)确认关联；历史native4/Witness4、cleanup_pending及关闭证明缺口不改写。下文“251b未执行”属于09:20历史记录。
- 主目录现为`v3-lab@6ea772f18bb1ad7b50a5a04eafc3e972af91116c`，冻结产品仍389aa735的已选字节。新34/35独立dataset `265e2174-1ba0-4bff-9e32-4cc74c22122b`，package SHA `8412c24810f94198c0968bb40f0b6bbc982e2ebe8c502d53ec004941150c13b5`，bootstrap SHA `86e142e4640268af9d33bbfc03b0f239fadeb37f10c8b39e22427e7e3860988e`。399pins再次核实，旧32任务数据与已消费权限保留。
- v8预启动只读检查通过，但实际PS7.6.5将JSON UTC转换为`DateTime`，`DateTimeOffset.Parse`隐式字符串化时丢掉时区，年龄增加28800秒，启动助手在Witness启动前拒绝（`2eeaf4`、诊断`b2cd68`）。此时无新run artifact或DB，保留prestart02；修复只限时间类型处理及新观察路径，不放宽60秒窗口。
- v9按原类型保留DateTime.Kind，string仅接受带Z/offset且严格roundtrip的ISO-o格式；未知/Unspecified/无时区拒绝，0..60秒窗口保持。双PowerShell有限验证与包检查见[助手交接](../../../tmp/p6-r7-review/app-lifecycle-owned-34/helpers-handoff-v9.md)。主控最小diff`cc8398`；invoke-v9 SHA `875004a5a1bc1d4ccf954ed7cfaa5a6002ac6799121e7a4c70405b31e8a4a2b9`，prestart-v9仅02→03，SHA `ab10584970fa9164a8c86442ce491ccae7c1004472c3870d575c843b9eb51f3a`、parser0（`c52081`）。
- 真实启动`3e2648`，原执行session24814保持运行，prestart为13:04:26Z；App57520/creation134339510728148577、原Witness57116、Node16592/creation134339510752086777。用户确认已点“是”后，native40240 / attempt `03a01990-a1e1-4c15-9836-dff0e4938364` / broker8456完整预检通过：seq13 ready=true、actual0、六true/pendingfalse（`b6305d`）。
- 真实UI单键发送小写`hi`，完整回复“嗨，Lynx。”；普通session `04b00fc5-44a2-4603-aade-2e7922cf09b3`、provider `01a0a52e-488c-7331-a02f-9aff06e26384`、turn `01a0a52e-49be-7cb3-8e6d-0880643d4325`。session仍open；精确provider终态及关闭仍待post-close collector，不用pending_requests0代替。
- [短聊后DB](../../../tmp/p6-r7-review/app-lifecycle-owned-34/db-after-short-chat-01.json)只读actual0，tasks[]（`028437`）。[39条Witness链观察](../../../tmp/p6-r7-review/app-lifecycle-owned-34/witness-after-short-chat-01.json)验证当前登记（`c25eee`），不给恢复权限或原持柄死亡证明。批量type_text在聚焦与切换英文后均无文字输入，单键可用；已请用户粘贴固定enqueue句，当前草稿仍空，尚未发送enqueue/status/start/pause/resume。
- 后续仅通过真实普通原话操作本轮新ID。为缩短运行→暂停时间窗，可在一条原话内明确顺序status→start→若返回仍running立即pause；代码允许同一绑定ID的动作集合，但只有实际事件、精确turn终态和完整清理才算通过。输入框旁“停止”只停止普通回复，不能替代队列pause。原32的pending任务保留，不作34任务。
- 新post-close [collector-v7](../../../tmp/p6-r7-review/observe-product-ordinary-events-v7.mjs)仅从v6替换34/35及package/dataset，SHA `674a1361d491c78c939b68ed8cd6f6da9b40f99bd947f2a86475b9609be726a3`；主控生成/语法/最小diff`4de767`通过，绑定RegExp回调与strictclosed规则保持，尚未调用GET。接续优先核当前34进程与事件并继续原窗口，不重用其已消费bootstrap。Witness首窗限时须按原配置处理，不能静默延长或把超时当正常关窗。

## 09:20 已完成的现场收尾（历史快照）

当前 P6 / Goal 1 未完成。owned32已完成真实普通短聊、唯一公开任务入队、两个精确provider终态及App/Node正常关闭；唯一后继33在执行器预检返回1223/native4，未就绪、未执行任务，已精确结束失败App/Node，原Witness actual4保留。清理后任务保持pending。c874/7574固定规则当前缺席已证；新251b固定只读检查已准备并独审，尚未执行，规则状态仍unknown。执行控制及成功同库后继恢复仍待验收。

## 固定候选与启动

- 主目录 `v3-lab@aeb7f71a5b6fa454e0027392b3334d06d2e7b644`；冻结产品工作树仍为 `codex/p6-r7-product@389aa735` 的已选字节。399/399 pins再次独审匹配；App209源/152bundle、Node24闭包、Witness05/native均未改动。既有191项App/76项Node测试与构建证据不变，本次没有重建。
- owned30/31 package SHA `772d027e21485bcc187f3d7f380a84c9bb86619c416c3abdba55564e25294b0d`；dataset `a297924b-2e2f-4ae0-8272-f624a03a9f36`；bootstrap SHA `89addf73c5211b0361b662ecf4dd9c8a6581f5ea85c7f28146bc5db1e65502af`。真实配置构造器只读验证已通过，不等于运行通过。
- v5预启动检查成功，但启动助手将UTC与本地`DateTime`相减，得到负8小时而在启动前拒绝（`44bd2c`）。v6仅改为`DateTimeOffset`计算60秒新鲜度，并使用新的预检回执文件；保留全部候选、共享服务及缺席检查。语法与UTC/+08同一时刻校验通过（`86a81a`、`cb35f7`）。
- [prestart-v6](../../../tmp/p6-r7-review/verify-product-prestart-v6.ps1) SHA `1fa39094617ba3a1061b7fc0630d260a6cc77ac1248c7977e977b140942d6c86`；[invoke-v6](../../../tmp/p6-r7-review/invoke-product-recovery-v6.ps1) SHA `86729fd619141c3b76c914ea191fbf80425168c5e9d0673b8e035b6ccf1c33a1`。实际启动 `014226`，00:11:21Z。已消费的30 bootstrap不得再次使用。

## c874 只读检查02：当前规则缺席

- 固定旧29 attempt `c8749dc7-94b8-4221-ae73-29b6c6304530` 的检查02实际完成（`77d26d` / `ce16af` exit0）。collector41028与inspector实际退出均0；00:08:23–00:08:30Z。
- 三个精确filter与一个sublayer全部缺席，inspection_complete、transaction_ended、resources_closed为true；零删除、零模型请求。
- [结果](../../../tmp/p6-r7-review/app-lifecycle-owned-29/c874-rule-inspect/app-native-rules-actual-02.json) SHA `0a8c39b428ec7016c52fea745453f8550a1b79c3f632573ccb560b7f94386e1d`；[外层实际退出回执](../../../tmp/p6-r7-review/app-lifecycle-owned-29/c874-rule-inspect/readonly-uac-actual-02.json) SHA `62721f5016547c8a0311fae30d2ad99891a98564a1d2acd74a18474bb21f036c`。独立复核通过（`ccab7a`、`53a3a9`）。
- 这只证明观察时规则不存在，不能改写旧29 native actual4、cleanup_pending及不完整的历史关闭证明；未查询原Job，不提升恢复权限。

## owned30：预检失败及精确收尾

- 自有App47496、Node28236、原Witness55028；preflight native48872，attempt `7574bd66-475d-4ba5-8919-6fa1523ba073`，broker16400。00:13:39Z实际返回`task_helper_shell_execute_win32_1223 / native_startup_timeout`，native actual4。
- 无native child/普通session/turn/task，upstream0。最终seq11仍为`shutdown_unconfirmed / start_unconfirmed`，历史native关闭证明不齐、cleanup_pending=true。不能从Windows返回1223推断用户具体点击动作或弹窗是否可见。
- [精确清理脚本](../../../tmp/p6-r7-review/cleanup-failed-product-30.ps1) SHA `49dd60cf05cd74e19f1cce687bc1a21509b651c72dbdcd714ce24e9e59618f92`；核对完整命令、镜像、创建时间、事件及所有直接子进程后实际VerifyOnly/Apply成功（`88be29` / `01bad9`）。只终止App与Node，新held actual exit分别-1；conhost36112仅观察自然退出0。
- [清理回执](../../../tmp/p6-r7-review/app-lifecycle-owned-30/forced-failure-cleanup-01.jsonl)与[原Witness退出](../../../tmp/p6-r7-review/app-lifecycle-owned-30/witness-actual-exit.json)分开保存。原Witness actual4 / first_close（`eeff28`），无successor31。不是正常关闭或恢复通过。
- [最终Witness链](../../../tmp/p6-r7-review/app-lifecycle-owned-30/witness-final-failed-01.json)已只读收取（`83c6c4`）。候选数据目录和`candidate.sqlite`均不存在（`83c6c4`、`174a31`），因此本轮不能写作“DB任务为空”；数据库未创建。

## 7574 只读检查：03成功，前两次失败保留

- 固定四键检查器 SHA `72adc340a7435fd86762cfb57e93f9e307ad00fed2866d9513d16f7ea9df7cd6`；source SHA `22cf1b855648bc1e3921d03d9207b6a99ad121a81bc139e093cd525cc12813f2`。只绑定该attempt、原prepared/final哈希与精确四键，不支持删除或自由枚举。
- 检查01实际入口`f535bd`，最终`45e097` exit1；00:18:47–00:20:50Z。[原回执](../../../tmp/p6-r7-review/app-lifecycle-owned-30/7574-rule-inspect/readonly-uac-actual-01.json) SHA `d484b6351b0c308e5d1e9592b842c7e7d2838919447f1b78131f386ef4c3d087`。
- collector_started=false，未取得PID/退出码；失败阶段collector_launch，单层InvalidOperationException/HResult -2146233079，未取得Win32 code。检查报告与capture文件均不存在（独审`f78f9f`）。不能归因为1223，也不能声称7574已查询、规则缺席或完成清理。
- 用户说明刚才未注意弹窗，并明确要求重新启动一次。02保留全部冻结检查边界并使用新的CreateNew输出路径，但本次主控遗漏正常审批启动模式，立即返回同类collector_launch失败（`8e5f37`）；仍无检查报告。成功c87402与7574-01原调用使用`require_escalated`，实际调用历史已核对（`6ce6f0`）。路径差异是已观察事实，不能据此宣称Windows/sandbox失败根因已被证明。
- 03只机械更换新的观察输出路径及capture pin（语法0，`0e6555`），恢复与成功c87402相同的正常审批启动路径；Windows确认由用户处理。实际`fd65ec` exit0，collector52272与inspector实际退出均0，00:29:45–00:29:48Z。
- [03结果](../../../tmp/p6-r7-review/app-lifecycle-owned-30/7574-rule-inspect/app-native-rules-actual-03.json) SHA `7fe8f3cd619a49f9d5226b17222db89843a8a03b4b3186ce88fe98db8d741da8`：精确3filter/1sublayer缺席，inspection_complete/current_rules_absent_verified/transaction_ended/resources_closed为true；零删除、零模型请求。历史cleanup_pending和原关闭证据缺口不改写。
- [独审03](../../../tmp/p6-r7-review/app-lifecycle-owned-30/7574-rule-inspect/INDEPENDENT-REVIEW-03.md) SHA `de2d4bb1965a4f5d0c49e7a9893fc4e92b7bd79c2ef89ab265022918186f92d9`，7项pin与回执关联通过（`ddecb2`、`66702f`）。

## owned32/33：普通短聊已得到实际回复

- 新dataset `3a62196b-edd6-4b3c-bf22-6251d3cfc4d7`；package SHA `1ba80b48bb33fa1b8fd50f8d9e0437d6490178c492b5ab716abbecc076b6d9a6`；bootstrap SHA `db91823603ffd0d85f1ea713268bb4e2bf3dfc98766c100637b22c2677b6b6e9`，399/399 pins匹配。
- v7启动助手仅从已审v6替换32/33、dataset/package/bootstrap，保留DateTimeOffset与全部guard；collector-v5绑定roles32/33。真实配置构造器Dispose通过（`0abd8b`），生成/差异复核`78e905`、`5084d5`及[独审](../../../tmp/p6-r7-review/app-lifecycle-owned-32/independent-v7-helper-review-01.md)通过。
- 实际启动`5119d5`，00:31:32Z prestart；Node54572，host13824。preflight native13740 / attempt `dc879dff-3ed5-41ca-8d67-ae83a5fe9f59`，00:31:59Z seq12 ready；actual0、六项true/pendingfalse、upstream0（`cc21b2`、`c7bf02`）。
- 真实UI按键发送`HI`，普通session `ee0a56a7-f2a9-4a1c-8246-56d770f0e97c`、provider thread `01a0a27b-e5df-7570-9fad-c8be070c8bf8`、turn `01a0a27b-e6cd-7502-9ccc-9a36c786d50a`；UI显示完整“嗨，Lynx。”并恢复发送按钮。后续post-close collector已核实此精确turn由`turn/completed`终结（provider seq30），工具调用0。
- UI回复完成、第二条消息未发送时，[只读DB](../../../tmp/p6-r7-review/app-lifecycle-owned-32/db-after-short-chat-01.json)任务数0（`5b5419` actual0），SHA `29cbd3cd27753076fbcc2fa8c7c7eee6036d39c253453e908587517fe2c1a709`。此新库只读结果与30从未建库分开报告。
- 固定中文入队句的`type_text`调用后输入仍空，fresh UIA `set_value`返回元素不在缓存。用户随后确认已粘贴且未发送，主控置前核对并点击发送按钮；新消息UI完整显示固定原话。
- 唯一任务`0eb10d6e-b67c-42eb-a7cb-8d88773f3c8a`已由真实普通聊天返回。[入队后DB](../../../tmp/p6-r7-review/app-lifecycle-owned-32/db-after-enqueue-01.json) actual0（`a5f70d`），SHA `7db5806fc7cb2b1f561cb57a85b8adab443a8da14fcb4f09fe636d60b642d1ee`；标题/目标/精确conversation匹配，pending/retry0/actions[]，execution epoch/session/turn/phase为空，结果0字节。该DB投影不含generation，首代仍以原Witness链核对。
- 后续最短精确原话可用`task status <UUID>`、`task start <UUID>`、`task pause <UUID>`、`task resume <UUID>`，每句只含该唯一完整ID；只是授权工厂支持，不代表已执行。批量输入和快捷键未能可靠写入，单键输入及原生编辑菜单可用。草稿`taskstatus。0eb10d6e-b67c-42eb-a7cb-8d88773f3c8a`未发送；本轮没有status/start/pause/resume。为避免首窗口时限耗尽，主控告知用户后先做pending任务的正常关闭与单次后继；不得写作运行中或暂停态恢复。
- post-close collector-v6在v5基础上仅修复未绑定的`RegExp.test`回调，并更正32/33注释；SHA `7a9c9fffb8cfd57b2dccb774e669632dccee22eb3f103eb82c31529cec5fd33a`。原ID规则的合法/非法样例与旧未绑定回调TypeError对照通过（`8eba08`），严格closed/逐turn终态、固定GET、精确tool、输出CreateNew条件保持。实际收取`a57100` exit0：[83事件闭合报告](../../../tmp/p6-r7-review/app-lifecycle-owned-32/ordinary-events-01.json) SHA `a1e3f9656ecb379f1cdf6a0d6f048a725bbf52c45172037401e6d6067a3fcb78`。
- 入队turn `01a0a280-9448-7991-8897-5ad430217bef`恰好1次enqueue call与1次成功result，原call ID `exec-d5929278-7b9b-4787-8a77-6186cf71bf1d`，标题/目标精确匹配；`turn/completed`为provider seq82，session_closed为seq83并绑定上述两个终态。主控读取核实`8eaed8`，另有[独立只读复核](../../../tmp/p6-r7-review/app-lifecycle-owned-32/independent-ordinary-events-review-01.md)。该证据证明普通话轮及入队，不证明任务执行结果。

## owned32正常关闭、唯一33后继预检失败

- 真实点击首App标题栏关闭后，01:01:30Z Node seq69 `shutdown_completed / input_shutdown`，普通guardian已关闭、两个turn与原任务绑定不丢（`951771`）。[原Witness链投影](../../../tmp/p6-r7-review/app-lifecycle-owned-32/witness-after-pending-close-02.json)只读通过（`4a3340`），SHA `89d81a6eac265229c224cfc83afb682b197db3550f36907385a601cdcd195a5f`。
- 该137事件链seq132为app_closed，双EOF/stdin/store/client证明完整；seq133记原持柄App48856、Node54572实际退出各0，原因normal_app_closed。随后只有一次successor intent/register/claim/consume：generation1→2，注册App48024。只证明32正常关闭及单次授权后继启动，不能提前宣称33恢复通过。
- 33的Node52904未ready；preflight native44980 / attempt `251bf633-8491-421b-8434-0e6830f21b92` / broker19950。01:03:45Z seq8为`shutdown_unconfirmed / start_unconfirmed`，native实际4、`task_helper_shell_execute_win32_1223 / native_startup_timeout`、cleanup_pending=true，upstream0、无child、普通session_start_attempted=false；见[失败观察](../../../tmp/p6-r7-review/app-lifecycle-owned-33/pending-successor-observation-01.json)。1223不能证明用户具体点击或弹窗可见性。
- [33清理脚本](../../../tmp/p6-r7-review/cleanup-failed-product-33.ps1) SHA `cbc585834e21584cd65b8b6020c3650e269e3e82f0b0b78378050d7d26aff906`，从30仅替换精确32/33实例常量、recover模式及8行事件约束；完整argv/创建时间/镜像/直接子进程和失败状态均核实。主控VerifyOnly `d0239c`、Apply `2cf4f4 / 02047c`均actual0。新held App48024与Node52904分别-1；conhost35084仅观察自然0，未终止Witness/native/共享服务，未修改规则或数据。见[清理回执](../../../tmp/p6-r7-review/app-lifecycle-owned-33/forced-failure-cleanup-01.jsonl)。
- 原启动执行单元32747已排空（`9a230e`）：Witness actual4，`owned_recovery_frozen / stage successor`；外层启动脚本actual1。见[原实际退出](../../../tmp/p6-r7-review/app-lifecycle-owned-32/witness-actual-exit.json)。这不改写32正常关闭，也不是33正常关闭；已消费bootstrap不可重用。
- [失败后只读DB](../../../tmp/p6-r7-review/app-lifecycle-owned-33/db-after-successor-failure-01.json)仍唯一原任务pending/retry0/actions[]、无execution binding、结果0字节，context与入队时一致。数据库被保留不等于后继App已成功打开数据库或恢复验收通过。
- [清理后DB](../../../tmp/p6-r7-review/app-lifecycle-owned-33/db-after-cleanup-01.json)再次只读核实状态未变（`b61752`），SHA `c84c19774a460b48881b94e11b28e98a276b240f3c7473f9eda91b67e7fe3458`。[最终138条Witness链](../../../tmp/p6-r7-review/app-lifecycle-owned-32/witness-final-failed-01.json)只读校验通过（`38285c`），SHA `9f3b84ccc4233bbcba620eec2687677ad49bc243f5419bda905e9583be5262c5`；唯一后继intent/register/claim/consume各1，无再次派生、无successor_actual_exit成功证明，不能补齐恢复成功。

## 251b固定只读检查准备完成，未实际运行

- 保护元数据只读核对（`587f40`）：scope `7f6856c2-003b-2060-2e7e-dcc02b266cc7`、owner44980/creation134339076994623093、broker19950及native/CLI字节匹配；prepared SHA `e9d0808bf54a2c23a87a3969e2657a05101f3d66c76df59e6e98d719246afe83`，final SHA `624678e911a40b257ec1a9d65faca3215b3afed11bc2d73c01bfa7b3070bc9b9`。started=false、无child、历史cleanup_pending=true保留。
- [检查准备交付](../../../tmp/p6-r7-review/app-lifecycle-owned-33/251b-rule-inspect/README.md)：相对7574只改六组实例常量，严格固定三filter/一sublayer；无枚举、删除或恢复授权入口。编译actual0（`9bb29f`）、静态4/4（`b3046f`）、两包装器语法0（`96cb88`）。主控最小diff/包装器复核（`436b8c`）及[独审](../../../tmp/p6-r7-review/app-lifecycle-owned-33/251b-rule-inspect/INDEPENDENT-REVIEW-01.md)通过，10个manifest pins匹配。
- source SHA `fcd65d2b982552155523a0a00ae5239eec05ff6a4ce1d5edee447d0550643163`；exe SHA `6bcda8ae5947b825d827791a519c5ecd3917829df5ebddc960cf2720eb65e0d9`；capture SHA `9cb49dd05e5e6cfc90531e2d1c89f23ce124054005bb9fd7939b2c8c0b95095c`；launcher SHA `a06d0ae02d1d54bf0825d5917b52bc85bf442b271e80240b87e3592a9a0f25ba`。
- 本次没有启动251b检查器或再次触发UAC。未来由主控使用已审`launch-readonly-inspection-01.ps1`、正常获准的启动方式及原持柄实际退出收口；Windows安全确认由用户本人点击。当前3+1规则为not_inspected，不能从静态通过推断缺席或清理完成。

## 接续与保留边界

普通Gateway47831仍为Node7384/parent21348/新版CLI50692，47841仍为原25332。最终01:16:52Z创建时间、parent及端口归属只读核实未变（`6bafcd`）；失败33的App/Node/conhost/native/Witness五个精确PID当前缺席，01:17后复核仍0个（`597ca4`）。[最终观察02](../../../tmp/p6-r7-review/app-lifecycle-owned-33/final-process-observation-02.json)修正01中空PowerShell成员投影序列化为`[null]`的问题，保留原01及服务观察时刻；当前缺席本身不作原持柄退出证明。新版CLI已在32完成两个真实普通话轮并取得精确provider终态。隐藏helper窗口不能证明UAC未显示；Witness的StartApp启动的是Flutter App，不是Node。

先完成251b固定规则只读核查；当前不再重复唤起无人处理的Windows确认。下一轮须依据未消费的新授权包进入精确status/start、运行中pause/resume、最终结果及成功同库后继，不能重新激活32/33的已消费权限。Windows安全确认只能由用户本人点击，不能用输入工具代点。普通入口短聊、明确enqueue与32正常关闭已有本轮证据；仍不得继承旧候选的运行/暂停恢复结果。默认生产保持拒绝，真实任务`fc91503a-0e59-4f7f-a480-14215e67cb05`未操作，无提交、推送或发布。
