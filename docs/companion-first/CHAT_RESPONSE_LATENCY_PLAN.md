# 角色回复速度专项

> 目标：降低角色聊天的首字等待、整段等待和语音播放等待，让普通聊天先“有反应”，再逐步优化完整回复和出声体验。

## 当前阶段

**Phase 1 裸流式实验失败，已回退到完整回复优先。接下来做 Phase 2。**

本专项按”小切片、可验证、可单独提交”的方式推进。每次继续时，先读本文件，再只选择一个高收益改动执行。

## 现状诊断

| 慢点 | 位置 | 影响 | 判断 |
|---|---|---|---|
| 角色聊天裸流式失败 | `CompanionAgent.chat` 曾切到 `runStream(useStream: true)` | MiniMax M3 会把英文思考链作为可见 chunk 滚出；chunk 语义还可能是 delta，导致最终只剩最后几个字 | 不再直接裸流式 |
| 玩具连接同步等待 | `PersonaChatScreen._sendMessage` 发送前 `_ensureToyConnected(timeout: 22s)` | 配了玩具但连接慢/失败时，模型请求前就被卡住 | 高风险阻塞 |
| 工具集过重 | `CharacterToolsFactory.buildCompanionTools` 默认挂大量工具 | 工具 schema 全进请求体，增加 prompt 和模型决策成本 | 高收益优化 |
| 撤回宽限 900ms | `_recallGracePeriod` | 每次发送固定增加近 1 秒 | 保留，暂不优先改 |
| TTS 非流式 | `MiniMaxTtsService.textToSpeech` 使用 `stream: false` | 文字完成后还要等完整音频生成才播放 | 后续优化 |
| 上下文串行组装 | `CharacterContextAssembler.build` 多个 await 串行读取 | 每轮回复前本地上下文准备时间偏长 | 可排后 |

## 分阶段计划

### Phase 1：首字速度

- [x] 裸流式输出实验
  - 目标：角色文字首字能尽快显示，不再等整段回复完成。
  - 结果：失败。MiniMax M3 在 streaming chunk 中泄漏英文思考链；UI 假设 chunk 是 cumulative full text，但实际兼容客户端可能返回 delta，导致最终显示/持久化被截断。
  - 改动：`companion_agent.dart` 切为 `agent.runStream(useStream: true)` 逐 chunk yield；`persona_chat_screen.dart` 适配 cumulative full-text chunk。
  - 处置：已回退到 `agent.run(useStream: false)`，保证普通角色消息完整。后续不要再做“原始 chunk 直出”。

- [ ] 受控首显方案
  - 目标：改善体感，但不泄漏思考链、不依赖 provider chunk 语义。
  - 候选：发送后立即显示稳定的“正在想/正在输入”状态；或等完整回复返回后做本地模拟打字；或只在明确能区分 `thought` 与 `textOutput` 的 provider 上启用白名单流式。
  - 验证：MiniMax M3 不显示英文思考链；最终文本完整；动作消息和工具回合不丢。

### Phase 2：发送前阻塞

- [ ] 玩具连接异步化
  - 目标：普通聊天发送不等待玩具连接。
  - 方向：只有已连接时挂 toy tool；未连接时后台连接，下一轮或明确玩具互动时再使用。
  - 验证：未配置玩具、配置但未连接、已连接三种状态。

### Phase 3：工具分层

- [ ] 普通聊天默认工具瘦身
  - 目标：普通闲聊只带核心工具，重工具按意图加入。
  - 建议默认保留：角色记忆读写、动作消息、提醒、必要的生活记忆查询/写入。
  - 建议按意图加入：财务、购物、网页搜索、路线、手机使用、手表、微信读书、阅读正文、设备拦截。
  - 验证：普通聊天变轻；用户说“记账/花了/买/搜/查/路线/睡眠/手机使用”等时，对应工具仍可用。

## 后续候选

- [ ] 上下文组装并行化
  - 把角色记忆、world entries、profile、timeline、checkpoints、knowledge cards 的读取改为并行。
  - 收益取决于本地 IO/DB 实际耗时，优先级低于流式和工具瘦身。

- [ ] TTS 分句流水线
  - 文字回复完成后按句切分，先生成第一句音频并播放，后续句子排队生成。
  - MiniMax 当前不是实时 TTS 流，分句流水线比改协议更现实。

- [ ] Chat latency instrumentation
  - 增加关键耗时日志：发送到模型请求、模型首 chunk、模型完成、入库完成、TTS 请求、TTS 播放开始。
  - 用于验证每个切片是否真的改善体感。

- [ ] Provider-safe streaming
  - 只在能稳定区分 thought/reasoning 与 visible text 的模型客户端上启用。
  - 对 MiniMax M3 这类把 reasoning 混入 visible text 的模型，默认关闭 raw streaming。

## 暂缓和保留

- **保留 900ms 撤回宽限**：它是有价值的体验功能。先优化更大的阻塞点。
- **保留 SendActionMessage**：动作 + 台词分离是角色表达能力的一部分。不要为了提速砍角色表达。
- **暂不做激进上下文缓存**：角色记忆和 timeline 会频繁变化，TTL 缓存容易带来一致性问题。先做并行化和工具瘦身。
- **暂不关闭全部 checkin/call 能力**：普通聊天可以瘦身，但涉及即时来电、提醒、主动陪伴的工具要按意图精细保留。

## 每次继续时怎么做

1. 先读本文件，确认当前阶段。
2. 只选择一个未完成 checkbox 作为本次切片。
3. 改代码前说明将动哪些文件和为什么。
4. 完成后跑针对性验证。
5. 更新本文件对应 checkbox/备注。
6. 在 `DEVLOG.md` 最前面追加本次产出。
7. 做收工检查，建议 commit 分组；不自动 commit/push，除非用户明确确认。

## 建议提交粒度

```text
perf(companion): stream role chat replies
perf(companion): avoid blocking sends on toy connection
perf(companion): gate heavy tools by chat intent
perf(companion): pipeline tts playback by sentence
```

## 固定唤起语

```text
继续回复慢专项，按计划做下一步。
```

```text
看回复慢专项，告诉我下一步。
```

```text
继续回复慢专项，这次只做一个小切片。
```

```text
回复慢专项收工检查。
```
