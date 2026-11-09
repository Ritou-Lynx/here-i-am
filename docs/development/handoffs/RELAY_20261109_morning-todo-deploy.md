<!-- relay:contract v1 -->
## 目标
部署 PR #116 已合并的晨间待办日期修复，重生成当前逻辑日的晨间摘要。
## 完成标准
- [ ] 只读轮确认计划任务、启动器、配置及已部署模块版本匹配。
- [ ] 用户在 write 指令评论点 👍 后，更新实际运行副本的单个生成逻辑模块。
- [ ] 配置检查通过，并使用 --stage morning --no-push 重生成晨间摘要。
- [ ] 回执确认模块版本与生成结果；不输出摘要正文、配置或本机路径。
## 允许修改的路径
- tools/relay_scripts/life_digest_update/
- docs/development/handoffs/RELAY_20261109_morning-todo-deploy.md
## 部署步骤
1. watcher 每三分钟发现 agent-relay PR 的 read 指令，核对已提交脚本哈希后检查现役启动器及模块版本。
2. write 指令须用户本人点赞；脚本再核验一次，生成器正在运行或版本不符即退出。
3. 备份旧模块及当天摘要，复用生成器锁，替换单个 life_digest_lib.mjs；不更换任务、配置、MCP 服务或 App。
4. --check 失败恢复旧模块；通过后运行当前逻辑日 morning 阶段，禁止推送通知。重生成失败时保留备份并明确失败，不宣称已完成。
5. 家里电脑执行回执成功后，云端再用 life_digest 核验新生成时间及日期表述。
## 不做 / 边界
- 不构建安装 App，不改数据库、账户、令牌、心率服务或计划任务设置。
- 不自动点赞、不绕过 write 审批；只读轮不调用生成器，不写生产。
- 不将真实摘要、配置、聊天、路径或原始日志放进公开回帖。
- 本次只更新已知旧哈希或已修复哈希；未知现役版本立即阻断。
## 验证命令
- node --test tools/relay_scripts/life_digest_update/update.test.mjs tools/life_digest/life_digest.test.mjs tools/i_remote_mcp/life_digest.test.mjs
## 需要真人的部分
- 用户在 write 部署指令评论点一次 👍；这是本机 watcher 的执行闸门。
