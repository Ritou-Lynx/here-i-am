<!-- relay:contract v1 -->
## 目标
接力需要用户处理时，watcher 把提醒推到用户微信（PushPlus），iPhone 可选再推一份 Bark。原因：PR 里所有评论都以用户本人账号发出，GitHub 不会给自己发通知，用户至今收不到任何提醒。

## 完成标准
- [ ] 新增 `tools/agent_relay/relay_notify.mjs`：`sendNotification({ title, content, url }, config, fetchImpl)`，按配置向已启用的通道各发一次，返回每个通道的成败；单个通道失败不影响其他通道，不抛出到调用方。
  - PushPlus：`POST https://www.pushplus.plus/send`，JSON `{ token, title, content, template: "txt" }`；响应 JSON 的 `code === 200` 视为成功。
  - Bark（可选）：`POST <server>/push`，默认 server `https://api.day.app`，JSON `{ device_key, title, body, url, group: "agent-relay" }`；HTTP 200 且响应 `code === 200` 视为成功。
  - 两个通道都没配置时什么都不发，只在日志里记一行“未配置通知通道”。
- [ ] 配置：`relay.config.example.json` 增加 `"notify": { "pushplusToken": "", "barkKey": "", "barkServer": "https://api.day.app" }`；空字符串表示不启用。真实 token 只写在已忽略的 `.state/config.json`，不进仓库、不写日志、不进回帖。`validateConfig` 校验类型，`barkServer` 必须是 https。
- [ ] 触发（每次 `--once` 都做，放在执行任何一轮之前，执行一轮之后不再重复扫描）：
  1. 扫描所有带 `agent-relay` 标签的 open PR（**包括**带 `relay-paused` 或 `relay-needs-human` 的 PR），找第一行为 `<!-- relay:done -->` 或 `<!-- relay:to-human -->`、作者在 `allowedAuthors` 里的评论。
  2. watcher 自己回帖 `to-claude status=failed` 时，同时发一条通知。
  3. 不为 `to-codex`、`to-claude done/blocked` 发通知（那是 AI 之间的交接，用户不需要处理）。
- [ ] 内容：标题分别为 `接力 PR #N：完成，等你验收`、`接力 PR #N：需要你决定`、`接力 PR #N：第 K 轮失败`；正文为 PR 标题 + PR 链接 `https://github.com/<repo>/pull/N` + 评论正文前 300 字（去掉第一行标记、`---` 之后的署名，经 `redact`）。Bark 的 `url` 填 PR 链接。
- [ ] 去重与补发：已通知的评论 ID 记入 `state.json` 的 `notified`；通道全部失败时记为待重发，下次运行重试，最多 3 次后放弃并记日志。首次启用通知时只记录现有 done/to-human 评论为已通知、不补发历史消息（用 `state.notifyEnabledAt`）。
- [ ] `--test-notify`：读取配置，发一条 `接力测试通知` 后退出，打印每个通道成败；不读写 state、不访问 GitHub。
- [ ] `--dry-run` 不发送任何通知（打印将要发送的标题即可）。
- [ ] 测试（全部用假 fetch，不联网）：两个通道请求体与地址正确；PushPlus 返回非 200 code 判失败；一个通道失败另一个照发；未配置不发；done/to-human 触发、to-codex 与 to-claude done 不触发；带 `relay-needs-human` 的 PR 仍触发；非白名单作者不触发；同一评论不重复；首次启用不补发历史；失败重试至多 3 次；watcher failed 回帖触发通知；dry-run 与 `--test-notify` 行为；token 不出现在任何日志或回帖文本中。`node --test tools/agent_relay/` 全部通过。
- [ ] README 增加“手机通知”一节：PushPlus（微信扫码登录 pushplus.plus → 一对一推送 → 复制 token）与 Bark（App Store 安装 → 复制 key）的设置步骤，填到 `.state/config.json` 后运行 `--test-notify`。

## 允许修改的路径
- tools/agent_relay/relay_notify.mjs（新建）、relay_notify.test.mjs（新建）
- tools/agent_relay/relay_watcher.mjs、relay_watcher.test.mjs、relay_core.mjs、relay_core.test.mjs
- tools/agent_relay/relay.config.example.json、tools/agent_relay/README.md

## 不做 / 边界
- 零 npm 依赖，HTTP 用 Node 内置 fetch（以可注入的 `fetchImpl` 传入，测试替换）。
- 不改协议标记、不改轮次逻辑、不改计划任务脚本；通知失败绝不影响接单、执行、推送和回帖。
- 不构建、不安装 App，不碰真实数据库；本轮不配置真实 token，不发真实通知。

## 验证命令
- `node --test tools/agent_relay/`
- `node tools/agent_relay/relay_watcher.mjs --dry-run`

## 需要真人的部分
- 合并后在 pushplus.plus 微信扫码取 token（可选 Bark key），填进本机 `.state/config.json`，运行 `--test-notify` 确认两台手机都收到。
