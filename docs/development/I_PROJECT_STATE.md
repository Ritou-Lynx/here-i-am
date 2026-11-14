# 林埃的项目状态

本文件只写现状，供林埃（i）与各会话读取。2026-10-23 之前的逐日记录已移入 [历史归档](archive/I_PROJECT_STATE_HISTORY_20261023.md)，过程细节见 [DEVLOG](../../DEVLOG.md)，总指挥规则和计划见 [总指挥交接](handoffs/COMMANDER_HANDOFF_20261022.md)。

## 当前状态（2026-11-10）

### 生产
- schema6 Core 已上线（D1b，10-22 完成）。11-08 起现役登录任务为 `HereIAm-iCoreSchema6-n2-notes-20261108`：Core 包 `release-78e11df7`（manifest `ded493e5`，E3 记账随 #106 换入），MCP server 候选 `4b1014e0`（E3 记账 + N2 笔记工具，#109）。此前的 e3-expense、m1-digest、hr1-heart、n2-food 及更早任务停用保留，不删。
- i MCP 现有工具：上下文与记忆（`i_context`、`i_chat_turn`、`i_recall`、`i_remember`）、饮食（`food_log`、`food_day`）、记账（`expense_log`、`expense_day`）、心率（`heart_rate`）、学习（`study_*`）、日摘要与待办（`life_digest`、`life_todo`）、飞书笔记只读（`notes_recent`、`notes_search`、`notes_read`）。各前端开放范围见对应 DEVLOG 条目。
- 前端：claude_web、chatgpt_web、gemini_web、antigravity、sesame 都已与 Core 配对。Claude、ChatGPT、Antigravity、Sesame 真人验收通过；Gemini 能添加，但对话里工具调用不生效，用户 10-24 决定不再跟进。
- 本机定时任务：`FeishuTutor-Daily`（06:30 学习账本）、`FeishuNotes-Mirror`（每 30 分钟加 19:20 笔记副本）、日摘要（04:30 定稿、07:30 晨间、19:30 白天版）。心率监听在本机 47866，经 tailscale serve 8447 访问。
- 维护工具副本与换候选流程以最近一次部署合同为准（`docs/development/handoffs/RELAY_20261108_n2-notes-mcp.md`、`RELAY_20261108_e3-expense-deploy.md`）；以后换 MCP 候选以 n2-notes 任务为起点。维护脚本一律用 Windows PowerShell 5.1（pwsh 7 会误报 `login_core_port_invalid`）。
- relay watcher：已按 A4 迁移为 `conhost --headless` 启动，codex 路径每轮自动查找。本机脚本经 relay 脚本轮执行（read 直接跑，write 等用户确认）。

### GPT-Live 通话页（2026-11-08，修复入库并已安装）
- 服务端结束或接通后连接失败会自动退出；手动挂断先等待收尾，连接前错误保留提示。重复操作只退出一次，被其他页面覆盖时只移除通话页。
- 与远端 88b60b71（含 #109/#110）整合后，6 项 widget 与 16 项协议测试共 22 项再次通过，相关静态分析无问题；通话页源码与已安装候选一致。原故障已在修复前复现。
- 已安装产物基于 426d95cb 加本修复（不含随后合入的 #110 设置清理），hereIAmV3 debug 构建、覆盖安装与冷启动通过，原聊天数据库文件保留；APK SHA-256：`2fa96e4e3c9fa2fc5dfe774f13132a59bf0e3d2ca8b46acadc46ef64f3748cc0`。真实通话返回页面待用户确认。
- 修复源码与回归测试纳入 v3-lab，保留其他来源提交；正式本机工作区待同步。

### 运维注意
- STATE 中留有旧 shortcut-mail 日志库的 -wal/-shm，stop 最后一步会报 `database_sidecars_present`；只要 `stop.receipts` 已通过，会话就已干净关闭。
- 任何时候都不要绕过闸门去改 STATE 内的文件。
- 注销前先手动停服（L 注销强杀问题暂停，未修）。电脑重启后现役会话以 0xC000013A 退出、服务停摆，需手动 `Start-ScheduledTask` 拉起现役任务。
- 换候选后，旧会话里的 i 连接器会报 Bad Gateway，需开新会话确认。

### 最近完成
- 11-10：电脑端 Dev Room bridge 自启移除并停用（#115）。
- 11-10：全项目排查（#118）：删除不可达的 Dart 文件和上游遗留的 GitHub 配置，设计稿素材移出 App 打包，CI 补上 i_core、Python 和 Windows 专用测试。
- 11-09：GPT-Live 通话页美化（#111）、通话入口合并与静音自动挂断（#113）、晨间摘要不再把旧待办当成今日安排（#116，#117 部署）。
- 11-08：设置里的旧 memex 功能清理 A（#110：模型用量、异步任务页、自定义 Agent、Skills）与清理 B（#114：Dev Room 与项目记忆）；记账 E3 上线（#106）；飞书笔记工具 N2 上线（#109）；日摘要 M1（#101）；GPT-Live 记录结束原因（#107）、删除 5 个旧人设字段（#108）。
- 11-07：催睡来电（#99）真机测试跑通；本机连续性网关 i bootstrap 退役（M6，#102）；饮食刷新报错修复（#90）。
- 11-05：臂带实时心率进 i MCP（HR1，#91），11-07 验收。
- 更早（10-22 至 11-03）：A1–A4 维护工具与 watcher、C1 来源标签、D1–D4 前端身份、D2 Sesame、F1 飞书学习导师、S1 床头哨兵、N1/N2 食物记录、三科每日学习流程，均已合并，过程见 DEVLOG。

### 进行中
- 手机 App：需从 v3-lab 重装一次，之后验收账本投影、GPT-Live 通话页（实拨）、Sesame / Antigravity 来源标签。
- 催睡来电：待整夜试跑后调阈值。
- 心率：夜间记录导出后对照 COROS 定判睡阈值（H1）。
- 摄像头按需查看 CAM1（#105）：代码已就绪，硬件到货实测前不合并。
- 生活摘要 M2–M5 待开。

### 之后
- R1 shortcut-mail 关闭前 checkpoint，留到下次换包一起做；清理生产 STATE 里的旧 sidecar 需用户单独同意。
- 注销 / 重启强杀会话（问题 L）未修，重启后仍需手动拉起现役任务。
- 数据中枢 P1：旧 #19 已关闭，分支 `codex/hub-golive-src-20261007` 保留作参考。

### 长期边界
- 唯一仓库 `Ritou-Lynx/here-i-am`，集成分支 `v3-lab`；各设备按 [多设备协作说明](MULTI_DEVICE_GITHUB_WORKFLOW.md) clone。仓库公开，不写 SID、本机绝对路径、域名、凭据或私人内容。
- 合入 v3-lab、操作生产、动真实数据都要用户明确同意。生产长任务仍拒绝执行，活动诊断默认关闭。
- 真实数据库、账户、签名、原始设备回执不进入 GitHub。

## 历史归档

- [2026-10-23 之前的项目状态全文](archive/I_PROJECT_STATE_HISTORY_20261023.md)：schema6 切换全过程（10-06 至 10-22）、个人数据中枢 W0–W7、白板暂停、学习系统、GitHub 单一谱系恢复等。
- [Memory V3 旧交接提示词](archive/SESSION_HANDOFF_MEMORY_V3_20260703.md)：原仓库根目录 `SESSION_HANDOFF.md`，10-01 起已标为历史。
