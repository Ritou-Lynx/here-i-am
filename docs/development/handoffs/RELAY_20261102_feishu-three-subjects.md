<!-- relay:contract v1 -->
## 目标
用脚本轮在本机启用学习导师三科（#83）：加科目、换导师规则和科目文件、装练习链接脚本，并试跑一次每日任务。
## 完成标准
- [ ] 脚本轮输出 `check` 为 ok，`install` 为 ok 且 `link_probe` 为 true。
- [ ] 试跑 `trial_run` 的 verdict 为 `daily_done`，学习单分为三科，`practice_links` 大于 0（或有提示词引用块）。
- [ ] 最后一行为 `{"step":"done","ok":true}`。
## 允许修改的路径
- tools/relay_scripts/feishu_tutor/
- docs/development/handoffs/RELAY_20261102_feishu-three-subjects.md
## 不做 / 边界
- 无代码轮；Codex 不参与。
- 只运行已提交并固定哈希的脚本；`mode=write`，须用户本人点 👍。
- 临时配置 check 不通过时不改任何本机文件；替换前备份到学习目录 `backup\`。不删除任何东西，不改 risk-control，不注册或修改计划任务（只触发一次现有的 FeishuTutor-Daily）。
- 回帖只含步骤结论、计数和标题结构，不贴学习内容。
## 验证命令
- 脚本轮回帖。
## 需要真人的部分
- 先在飞书“学习账本”“练习记录”两张表的“科目”字段加上“英语”“数据分析”选项，再在 `to-runner` 评论上点 👍。
