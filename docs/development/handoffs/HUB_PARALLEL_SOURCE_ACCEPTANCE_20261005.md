# W3/W4/W5 与 W7 前置组合源码验收（2026-10-05）

## 基线与集成

源码收尾于2026-10-06（跨午夜）；任务文件沿用20261005编号。精确基线 v3-lab@8dde12b312ad83f7475df8bd99a359f1b2d782d6；组合分支 codex/hub-parallel-20261005。只整合正式净化谱系，不合入D私人历史。主线和现役服务未切换。

| 工作包 | 候选来源 | 组合结果与边界 |
|---|---|---|
| W3 | cba934392107b9c12d0cf0378ca88e02c1fdc034 | 领域MCP、本机规划入口、Core notes与旧读取白名单；172/172由主窗同套独立复验。生产issuer、token、固定Core4兼容及notes迁移仍未启用 |
| W4 | 6ecf3a9b3820bf2f79215e8a7fa32a3df0e91a47（含f324e240前置） | 真实W7捕获、本机识别/键盘、手机显式生活记录到Organizer、版本/删除关系、Android alias/tile/冷暖桥；主窗新增真实入口及热启动锁门控 |
| W5 | 64c2b589254b2349785e77935dcd67a770362a36 | 今天/本周、只改完成/放弃、离线覆盖/拒绝提示、派生提醒；主窗接生活空间入口及页面外宿主。旧日程保留 |
| W7新增前置 | 13cf6dec + 主窗后续接线 | 逐记录/修正/操作行、事务迁移、去重退役；不等同逐域影子/冻结/迁移完成 |

## 共享接线与复核返修

- CaptureActivity初始/quick-capture在main走独立分支，不加载陪伴首页、check-in/前台常驻/旧输入收集；常规quick_note和warm native桥指向新页。App锁检查完成且已解锁之前，统一route gate不构造捕获子树；后台立即撤销，页面dispose停止语音。Android系统解锁仍由语音适配器另行校验。
- app-scoped runtime保持W7 API及动态owner store映射；默认空Core配置，以持久installation的phone-local明确本机保存。Core/shadow缺真实issuer拒绝，不能用UUID或local-ui作为Core授权证明。后续phone→Core须显式迁移同源记录/consumer ledger，不自动换namespace。
- send只等事务落盘，模型异步处理；模型失败保留待处理。kv通知只刷新视图/提醒，不循环消费；owner连接和sync通知才触发消费，旧binding的提取结果被拒绝。页面外启动/前台恢复/同步后可派生提醒。
- 独立capture engine禁用提醒接管；空owner也不建立规划提醒owner，避免同installation第二引擎清主引擎的提醒。已接管后明确失效/换binding仍清理旧提醒。双SQLite连接同文件测试保留提醒queue/metadata。
- DB关闭前suspend runtime，异步create以epoch作废并释放；账户重查后Owner重建新的DB绑定，Provider清旧Ok。AppDatabase.closeCurrent与已有open队列串行；不改变schema。
- 主窗复核diff/关键断言后修复暖启动锁录音、空引擎提醒接管、账户旧库引用，以及后台丢草稿；普通/独立capture的Router持续保留Gate文字会话，锁时停止录音，恢复保留ID与文本且需手动重录。进程终止后的未发送草稿恢复不在此仅内存会话范围。

## 验证

主窗最终Flutter组合235/235（exit0），包括PDH全部专项、捕获/规划widgets、Organizer/Finance、用户本轮改卡、companion shell、路由初始化与DB生命周期；没有新增跳过或放宽断言。任务PR的精确head CI是完整Linux回归及Windows构建的结果入口，源码候选不等于完整生产验收。

- Node W3同套172/172、无跳过/失败；使用合成Core及随机loopback，不接现役原库。相同命令已接入现有Node CI，不增加工作流权限。
- 强化Windows真实VM终止的行存储14 + 原同步61组合75/75；另去重/Organizer/Finance37/37。首轮组合的Windows临时目录占用错误已通过确保重开句柄在断言前finally释放修正；清理仍有限重试、失败报红。最终235项重验包含全部13处实际写入VM终止。
- 最终新增/改动模块及专项严格分析无问题（exit0）；main/settings/AppDatabase共享旧文件按message/code忽略行偏移对照精确基线，43条完全一致（原始analyze仍exit2），新增诊断为0。不关闭lint或屏蔽测试。
- critical checks3/3。在线依赖解析及 :app:compileHereIAmV3DebugKotlin 任务成功（exit0，部分up-to-date）；完整 hereIAmV3 debug APK 在 jni:configureCMakeDebug[arm64-v8a] 的编译环境阶段失败，CMake临时文件无法写入，未生成可交付APK。未修共享SDK/插件缓存或跳过任务；完整包和三星真实侧键/速度/权限/提醒仍各自未验，未安装手机。

- 真实双连接竞争发现Drift2.31/sqlite3 2.9.4缓存DML遇busy后阻碍后续COMMIT；最小修复在DomainStore读/写（含首次迁移）及Consumer写事务首部，以无参且不改行的UPDATE先取得写锁。busy仍向调用者抛出，不关闭缓存或升级依赖。phone/Core各两个版本实测竞争，失败连接首次原地重试返回0，两卡ID保留、一ledger，Core每版本仅一ack；单进程两独立SQLite连接的有限证据不等同Android双引擎设备验收。

合成生产widget预览：

- [记一下](../assets/hub_preview_20261005/quick_capture_widget.png)
- [今日规划](../assets/hub_preview_20261005/planning_today_widget.png)

生成测试1/1，430×1050；实际AppTheme、仓库CJK字体与假数据，主窗已目视确认中文/按钮/背景。截图不是当前手机安装状态或真人Gate。

## 部署前只读调查

用户指定线程01a10c93-10d4-73b2-928d-f740fde50046；codex/predeploy-audit-20261005报告经二审收紧措辞，最终19588f4f5e5c10ffb96577d0e27f35d1b0628737，仅报告两次提交，不push、不合入本候选或v3-lab。没有原文或凭据。

现役Core4仍加载仓库缺少的transcript/replay；最近实际客户端调用证据不足。10条手机companion最支持B3代码路径归因，但不是逐请求证明；当前持续上传及实际手机安装身份未知。B3本机候选DB62与主线60有兼容缺口；ADB0连接，现装包未核。报告末节列transcript过渡、replay保护、旧47862桥退役及具体发布范围D1–D4，不重新要求已确认ADR原则。

## 未接受的环节

- W3 Core模式切换前：保全固定Core4功能、可信issuer/最小令牌/owner policy、旧notes冻结导入对账、单一新consumer真实增改删闭环。源码开关不等于现役已切换。
- W4新capture的Organizer已生成Memory V3生活卡；收支/经期/睡眠的Core领域intent及账本直入仍是W7逐域包，不能称“已入账”。
- W5无生产授权适配器时只读；现实Core权限、提醒OS权限与实际送达未验。W8规划助手存储/监视器尚未开工，不会由手机自行生成今日单。
- W7逐域字段回填/真实影子七天/逆向回滚/冻结切换未执行，v1→v2物理存储没有自动降级支持。
- 不继承旧手机候选的安装/真人Gate；未安装主力手机、升级原库、停启服务、改线上配置或启用林埃回复生产上传。
