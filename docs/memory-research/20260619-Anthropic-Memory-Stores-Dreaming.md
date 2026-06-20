# AI Agent 终于有了「真正的记忆」！Anthropic Memory Stores + Dreaming

> 来源：小红书 · Funny ai（视频笔记）
> 链接：https://www.xiaohongshu.com/discovery/item/6a1a353b00000000380213a5
> 提取时间：2026-06-19

---

## 笔记原文

Anthropic 在 5 月 6 日 Code with Claude 2026 开发者大会上正式发布了 Memory Stores + Dreaming 特性，目前处于 research preview 阶段，主要集成在 Claude Managed Agents 中。

**核心更新要点：**

• **Memory Stores：** 持久化文件系统式存储，Agent 可跨 session 主动读写结构化记忆（支持 markdown、目录、索引等）。
• **Dreaming：** 异步后台"睡眠"过程。Agent 在 idle 时回顾过去 sessions 的 transcripts + 当前 memory store，自动执行去重、合并矛盾信息、移除过时条目、提取跨 session 模式、recurring mistakes、团队偏好，生成新的优化 memory store（原版保留供人工审查）
• **其他配套特性：** Outcomes-based evaluation、Multi-agent orchestration、Webhooks 等。

**实测效果：**
• Harvey（法律 AI 初创）内部测试显示，任务完成率提升约 6x（仅靠记忆优化，无需升级模型）
• 成本控制较好，通过结构化和缓存实现高 hit rate

这不是简单地把更多上下文塞进 prompt，而是让 Agent 拥有持续状态和自我迭代能力。它会记住有用信息、反思错误、每晚复盘优化，下一次就变得更聪明。

从此以后，Agent 不再是临时工具，而是一个会越来越懂你、越来越强的长期伙伴。

**标签：** #AIAgent #Claude #Anthropic #AI记忆 #AI人工智能 #agent

---

## 互动数据
- 点赞：2071 | 收藏：3235 | 评论：39
- 类型：视频笔记

---

## 评论区

### Cloud
> 发音真舒服呀
- 13赞

### Foggy London
> 这在企业里早就有了
- 2赞

### 问一问 回复多条
（多位用户 @问一问 要求整理核心内容，问一问均有回复总结，内容与笔记正文基本一致）
