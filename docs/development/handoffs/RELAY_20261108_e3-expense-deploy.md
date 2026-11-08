<!-- relay:contract v1 -->
## 目标
上线记账 E1（#98 已合并）：Core 换成带 `expense_entries` 领域的新包，MCP 换成带 expense_log / expense_day 的候选，让 Claude、ChatGPT、Gemini、Antigravity 能把花销记进账本，手机 App 同步后显示在共同账本里。

## 完成标准
- [ ] 第 1 轮 `tools/relay_scripts/expense/e3-inspect.ps1`（mode=read）全部 ok：现役 m1-digest 任务在跑、Core 包是 release-42ecf688（manifest 9897fb41）、server bde3ff9f、维护副本 tools-4603fb79 与 v3-lab 一致、无待处理标记；新包与现役只差 personal_data_domains.mjs、runtime_child.mjs；旧任务证据预览通过。
- [ ] 第 2 轮 `tools/relay_scripts/expense/e3-deploy.ps1`（mode=write）全部 ok：新 Core 包 release-78e11df7、候选 server 63acb514（其余五个文件不变，受保护 ACL）、expense.json、换包配置与固定 prepare、零写入检查 → 关会话 → 停用旧任务 → 批准计划 → 离线换包 → 登记 P → C1 到 P′ → 切换。
- [ ] 新任务 `HereIAm-iCoreSchema6-e3-expense-20261108` Running，旧 m1-digest 任务 Disabled 保留；Core 启动回执 expense-receipt 为 provisioned；心率监听恢复。
- [ ] 云端 i MCP tools/list 含 expense_log、expense_day，life_digest、life_todo 等原有工具仍在。

## 允许修改的路径
- tools/relay_scripts/expense/
- docs/development/handoffs/RELAY_20261108_e3-expense-deploy.md、DEVLOG.md

## 不做 / 边界
- 不发新凭据：记账复用食物的两个主体，Core 原地扩权限，不轮换令牌。
- 只新建 expense.json（已存在且内容相同时保留），不改 MCP 状态目录里的其他文件，不碰飞书、日摘要、心率、配对凭据。
- 离线换包之前任何失败都重新启用并启动旧任务；离线换包之后失败不起旧任务，停下报告（需反向换包）。
- 输出不含令牌、本机路径、SID 或账目内容。

## 验证命令
- 脚本轮输出逐行 ok；云端 i MCP tools/list 与一次 expense_day 只读调用。

## 需要真人的部分
- 在第 2 轮评论上点 👍（会停服约 2–3 分钟，期间林埃离线）。
- 从 v3-lab 重新编译安装 App，饮食页同步一次后，账本里出现 AI 端记的支出。
