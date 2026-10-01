# W4-SUBTITLE — YouTube / 哔哩哔哩平台字幕抓取调研

> W0 现实核对（2026-08-23）：调研完成后，Wave3 的 Bilibili 链接入库、顶层播放器时间桥、统一平台字幕 resolver 与 SRT/VTT 后路已经合入 `v3-lab`。当前真实缺口不再是从零建立字幕模型，而是 `DisabledBilibiliSameOriginSubtitleProbe` 尚未替换为合规、无 Cookie 的真实字幕 transport。本报告的 API 与合规研究继续作为该 transport 的实现依据；实际排程以 `AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md` 为准。

> 状态：调研完成，可移交 W0/W4 落地
> 日期：2026-08-23
> 触发问题：`白板当前完全抓取不到 YouTube / 哔哩哔哩视频字幕`，需调研现成可靠方案。
> 拥有路径：本文档 + 后续落地时涉及 `lib/domain/whiteboard/video/`。
> 不做事项：不改 `PlayerAdapter` / `WhiteboardSnapshot` 任何共享契约语义；不引入任何绕过登录/DRM/平台限制的行为。

---

## 一、问题定位（项目现状）

| 维度 | 现状 | 说明 |
|---|---|---|
| 接口设计 | ✅ 已就位 | `TimedTextTrack` / `TimedTextCue` / `TimedTextSourceKind` 契约完整，UI 有 `subtitleFetchStatus` / `subtitleFetchMessage` 状态机。 |
| YouTube 字幕服务 | ⚠️ 已实现但常失败 | `YouTubeTimedTextService` 通过解析 watch/embed 页 `ytInitialPlayerResponse` 中的 `captionTracks` → 签名 `baseUrl` + `fmt=json3` 拉取。**Web 路线被 CORS 拦截**；native 下 `HttpTimedTextTransport` 默认 UA 也容易被 YouTube 反爬挡掉（403/无 `captionTracks`），导致 UI 长期停在「需要字幕」。 |
| 哔哩哔哩字幕服务 | ❌ 完全没有实现 | `BilibiliPlayerAdapter` 只有「link-only」stub（`canEmbedPlayer=true`，其它全 false），没有任何字幕抓取代码。`_providerId==bilibili` 时 `_canAutoFetchSubtitles` 直接返回 false，UI 永远显示「需要字幕」。 |
| B 站 ingest | ❌ 被标记为不支持 | `LinkIngestor` 对 `bilibili` provider 直接返回 `IngestionStatus.unsupported`，因此 B 站视频根本无法进入白板研读流。 |

用户当前体验：所有真实 YouTube / B 站链接都无法拿到字幕 → 功能"完全不可用"。

---

## 二、GitHub 调研结果（现成方案）

### 2.1 B 站字幕（含 AI 字幕）— 现成可靠方案非常多

**结论：有成熟开源实现，门槛极低，不需要 ASR。**

#### 关键开源项目（按可用性排序）

| 项目 | 类型 | 字幕相关能力 | 备注 |
|---|---|---|---|
| **yutto-dev/yutto** (2.0k★) | 完整下载器 (Python 3.11+) | ✅ 原生支持 UGC + 番剧字幕抓取 → SRT；含 AI 字幕。**未做 WBI 签名**（直接裸 GET）也能拿到字幕列表 | GPL-3.0，可作参考实现 |
| **NaiboWang/Bilibili-XMLSubtitle-to-ASS** (201★) | 转换器 | ✅ `.bcc → .srt/.ass/.lrc` 转换（含弹幕 XML 也可转） | MIT，可参考 bcc 解析 |
| **y2361547758/bcc2ass** (24★) | 转换器 | ✅ `.bcc → .srt/.ass/.lrc`；**直接给出 bcc JSON 字段定义** | Unlicense，最适合直接读格式 |
| **yt-dlp** (186k★) | 通用下载器 | ✅ `bilibili.py` 中 `_get_subtitles()` 走 `x/player/wbi/v2` 拉字幕列表 | Unlicense |
| **DavinciEvans/bilibili-subtitle-download-skill** (47★) | Claude Code skill | ✅ 完整的「BV 号 → 分块字幕 → LLM 总结」流水线（含扫码登录） | MIT，验证 SESSDATA 可提升 AI 字幕可见率 |
| **suyuan2022/bilibili-subtitle-fetcher-skill** (22★) | Claude Skill | ✅ B 站字幕获取 + Markdown 输出 | 类似 |

