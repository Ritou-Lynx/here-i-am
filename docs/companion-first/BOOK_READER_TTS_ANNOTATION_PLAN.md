# 小说阅读器：本地听书与划线批注方案

> 状态：划线批注基础版已落地；R0 App 内音色实验室已落地，等待真机赛马  
> 日期：2026-08-11  
> 范围：当前 TXT 小说阅读器；EPUB / PDF 后续复用同一定位模型

## 1. 目标

把小说阅读从“能打开、能继续看、能和林埃聊”推进到可以逐步替代微信读书的日常入口：

1. 免费、本地、尽量自然的 TTS 听书。
2. 可暂停、后台与锁屏播放、退出 App 后仍能续听。
3. 看书和听书共用同一套语义进度，林埃知道用户实际推进到了哪里。
4. 从当前阅读位置开始听，或回到上次暂停位置继续听。
5. 支持划线、写批注、回看与修改感想。

本文把用户口述的“bgm 书”先解释为后台 / 锁屏连续听书。如果实际还需要在人声下铺背景音乐，放到听书主链稳定后的独立混音阶段，不阻塞首版。

## 2. 现状与缺口

当前 `BookReaderScreen`：

- 章节正文是一个 `SelectableText`，支持系统复制，但没有自定义划线或批注。
- 阅读进度只有 `chapterNumber + scrollRatio`；滚动比例与文字位置、TTS 句子无法稳定互相换算。
- 切到章节底部会自动进入下一章。
- 共读会话只知道作品和章节，不知道章内具体读到哪一句。
- 现有 `TtsService` 只路由 MiniMax / ElevenLabs 云端角色语音，不适合长时间听书的成本和断点需求。
- 项目已经依赖 `sherpa_onnx 1.13.2` 和 `just_audio`，前者本身已有离线 TTS Dart API，后者可继续承担音频播放。

因此不能直接把正文整章丢给现有角色 TTS。应先建立稳定的文本定位层，再让屏幕阅读、听书和批注都使用同一坐标。

## 3. TTS 选型

### 3.1 微信读书能借鉴什么

微信 AI 在 2021 年公开过与微信读书合作的方案：声学侧使用 Tacotron + Parallel WaveNet；热门书提前合成并缓存，未缓存内容在线合成，客户端朗读当前句时预取下一句。它是云端生产系统，不是可直接复用的本地引擎。当前微信读书是否已经更换模型没有权威公开说明，因此不把旧公开架构当成 2026 年现状。

可借鉴的是三个产品原则：

- 按句 / 短段切分，而不是整章阻塞生成。
- 播放当前段时预生成后续段。
- 音频缓存键包含模型、音色、语速和文本摘要，重复收听不重复合成。

### 3.2 推荐路线

第一候选：`sherpa-onnx + Kokoro multi-lang v1.1 int8` 可下载音色包。

- 完全离线，支持中英文混读。
- 103 个 speaker，其中 100 个中文音色（55 女、45 男）。
- Kokoro 中文模型权重标注 Apache-2.0；发布前仍需对完整模型包和随包词典逐项留存许可证。
- 项目已有 sherpa-onnx，不再增加第二套原生推理运行时。
- 采用 int8 包控制存储和内存；模型不塞进 APK，首次启用时单独下载，可删除。

第二候选：`sherpa-onnx + vits-melo-tts-zh_en`。

- 中文 / 英文单音色，官方模型表给出的模型文件约 163 MB。
- 音色选择少，但可能更适合作为低存储、低性能设备的轻量包。

兜底：Android 系统 TTS。

- 不新增模型下载，启动快。
- 实际音质、是否真离线、可用音色取决于用户安装的系统引擎，设备间不一致。
- 适合作为“本地模型未下载 / 设备跑不动”时的降级，不作为默认品质承诺。

暂不选：把 MiniMax / ElevenLabs 当听书默认引擎。它们继续服务林埃的角色语音；长书按量调用成本高，也不能保证无网续听。Piper 中文音色和自然度不作为首轮重点。

### 3.3 先做真机音色赛马

不凭网页样音直接定默认音色。使用同一组 2–3 分钟中文测试稿，在主力手机和墨水屏设备各测：

- 叙事、对话、数字日期、中英混读、多音字。
- 首句等待、实时率、连续 20 分钟温度 / 耗电 / 内存。
- 0.8x、1.0x、1.25x、1.5x 的可懂度和机械感。
- Kokoro int8 的 6–10 个候选中文 speaker；MeloTTS；设备系统 TTS。

通过门槛：1.0x 能稳定边生成边听；连续播放无明显段间空洞；主力手机不发烫到影响使用；墨水屏至少能用轻量包或系统 TTS 兜底。

## 4. 统一定位模型

### 4.1 不再让 `scrollRatio` 做唯一事实

定义统一 `ReadingLocator`：

```text
bookId
chapterNumber
charOffset        // 规范化章节正文中的 UTF-16 offset
blockIndex        // 冗余加速定位，可由 charOffset 重建
contentFingerprint
updatedAt
```

