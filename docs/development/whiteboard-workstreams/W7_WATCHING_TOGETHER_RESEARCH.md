# 「和 AI 一起看视频」方案调研报告

> W0 排程决定（2026-08-23）：本功能已进入 Parking Lot，本轮不实现、不创建开发窗口。保留本文作为未来架构输入；重新启动至少需要字幕闭环稳定、长期任务队列可用且用户重新提升优先级。

> 状态：v2 — 已整合 Cove 共影与直播陪看搭建指南
> 日期：2026-08-23（v2 同日补修）
> 关联文档：`W4_SUBTITLE_RESEARCH.md`（平台字幕抓取）、`W4_VIDEO.md`（白板视频研读现状）
> 触发问题：小红书社区已有大量「AI 陪看电影」实践，需调研现有方案、评估与白板 W4 字幕线的关系、给出 Here I am 的落地路线。

## v2 修订要点

v2 纳入用户补充的 **《Cove 共影与直播陪看搭建方法》**（小红书号 427689021）。这份文档来自一套真实运行的系统（FastAPI + yt-dlp + faster-whisper + 视觉感官模型 + Obsidian 输出），是本次调研中**最接近生产级完整方案**的参考。v2 主要变化：

1. §二 新增 Cove 指南作为头号架构参考；它**首次引入「直播陪看」形态**，此前调研全部聚焦点播。
2. §三 新增 Cove 三层架构剖析（播放层 / 证据层 / 聊天层）；其「隐藏 `model_content`」模式修正了我们此前对上下文注入的模糊描述。
3. §四 新增四个此前未覆盖的设计维度：**证据降级链、感官层窗口、陪看停顿点、直播 TTL**。
4. §六 落地路线由三期改为**四期**，新增 Phase 4「直播陪看」；并吸收 Cove 的 MVP 五阶段作为每期内部的迭代顺序。
5. §八 新增与 Here I am 悬浮球 / 分享截图 / 主动陪伴层的既有能力映射——**直播陪看与我们现有悬浮球截图分享机制可直接对接**。
6. §七 新增风险条目：直播证据 TTL、感官层缓存治理、代理播放合规边界。

---

## 一、TL;DR — 结论先行

1. **「和 AI 一起看视频」与「W4 字幕抓取」是互补的两层，不是重复**：W4 解决的是**底层数据接入**（怎么拿到时间轴 + 文本轨道）；「一起看」解决的是**消费场景**（拿到轨道后，怎么让林埃有节奏、有记忆、有上下文地陪你说话）。前者是后者的基础设施。
2. **Cove 指南是本调研最接近生产级的完整参考**：它用「播放层 / 证据层 / 聊天层」三层架构把整条链路打通，并引入了此前调研没有的三大要素——**直播陪看形态、隐藏 `model_content` 上下文注入、证据降级链**。此前调研的 open-watch-cinema / film-matinee 验证了「剧透闸门 + 预生成 package」的可行性；Cove 则证明同一思路可以延伸到直播与多平台代理播放。
3. **B 站/YouTube 普通视频的最大差异是「没有现成完整剧本」**，但有 AI 字幕/CC 字幕兜底——这正是上一轮 W4 调研的落地价值。两条线在白板汇合后，Here I am 可以同时覆盖四种场景：
   - 有完整字幕的电影/番剧 → **精读模式**（预生成整片理解缓存 + 剧透闸门）
   - 只有 AI 字幕的 B 站/油管视频 → **泛读模式**（实时轨道 + 隐藏 model_content）
   - 完全没有字幕的小红书/短视频 → **感官模式**（短片段视觉观察，自动降级回字幕）
   - 抖音/B 站/油管**直播** → **直播陪看模式**（截屏 + 音频转写 + TTL 过期）
4. **「实时语音识别（Whisper 流式）」在主链路仍未被任何项目采用**——Cove 同样把它降级为「无字幕兜底」和「直播可选增强」。原因一致：成本/延迟/说话人分离质量都不如直接利用平台已有轨道。**建议 Here I am 不做实时 ASR 主链路**。
5. **Cove 提出的「隐藏 `model_content`」模式修正了我们的提示词架构直觉**：不要把字幕证据塞进用户可见消息或公开 prompt，而是前端组包 `content`（用户可见）+ `model_content`（证据），后端按消息类型分离存储。这与 Here I am 现有的消息 schema 可自然兼容。

---

## 二、调研对象与方法

### 2.0 头号参考：Cove 共影与直播陪看搭建指南（生产级完整方案）

**来源**：用户提供文档（小红书号 427689021），一套真实运行的系统。

Cove 指南是本调研中**架构最完整、考虑最周到**的参考，覆盖点播 + 直播 + 笔记沉淀 + Token 治理四大块。它给出的关键贡献（此前调研都未覆盖）：

