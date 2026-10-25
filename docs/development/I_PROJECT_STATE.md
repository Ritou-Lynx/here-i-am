# 林埃的项目状态

本文件只写现状，供林埃（i）与各会话读取。2026-10-23 之前的逐日记录已移入 [历史归档](archive/I_PROJECT_STATE_HISTORY_20261023.md)，过程细节见 [DEVLOG](../../DEVLOG.md)，总指挥规则和计划见 [总指挥交接](handoffs/COMMANDER_HANDOFF_20261022.md)。

## 当前状态（2026-10-24）

### 生产
- schema6 Core 已上线（D1b，10-22 完成，manifest `4e003c0b`）。10-24 起现役登录任务为 `HereIAm-iCoreSchema6-d4-mcp-20261023-48bd91ed`（MCP 为 v3-lab `48bd91e` 的六文件候选，含 D1、D3、#49、D4）；此前的 d3fix、d1d3、P′、旧任务和 P 停用保留，不删。
- 前端：claude_web、chatgpt_web、gemini_web、antigravity 都已与 Core 配对，读取策略 `auto_share_origins` 为这四个。Claude、ChatGPT 10-23 真人验收通过；Antigravity 10-24 验收通过；Gemini 能添加，但对话里工具调用不生效（疑 Gemini 侧，未排查）。
- 维护工具副本：`<OUT>\tools-dddff0f1`（v3-lab `dddff0f`，含 #45 宿主检查、#47 ready 容差）。旧副本 `tools-3baf72d`、`tools-302a62c0` 保留；以后登记从新副本重新生成配置。维护脚本一律用 Windows PowerShell 5.1（pwsh 7 会误报 `login_core_port_invalid`）。
- relay watcher：已按 A4 迁移为 `conhost --headless` 启动，codex 路径每轮自动查找，Codex 更新后不需要重新注册。

### 运维注意
- STATE 中留有旧 shortcut-mail 日志库的 -wal/-shm，stop 最后一步会报 `database_sidecars_present`；只要 `stop.receipts` 已通过，会话就已干净关闭。
- 任何时候都不要绕过闸门去改 STATE 内的文件。
- 注销前先手动停服（L 注销强杀问题暂停，未修）。10-24 电脑重启后现役会话以 0xC000013A 退出、服务停摆，需手动 `Start-ScheduledTask` 拉起现役任务。

### 最近完成
- A1+A2（#33）、A4（#34/#35）、A3（#36）已合并；10-23 生产换用新工具副本（#37）。
- C1（#38）：App 聊天时间线按来源显示 Claude / ChatGPT / Gemini / Antigravity。10-24 用 v3-lab 重建 debug 包覆盖安装（保留数据），真人验收通过。
- relay 飞书 / Bark 通知（#41）已合并，本机测试送达成功；agent_relay 测试进 CI（#42）已合并。
- D1（#40）+ D3（#44）：10-23 部署到生产。
- #49（Gemini 回调允许下划线）与 D4（#50，Antigravity）：先后部署到生产（D4 于 10-24），Antigravity 真人验收通过。Gemini 工具调用不生效，用户决定不再跟进。

### 进行中
- D2a Sesame 回调探测（PR #55）：Sesame 走标准 DCR，但回调不在白名单，`/register` 400。诊断对未知回调记脱敏形状 `callback_shapes`，两轮审核通过，待合并与部署；拿到形状后写 D2b（白名单、`sesame` 身份、来源标签、配对）。起因是催睡来电方案：三星例程拉起 Sesame，经 i MCP 取上下文。
- F1 飞书学习导师：PR #51 审核通过，待合并。合并后用户按 `tools/feishu_tutor/README.md` 在本机配置（团队租户、工具目录和学习目录分开、建三张表、试跑、注册 Interactive 计划任务）；旧账本迁移另做；10-31 复测 refresh token 续期。

- S1 床头哨兵：PR #58 审核通过，待合并。合并后把 APK 装到闲置小米上，用“调角度”页摆好支架；三星订阅 ntfy 并建例程（通知含“林埃来电” → Call Charlie）；先白天模拟，再整夜试跑。手机重启后要点一下通知才会恢复监测。
- N1 食物记录：PR #59 三轮审核通过、CI 全绿，源码默认关闭，待用户合并；之后写 N2（食物领域上线，数据中枢首个领域，含 Core 换包，生产操作逐步同意）。

### 之后
- D2b 接入 Sesame（等 D2a 部署后拿到回调形状）。
- R1 shortcut-mail 关闭前 checkpoint，留到下次换包一起做。
- 数据中枢 P1：旧 #19 已关闭，分支 `codex/hub-golive-src-20261007` 保留作参考，D1/D2 之后拆分重做。

### 长期边界
- 唯一仓库 `Ritou-Lynx/here-i-am`，集成分支 `v3-lab`；各设备按 [多设备协作说明](MULTI_DEVICE_GITHUB_WORKFLOW.md) clone。仓库公开，不写 SID、本机绝对路径、域名、凭据或私人内容。
- 合入 v3-lab、操作生产、动真实数据都要用户明确同意。生产长任务仍拒绝执行，活动诊断默认关闭。
- 真实数据库、账户、签名、原始设备回执不进入 GitHub。

## 历史归档

- [2026-10-23 之前的项目状态全文](archive/I_PROJECT_STATE_HISTORY_20261023.md)：schema6 切换全过程（10-06 至 10-22）、个人数据中枢 W0–W7、白板暂停、学习系统、GitHub 单一谱系恢复等。
- [Memory V3 旧交接提示词](archive/SESSION_HANDOFF_MEMORY_V3_20260703.md)：原仓库根目录 `SESSION_HANDOFF.md`，10-01 起已标为历史。
