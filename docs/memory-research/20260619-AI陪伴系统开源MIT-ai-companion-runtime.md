# 把AI陪伴系统整套开源了，MIT随便商用

> 来源：小红书 · 十四香
> 链接：https://www.xiaohongshu.com/discovery/item/6a2bbb590000000021019384
> 提取时间：2026-06-19

---

## 笔记正文

做 AI 陪伴产品，难的从来不是"聊天"，是工程：
- 流式回复怎么不卡？
- 用户说"我好累"怎么接住？
- 极端情绪怎么兜底？

我把这一整套写出来，开源了。

✅ 7 种情绪识别，"很累"和"有点累"分得清
✅ 4 级风险分级，2 毫秒拦截，高危直接给心理热线
✅ 5 层记忆架构，它记得你上周说过什么
✅ 模型随便换：Qwen / DeepSeek / OpenAI，改个配置自动热加载
✅ 300 毫秒出首句，主模型慢了自动换快模型兜底
✅ 每次对话全链路可追踪，延迟和成本看得一清二楚

前后端全套（FastAPI + Next.js），Docker 一条命令跑起来，MIT 协议，商用随便。

刚开源，目前一个 star 都没有😂

**仓库：** yf0522/ai-companion-runtime（GitHub 直接搜）

**标签：** #ai #人工智能 #个人开发者 #多模态人工智能 #软件开发 #大模型 #智能体

---

## 互动数据
- 点赞：467 | 收藏：682 | 评论：76

---

## 评论区

### 圣宗筑基剑种
> 聊天能聊多少？商用to C的话其实可以直接markdown存起来然后快速启动，并且应该嵌套那种拟人化agent，你这个输出出来应该也和我的项目一样，说话不太像人类
- 2赞
  - **作者回复：** 这个可以通过提示词和模型来弥补
  - **诗缘人回复：** 不像人就嵌入蒸馏人格skill应该会好很多
  - **圣宗筑基剑种回复：** 我试过了，不太好，只能说勉勉强强

### 卢煜坤
> 我的想法是不用大模型，然后从陪伴开始一步步学习成长到最后"长大成人了"
- 1赞
  - **自问自答：** 设计一种树形网状无限递归模式的记忆网络，把记忆进行分层处理，越无关紧要的记忆越放到树梢，但是树梢末端也需要横向联通，这种可行吗

### jaxon
> 能纯本地运行+语言聊天不？tts+llama.cpp+stt可行不？
  - **作者回复：** 这个可以，但是你电脑的性能得能撑的住

---

## GitHub 仓库 —— yf0522/ai-companion-runtime

> **Python · ⭐27 · MIT License**
> 描述：Real-time AI Companion with emotional support, tool calling, long-term memory, model hot-swap, and full-chain trace observability

### 核心架构

```
用户端 (Next.js 14) → WebSocket → 
  并行分析器 (Intent / Emotion / Risk / Memory)
  → Agent Harness 编排 (Risk拦截→Fast Reply赛马→Prompt Builder→Model Router)
  → WebSocket 流式返回
后台异步: Memory压缩归档 + Embedding + Reflection + Trace写入
```

### 核心特性

| 功能 | 说明 |
|------|------|
| **情绪引擎** | 7 种情绪识别 + 强度评分 + 情感极性，规则+关键词匹配，无模型调用 |
| **风险分级** | 4 级响应（low→critical），2ms 拦截，高危给心理热线 |
| **5 层记忆** | L0 Working Memory → L1 Session Summary → L2 User Profile → L3 Vector Memory → L4 Archive |
| **模型热插拔** | 改 models.yaml 自动加载，支持 Qwen/DeepSeek/OpenAI/本地模型 |
| **动态人格** | personality.yaml 定义，根据情绪状态调节语气 |
| **Fast Reply 赛马** | 300ms 内主模型没出首 token 就换快模型兜底 |
| **全链路 Trace** | OpenTelemetry + Jaeger + Prometheus + Grafana |

### 技术栈
- 前端: Next.js 14 + TypeScript + TailwindCSS + Zustand
- 后端: Python 3.11 + FastAPI + WebSocket
- 数据库: PostgreSQL 16 + pgvector
- 缓存/异步: Redis 7 + Celery
- 部署: Docker Compose
