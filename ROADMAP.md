# Memex 个人迭代总览

> 本文件记录在上游 Memex 基础上的自定义改动现状，以及后续规划。
> 与 DEVLOG.md 的区别：DEVLOG 是时间序的施工日志，本文是横向的功能地图。

---

## 一、原版 Memex 功能（上游维护，不改动）

### 核心录入
- 多模态输入：文字、图片、语音
- 自动 EXIF 提取（时间戳、GPS）、OCR、图片标注（Google ML Kit）

### AI 卡片生成
- 多 Agent 架构自动生成结构化卡片：
  - 生活效率类：task、routine、event、duration、progress
  - 知识媒体类：article、snippet、quote、link、conversation
  - 人物地点类：person、place（含地图预览）
  - 数据指标类：metric、rating、transaction、spec sheet
  - 视觉类：gallery
- 自动标签、实体提取、交叉引用

### 知识与洞察
- P.A.R.A 知识体系组织（Projects / Areas / Resources / Archives）
- Insight 卡片：趋势图、叙事摘要、地图路线、时间轴、画廊
- Schedule Aggregator Agent（日程简报）

### 伴侣系统（原版）
- Companion Agent：聊天 + 卡片评论
- 角色记忆系统：长期记忆 / 世界书 / 事件流 / 滚动摘要四层架构

### 其他
- P.A.R.A 全文搜索（SQLite FTS5 + jieba 中文分词）
- App 锁 + 生物识别
- 备份 / 恢复（.memex 自定义格式）
- 多 LLM 提供商支持（Gemini / OpenAI / Claude / Bedrock / MiniMax / Qwen 等）
- Custom Agent System（用户可自建 Agent，支持 SKILL.md / JS 执行 / 事件触发）
- Android Early APK 自动构建（GitHub Actions）

---

## 二、自定义功能（个人迭代）

### 阶段 1 — 外部数据接入
- **微信读书同步**：自动拉取读书笔记生成知识卡片
- **HTTP Fetch 工具**：Agent 可主动调用外部 API

### 阶段 2 — 健康数据 & MCP 协议
- **MCP 协议实现**（mcp_protocol / mcp_client / mcp_oauth）
- **COROS 运动数据接入**：通过 MCP + OAuth 同步跑步、骑行等运动记录

### 阶段 3 — 主动推送系统（Companion 主动触达）
- **Checkin Service**：随机脉冲（仿 Cyberboss 架构），AI 自主决策是否推送
- **Reminder 队列**：AI 为自己创建未来提醒（如"20分钟后看用户吃完没"）
- **高优先级通知频道**（agent_checkin_v2）：突破锁屏送达

### 阶段 3.5 — Samsung Freecess 绕过
- **前台服务路径**（flutter_foreground_task）：Foreground Service 免疫三星 Freecess 冻结
- **WorkManager → Foreground Service 链路**：自动触发路径接入前台服务，覆盖熄屏 / 锁屏场景
- 整套链路端到端验证：WorkManager 唤醒 → 前台服务 → AI 决策 → 通知送达 + 写入聊天记录

---

## 三、Roadmap（接下来要做的）

### 语音系统（进行中）

**当前状态**：已通过 ElevenLabs TTS 实现基础朗读功能（角色消息下方有朗读按键）。
存在问题：中文支持一般 / token 贵 / 需要关 VPN 才能使用。

**接下来**：

1. **TTS 迁移到 MiniMax**
   - 解决中文音色问题
   - 解决 VPN 依赖问题
   - 调试找到满意的音色

2. **Live 实时对话（大框架）**
   - ASR 打通（语音识别 → 文字）
   - LLM 打通（复用现有 Companion Agent 对话链路）
   - TTS 打通（文字 → 语音实时播放）
   - 目标：与角色进行连续实时语音对话

### 卡片系统优化

3. **意图匹配改进**
   - 当前问题：AI 对用户输入的意图识别不够准，卡片类型匹配有偏差
   - 方向：优化 Card Agent prompt / 匹配规则

4. **扩充卡片类型**
   - 现有卡片库不足以覆盖信息需求
   - 需持续观察哪些场景缺卡片、哪些现有卡片效果差

5. **嵌套卡片方案**
   - 问题：新接入的 Agent（如 COROS、WeRead）输出的是粗糙纯文本，而非结构化卡片
   - 目标：支持 Agent 输出嵌套卡片格式，而非 fallback 到纯文本
