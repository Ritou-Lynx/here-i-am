# schema6 部署准备与现场切换边界（2026-10-06）

基线为已合入 PR13 的 `v3-lab@90f23ce1d38628901e25b421d8f0f21c084f093b`。本轮仅实现源码、固定候选和合成验证；本文件不是线上启用回执。旧 Core、MCP、47862 手机桥和主力手机没有因本轮工程改变。

## 三个接线包

| 工作包 | 接口/证据 | 范围 |
|---|---|---|
| Windows 生命周期 | `release_schema6/lifecycle/start_schema6.ps1`、认证停止入口、Windows Job/guardian/独占锁 | 固定包与受保护显式配置；关闭 listener/SQLite 后仍须确认实际 child 退出和 Job 空，才生成可重开的 clean_closed 回执 |
| 迁移/恢复 | `recovery_adapter.mjs`；独立 custody 目录的认证最新 head 与不可覆盖历史链 | 原 canonical live 路径；4 的新活动 genesis 与已有5/6可信 floor分开；不激活备份，不清活动 lease，不现场批准目标自己的历史 |
| 完整运行备份 | `backup_bundle.mjs`、受保护 DPAPI 密钥与固定 wrapper | 显式完整旧 release/配置/任务/凭据/域策略/DB/grant/replay/custody inventory；AES256GCM 加密，解密逐项哈希核验，无明文密钥/归档临时文件，无自动恢复覆盖 |

每条证据必须区分 portable 算法测试、真实 Windows 固定入口、真实库副本和线上运行。本轮的 runtime 测试数据是新建合成数据根；现役原库不参与。测试精确提交、数量和包清单见主窗验收，不能沿用 PR13 的结果替代本轮新增守护逻辑。

## 固定候选与配置

使用本轮集成提交打包；Core、wrapper、恢复和备份工具都从同一个 Git 树读取，Node 固定24.14.1，外部保管 manifest SHA。不要把工作副本或仓库目录直接设成运行目录。发行目录、state、control、配置、密钥和恢复 custody 分别保护并保持路径隔离；使用独立 control 目录执行每一次生命周期，不重复使用旧停止令牌。

保持单一 `legacy_b3` 上传器，reply jobs/activity关闭；pairing/外部grant/replay绑定来自受保护配置，不继承环境扩大权限。新包不签发领域凭据或自动启用手机领域同步。当前监督配置固定relay关闭，尚不证明旧Shortcut邮件运行配置兼容；其现场依赖需保全，接线/验收完成前不能据此覆盖现役邮件能力。受限 transcript 与 PR10 不能同时写。是否改为 PR10 必须与手机版本/队列/来源ID一起单独验收。

备份密钥和恢复凭据密钥独立，由当前用户 DPAPI 保管，purpose及规范密钥目录分别绑定。密钥不放在命令行、环境、Git或报告；读取只在固定受验证子进程的内存/管道。主库迁移生成的 backup_read_only 副本不能作为可启动live库，不能翻role绕过。

## 完整清单的审阅

现场执行前，核对实际任务动作、wrapper、Node及所有加载源码的路径/哈希，实际state路径、Core端口所属进程与开始时间、旧release manifest，并保全任务原XML和启动/恢复设置。现役MCP与旧remember桥另有任务，不能把停Core等同停全部相关消费者。

显式备份清单至少包含九类：主库（包含耐久72 replay账本与已有设备凭据）、完整旧运行包及manifest、普通配置及外部Node依赖、任务配置、其他凭据保管、owner域策略、transcript grant、外置72 replay、独立floor/custody及其保管说明。副库、relay journal、证书、pairing/relay配置、当前floor/head链等按实际加载依赖加入；有意关闭的组件必须保留与当前配置哈希绑定的关闭证据。不能把一个文件重复贴九种标签冒充完备。

`inventory_only`和`production_completeness_not_attested:true`是刻意保留的限制：工具能验证提供的清单完整稳定，不能自动发现所有生产依赖。以前的四输入备份仍保留，但不能替代这份完整运行清单。现场备份前后需由真正持锁的监督流程核实所有writer状态；仅清单加密通过不证明已停writer。

## 首次旧v4接管仍须独立处理

本机只读复核旧 pinned wrapper SHA仍为`55ccaa5369687b3c3d9c888cc296b4d4ea16d8fdf3b0eb6dd8dbd97a3cf1b90f`，其共享runtime锁仍存在。旧 server SHA为`9ac97b01711bc580861f5d3aa2308846dad7606f5d28b4ba02939db83c269d46`，启动入口没有SIGINT/SIGTERM或仓库新式graceful-shutdown接线。源码有内部close方法不等于运行进程向外提供清停控制。

因此，拿到新锁、旧PID消失、端口关闭或SQLite看似正常，均不能伪装成新supervisor已经见证旧store.clean_close。新空实例的初始化和既有schema6 clean-close重开也不能授权迁入现役旧库。旧库缺真实可接受交接证据时，固定入口必须拒绝首次接管。