章节导入后先做确定性的正文规范化，并切成段落 / 句子块。每个块保存 `startOffset` 和 `endOffset`。屏幕、TTS、划线全部引用这些字符区间。

保留 `scrollRatio` 仅用于旧数据迁移和布局恢复兜底，不再用它表达“读到了哪句话”。

### 4.2 同时保留三个位置

一本书需要三个相关但不同的定位：

| 位置 | 含义 | 更新时机 |
|---|---|---|
| `visualLocator` | 当前屏幕正在看的位置 | 用户滚动、跳章、点划线 |
| `audioResumeLocator` | 上次听书暂停 / 中断的位置 | 播放中、暂停、后台销毁前 |
| `furthestLocator` | 已经看过或听过的最远位置 | 两种模式推进时只向前更新 |

听书播放时，同时推进 `audioResumeLocator`、`visualLocator` 和 `furthestLocator`。手动滚动只更新 `visualLocator`；这样用户翻回前文不会抹掉上次听书位置，也不会降低总体进度。

### 4.3 “从哪里开始听”

用户点听书时：

- 如果当前屏幕位置和上次听书位置非常接近，直接继续，不弹窗。
- 如果两者跨段明显或跨章节，弹一个底部选择：
  - `从当前开始`：显示当前章节与截断的一句文字。
  - `继续上次听到的地方`：显示上次章节、句子和时间。
- 记住本次选择只影响本次启动，不设置永久偏好，避免以后误跳。

播放开始后正文自动滚到当前朗读句，并做低干扰高亮。用户手动滚动查看前后文时不强行拉回；显示“回到正在朗读”按钮。

## 5. 听书播放架构

### 5.1 队列

1. 从选择的 locator 找到所属句子。
2. 将正文切成约 10–25 秒的语义段，保留每段的 `startOffset/endOffset`。
3. 后台 isolate 用本地 TTS 生成 WAV / PCM 文件。
4. 播放当前段时预生成后 3 段，缓存上限按磁盘空间滚动清理。
5. `just_audio` 播放本地段队列，段完成后把语义进度推进到 `endOffset`。

缓存键至少包含：`modelVersion + speakerId + speed + normalizedTextHash`。切换模型、音色或语速不会误用旧音频。

### 5.2 暂停与精确续播

持久化：

- 当前语义段的 `startOffset/endOffset`。
- 当前段的 `positionMs`。
- 模型版本、speaker、语速。
- 播放状态更新时间。

正常暂停后从段内毫秒位置继续。若缓存被删、模型改变或音频校验失败，则安全回退到当前句开头，不跳过内容。

进度写入采用“播放中每 2–3 秒节流 + 暂停 / 章节切换 / App 生命周期变化时立即写”，不要每个音频采样点写数据库。

### 5.3 后台和锁屏

引入 `audio_service` 承担后台媒体会话，播放状态由 AudioHandler 作为单一事实源：

- 通知栏 / 锁屏：播放、暂停、上一段、下一段、快退 15 秒、快进 30 秒。
- 耳机按键与系统音频焦点。
- 电话、导航等打断后保持暂停位置；是否自动恢复遵循音频焦点策略。
- 通知显示书名、章节和当前句摘要。

不要复用当前聊天角色 TTS 的 `_audioPlayer` 状态机。角色说话与听书属于两类会话，需要一个明确的音频仲裁器：开始听书时停止角色 TTS；林埃来电 / 语音通话开始时暂停听书，结束后提示是否继续。

## 6. 划线与批注

### 6.1 交互

沿用原生文本选择手势，在系统复制菜单旁增加：

- `划线`：立即保存默认颜色。
- `批注`：保存划线并打开底部输入框写感想。

点已划线文字可查看、编辑、删除批注，也可选择“和林埃聊这一段”。书内提供“本书笔记”入口，按章节排列所有划线与批注，并可点击回到原文。

第一版只做一种克制的春雨昼眠高亮色；数据模型保留 `style` 字段，但先不做彩虹色盘。

### 6.2 数据模型

新增独立 `BookAnnotations`，不与旧 Memex 卡片体系建外键：

```text
id
bookId
chapterNumber
startOffset
endOffset
quote
prefixContext
suffixContext
contentFingerprint
style
note
createdAt
updatedAt
deletedAt
```

`quote + 前后文 + fingerprint` 用于章节内容被重新同步后的锚点修复：先信 offset；内容不匹配时在原位置附近搜索 quote；仍无法定位则保留为“待重新定位”，不能静默丢失用户笔记。

### 6.3 与林埃、Memory V3 的边界

- 原始划线和批注是阅读域的一等数据，保存在 Interests / Reader，不为每条划线自动生成 Memory Card。
- 当前章节的相关批注可以随共读上下文提供给林埃，让她知道用户刚才的感想。
- 用户主动点“记到我的记忆”或明确说“记住这段感想”时，再由 Record Organizer 提升为 Memory V3，并带上 `bookId/chapter/annotationId/quote` 来源。
- 只划线、没有批注的内容默认不代表用户认同，不能当作用户观点。