#### B 站字幕 API 事实（yutto 实测）

请求链（无需 WBI 签名、匿名可用 UP 主上传字幕；AI 字幕匿名经常不发，需要登录 Cookie 提升可见率）：

```
GET  https://api.bilibili.com/x/web-interface/view?bvid={bvid}
     → 取 aid / cid / pages

GET  https://api.bilibili.com/x/player/wbi/v2?aid={aid}&bvid={bvid}&cid={cid}
     → data.subtitle.subtitles[]
       每项含:
         lan           (如 "ai-zh" / "zh-CN" / "en")
         lan_doc       (如 "中文（自动生成）" / "中文（中国）")
         subtitle_url  (协议相对 URL, 以 // 开头; 内含 auth_key)
         type          (AI 字幕与普通字幕的区分字段)

GET  https:{subtitle_url}
     → bcc JSON:
       { "body": [
           {"from": 0.0, "to": 2.96, "content": "..." , "location": 2},
           ...
         ] }
```

**AI 字幕判断**：`lan` 以 `ai-` 开头即为 B 站 AI 生成字幕（常见 `ai-zh`、`ai-en`）。yutto 没做区分，但 `lan` 字段已足够。

**登录需求**：
- UP 主上传字幕：匿名可拉。
- AI 字幕：匿名时 `subtitles[]` 经常为空或缺失。yt-dlp 与 bilibili-subtitle-download-skill 都靠 **`Cookie: SESSDATA=xxx`**（B 站大会员/普通账号均可）解决。`need_login_subtitle` 字段会被置为 true。
- 字幕内容 URL 自带 `auth_key`，无需进一步签名。

**对应项目落地**：B 站字幕抓取在 Dart/Flutter 里只需两个 `http.get` + 一次 JSON 解析，无需引入 yutto 或 yt-dlp，也无需设备端 ASR。

### 2.2 YouTube 字幕 — 现成方案多，但稳定性依赖访问通道

**结论：Dart 原生方案不稳定（受 CORS / UA 反爬影响）；yt-dlp 是黄金标准。**

| 方案 | 可靠性 | 是否适合本项目 |
|---|---|---|
| **yt-dlp** (Python) | 🟢 最高。持续对抗 YouTube 反爬，支持 cookie / PlayerClient 切换 / poToken | 🟡 项目本体是 Flutter；要落地需要 (a) 在桌面平台嵌入 Python 运行时调用，或 (b) 走设备端/云端代理转发请求。**复杂度显著增加**。 |
| `YouTubeTimedTextService`（项目内现有） | 🟡 native 平台基本可用；**Web 受 CORS 拦截**；部分视频 `captionTracks` 不存在或受限 | ✅ 架构已对接好；只需修复失败率问题（加 UA + Referer + 真实 Cookie 透传 + 失败原因可见）。 |
| youtube-transcript-api (Python) | 🟢 稳定 | 🟡 同 yt-dlp，需要 Python 环境。 |

**项目现状诊断**：
- `_canAutoFetchSubtitles` 只在 `kIsWeb` / `Android` / `Windows` 启用，已含 Web。
- Web 端失败的根因：浏览器对 `youtube.com` 的 XHR 受同源策略限制 → 永远走「诚实失败」分支，UI 显示「需要字幕」+ 错误原因。这是 **设计内的诚实失败**，不是 bug。
- native（Android / Windows）失败原因更可能是：默认 UA 被识别为 bot；或某些视频确实没字幕。

