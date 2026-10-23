<!-- relay:contract v1 -->
## 目标
接力需要用户处理时，watcher 把提醒推到用户的飞书（自定义群机器人 webhook），iPhone 可选再推一份 Bark。（修订 1，10-23：用户决定 PushPlus 改为飞书机器人，原因是 PushPlus 可能收费、需实名。）这是旧 PR #17 的重做：#17 写在 A4 之前，与现在的 `relay_watcher.mjs` 冲突，改为在当前 v3-lab 上重新接线。原因不变：接力评论都以用户本人账号发出，GitHub 不会给自己发通知。
## 完成标准
- [ ] 新增 `tools/agent_relay/relay_notify.mjs`：导出 `sendNotification({ title, content, url }, notifyConfig, fetchImpl = fetch)`，返回 `{ feishu, bark }`，取值 `'ok' | 'failed' | 'off'`。每个通道 10 秒超时，异常一律吞掉只返回 `failed`，单个通道失败不影响另一个，不向调用方抛出。
  - 飞书：`POST <feishuWebhook>`，JSON `{ msg_type: "text", content: { text } }`，`text` 为标题、空行、正文；配置了 `feishuSecret` 时另加 `timestamp`（秒）与 `sign`（以 `timestamp + "\n" + secret` 为 HMAC-SHA256 密钥、对空串签名后 base64）。HTTP 200 且响应 `code === 0`（兼容旧版 `StatusCode === 0`）为成功。
  - Bark：`POST <barkServer>/push`，默认 `https://api.day.app`，JSON `{ device_key, title, body, url, group: "agent-relay" }`；HTTP 200 且响应 `code === 200` 为成功。
  - 两个通道都没配置时什么都不发，日志记一行“未配置通知通道”。
- [ ] 配置：`validateConfig` 接受可选 `notify: { feishuWebhook, feishuSecret, barkKey, barkServer }`，缺省视为全部关闭；`feishuWebhook` 非空时必须以 `https://open.feishu.cn/open-apis/bot/v2/hook/` 或 `https://open.larksuite.com/open-apis/bot/v2/hook/` 开头；`barkServer` 必须是 `https://`，否则报错。不再有 PushPlus。`relay.config.example.json` 增加 `notify`（值为空串）。真实 token 只写在已忽略的 `.state/config.json`。
- [ ] 触发：每次 `runOnce` 在 `for (const pr of prs)` 资格过滤**之前**，对全部带 `agent-relay` 的 open PR（含带 `relay-paused` / `relay-needs-human` 的）扫描评论，第一行为 `<!-- relay:done -->` 或 `<!-- relay:to-human -->`、作者在 `allowedAuthors` 内的，各通知一次。扫描在锁内、`cleanup-blocked` 检查之后进行，且不受 `codex-not-found` 提前返回影响（扫描先做完）。watcher 自己发出 `status=failed` 的 `to-claude` 回帖（含超时补报）送达后，也发一条失败通知。`to-codex`、`done/blocked` 的 `to-claude` 不通知。
- [ ] 内容：标题分别为 `接力 PR #N：完成，等你验收` / `接力 PR #N：需要你决定` / `接力 PR #N：第 K 轮失败`；正文为 PR 标题 + PR 或评论链接 + 评论正文前 300 字（先去掉第一行标记，再经 `redact` 脱敏）。`gh pr list` 的 `--json` 需加 `title`。
- [ ] 去重与补发：state 新增顶层 `notified: { [commentId]: { status: 'sent'|'pending'|'gave_up', attempts, at } }` 与 `notifyEnabledAt`（与现有 `comments[id].notification` 回帖投递字段互不相干，不要复用）。全部已启用通道都失败才算失败，下次运行重试，累计 3 次后记 `gave_up`。首次启用通知（state 没有 `notifyEnabledAt`）时只记录基线、不补发此前的历史评论。旧 state 文件没有这些字段时正常读取。
- [ ] 令牌不出现在任何日志、回帖、Codex 提示词和错误信息里：`redact` 支持传入额外需要隐藏的字符串，watcher 把 `feishuWebhook`（整串及其 hook 段）、`feishuSecret`、`barkKey` 传进去。
- [ ] `main` 新增 `--test-notify`：读配置、发一条“接力测试通知”、打印各通道结果，全部失败或全部 off 时返回 1。`--dry-run` 不发任何通知，只打印将要通知的条目。
- [ ] `runOnce` 增加可注入的 `fetchImpl` 参数；测试全部用假 fetch，不联网。新建 `relay_notify.test.mjs`，并在 `test_entry.mjs` 中 import。原有 67 项继续通过。
- [ ] README 增加“手机通知”一节：建只有自己的飞书群、加自定义机器人取 webhook（可选开启签名校验，或设置关键词“接力”）、Bark 取 key、填 `.state/config.json`、运行 `--test-notify`。
## 允许修改的路径
- tools/agent_relay/relay_notify.mjs（新建）、tools/agent_relay/relay_notify.test.mjs（新建）
- tools/agent_relay/relay_watcher.mjs、tools/agent_relay/relay_watcher.test.mjs
- tools/agent_relay/relay_core.mjs、tools/agent_relay/relay_core.test.mjs
- tools/agent_relay/test_entry.mjs、tools/agent_relay/relay.config.example.json、tools/agent_relay/README.md
## 不做 / 边界
- 零 npm 依赖，HTTP 用 Node 内置 fetch。
- 不改协议标记、轮次逻辑、codex 解析（A4）、`install_relay_task.ps1` 与计划任务；通知失败不影响接力执行和返回状态。
- 不配置真实 token，不在本机发真实通知；不碰生产与真实数据。
- 可参考旧 PR #17 提交 `d284082` 的实现（`git show d284082:tools/agent_relay/relay_notify.mjs` 等），本机没有该对象就按本合同重写；watcher 接线必须按当前代码重新写，不要整文件覆盖。
## 验证命令
- `node --test tools/agent_relay/`
- `node tools/agent_relay/relay_watcher.mjs --dry-run`（本机没 token 时应输出“未配置通知通道”；沙箱无 GitHub 认证导致的失败可忽略，照实贴出）
## 需要真人的部分
- 合并后在飞书建一个只有自己的群，添加“自定义机器人”，复制 webhook 地址（可选签名密钥、可选 Bark key），填进本机 `tools/agent_relay/.state/config.json` 的 `notify`，运行 `node tools/agent_relay/relay_watcher.mjs --test-notify`，确认手机收到。

## 审核记录
- 10-23 第 1 轮（946880b）：通过。只改合同允许的 9 个文件；云端复跑 `node --test tools/agent_relay/` 104/104。逐条核对：扫描在资格过滤与 codex-not-found 之前完成，单个 PR 评论读取失败不再阻断其他 PR；`notified` 与回帖投递字段分开；首次启用只记基线，扫描不完整时不推进基线；token/key 在日志、回帖、提示词、stdout 日志和错误信息中均被隐藏。Codex 沙箱内 `--dry-run` 因无 GitHub 认证退出 1，属环境限制。
- 10-23 修订 1：用户在 #41 第 1 轮通过后决定 PushPlus 改为飞书自定义机器人（保留 Bark），第 2 轮执行。
- 10-23 第 2 轮（aee4e5f）：通过。只改合同允许的 6 个文件；云端复跑 105/105，`git grep -i pushplus -- tools/agent_relay/` 无结果。飞书 payload 与签名（timestamp+"\n"+secret 为 HMAC 密钥、空串签名、base64）符合官方规则；webhook 只接受飞书/Lark 机器人地址，整串与 hook 段都进脱敏列表；旧 `pushplusToken` 字段明确报错。