## 7. 林埃的阅读进度感知

共读上下文从“只知道章节”升级为：

```text
正在阅读 / 听书
作品、章节
当前句前后的小窗口
本章进度与全书最远进度
最近一条用户批注（如有）
本次推进方式：read | listen
```

这些是临时的 turn context 和阅读域状态，不自动写成 User-truth。完成一次有实际讨论的共读会话后，现有 `CoReadingNoteService` 仍按既有规则整理讨论；纯听书推进不制造 Memory Card。

## 8. 实施切分

### R0：本地音色赛马

- 做开发页或小型诊断入口，下载 / 删除模型并试听同一测试稿。
- 在主力手机和墨水屏上记录质量、实时率、内存、温度、包体。
- 定默认音色、轻量兜底和最低设备要求。

用户侧逐步操作与评分标准见 `docs/development/BOOK_TTS_VOICE_BAKEOFF.md`。

2026-08-12 已完成首版 App 内实验室：阅读书架右上角波形入口；首次下载、流式解压并以 SHA-256 校验 Kokoro v1.1 int8；以同一段文字和 1.0× / 1.25× / 1.5× 对三种匿名中文女声 A / B / C 盲听评分；生成工作放到后台 isolate，自动记录首段等待、冷启动、实时率和内存增量；评分持久化，结果可复制，模型可一键删除。首版先做 Kokoro 内部音色筛选，MeloTTS / 系统 TTS、20 分钟连续测试、温度与电量记录仍在下一轮扩展，不能把当前 A / B / C 误写成最终跨引擎结论。

### R1：语义定位地基

- 章节规范化、段落 / 句子 offset。
- 迁移 `scrollRatio` 到 `visual/audio/furthest locator`。
- 屏幕滚动和恢复改用 char offset，保留 ratio 兜底。
- 共读上下文获得当前句与推进方式。

### R2：前台听书 MVP

- 本地模型下载、校验、删除。
- 分段生成、预取、缓存、播放 / 暂停 / 变速。
- “从当前 / 从上次暂停”选择。
- 朗读句高亮、自动跟随、回到正在朗读。

### R3：后台与可靠续播

- `audio_service`、通知 / 锁屏 / 耳机控制。
- 进程重建后的精确续播。
- 电话、角色 TTS、蓝牙切换和音频焦点仲裁。

### R4：划线批注

- 自定义选择菜单、持久化高亮、写 / 改 / 删批注。
- 本书笔记列表与原文跳转。
- 章节变更后的锚点修复和失败提示。
- “和林埃聊”与显式“记到我的记忆”。

2026-08-11 已完成基础版：长按正文可直接“划线 / 批注”，高亮可点击编辑或删除，右上角“本书笔记”可按章节回看并跳回原文；落库同时保存 quote、前后文和正文 fingerprint，重叠划线会提示编辑已有内容。锚点自动修复、“和林埃聊”和显式提升到 Memory V3 留在后续增强，不影响当前划线批注使用。

### R5：体验增强

- 睡眠定时、章节末停止、定时关闭。
- 发音词典 / 多音字纠正。
- 可选更多高亮样式与笔记导出。
- 如确认确实需要，再增加低音量 BGM 混音与独立音量控制。

## 9. 首轮验收

- 无网状态能从已下载模型连续听 30 分钟。
- 锁屏、切到其他 App 后不断播；通知、耳机均可暂停和继续。
- 强杀前后最多回退到当前句开头，不能跨句漏读。
- 听完 3 个段落后退出，书架进度、再次打开位置、林埃获得的当前进度一致。
- 当前阅读位置与上次听书位置不同时，启动选择准确且不会覆盖另一位置。
- 划线后退出 / 重启仍在；批注可编辑删除；从笔记列表能回到原文。
- 纯划线不被林埃误当成用户立场，也不自动污染 Memory V3。

## 10. 调研依据

- [微信 AI 与微信读书的 Tacotron + Parallel WaveNet、预生成缓存和次句预取方案](https://cloud.tencent.com/developer/article/1866891)
- [sherpa-onnx Kokoro v1.1：中英双语、103 speakers、Dart / Android 示例](https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese-English/kokoro-multi-lang-v1_1.html)
- [sherpa-onnx Kokoro 模型与 int8 版本](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html)
- [Kokoro 中文模型卡与 Apache-2.0 标注](https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh/blob/main/README.md)
- [sherpa-onnx VITS / MeloTTS 中文模型表](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/vits.html)
- [audio_service：后台、锁屏、耳机和 TTS reader 支持](https://pub.dev/packages/audio_service)
- [Android MediaSessionService 后台播放规范](https://developer.android.com/media/media3/session/background-playback)
- [Flutter SelectableText 自定义选择菜单](https://api.flutter.dev/flutter/material/SelectableText/contextMenuBuilder.html)