**落地优先级**：
1. 短期：保留 `YouTubeTimedTextService`，把 subtitleFetchMessage 透传到 UI（已有），让用户能看到「需要登录/地区限制/该视频无字幕」等真实原因。
2. 中长期：考虑桌面平台通过本地 sidecar（Dart `Process` 调 yt-dlp 或一个轻量 Python 微服务）抓字幕，native 手机端继续走原生 HTTP。

### 2.3 小红书调研

小红书搜索页面对爬虫不友好（JS 渲染 + 反爬），本次 GitHub 调研已覆盖足够事实，**小红书无公开 CC/AI 字幕接口**（短视频字幕大多是视频内嵌硬字幕，不是可调接口拉取的轨道）。这与既有矩阵结论一致：`Platform may provide subtitles` 对小红书是 `notConfirmed` 事实正确，不需改动。

---

## 三、与 WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER 的合规性核对

| 总纲要求 | 本方案的符合度 |
|---|---|
| 「字幕优先平台 / 创作者，其次用户导入 SRT/VTT，权利允许时才做本机 ASR」 | ✅ 完全按此。B 站 AI 字幕用平台已生成轨道，**不需要本机 ASR**。 |
| 「平台无可靠字幕时明确标记需要字幕，不伪造支持」 | ✅ 所有失败走诚实 error，UI 已有的 `subtitleFetchStatus.failed` 状态直接用。 |
| 「小红书、哔哩哔哩、YouTube 可以使用不同 provider」 | ✅ 新增 `BilibiliTimedTextService` 不动共享契约。 |
| 「不绕过 DRM / 登录 / 付费限制」 | ✅ 只使用公开 web 端点。匿名拿不到 AI 字幕时 UI 诚实提示「需要登录后可见」，由用户在设置中粘贴 SESSDATA（一次性、可撤销），不内置扫码。 |
| 「PlayerAdapter 契约不改」 | ✅ 仅在 `ProviderCapabilityMatrix` 里在真实可用后把 bilibili `hasTranscript` 从 false 改成 partial，并加 `BilibiliTimedTextService`；不动 `PlayerCapability` 结构。 |

---

## 四、落地建议（按优先级）

### P0 — B 站字幕服务（新增 `BilibiliTimedTextService`）

这是**最高 ROI** 的修复：完全用现有 `TimedTextTransport` 模式即可实现，Dart 侧估计 200–300 行代码。

实现路径：
1. 新建 `lib/domain/whiteboard/video/bilibili_timedtext_service.dart`：
   - `Future<BilibiliTimedTextResult> fetchForVideo(String bvidOrUrl, {String? sessdata})`；
   - 内部三步：`view` API 拿 aid/cid → `player/wbi/v2` 拿 `subtitles[]` → 抓 `https:{subtitle_url}` 解析 bcc `body`；
   - 把 `body[i].from/to`（秒，浮点）→ `startMs/endMs`，`content` → `text`；
   - 通过 `lan` 字段以 `ai-` 前缀判定 AI 字幕，对应 `TimedTextReliability.partial`，人工字幕为 `reliable`；
   - 失败时返回诚实 error（区分「无字幕」「需要登录」「视频不存在」「解析失败」）。
2. 在 `VideoStudyViewModel` 中扩展 `_canAutoFetchSubtitles` 支持 bilibili；相应把 `YouTubeTimedTextService` 抽象为 `PlatformTimedTextService` 接口或工厂。
3. `ProviderCapabilityMatrix.capabilityFor('bilibili')` 中 `hasTranscript` 由 false → 仍是 false，**保留运行时 Availability 判定**（与 YouTube 一致的纪律）。
4. 在 Settings 增加可选「B 站登录 Cookie」（粘贴 SESSDATA），存入 `shared_preferences` 或更安全的 storage；用户不填则匿名模式兜底。

