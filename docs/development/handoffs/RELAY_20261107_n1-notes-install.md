<!-- relay:contract v1 -->
## 目标
把飞书笔记副本（#92，notes_mirror）装到家里电脑的 feishu-tutor-tool，试跑一次，把「日记/日报」和「工作」两个文件夹的文档拉到本机 `%USERPROFILE%\feishu-notes`，再注册每 30 分钟一次的计划任务，给后面的 N2（i MCP 读笔记）做数据源。

## 完成标准
- [ ] 脚本轮 `tools/relay_scripts/notes/n1-install.ps1`（mode=write）各步 ok：launcher → preflight → install（先备份）→ self_check → test_run → schedule。
- [ ] test_run 输出 `notes_ok`，两个文件夹的文档数都大于 0；第一次文档多时允许 `deferred>0`（12 分钟预算用完，剩下的由计划任务接着拉）。
- [ ] 计划任务 `FeishuNotes-Mirror` 为 Interactive、每 30 分钟、无期限，下一次在 :10 或 :40。
- [ ] 学习单（FeishuTutor-Daily）不受影响：feishu_sync.mjs、layout.mjs、schema.mjs 不变，cli.mjs 只多一个只读命令。

## 允许修改的路径
- tools/relay_scripts/notes/
- tools/feishu_tutor/sync/notes_mirror.mjs、notes_mirror.test.mjs、tools/feishu_tutor/README.md
- docs/development/handoffs/RELAY_20261107_n1-notes-install.md、DEVLOG.md

## 不做 / 边界
- 对飞书只读（drive files list、docs +fetch），不写、不删飞书。
- 不碰 lark-cli 的配置、登录和 risk-control；不复制凭据。
- 家里的 feishu_sync.mjs / layout.mjs / schema.mjs 必须是已知的当前版本，cli.mjs 必须是已知版本，否则什么都不改直接停。
- 改动前把 cli.mjs、notes_mirror.mjs、config.json 备份到工具目录 backups\n1-notes-<时间>；安装或自检失败就还原。
- config.json 只加 `notes.folders`，其他字段不改；已有不同的 notes 设置时停。
- 只注册 `FeishuNotes-Mirror` 一个任务；同名任务不是本脚本建的就停。不动其他计划任务，不立即触发。
- 输出不含令牌、本机路径、SID、文档标题或正文。

## 验证命令
- `node --test tools/feishu_tutor/sync/*.test.mjs`
- 脚本轮输出逐行 ok；之后看计划任务历史和 `feishu-notes\index.json` 的 last_run。

## 需要真人的部分
- 用户已于 11-07 本人完成 `drive:drive:readonly` 授权。
- 在脚本轮评论上点 👍。