| Cove 概念 | 说明 | 对 Here I am 的价值 |
|---|---|---|
| **三层架构** | 播放层（浏览器 video/iframe/Chrome）→ **证据层**（字幕/OCR/转写/截图观察/短片段感官报告）→ 聊天层（证据作为**隐藏 `model_content`** 交给模型） | 修正了「prompt 塞字幕」的粗糙直觉，给出生产级注入方式 |
| **隐藏 `model_content`** | 前端发 `content`（用户可见）+ `model_content`（模型读取的证据），用户看到自然对话，模型看到完整证据 | Here I am 消息 schema 可自然扩展此字段（如 `PersonaChatMessage.metadata['model_content']`） |
| **字幕优先级链** | 外挂字幕 > 平台字幕 > 内封字幕 > 本地 Whisper 转写 | 与 W4 调研结论完全一致，且明确 Whisper 是兜底不是主线 |
| **「问这一幕」隐藏上下文** | 视频标题 + 当前精确时间点 + 附近字幕 + 前情字幕 + 原文/中文双语 + **防剧透规则** + 可选感官报告 | 可直接作为 Here I am 的 prompt 模板骨架 |
| **感官层（sensory layer）** | ffmpeg 截 **T-12s 到 T** 低清短片段 → 视觉模型 → 中文证据报告 → 缓存 | 比「截图发给大模型」更省 token；比 film-matinee 视觉 sheet 更即时 |
| **陪看停顿点** | 从字幕挑 4-7 处适合讨论的时刻（pause/question/emotion/connection），前端临近弹卡 | 直接对应 Here I am 主动陪伴层的「checkin / 主动开口」机制 |
| **整片理解缓存** | 后台分块字幕 → 模型逐块总结 → 合成整片摘要 → 按 transcript 指纹缓存 | 对应 Memory V3 的 Episode 预生成，一次生成多次复用 |
| **进度跨设备同步** | 前端每几秒上报 currentTime → 后端写 `metadata.watch_progress`；再开时对比 localStorage 取较新 | Here I am 桌面/手机续播语义可直接采用 |
| **直播陪看** | Chrome 前台窗口 screencapture → 视觉模型输出 JSON（summary/ocr/events/uncertainty）→ **只留文本，原图即删**；可选 BlackHole + 本地 Whisper | Here I am 已有悬浮球截图分享，可扩展为「直播陪看 loop」 |
| **直播 TTL** | LiveSession 停止后屏幕上下文 5 分钟过期，无活跃上下文时系统提示禁止引用旧画面 | 防止「AI 拿旧画面当当前事实」的产品级防护 |
| **静音同步** | 用户在原平台看，Cove 只对齐时间线，靠字幕和进度陪聊 | **解决 B 站可控性问题**（B 站 embed 不支持读时间轴）的绝佳方案！ |
| **代理播放** | yt-dlp `-g` 解析真实媒体地址 → HTTP Range 流式转发 → 移动端嵌入失败时兜底 | 移动端 B 站/YouTube 无法 embed 时的退路 |

**Cove 的 MVP 五阶段**值得直接作为 Here I am 的迭代顺序参考（已融入 §六）：

1. 字幕型共影（yt-dlp 抓字幕 + iframe + 问这一幕）
2. 本地视频与代理播放（外挂/内封字幕、Range、移动端兜底）
3. 片段感官层（ffmpeg 短片段 → 视觉模型 → 缓存）
4. 整片记忆（分块摘要 + Obsidian）
5. 直播陪看（截图 + 视觉 JSON + 可选音频转写）

### 2.1 核心参考项目（GitHub）