测试：单元测试用 fixture JSON 覆盖「有 AI 字幕」「无字幕」「需要登录」三种情形。

### P1 — 修好 `LinkIngestor` 对 bilibili 的拒绝

当前 `bilibili` 在 ingest 阶段被标 unsupported，根本走不到 study 屏幕。修复：增加 `_bilibiliPreview()`（类似 `_youtubePreview()`），生成 `mediaType: SourceMediaType.video` 的 `IngestionResult`，`canonicalId` 用 BV 号。

### P2 — YouTube 字幕稳定性改进

- 短期：把 `HttpTimedTextTransport` 默认 UA 升级为 yt-dlp 当前 UA（Chrome stable + 合理 Accept-Language），在 `_fetchTrackList` 失败时记录 HTTP 状态码到 `subtitleFetchMessage`，便于诊断。
- 中期：桌面（Windows）可以考虑用 `Process.start` 调本地 `yt-dlp --write-auto-sub --skip-download` 抓字幕，结果转 `TimedTextTrack`。需要评估安装体积与维护成本。
- 不做：Web 端字幕自动获取 — CORS 是浏览器物理事实，无法绕过；继续走「需要字幕」+ 用户导入 SRT/VTT。

### P3 — 小红书

明确不支持平台字幕，UI 上不再尝试自动获取，避免误导。

---

## 五、可复用的开源资产摘要

| 用途 | 直接使用 | 仅参考 |
|---|---|---|
| B 站 bcc JSON 字段定义 | — | `y2361547758/bcc2ass`（Unlicense） |
| B 站字幕 API 调用顺序 | — | `yutto-dev/yutto/api/ugc_video.py::get_ugc_video_subtitles` |
| B 站字幕完整流水线（含登录） | — | `DavinciEvans/bilibili-subtitle-download-skill`（MIT） |
| B 站 WBI 签名实现 | — | `yt-dlp/yt_dlp/extractor/bilibili.py::BilibiliBaseIE._sign_wbi` （仅未来签名收紧时需要） |
| YouTube 字幕 API | — | `yt-dlp`（如需 sidecar 方案） |

---

## 六、风险与注意事项

1. **B 站 AI 字幕的匿名可见率不稳定**——yutto 实测匿名能拿到部分视频的 AI 字幕，但不是全部。产品上要保留「登录后可看到更多字幕」的诚实提示，不要默认承诺。
2. **`SocialSisterYi/bilibili-API-collect` 已因法律原因关闭**——所有 B 站 API 调研只能依赖 yt-dlp / yutto 等仍活跃的实现做参考，不要把已删除仓库当作权威文档。
3. **yt-dlp 在 Flutter 中直接用 Dart 端口重写不现实**：它包含 poToken 计算、player JS 解析等大量对抗逻辑，任何 Dart 重写都会滞后于其主仓库。如未来 YouTube 字幕进一步失效，建议 sidecar 而不是 port。
4. **用户登录 Cookie 是敏感数据**：如落地 P0 第 4 步，SESSDATA 需要加密存储（例如 `flutter_secure_storage`），并在 UI 上清楚标注用途与撤销方法。

---

## 七、给下一个 session 的最小启动建议

如果按总纲继续走 W4 字幕，下一轮可以只做这件事的最小闭环：

> 新增 `BilibiliTimedTextService`，对一个真实 BV 号（已确认有 AI 字幕）完成 `bvid → aid/cid → subtitle list → bcc 解析 → TimedTextTrack` 全链路；只改 `lib/domain/whiteboard/video/` 一个新文件 + `ProviderCapabilityMatrix` 一处注释 + 单元测试；不写 UI、不接 ViewModel、不动 ingest。

测试命令：`flutter test test/domain/whiteboard/video/bilibili_timedtext_service_test.dart`（先写测试再写实现）。

参考真实测试视频（B 站官方 MV，含 AI 字幕）：`BV1GJ411x7h7`。