若现场旧启动器无法提供可验证的优雅停机，需要另行审查受控停止旧v4及SQLite一致恢复/保全的接管方案，明确区分非优雅停止与清停。这个例外的源码接线、WAL保全/恢复演练及用户具体授权必须先完成，不能把普通JSON声明、历史审计或合成capability当生产交接。

## 现场顺序（未执行）

1. 保全当前运行包/配置/任务及全部密钥保管，核实具体旧writer和首入交接方案；现场核对不能复用10/05的PID。
2. 获得对应Core停启/升级授权后，冻结启动任务与相关writer，取得真实交接证据，保全一致SQLite输入和全部授权文件；加密并恢复验证完整清单。
3. 在同canonical路径、可信持锁adapter下执行4→5→6；schema4新genesis独立封存，已有5/6必须用此前独立current-head。逐阶段复核锁/进程，保全旧业务/身份/序号/外置grant/完整72映射及新域权限边界。
4. 以固定候选启动，验证schema6/身份/设备/受限grant/完整72 replay行为、单上传器及默认关闭jobs/activity；原有路由/桥维持到对应Gate通过。
5. MCP切换、主力手机安装及上传能力配置各自另取具体授权。captures真实新增/改版/删除和用户改卡保护验收前继续保留47862；切换时只留一个消费者。

## 失败与恢复

保留失败候选、密文备份和元数据回执，停止受影响writer并保全新接受数据，优先前向修复。已有domain写入、权限/游标或序号推进时拒绝降级；仅原迁移函数确认域完全为空时，才可在可信持锁adapter下讨论6→5演练。不提供整库覆盖或把备份转成live的激活路径。

旧DB、旧停机marker和旧floor一起恢复也必须被库外最新head拒绝；不得恢复/回退这个独立head以使旧副本通过。不确定floor来源、清停状态或完整配置时保留现役服务，不宣布部署完成。
## 旧v4首次接管的下一步源码方案（二审建议，尚未实现）

采用独立“非优雅停止后恢复”流程，不能生成或借用旧实例的clean_closed。新增legacy-adoption固定能力必须绑定旧包/Node/路径/原进程句柄与开始时间，并记录unclean_stop_observed；冻结任务和真实退出后才排除孤儿/其他writer并接管同一锁。这个类型只准schema4恢复，不能传入现有cleanCloseReceipt。

在任何SQLite打开前先流式加密保全原始DB、存在的WAL/SHM/rollback journal和实际副库，含缺失状态、大小、摘要与稳定文件身份。现有普通备份仍拒绝sidecar；新增原始恢复证据格式必须独立，不能放宽一致备份规则。持续持锁下由受审SQLite代码在canonical原址恢复和checkpoint/close，禁止先构造自动迁移CoreStore或手工删日志。结果为sqlite_recovered_verified，不能追认旧实例优雅退出。

恢复后验证身份/凭据/业务行/序号/grant/exact72，生成普通完整运行密文备份，再用原始文件集、恢复后摘要与清单绑定的一次性adoption能力进入4→5→6。库外不可回退adoption状态必须先耐久化；中断不能重新按首次自签。只有新实例真正清停后，才进入普通clean_closed协议。

必要合成Gate包括launcher死亡留下Node、PID重用/任务重启/未知句柄/锁丢失，WAL已提交与未提交/截断尾/hot journal/错配或缺失日志，每阶段强杀恢复，原始密文和恢复后一致备份分别认证，以及恢复期间无listener/relay/消费者。缺日志、身份/序号/授权冲突、密钥不可用、阶段不确定或已有5/6缺可信floor均不自动修复。SQLite完整性通过不证明所有此前ACK已保全，仍需客户端队列对账；在途邮件不自动重发。

现场具体决定在源码和合成Gate完成后提出：停机窗口、冻结的精确任务/消费者、允许终止的精确进程、原址恢复写入、备份/密钥位置、迁移启动范围及失败时保持停机的策略。MCP和手机切换仍分别确认。本轮仅交付方案与新受监督实例工程，未操作这些现场事项。

## 本轮收尾与审核暂停

[真实九类保全与只读恢复](SCHEMA6_REAL_BACKUP_RESTORE_20261006.md)已完成，限各库一致副本与新目录检查还原，不能授权canonical-live覆盖或首次legacy接管。[运行操作](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)分别列Core/MCP/Cloudflare停启与确认、客户端停机表现、关机/睡眠/断电/蓝屏、自启与人工处理、迁移前后退回边界；[给Lynx的一页操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)列每步预计影响、成功/失败处理。

旧v4首接、断电原始日志保全/恢复、生产新空control自启封装和Windows关机事件仍缺；这些必须在任何现役停机之前完成。用户接受调试邮件先关，保留SMTP配置/凭据/journal，停止发送/查调试回执，不自动重发在途邮件。本轮整包完成后推codex分支并创建草稿PR，暂停等审核，不合v3-lab或开始下一工程。