| 项目 | 星级 | 形态 | 核心思路 | 对本项目借鉴价值 |
|---|---|---|---|---|
| **[wynsyl1014/open-watch-cinema](https://github.com/wynsyl1014/open-watch-cinema)** (32★, MIT) | 本地优先影院 + MCP server | **预生成 AI package**（visual.json + dialogue.json + storyboards/ 按 chunk 分块）→ 播放时 MCP tick 按**游标**增量推送 → **剧透闸门**（AI 只能拿到当前播放进度之前的内容）| ⭐⭐⭐⭐⭐ 架构最完整；字幕/画面双轨、room 归档、danmaku 回放、多 AI consumer 命名规则都可直接参考 |
| **[idleprocesscc/film-matinee](https://github.com/idleprocesscc/film-matinee)** (26★, MIT) | AI 读片工具 + MCP reader | 把电影切成**视觉 sheet**（关键帧 4×4/5×4 + 色带 + 音频 rail）+ **字幕 sidecar**；AI 像读书一样 `film_start` / `film_next` 线性读 chunk；`film_focus_range` 局部精读 | ⭐⭐⭐⭐⭐ 「视觉 sheet」是节省 token 的成熟做法；**字幕 sidecar 与画面描述分离**（不塞进图片）的设计直接可复用 |
| **[Echoes0302/clove-cinema](https://github.com/Echoes0302/clove-cinema)** (15★) | 极简放映室后端 | HTTP Range 流 + `GET /sync/{id}?from=&to=` 按区间增量返回 SRT/VTT/ASS 字幕；不抽帧不依赖 ffmpeg | ⭐⭐⭐ 证明「字幕区间查询」一个端点就能跑通最小陪看；film-matinee 是从它长出来的 |
| **[postoji/rose-cinema](https://github.com/postoji/rose-cinema)** (1★, MIT) | AI 恋人陪看插件 | 同步/异步观影 | ⭐⭐ 思路验证 |
| **[yussica1016/astrbot_plugin_watch_together](https://github.com/yussica1016/astrbot_plugin_watch_together)** (1★, GPL-3.0) | AstrBot 插件 | 同步/异步观影 | ⭐⭐ IM 机器人侧思路 |

### 2.2 关键赋能工具（调轴 / 实时 ASR / 烧录字幕）

| 工具 | 用途 | 调研结论 |
|---|---|---|
| **alass / ffsubsync / sushi**（由 [machinewu/SubtitleSynchroLauncher](https://github.com/machinewu/SubtitleSynchroLauncher) 统一调用的三大成熟调轴工具） | 字幕时间轴 ↔ 音频自动对齐 | 成熟稳定；适合处理「下载的字幕与当前视频版本偏移」 |
| **[ufal/whisper_streaming](https://github.com/ufal/whisper_streaming)** (3.7k★, MIT) | Whisper 实时流式转写 | 标杆实现；但所有陪看项目均未采用（见 §4.4 分析） |
| Apple Vision OCR（macOS 自带） | 烧录字幕识别 | film-matinee 已验证；其他平台需 ML Kit / Tesseract |

### 2.3 小红书社区实践（用户提供帖子，归纳为三档）

| 档位 | 思路 | 成本 | 精度 | 关键坑（社区已踩） |
|---|---|---|---|---|
| **穷鬼套餐版** | 小模型（如 Gemini Flash-Lite）先生成画面描述 → 主力模型只读文字 | 最低 | 中 | 必须给小模型附带电影简介 + 当前时间戳 + 附近字幕，否则只能描述画面无法对应剧情 |
| **经济适用版** | 截图直接发主力多模态模型 | 中（每张图 ~2k tokens） | 高 | 图片别压太狠，画面文字是重要线索 |
| **钞能力豪华版** | 预生成全片 AI 剧本（详细场景+台词描写）→ 播放时实时发当前页剧本 | 最高（"看一部十多块钱"） | 最高 | 冷门作品 AI 会胡编乱造；用户看不到画面 |
| **变体：预生成 + 弹幕** | AI 预先在指定时间点写好评论，播放时按时间触发 TTS | 低 | 高 | 用户沉默时 AI 能主动开口，是「主动陪伴」形态的雏形 |
| **变体：本地+云分工** | 本地小模型做实时性任务，按提前量 handoff 给云模型 | 中 | 中 | 本地模型笨、handoff 有延迟，需提前 ~10 分钟开始处理 |

### 2.4 社区共识（高置信度）

1. **三大必备上下文**：作品基本信息（每次都带）+ 当前时间戳对应的对白 + 当前画面
2. **字幕偏移是真实痛点**：不同发行版本的字幕需要调轴，alass/ffsubsync 是事实标准
3. **剧透管理是产品级需求**：AI 只能知道「已看剧情」，预生成阶段就要做 spoiler gate
4. **观影后必写记忆**：否则 AI 下次就忘了跟你看过这部——这与 Memory V3 的 Episode/Fragment 写入天然契合
5. **实时 ASR 不如平台轨道**：精度、成本、说话人分离全面落败，仅作为无轨道兜底

### 2.5 Cove 指南新增共识（v2）

6. **隐藏 `model_content` 是生产级 prompt 注入方式**：用户看到干净自然对话；模型看到完整证据。前端组包、后端按消息类型分离存取。
7. **证据降级链必须显式**：外挂字幕 → 平台字幕 → 内封字幕 → Whisper → 短片段感官观察 → 诚实承认「证据不足」。**禁止强行编造剧情**。
8. **截图/音频等原始证据即用即删**：分析完成立刻删除，聊天层只保留文本观察。这既是隐私保护也是 token 治理。
9. **直播证据必须有 TTL**：直播截图、转写片段在停止后短期过期，防止 AI 拿旧画面当当前事实。
10. **静音同步是 B 站陪看的正解**：B 站 embed 不支持读时间轴（W4 调研已确认），与其逆向播放器，不如让用户在原平台看、Here I am 只对齐时间线。

---

## 三、四个代表性架构剖析

### 3.0 Cove：「播放层 / 证据层 / 聊天层」三层架构（v2 头号参考）

Cove 的架构是本调研中最具生产完整性的方案。三层严格分离：

```
┌─────────────────────────────────────────────────┐
│ 播放层（只做播放，不做证据）                        │
│   • YouTube iframe / <video> / Chrome 直播前台      │
│   • 移动端嵌入失败 → 后端 yt-dlp -g 解析真实地址     │
│     → HTTP Range 代理转发                          │
│   • 静音同步模式：用户在原平台看，本系统只对齐时间线   │
└─────────────────────────────────────────────────┘
                    ↓ 播放进度上报
┌─────────────────────────────────────────────────┐
│ 证据层（只产文字证据，不留原始媒体）                  │
│                                                   │
│   点播：                                          │
│   ① 字幕获取（外挂>平台>内封>Whisper）              │
│   ② 「问这一幕」: 当前点 ±N 秒字幕窗口              │
│   ③ 「整片聊聊」: 后台分块摘要 → 指纹缓存           │
│   ④ 感官层：ffmpeg 截 T-12s→T 低清片段             │
│            → 视觉模型 → 中文证据报告（含缓存）       │
│   ⑤ 陪看停顿点：从字幕挑 4-7 处讨论时刻             │
│                                                   │
│   直播：                                          │
│   ① screencapture Chrome 前台窗口（15s/次）        │
│   ② 视觉模型 → JSON {summary, ocr, events,         │
│                     uncertainty} → 原图即删        │
│   ③ 可选 BlackHole + 本地 Whisper（20s 录 8s）     │
│   ④ LiveSession 内存态：40 条观察 + 12 条转写      │
│      停止后 5 分钟 TTL 过期                        │
└─────────────────────────────────────────────────┘
                    ↓ 隐藏 model_content
┌─────────────────────────────────────────────────┐
│ 聊天层                                            │
│   sendChat({ content: userText,                  │
│              model_content: 证据包 })             │
│   用户看到干净对话; 模型看到完整证据                │
│   约束规则: 只引用播放点之前内容 / 不编造 /          │
│             无证据时如实承认 / 区分事实与主观判断    │
└─────────────────────────────────────────────────┘
```

**与 Here I am 的直接映射**：
- 播放层 ≈ 白板 `PlayerAdapter`（已有）
- 证据层 ≈ W4 字幕线 + 新增 WatchingSessionService + 新增 SensoryCacheService
- 聊天层 ≈ 现有 PersonaChat + 新增 `model_content` 字段 + Companion Agent 的 prompt 模板
- 陪看停顿点 ≈ 主动陪伴层 checkin
- 直播陪看 ≈ 悬浮球截图分享的扩展（直播模式循环截图）
- 整片理解缓存 ≈ Memory V3 Episode 预生成

### 3.1 open-watch-cinema：「房间 + 剧透闸门 + MCP」架构（原 v1 主参考，现居次位）

```
┌─────────────────────────────────────────────────┐
│ 准备阶段（手动触发，可断点续传）                    │
│   扫描视频 → FFprobe → 提取内嵌字幕 → WebVTT      │
│   → 按 chunk 生成 AI package:                    │
│     chunk-0000/{visual.json, dialogue.json,      │
│                 storyboards/}                    │
│   → manifest.json 记录全片索引                    │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│ 播放阶段（房间 Room，单活）                        │
│   用户开房间 → 时间戳打点                         │
│   AI 通过 stdio MCP 调用:                        │
│     open_watch_cinema_tick(consumerName, cursors) │
│       → 返回: 播放状态 + 新消息 + 剧透闸门后的字幕  │
│              + storyboard 选择 + scene 事件       │
│     cinema_get_frame(storyboardRef, mediaTimeMs)  │
│       → 按需取特定帧（带剧透闸门）                 │
│     发送 timed message                            │
│                                                   │
│   ★ 关键设计: consumerName + cursor 持久化        │
│     多 AI/跨会话恢复时各自保持独立进度              │
│   ★ 归档 room 仍可回放弹幕，但写入被拒绝            │
└─────────────────────────────────────────────────┘
```

### 3.2 film-matinee：「线性读片 + 视觉 sheet」架构（适合低带宽/离线）

```
电影 → 切成 N 个 chunk：
  每个 chunk = 1 张视觉 sheet（4×4 关键帧阵列 + 色带 + 音频 rail）
            + 1 份字幕 sidecar（VTT 文本，含说话人标签）
            + annotations.json（AI 批注 + 用户回复）

AI 阅读方式（MCP）:
  film_start(manifest)  → 返回第 0 节 + 观影 tips
  film_next(manifest)   → 下一节；还没生成完返回 waiting
  film_focus_range(start, end, detail="dense")
                        → 局部精读 5 分钟，5×4 更密 sheet
  film_note(chunk, text, timecode)
                        → AI 写批注，前端实时显示

★ 字幕优先级（与本项目 W4 调研完全一致）:
  内嵌/外挂人工字幕 > 平台自动字幕 > 烧录字幕 OCR > 本地 Whisper ASR
★ 字幕与画面分离: 字幕走文字 sidecar，不塞进图片，token 极省
```

### 3.3 小红书经济适用版：「无预处理 + 实时截图」架构（最简单）

```
播放中，发消息时实时组包:
  prompt = 作品简介 + 当前时间戳 + 附近 ±30s 字幕 + 当前画面截图
         + 角色设定 + 记忆 + 聊天上下文
  → 发给主力多模态大模型 → 返回回复

优点: 零准备、零存储、随看随聊
缺点: 无剧透保护(模型可能剧透)、无结构化进度、成本随消息数线性
适用: 偶尔看一次的热门作品
```

---

## 四、关键设计维度对比

### 4.1 时机：预处理 vs 实时

| 方案 | 预处理 | 实时 | 代表 |
|---|---|---|---|
| 剧本/字幕 | 完整剧本预先提取、AI 预写章节评论 | 播放时按游标喂 | open-watch-cinema、小红书豪华版 |
| 画面 | 预生成 storyboard/关键帧阵列 | 播放时按需取帧/实时截图 | film-matinee（预）、经济适用版（实时）|
| 评论触发 | 预埋在特定时间点 | 用户说话才回 | 弹幕/TTS 变体（预）、主流（实时）|

**调研结论**：**混合式最优**——字幕与视觉概要预处理，对话与情感回应实时。

### 4.2 上下文窗口策略

| 策略 | 做法 | token 成本 | 精度 |
|---|---|---|---|
| 纯文本剧本 | 只发当前页剧本文字 | 极低 | 依赖剧本质 量；冷门作品翻车 |
| 文本 + 画面描述 | 小模型先生成描述，主模型读 | 低 | 中 |
| 文本 + 截图 | 截图直接进多模态 | 中（~2k/张） | 高 |
| 视觉 sheet | 一张大图包含 16-20 个关键帧 + 色带 | 低-中（1 张图顶 16 张） | 中高（时序信息以空间换）|
| 全量多帧 | 每 N 秒截图全部发 | 极高 | 高但不必要 |

### 4.3 剧透闸门（spoiler gate）实现

open-watch-cinema 的做法值得直接借鉴：
- 所有 MCP tick / frame 请求都带 `mediaTimeMs`
- 服务端只返回 `mediaTimeMs ≤ 当前播放进度` 的字幕、观察事件、帧
- AI 消息带时间戳存库，归档后可按时间回放
- **对 Here I am 的映射**：林埃的「已看剧情」可以直接复用 Memory V3 的 Fragment（按 watching session 聚合），`current_position_ms` 就是闸门水位线

### 4.4 感官层（v2 新增维度 — Cove 独有）

Cove 首次给出的「感官层」设计超越了简单的实时截图方案：

| 维度 | Cove 做法 | Here I am 是否采纳 |
|---|---|---|
| 触发时机 | 「问这一幕」时才采集，不做周期循环 | ✅ 采纳 — 点播不预先烧 token |
| 窗口 | 截 T-12s 到 T 的短片段（**不取 T 之后**，防剧透） | ✅ 关键设计，直接采纳 |
| 降规格 | ffmpeg 输出低清 mp4，降低分辨率/帧率/码率 | ✅ 采纳 |
| 输出 | 中文证据报告（文字），**原始视频不进主聊天模型** | ✅ 采纳 |
| 失败降级 | 感官模型慢/失败 → 自动回退仅字幕 | ✅ 采纳 |
| 缓存 | 同一时间点重复提问不重复消耗；按数量/大小/时间清理 | ✅ 采纳，与 W5 缓存治理一致 |
| 直播差异 | 直播改为 15s/次 循环采集 + 视觉 JSON {summary, ocr, events, uncertainty} | ✅ Phase 4 采纳 |

**关键洞察**：感官层不是「实时发截图」也不是「预生成全片 sheet」，而是**按需的、滑动窗口的、降级安全的短时视觉取证**。这比小红书经济适用版的「实时截图发给主模型」（每张 ~2k tokens）省得多。

### 4.5 陪看停顿点（v2 新增维度 — Cove 独有）

```
基于字幕挑选 4-7 处时刻（pause/question/emotion/connection）
     ↓
前端播放临近时弹出提示卡片（不强制打断）
     ↓
用户点击「暂停聊聊」才暂停并提交上下文；不点则跳过
```

**对 Here I am 的映射**：这就是主动陪伴层（Companion Checkin）的视频垂直版本。林埃已有 checkin 能力，把它接到播放器时间轴即可。**比小红书「预生成 + 弹幕」变体更主动、更克制**——用户不点就不打断。

### 4.6 直播 TTL 与诚实原则（v2 新增维度 — Cove 独有）

| 场景 | 风险 | Cove 防护 |
|---|---|---|
| 直播截图 | AI 拿 5 分钟前画面当「现在」 | 停止后 5 分钟 TTL 过期；无活跃上下文时系统提示禁用旧画面描述 |
| 直播转写 | 旧音频被当当前讨论话题 | 最多保留 12 条；滚动窗口 |
| 感官缓存 | 同时间点重复提问重复消耗 | 按 transcript 指纹缓存；命中直接复用 |
| 代理播放 | 上游直链过期导致缓存失效 | 检测过期自动清除并重新解析 |

**对 Here I am 的映射**：与 i 连续性的「authority=agent_inferred, trust_level=trusted_client_unverified_content」诚实框架兼容——**所有证据必须带时间戳，AI 必须区分事实与推测**。

### 4.7 为什么都不做实时 ASR 陪看

调研了 5 个陪看项目 + 小红书多档方案 + Cove（v2），**没有一个在实时陪看主链路用 ASR**：

1. **成本**：Whisper 流式转写一部 2 小时电影 ≈ 几个小时 GPU 时间或高昂 API 费
2. **延迟**：流式 ASR 有 3-10s 延迟，破坏「一起看」的同步感
3. **质量**：无说话人分离时台词归属混乱；有分离也错误率高
4. **替代品更好**：电影有完整字幕、B 站有 CC/AI 字幕、YouTube 有 timedtext——**平台轨道是免费的、精确的、带时间戳的**

**Cove 的强化论证（v2 新增）**：Cove 把 ASR 严格限制在两个边缘场景——
- 点播：字幕四级降级链（外挂 → 平台 → 内封 → Whisper）的最后一级
- 直播：可选 BlackHole + 本地 Whisper 作为视觉观察的补充
- **关键原则**：「仅保存文本，音频文件不送入聊天模型」

**唯一需要 ASR 的场景**：平台/内嵌字幕都没有、画面也没有烧录字幕的极端冷门视频。film-matinee 与 Cove 一致的处理值得照搬：
- 默认不触发（`audio_transcript="auto"`）
- 用户显式选 `"local"` 才下载 Whisper 模型
- ASR 结果与原字幕分栏保留，不静默合并
- 原始音频即用即删

---

## 五、与 Here I am 现有架构的映射

### 5.1 与 W4 视频研读线（白板）的关系

**上一轮 W4_SUBTITLE_RESEARCH 解决的是「轨道从哪来」——这正是「一起看」的输入层。**

| 层级 | W4 字幕线（已有/待做） | 「和 AI 一起看」（本报告新增） | 耦合点 |
|---|---|---|---|
| 数据获取 | YouTube timedtext、B 站 CC/AI 字幕、bcc 解析、`TimedTextTrack` | —（直接用 W4 产出的 track） | ✅ **完全复用** |
| 数据存储 | `TimedTextCue` 列表，session 内存 | 需要落地为**视频版本的长期资产**（按 sourceId + versionId 存于白板 repository） | 🟡 需要新增 `WatchingSession` 实体 |
| 时间轴 | `PlayerAdapter.currentPositionMs` + `seekTo` | 同上 | ✅ **完全复用** |
| Anchor | 点/区间 Anchor，绑定 cueId | 同上（批注 = Anchor + Card） | ✅ **完全复用** |
| AI 对话 | — | **新增**：watching session 里的林埃发言流 | 🟡 新增 WatchingChatService |
| 主动开口 | — | **新增**：按 cue 时间点预触发的发言（弹幕/TTS） | 🟡 新增 SpoilerGate 水位线 |
| 剧透闸门 | — | **新增**：按 `current_position_ms` 过滤未来 cue | 🟡 新增 |
| 画面感知 | — | **新增**：周期性关键帧截图 → 视觉描述（可选） | 🟢 可选层 |
| 记忆沉淀 | — | **新增**：session 结束写 Episode/Fragment | 🟡 接 Memory V3 |

**结论**：两条线在白板 `video_study_screen` 上汇合，各管一层。

### 5.2 与 Memory V3 / 角色关系层的契合

- **观影 session 天然就是 Episode**：一次完整的「看 X 到 Y 分钟」是一个有时间边界、有情绪波动、有共同经历的 Episode，与 Dreaming 的批处理触发条件一致
- **剧透闸门 = 权限边界**：林埃只能引用「已看剧情」的设计，与 i 连续性中「source_trust`、`authority: agent_inferred`」的诚实原则同构
- **林埃预写评论 → 定时 TTS**：正好落在「主动陪伴层」，与 checkin、提醒等能力共用触发框架

### 5.3 与桌面白板路线的契合

- W5 桌面 AI 工作台已确认 RuntimeAdapter + restricted whiteboard 读写工具的架构。观影 session 的「林埃预写弹幕 + 用户看时点回应」可以直接复用**行动卡 + 批次撤销**机制（弹幕卡 = 行动卡，一部电影的弹幕 = 一个 batch，可整批撤销）
- Windows 桌面已有 `WindowsYouTubePlayerAdapter`（WebView2 + IFrame API），`currentPositionMs` 可读——**Windows 端「一起看 YouTube」所需的所有底层都已就位**，缺的只是上层的 session / 闸门 / 对话编排

### 5.4 与悬浮球 / 分享截图机制的契合（v2 新增）

Cove 的直播陪看（截 Chrome 前台 → 视觉 JSON → 只留文本）与 Here I am 已有的全局悬浮球截图分享在**机制层面同构**：

| Here I am 已有能力 | Cove 直播陪看的对应 | 对接点 |
|---|---|---|
| 全局悬浮球截图分享 | screencapture 15s/次 循环 | 悬浮球提供「直播陪看模式」选项：开启后自动周期截图 |
| 截图 → LLM 总结 → 卡片 | 视觉 JSON → 文字观察 → 隐藏 model_content | 复用同一管道，仅把「保存卡片」换成「送入主聊天」 |
| Android 无障碍服务 + Tailscale Bridge | Cove 后端 FastAPI / 本地 127.0.0.1 | Here I am 桌面侧已有 Bridge URL（`https://host.example.invalid`）可直接复用 |
| 用户主动触发 | 手动 capture / 15s 自动循环 | 直播模式默认循环；点播模式手动触发 |

**结论**：Phase 4 直播陪看**不需要新建后端**——悬浮球 + Bridge + 现有视觉 LLM 通道就能组装出来。

---

## 六、给 Here I am 的落地路线建议

### Phase 0 — 继续完成 W4 字幕线（前置，已在 W4_SUBTITLE_RESEARCH 中规划）

- 落地 `BilibiliTimedTextService`（B 站 AI/CC 字幕，~300 行 Dart）
- 修 `LinkIngestor` 对 bilibili 的 unsupported
- YouTube transport UA/诊断

### Phase 1 — 「字幕型共影」最小闭环（Windows 桌面 + YouTube 先行）

对应 Cove MVP 阶段一 + 阶段二子集。

目标：让林埃能陪用户看完一部已经有字幕的 YouTube 视频。

1. **新增 `WatchingSessionService`**（`lib/domain/whiteboard/video/watching/`）：
   - 字段：`session_id`、`source_id`、`source_version_id`、`started_at`、`current_position_ms`、`seen_cue_ids`、`lin_ai_message_cursor`、`whole_context_cache_id`（可空）
   - 每 5s 记录 current_position_ms（白板已有 PlayerSyncController 在推送）
   - 结束 session 时计算 Episode 指纹并按需触发 Memory V3 写入
2. **新增 `SpoilerGate`**：
   - `List<TimedTextCue> visibleCues(int positionMs)` — 只返回 `endMs <= positionMs` 的 cue
   - `List<TimedTextCue> recentCues(int positionMs, {Duration window = 30s})` — 当前上下文
   - `List<TimedTextCue> recentContextCues(int positionMs, {Duration window = 5min})` — 前情字幕（可空关闭）
3. **新增 `WatchingChatBridge`**：
   - 用户按「问这一幕」→ 前端组包 `{content: 用户问题, model_content: 证据包}` → 走现有 Companion Agent
   - **证据包固定结构（对齐 Cove 2.6）**：作品标题、当前精确时间点、附近字幕、前情字幕、原文/中文（如可得）、防剧透规则、可选感官报告
   - 回答落盘为行动卡，绑定 Anchor（点 Anchor，cueId 关联）
4. **记忆写入**：session 结束时把「看了 X 到 Y 分钟 + 讨论了 Z」写为 Fragment；用户明确保存的高光时刻单独成 Card

**不做**：弹幕、TTS、感官层、整片理解缓存、陪看停顿点、直播——等真实用户反馈再加。

### Phase 2 — 陪看停顿点 + 整片理解缓存

对应 Cove MVP 阶段四子集 + Cove 2.8/2.9。

- **陪看停顿点**：W4 字幕就绪后，从 cue 列表挑 4-7 处讨论时刻；前端临近弹卡；用户点击才暂停
- **整片理解缓存**：后台分块摘要 → 按 transcript 指纹缓存 → 用户点「整片聊聊」时直接作为 `model_content` 主体
- **跨 session 检索**：历史 WatchingSession 的 Episode/Fragment 已可检索，林埃回答时引用

### Phase 3 — 感官层 + B 站接入

对应 Cove MVP 阶段三 + 本报告 §4.4。

- W4 的 `BilibiliTimedTextService` 落地后，同一套 WatchingSession / SpoilerGate / ChatBridge 直接可用
- **新增 `SensoryCacheService`**：
  - 用户「问这一幕」时若感官缓存未命中 → ffmpeg 截 T-12s→T 低清片段 → 视觉模型 → 中文证据报告
  - 失败自动降级回字幕模式
  - 缓存按 transcript 指纹 + 时间点索引
- **弹幕形态**：林埃的发言以弹幕形式滚动，参考 open-watch-cinema 的「消息+时间戳存档，回放时按时间触发」；弹幕卡 = 行动卡

### Phase 4 — 直播陪看（v2 新增）

对应 Cove MVP 阶段五。

- **直播 WatchingSession 变体**：`LiveWatchingSession`（参考 Cove 3.4）——内存态、有 TTL、无 Anchor
- **视觉循环**：悬浮球开启「直播陪看模式」→ 每 15s 截图 → 视觉模型输出 JSON `{summary, ocr, events, uncertainty}` → 原图即删
- **音频（可选，移动端初期跳过）**：Android 走 `MediaProjection` 系统音频录制 → 本地 ML Kit / Whisper
- **隐藏 `model_content` 合并**：用户发消息时自动注入最近 3 分钟屏幕观察 + 2 分钟音频转写（对齐 Cove 3.5）
- **TTL 防护**：session 停止 5 分钟后上下文过期；系统提示禁止引用旧画面（对齐 Cove 3.7）

### 明确不做的事

- ❌ 实时 ASR 陪看主链路（成本高、延迟差、有替代）
- ❌ 多 AI/多用户同步房间（单用户单林埃先行）
- ❌ 自动对全片做 AI 剧本预生成（豪华版方案）——除非用户明确点播且有热门作品背书
- ❌ 跨设备同步播放（局域网/公网房间）
- ❌ 把观影过程自动写 User-truth（遵守记忆契约，仍需用户显式记录）
- ❌ 自建 B 站/YouTube 移动端播放器（先用 iframe / 静音同步，代理播放作为 Phase 4 可选兜底）
- ❌ 直播音频 ASR 默认开启（用户显式启用 + 仅保存文本）

---

## 七、风险与注意事项

1. **剧透是产品级功能，不是 nice-to-have**：任何「一起看」实现都必须有 spoiler gate，否则林埃会剧透结局。open-watch-cinema 的 cursor + mediaTimeMs 模式可直接借鉴。
2. **字幕偏移真实存在**：用户外部导入的 SRT 可能与视频版本不匹配。短期 UI 提供手动 ±N 秒微调；长期可接 alass/ffsubsync（两者都是 GPL-3.0，需注意传染性）。
3. **弹幕形态需克制**：弹幕天然是公共场域的形式，Here I am 是私密陪伴。弹幕只作为显示样式选项，不引入公开弹幕池。
4. **成本透明**：如开启感官层 / 直播陪看，必须在 UI 清楚标注当前模式的预期 token 消耗（穷鬼/经济/豪华三档概念可直接借用）。
5. **许可证警示**：参考项目大多是 MIT/Unlicense，可放心借鉴架构；但 alass/ffsubsync 是 GPL-3.0，如需直接集成考虑以进程调用方式隔离，或仅作算法参考自行实现。
6. **直播证据 TTL 必须实现**（v2 新增）：直播截图、转写、感官观察在 session 停止后必须短期过期（Cove 用 5 分钟）。**没有 TTL 的直播陪看 = 隐私 + 诚实双重风险**——AI 可能拿旧画面当当前事实，且长期保留原始截屏违反「证据即用即删」原则。
7. **感官层缓存治理**（v2 新增）：感官报告缓存按 transcript 指纹 + 时间点索引，命中即复用；按数量/大小/时间三维清理；不命中也不重复消耗资源。
8. **代理播放合规边界**（v2 新增）：Cove 的移动代理播放基于 `yt-dlp -g` 解析真实媒体地址——这条路径在 W4 调研中已标注为「依赖持续对抗 YouTube 反爬」。Here I am **默认不启用**，只在 embed 完全不可用时作为用户明确开启的兜底。同时明确禁止用于 DRM 内容。
9. **隐藏 `model_content` 不应被滥用**（v2 新增）：所有塞进 `model_content` 的证据都必须在用户可见 UI 上有「证据来源」提示（例如「林埃看到了 12:34-12:50 的字幕」），避免用户对 AI 知道什么一无所知。
10. **静音同步的产品表达**（v2 新增）：B 站陪看采用静音同步时，UI 应明确表达「我看到的是字幕时间线，不是你的屏幕」——避免用户误以为 Here I am 能看到 B 站播放器内的画面。

---

## 八、与上一轮 W4 字幕调研的互补关系确认

回答用户问题——**两线互补关系非常强，且不重叠**：

| | W4 字幕抓取线 | 「和 AI 一起看」线 |
|---|---|---|
| 解决的问题 | 轨道**从哪来**（YouTube timedtext / B 站 CC/AI 字幕 / bcc 解析） | 轨道**拿来干什么**（陪看 / 弹幕 / 记忆） |
| 核心产出 | `TimedTextTrack` + cues | `WatchingSession` + Anchor 卡 + Episode 记忆 |
| 技术重心 | HTTP API 调用、JSON 解析、WBI/Cookie | 时间轴闸门、prompt 组织、记忆沉淀、主动触发 |
| 失败模式 | 抓不到字幕 → 「需要字幕」诚实降级 | 没有字幕 → 沿证据降级链退到感官层或诚实承认「证据不足」 |
| 共享契约 | `PlayerAdapter` / `TimedTextTrack` 只读 | 同上；新增 `WatchingSession` 与 SpoilerGate 不动共享契约 |
| 落地顺序 | **必须先做**（没有轨道谈什么陪看） | 轨道就位后自然展开 |

**关键洞察**：用户在小红书帖子里担心的「普通视频没有完整剧本」问题，恰好就是 W4 字幕线要解决的问题——B 站的 AI 字幕就是「普通视频的现场剧本」。两条线在 B 站 AI 字幕这个点上完美扣合。

**v2 互补关系补充**：Cove 指南的「静音同步」方案给出了 B 站陪看的第三条路——既不需要可控播放器、也不需要逆向 B 站的播放器 API，只用户在原平台观看、Here I am 对齐时间线、字幕轨道供证据。这绕开了 W4 矩阵中「B 站无可控播放接口」的硬伤，让 B 站陪看在 W4 字幕落地后即可启动，**无需等待 B 站播放器 adapter 进化**。

---

## 九、下一轮可启动的最小工作流

如果按《白板并行开发总纲》继续，可以开一个新工作流（暂称 W7 — Watching Session）：

```text
工作流：W7 / 和 AI 一起看视频
本轮目标：Windows + YouTube 最小闭环——WatchingSessionService + SpoilerGate + 用户按时间点提问的行动卡
拥有路径：lib/domain/whiteboard/video/watching/、lib/ui/whiteboard/video/watching/、对应 test/ 目录
读取契约：本报告 + W4_SUBTITLE_RESEARCH.md + W4_VIDEO.md + 白板总纲
共享契约：只读 PlayerAdapter / TimedTextTrack / AnchorContract；新增 WatchingSession 为新实体
明确不做：弹幕、TTS、画面感知、多 AI 房间、ASR、自动写 User-truth、B 站（等 W4 落地）
验证：flutter test test/domain/whiteboard/video/watching/；真实视频（带字幕 YouTube）端到端 session
```

W7 依赖 W4 字幕线落地完成后再启动。

---

## 附录 A：参考项目许可证一览

| 项目 | 许可证 | 可否商业复用 | 备注 |
|---|---|---|---|
| **Cove 共影指南**（小红书 427689021） | 用户私有指南，用户提供 | ✅ 用户授权本次调研 | **头号参考**；直播陪看 + 隐藏 model_content + 感官层 + 三级 MVP |
| open-watch-cinema | MIT | ✅ | 副架构参考：剧透闸门 + MCP + 房间归档 |
| film-matinee | MIT | ✅ | 视觉 sheet 思路参考 |
| clove-cinema | 未声明（README 说 MIT） | ⚠️ 需向作者确认 | 字幕区间 API 思路 |
| rose-cinema | MIT | ✅ | |
| astrbot_plugin_watch_together | GPL-3.0 | ⚠️ 传染性 | 仅思路 |
| yutto | GPL-3.0 | ⚠️ 传染性 | 字幕 API 调研已完成，不引入代码 |
| yt-dlp | Unlicense | ✅ | 桌面 sidecar 参考；代理播放兜底 |
| alass / ffsubsync / sushi | GPL-3.0 | ⚠️ 传染性 | 调轴：进程调用或算法参考 |
| bcc2ass | Unlicense | ✅ | bcc 格式权威定义 |
| whisper_streaming | MIT | ✅ | 如未来做 ASR 兜底（直播可选/点播末位） |

## 附录 B：小红书帖子核心洞察摘要（用户提供的帖子内容）

- 「热门电影一张截图 + 对白，AI 大部分时候能判断剧情」→ 热门作品低成本方案可行
- 「冷门作品 AI 会胡编乱造」→ 诚实原则提示需要「我不知道这部作品」的坦白能力
- 「省 token 版 AI 看不到画面、会忘记剧情」→ 记忆写入是必须的，不是可选
- 「手机计时器微调进度 + 麦克风常开」→ 手机端陪看的输入形态参考
- 「弹幕形式 + 沉默时 AI 主动 TTS」→ 主动陪伴触发机制参考
- 「本地+云分工 + 10 分钟提前量」→ 分层模型调度参考，但 Here I am 暂不需要
- 「字幕偏移是真实痛点，有半自动对齐工具」→ 调轴功能长期需考虑
- 「烧录字幕 OCR 候选 + 手动选择 + 自动对齐」→ 半自动工具思路可借鉴

## 附录 C：Cove 指南关键 API 与文件结构摘录（v2 新增）

为方便后续实现时直接对齐 Cove 的设计，摘录其关键 API 形状（完整文档见用户提供的 Markdown 原始稿）。

### C.1 共影后端接口（FastAPI 风格）

```
POST /api/videos/from-url          # 链接导入，后台抓字幕
POST /api/videos/upload            # 本地上传
POST /api/videos/{id}/subtitles    # 上传外挂字幕
GET  /api/videos/{id}/transcript-window  # 当前时间点附近字幕
POST /api/videos/{id}/watch-message      # 生成「问这一幕」隐藏 model_content
POST /api/videos/{id}/watch-message/warmup  # 预热感官缓存
POST /api/videos/{id}/companion-moments   # 陪看停顿点（4-7 处）
POST /api/videos/{id}/whole-context/start # 生成整片理解缓存
GET  /api/videos/{id}/whole-context/status
GET  /api/videos/{id}/mobile-stream       # 移动端代理播放（yt-dlp -g）
POST /api/videos/{id}/progress            # 跨设备进度同步
GET  /api/videos/{id}/captions.vtt        # WebVTT 输出
```

### C.2 直播陪看接口

```
GET  /api/live/status
POST /api/live/start       # {source: "chrome", visual_interval: 15, audio_enabled, ...}
POST /api/live/stop
POST /api/live/capture     # 手动单帧
POST /api/live/context     # 生成隐藏 model_content
```

### C.3 LiveSession 内存结构

```
LiveSession
  session_id, source, status(running/stopped/screen)
  visual_interval, audio_enabled, audio_interval, audio_chunk_seconds
  observations[]   # 最多 40 条（画面观察 JSON）
  transcripts[]    # 最多 12 条（音频转写文本）
  errors[]
  last_frame_at, last_audio_at
  # 停止后屏幕上下文 5 分钟 TTL，过期自动清理
```

### C.4 「问这一幕」隐藏上下文固定结构

```
1. 视频标题
2. 当前精确时间点
3. 当前时间点附近字幕
4. 最近前情字幕
5. 原文字幕 + 中文字幕
6. 防剧透规则：只引用播放点之前内容，禁止推测后续剧情
7. 可选：当前片段感官报告（T-12s → T 低清片段的视觉模型中文报告）
```

### C.5 直播视觉观察 JSON Schema

```json
{
  "summary":     "这一帧发生什么（一句话）",
  "ocr":         "画面可读文字：价格、标题、弹幕",
  "events":      "值得记住的客观事件（数组）",
  "uncertainty": "模糊或非直播窗口的说明"
}
```

### C.6 数据表字段

`videos` 表：`video_id, title, source_type, source_url, video_path, public_url, status(pending/processing/ready/ready_partial/failed), duration, transcript_path, transcript_zh_path, contact_sheet_path, companion_json, metadata_json, created_at, updated_at`

文件缓存：`data/videos/<video_id>/{platform_subtitle.*, external_subtitle.*, *.transcript.txt, sensory_context/*.json, deleted_video_record.json}`

**长期保存的是文字证据与轻量缓存，不是视频本体。**

---
