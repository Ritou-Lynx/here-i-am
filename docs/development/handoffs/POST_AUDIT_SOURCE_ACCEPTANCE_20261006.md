# PREDEPLOY 审计后源码与候选验收（2026-10-06）

本轮执行用户确认的 D1–D4 推荐。PR12 和 [PR #13](https://github.com/Ritou-Lynx/here-i-am/pull/13) 已普通合入 `v3-lab@90f23ce1d38628901e25b421d8f0f21c084f093b`；正式源码副本已仅快进，生产 Core、MCP 配置及主力手机保持原样。本次合并回执在原任务分支单独提交，不改写已测源码或追加主线提交。

## 已完成的授权动作

- B3 备份分支已推送：`codex/b3-writeback-local-20261003@3a9336b122b2fda22ff65ed32d9cee263e8fc2da`，远端 SHA 一致。正式与 B3 根提交均 `b96d9961950e8c0d6cbd71e4eafdb735833b0f7f`；和 D 私人旧谱系 HEAD 可达集合交集为0；153 新 blob 的敏感路径/字面密钥筛查无命中。筛查不是所有内容绝对无隐私的数学证明；没有迁入 D 旧历史、运行数据或凭据。
- [PR #12](https://github.com/Ritou-Lynx/here-i-am/pull/12) 在 `d9a8498264d349f8593cd421e76db3e77ad102fd` 五类精确 head 检查成功后普通合入 `64aea69331ecd374d4365d6b6a87025f757eb160`，合并时间 2026-10-05 17:22:32Z。
- [PREDEPLOY 原审计](https://github.com/Ritou-Lynx/here-i-am/blob/codex/predeploy-audit-20261005/docs/development/handoffs/PREDEPLOY_AUDIT_20261005.md) 保留在已推送的独立审计分支，未合入 v3-lab。本轮主窗在线复核远端ab6dc2c28a2f19e313c9eb0091fe1192b3aecad4及报告路径可达；独立文案复核的凭据限制不当成远端失联。

## 兼容与下游行为

1. [Drift61/62](SCHEMA62_COMPAT_20261006.md)：两个表定义和完整迁移区段按行尾归一后与 B3 逐字一致，schema63起预留给之后的新迁移。隔离白板候选 restart/recovery 的只读版本门槛也由60同步62，身份/来源/任务断言不变；旧60和未知63仍明确拒绝。毫秒/服务端序号排序与定位分页也恢复；真正新增 feed 按页/角色通知及调度一次，回声和重复不会重调度。
2. [D1/D2 transcript/replay](CORE_TRANSCRIPT_COMPAT_20261006.md)：当前 Android credential 绑定 grant，受限 transcript 与 PR10 共用不可变 digest/序号持久化；legacy_b3/pr10/disabled 三选一，旧 grant 不能授予 PR10。72 外置审批与 durable ledger 保留，alias/身份/载荷变更拒绝。
3. [单一上传器](B3_UPLOAD_COMPAT_20261006.md)：每轮 capabilities 只选一个入口；旧 companion outbox 的 sender 只在本机匹配后修复，不改 sync_id/origin sequence；拒绝的 companion 保留，403/404仍允许拉取，未知模式拒绝。
4. [PR12账本跟进](CAPTURE_LEDGER_FOLLOWUP_20261006.md)：记一下的收支卡进现有账本面板，同源修订复用稳定行；删 capture 清精确属主行，保护用户改卡且留提示，其他手工账本行不受影响。没有对全部既有已消费 capture 做自动回填，也没有把本机账本升级为 Core ledger 权威。
5. `claude.ai day_get` 保持 canonical queues 的事项 ID，额外返回 `item_titles` 的 title/revision。独立 `plan_items:read` 才可取标题；缺权限、删除、失败或超过500条有明确 issue。限4并发；标题是各项当前版本，不能称跨领域原子快照。
6. [D3 单消费者保护](CAPTURE_BRIDGE_TRANSITION_20261006.md)保留 47862、既有安全存储和 note receipt；网页 Core 消费缺真实闭环 Gate/来源 adoption 时阻断，包括墓碑，手机 quick capture 继续。切换只留一个消费者，过期租约可回收且旧 worker 被 fence。失效租约模型返回不落卡/回执，不发送新 ACK；已发出的 ACK 无法撤回，返回后仍不能越过 fence 推进游标。切换覆盖同一安装的同一 SQLite DB，不能声称跨不同数据库/跨设备互斥。
7. [D4候选包装](CORE_SCHEMA6_RELEASE_20261006.md) 固定同一提交的 Core/wrapper、Node24.14.1和17文件库存。现阶段只制作候选/只读预检，始终 `deployment_ready:false`；没有生产启动/停服/迁移/回滚动作或真实 recovery-floor 适配器。

## 真实一致副本（仅元数据）

- 主力手机仍为 B3 `versionName=1.0.30` / `versionCode=113`。通过 ADB run-as 读取主库与 WAL，设备前后及本机哈希一致，未停 App 或写设备。
- 原始副本 `user_version=62`：聊天6962、outbox11（全部user、重复来源序号0）、记忆卡128、kv45；已有永久companion标记10。整合 AppDatabase 连开两次，完整140表的列和数据指纹前后一致，integrity_check=ok。SQLite本机副本正常合并 WAL 属隔离副本处理，不能声称 raw 副本字节从未变化。
- 原始 Core schema4 一致副本单独演练4→5→6，7张旧业务表数据指纹一致；身份/设备/序号未变，grant1仍对应当前Android凭据，72外置/durable完整集合相同，新领域记录0，integrity/FK检查通过。
- 4→5 输入产生全新空 activity，没有证明现役 activity 历史恢复或生产 writer clean-stop。演练中的 offline proof/floor 只适用于该隔离、从未运行服务的副本，不能复用到生产。
- 原始手机/Core/两份外置授权的加密备份解密与输入 hash 校验通过；AES256GCM 密钥由当前用户 DPAPI 保护。密文 SHA256 `3b7f9102229dea7d57d13bbbe1c2fcd6430a20b420d9bdd669ed182bdba1429c`。DPAPI 实际恢复AES密钥后，在内存解密并逐项匹配归档清单与原始四输入 hash，通过后删除本轮专属明文工作副本/授权副本及临时明文密钥；保留密文、DPAPI密钥和加密迁移备份。普通文件删除不代表存储介质物理擦除。这份备份只覆盖本轮四个输入，不覆盖全部生产runtime/policy/env/密钥托管，发布前仍需完整保全。密钥、数据库、正文及授权内容不进入 Git。

## 最终验证回执

- 最终整合 Core/MCP 首轮递归569项：566过、2红、1既有平台跳。2红位于 MCP HTTP 夹具；本机动态端口范围1024–60000可能选中[Fetch禁用端口](https://fetch.spec.whatwg.org/#port-blocking)。测试启动器在接请求前重新绑定合规随机端口，原断言不变。修复后 MCP全套100/100；与 transcript/grant/replay/release 合并167/167、0跳。Core自身首次全套471项470过/1原有文件系统平台跳，后续Core执行源码未变。
- 固定预检专项本机Windows30/30；Linux CI显式接入，28项跨平台逻辑运行、2项仅Windows真实exe/PowerShell集成跳过。没有拿Windows通过冒充Linux实跑，CI结果以PR精确head作业为准。
- 最终整合相关schema/同步/捕获/桥/新设置模块 `dart analyze` 无问题。Main 25项与原文HEAD基线逐项相同；聊天UI19项也与基线相同，无新增error/诊断。旧共享模块诊断未屏蔽。
- Flutter扩大组合首轮346过/2红：一项是主窗误写不存在的finance测试路径；另一项是旧PR10 ChatClient没有实现新capabilities请求，真实Dio400被宽泛异常断言误当权限拒绝。只修夹具，显式经过GET/parser，并加强默认owner关闭、精确拒绝code、整行队列不变、重试JSON相同、legacy入口禁止断言；未修改生产逻辑或跳过测试。正确finance路径已核实。第二轮正确组合360过/1红：A20合成OS-kill夹具清理时的Windows文件锁32掩盖首错，历史锁归属未查明。夹具改为原子ready、所有退出路径回收实际writer/launcher并排空流、清理不覆盖首错；无ready/坏ready/无stdout握手负例和原9+4崩溃点仍实跑，Windows专项9/9、16个实际子进程。独立复核要求的POSIX无握手先kill漏洞也修复，POSIX实跑交Linux CI。最终主窗组合502/502、0红、0跳，退出码0，包含全部上述崩溃点、迁移、同步、捕获、规划、notes及candidate/白板相邻回归，首轮3分18秒。
- 首轮PR13 Linux CI报6处旧schema60测试预期及1处白板lazy列表离屏undo按钮。改预期后发现restart/recovery生产检查仍要求60，两处同步62而不放宽身份/来源/任务校验；candidate目录124/124，新增60/63拒绝；相关7路径分析退出码0、3条info，无error。白板诊断证实消息已载入、canUndo=true、目标11/15离屏未构建；仅在原undo前调用已有滚动助手，所有原动作/持久化/重启断言保留，相邻7/7。最终CI以最新提交为准。
- d1fa699b第二轮远端：白板1347过/0红/14既有跳，Node三组793过/0红/10平台跳（含发布预检2个Windows-only）；Linux全套2851过/1红/20既有跳。唯一白板tap警告的y417/406小于聊天顶部424，位于clip外，落到后面的画布；本机精确复现，旧rect407–427/396–416，单帧布局后变为887.8–907.8/893–913且hitTest=true，viewport424–913。仅夹具滚动末pump，原200轮预算内ensureVisible→pump→实际hitTestable等待，点击前唯一命中断言，tap同一目标；没有扩大超时、关闭miss警告、产品修改或断言删减。独立复核无阻断、相邻7/7。命中返修后主窗在8007582ffaf98d1b3703eb125915e5da91a0fa2a重新跑完整组合502/502、0红/0跳、3分30秒；此后仅文档变化，精确head最终CI见PR Checks回执，不继承d1的失败结果。
- 真实手机62副本专项1/1、140表列与完整数据指纹保全；Core隔离4→5→6演练如上一节，不等于生产升级。
- 构建前关键修复脚本3/3；`flutter build apk --debug --flavor hereIAmV3 --no-pub` 初建成功，Gradle219.6秒；两处candidate只读检查修复后在源码c0ba53a588fb43603514f7c4887a6dca23e96407再次构建成功，66.9秒，APK hash与初建相同。选择性采用B3 JNI staging，把CMake输出放当前checkout的build，解决PR12时共享Pub缓存写入失败。未升级依赖或改锁文件。

## 具体候选与保持现役的回执

| 候选 | 精确源码/产物 | 验证与范围 |
|---|---|---|
| Android hereIAmV3 debug | 构建源码 `c0ba53a588fb43603514f7c4887a6dca23e96407`；APK `build/app/outputs/flutter-apk/app-hereiamv3-debug.apk`，387060021字节；SHA256 `96b5cb4d886fa9cd70597b1d59a923011bb8285fbdc70d521d65609c988396a5` | 包名com.memexlab.hereiam.v3，1.0.30/113；签名验证通过，证书SHA256 `0011cc0372b17ccec1544eea667d2466adebade94ac91adb39239f3be8712e4e` 与现装B3相同；本机原签名文件只在ignored目录，未进Git。构建后仅测试/文档变化，lib/android/assets/pubspec无diff；未安装。 |
| 固定schema6离线Core包 | 源码 `263f3da67d9968d5ab8bbc50cda8f479711d0c8c`；17文件清单SHA256 `35be915b1e20ae6ba614744b1f0a6f3eac025e251667f030d27593637f67674d`；Node24.14.1固定SHA | 从已提交Core/wrapper同一树打包，无worker-onlyGit对象依赖。实际PowerShell入口在真实隔离6副本预检通过；72完整绑定、grant1、输入hash不变；身份/grant/绑定锚从独立5基线保留，schema6新领域权限单独核实为空集合。`deployment_ready:false`、启动服务0；没有生产launcher或真实recovery-floor适配器。 |

包与备份保留本机，不发布APK/真实配置。最后只读复核 Core health仍schema4；手机现装APK仍 `8b55be76011e8ea8ebba09a23316f7610c56bc25e2c6171846fd13ca4ab49b84`，与本轮候选不同。没有手机/设备写入、配置切换或原库升级。

## 发布边界与下一步

- 用户确认后，PR13 于2026-10-06 03:25:00Z普通合入 `90f23ce1d38628901e25b421d8f0f21c084f093b`；精确head `3ec7b1d65a047c895edacd72348af02a7b1ceded` 的五类检查全部成功。Linux全套2852过/0红/20既有跳、白板1347过/0红/14既有跳、Node793过/0红/10平台跳，Windows构建与集成通过。合并父提交为原主线64aea693与已测head，合并树与已测树同为 `9bd34abf434b7465570b3646ef96b855d3224d21`；正式源码副本已快进且工作区干净。
- 生产 Core/MCP切换和主力手机安装需绑定实际产物、保全整个运行配置/身份、真实 supervisor clean-stop 与独立恢复 floor；当前离线包装没有这些启动能力。
- captures 必须验真实新增/改版/删除和用户改卡保护，再以显式来源映射切消费者/退休47862；没有双写或自动切换。
- 主力手机未安装本轮候选；生产切换仍待独立授权及验收。本轮没有手机安装、服务重启、原库升级或生产领域/回复上传开关操作。
