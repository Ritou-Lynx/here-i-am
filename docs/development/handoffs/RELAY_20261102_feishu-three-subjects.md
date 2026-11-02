<!-- relay:contract v1 -->
## 目标
1. 用脚本轮在本机启用学习导师三科（#83）：加科目、换导师规则和科目文件、装练习链接脚本，并试跑一次每日任务。（第 2、3 轮已完成）
2. 新增 Gemini 同步：每日任务把学习单、笔记合集、学习进度导出到 Google Drive 电脑版同步文件夹，Apps Script 覆盖写进固定 Google 文档供 Gemini Notebook 自动同步；用脚本轮在本机启用。
## 完成标准
- [ ] 脚本轮输出 `check` 为 ok，`install` 为 ok 且 `link_probe` 为 true。
- [ ] 试跑 `trial_run` 的 verdict 为 `daily_done`，学习单分为三科，`practice_links` 大于 0（或有提示词引用块）。
- [ ] 最后一行为 `{"step":"done","ok":true}`。
- [ ] `node --test tools/feishu_tutor/sync/*.test.mjs` 通过；Gemini 启用脚本轮 `export` 为 ok，三个 .md 文件都在。
## 允许修改的路径
- tools/relay_scripts/feishu_tutor/
- tools/feishu_tutor/run-daily.ps1、tools/feishu_tutor/sync/export_gemini*.mjs、tools/feishu_tutor/gemini/、tools/feishu_tutor/README.md
- docs/development/handoffs/RELAY_20261102_feishu-three-subjects.md
## 不做 / 边界
- 无代码轮；Codex 不参与，代码由 Claude 写。
- 导出不联网、不碰飞书凭据，失败不影响 daily_done；Apps Script 只读写“here-i-am 学习同步”文件夹，不删除文件。
- 只运行已提交并固定哈希的脚本；`mode=write`，须用户本人点 👍。
- 临时配置 check 不通过时不改任何本机文件；替换前备份到学习目录 `backup\`。不删除任何东西，不改 risk-control，不注册或修改计划任务（只触发一次现有的 FeishuTutor-Daily）。
- 回帖只含步骤结论、计数和标题结构，不贴学习内容。
## 验证命令
- 脚本轮回帖。
## 需要真人的部分
- 先在飞书“学习账本”“练习记录”两张表的“科目”字段加上“英语”“数据分析”选项，再在 `to-runner` 评论上点 👍。（已完成）
- Gemini 同步：装 Google Drive 电脑版并登录；在 script.google.com 粘贴 Apps Script 并授权一次；在 Gemini Notebook 里添加三篇文档一次；Gemini 启用脚本轮点 👍。
