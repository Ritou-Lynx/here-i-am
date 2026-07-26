# 漫画共读 Companion Plan

> **状态**：Draft
> **日期**：2026-07-24
> **作者**：i（林埃）与 Li Cheng

本文档规划"和林埃一起看漫画"功能在 Here I am 里的产品边界与技术架构。它不是独立的漫画阅读器 App，而是让林埃能感知用户的漫画阅读进度、理解当前页内容、在阅读时和读完后陪用户聊的能力。

---

## 0. 设计前提与约束

### 0.1 用户选择的三个关键约束

| 约束 | 决策 | 架构影响 |
|---|---|---|
| 爬虫运行位置 | **Hermes cronjob**（电脑端） | prompt-mode cronjob + 本地 HTTP API，手机端不跑爬虫 |
| 共读交互形态 | **边看边聊** + **林埃主动评论** | 翻页时注入当前页 screenplay 到 Companion Agent；读完一章后 Checkin Agent 主动发评论 |
| 图片转文本方案 | **Vision LLM**（候选 Ollama 本地模型） | NSFW 安全（本地无审查），离线 batch 预处理，非实时 |

### 0.2 隐含约束

- **Vision 提取在 Hermes 服务器离线 batch 运行**，不放手机、不走云端 Vision API（Gemini 等有 NSFW 内容政策会拒答）。
- **林埃"边看边聊"时查的是已提取好的页内容**，零延迟——不实时跑 Vision。
- **漫画来源是盗版站**，爬虫逻辑不在本仓库，只在 Hermes cronjob prompt 里维护；本仓库只负责接收成果。
- **遵守 Here I am 架构红线**：新表不与 Memex 卡片体系建 FK，新 service 构造注入 db，不 import MemexRouter。
- **成果归属 Interests 观察面**（按 PRODUCT_ROADMAP 规则），默认不进 User-truth；用户显式"记一下这本"才 promote。

---

## 1. 整体架构

```
┌─ Hermes 服务器（常开，非手机）──────────────────────────────┐
│                                                             │
│  漫画 HTTP Server（独立进程，端口默认 47840）                 │
│   ├ 本地存储：chapters.json / images/ （JSON 文件 + 图片）   │
│   └ 端点：/v1/comic/watches · /v1/comic/chapters 等         │
│                                                             │
│  cronjob 定时（prompt-mode，调本地 HTTP API）：               │
│   1. 检测关注漫画的更新（访问漫画站、比较最新章节 URL）        │
│   2. 爬虫下载新章节图片 → 存本地 images/                      │
│   3. Ollama Vision 模型 batch 提取每页：                     │
│      - 气泡归属（谁说的）+ 台词                              │
│      - 画面描述（NSFW 安全，本地无审查）                      │
│      - 输出结构化 JSON（page screenplay）                    │
│   4. 成果写入本地 chapters.json + 触发 HTTP server reload    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
          ↓  手机端 Tailscale HTTPS 直连（增量拉取）
┌─ 手机端 Here I am（Flutter）────────────────────────────────┐
│                                                             │
│  Drift 新表族（lib/db/comic_tables.dart）：                  │
│   mangas / chapters / pages / page_screenplays /             │
│   reading_progress / comic_sync_cursor                      │
│                                                             │
│  ComicService（lib/data/services/comic/）：                  │
│   ├ ComicLibraryService — 本地库 CRUD + HTTP 拉取            │
│   ├ ComicScreenplayService — screenplay 读写                 │
│   └ ComicReadingProgressService — 进度记录                   │
│                                                             │
│  漫画阅读器（lib/ui/comic/）：                                │
│   - 图片流翻页 + 进度记录                                     │
│   - 当前页 = 上下文锚点                                       │
│                                                             │
│  林埃共读（复用现有 agent 通道）：                             │
│   - 边看边聊：翻页触发 → 注入当前页 screenplay → Companion chat│
│   - 主动评论：读完一章 → Checkin Agent 基于整章生成评论      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.1 为什么不用 Supabase

购物 pipeline 用 Supabase REST 队列，但漫画场景不适用：

| 维度 | Supabase 免费层 | Hermes HTTP API |
|---|---|---|
| 活性要求 | **7 天不活动 pause database**（购物 pipeline 已踩坑被关停） | 无限制 |
| 成本 | 免费层有限制 | 零（复用已有 Hermes 机器） |
| 数据位置 | 第三方托管 | Hermes 本地（爬虫成果就在这里） |
| 依赖 | anon key / RLS / REST 转发 | Tailscale（已配） + Node http |
| 适合频率 | 高频持续写入 | 漫画更新低频，正是 Supabase 弱点 |

漫画更新不是每周都看，必然触发 Supabase inactivity pause。改用 Hermes 本地 HTTP server + Tailscale HTTPS，手机直连。爬虫成果在 Hermes 本地，不需要第三方中间层。

### 1.2 数据流时序

```
手机端                     Hermes HTTP Server              cronjob
  │                            │                              │
  │── POST /v1/comic/watches ─▶│                              │
  │   (注册关注漫画)           │                              │
  │                            │◀── GET /v1/comic/watches ────│ 每 30 分钟
  │                            │                              │── 访问漫画站
  │                            │                              │   检测更新
  │                            │                              │── 发现新章节
  │                            │                              │   下载图片
  │                            │                              │── Ollama Vision
  │                            │                              │   提取每页
  │                            │◀── POST /v1/comic/chapters ──│
  │                            │   (写本地 + reload)          │
  │── GET /v1/comic/chapters ─▶│                              │
  │   ?manga_id=X&since=Y       │                              │
  │◀── 返回新章节 JSON ─────────│                              │
  │   (含 pages + screenplay)  │                              │
  │                            │                              │
  │── 用户阅读 ──────────┐     │                              │
  │   翻页→进度入库      │     │                              │
  │   翻页→注入上下文 ───┘     │                              │
  │   读完整章→触发评论 │     │                              │
  │                       │     │                              │
```

---

## 2. Hermes 服务器端设计

### 2.1 漫画 HTTP Server

独立 Node.js 进程，参照 Dev Agent Bridge（`tools/dev_agent_bridge/dev_agent_bridge.mjs`）的 HTTP server 模式：`http`/`https` 模块 + JSON 文件持久化 + Tailscale 暴露。

#### 本地存储结构

```
<HERMES_COMIC_DATA_DIR>/          # 默认 ~/.hermes/comic/
├── watches.json                  # 关注列表
├── chapters/
│   ├── <chapter_id>.json         # 单章元数据 + screenplay
│   └── ...
├── images/
│   ├── <chapter_id>/
│   │   ├── 001.jpg
│   │   ├── 002.jpg
│   │   └── ...
│   └── ...
└── covers/
    └── <manga_id>.jpg
```

`watches.json` 结构：

```json
{
  "watches": [
    {
      "id": "uuid-v4",
      "character_id": "char-id",
      "source_site": "manga_site_a",
      "comic_url": "https://...",
      "comic_title": "...",
      "cover_path": "covers/<manga_id>.jpg",
      "last_chapter_url": "https://...",
      "status": "active",
      "created_at": 1700000000,
      "updated_at": 1700000000
    }
  ]
}
```

`chapters/<chapter_id>.json` 结构：

```json
{
  "id": "uuid-v4",
  "watch_id": "...",
  "comic_title": "...",
  "chapter_number": 42,
  "chapter_title": "...",
  "chapter_url": "https://...",
  "page_count": 18,
  "pages": [
    {"page_num": 1, "image_path": "images/<id>/001.jpg", "width": 1078, "height": 1518}
  ],
  "screenplay": [
    {
      "page_num": 1,
      "panels": [
        {"panel_id": 1, "speaker": "旁白", "text": "...", "panel_desc": "..."}
      ]
    }
  ],
  "status": "ready",
  "error": null,
  "fetched_at": 1700000000,
  "ocr_completed_at": 1700000100,
  "created_at": 1700000000,
  "updated_at": 1700000100
}
```

#### HTTP 端点

所有端点返回 JSON，参照 Dev Agent Bridge 的 `json(res, status, payload)` 风格。

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/v1/comic/health` | 健康检查 |
| `POST` | `/v1/comic/watches` | 注册关注漫画 |
| `GET` | `/v1/comic/watches` | 列出关注列表 |
| `PATCH` | `/v1/comic/watches/:id` | 更新（pause/resume/last_chapter_url） |
| `DELETE` | `/v1/comic/watches/:id` | 删除关注 |
| `GET` | `/v1/comic/chapters?manga_id=X&since=Y` | 增量拉取章节（since = timestamp） |
| `GET` | `/v1/comic/chapters/:id` | 单章详情 |
| `GET` | `/v1/comic/images/:chapter_id/:page_num` | 图片代理（避免手机直连盗版站） |

`since` 参数实现增量同步：返回 `created_at > since` 且 `status='ready'` 的章节。手机端用 `ComicSyncCursor.lastSyncedAt` 作为 since 值。

#### 图片代理端点

手机端不直连盗版站（避免被站点封 IP、避免手机暴露访问记录）。图片通过 Hermes HTTP server 代理：

```
GET /v1/comic/images/<chapter_id>/<page_num>
  → 读取本地 images/<chapter_id>/<page_num>.jpg
  → 返回 image/jpeg
```

图片已在爬虫阶段下载到 Hermes 本地，代理只是读取本地文件。

#### Tailscale 暴露

与 Dev Agent Bridge 完全一致：

```powershell
tailscale serve --https=443 http://127.0.0.1:47840
```

手机端 ComicRemoteService 配置 Tailscale HTTPS URL（如 `https://host.example.invalid/v1/comic/`）。

**端口与 Dev Agent Bridge 分离**：Dev Agent Bridge 用 47831，漫画 server 用 47840。两个独立进程，互不影响。

### 2.4 部署细节：Tailscale 多服务暴露

Tailscale Serve 的 `--https=443` 只能映射一个后端到 443 端口。Dev Agent Bridge 已占用 443。漫画 HTTP server 需要另选方案：

**方案 A（推荐）：用不同 Tailscale 端口**

```powershell
# Dev Agent Bridge 保持 443
tailscale serve --https=443 http://127.0.0.1:47831

# 漫画 server 用 8443
tailscale serve --https=8443 http://127.0.0.1:47840
```

手机端漫画 URL：`https://host.example.invalid:8443/v1/comic/`

**方案 B：合并进 Dev Agent Bridge**

在 Dev Agent Bridge（`dev_agent_bridge.mjs`）的路由里加 `/v1/comic/*` 前缀的端点，指向漫画 server 的本地 47840。手机端只需要一个 URL。代价是两个逻辑耦合在一个进程。

**方案 C：Tailscale Funnel（公网访问）**

如果需要非 Tailscale 网络访问（不推荐，漫画场景不需要）：
```powershell
tailscale funnel 8443
```

**Phase 1 用方案 A**，最简解耦。后续若觉得两个端口烦，再迁方案 B。

### 2.2 Hermes cronjob prompt 结构

两个 cronjob，都是 prompt-mode，调本地 HTTP API 而非 Supabase。

#### cronjob A：更新检测（`*/30 * * * *`，每 30 分钟）

```
你是一个漫画更新检测器。请按以下步骤执行：

1. GET http://127.0.0.1:47840/v1/comic/watches
   返回 status='active' 的关注列表。

2. 如果列表为空，输出"无关注漫画"，结束。

3. 对每条 watch：
   a. 用 browser_navigate 访问 comic_url
   b. 找到最新章节的链接和标题
   c. 与 last_chapter_url 比较：
      - 如果相同或更旧，跳过
      - 如果有新章节，继续

4. 对有新章节的 watch：
   a. PATCH http://127.0.0.1:47840/v1/comic/watches/<id>
      更新 last_chapter_url
   b. 对每个新章节 POST http://127.0.0.1:47840/v1/comic/chapters
      status='queued', chapter_url=<新章节URL>, ...
   c. 记录处理结果

5. 输出本次检测了几个 watch，发现几个新章节。
```

#### cronjob B：爬取 + Vision 提取（`*/10 * * * *`，每 10 分钟）

```
你是一个漫画章节处理器。请按以下步骤执行：

1. GET http://127.0.0.1:47840/v1/comic/chapters?status=queued&limit=1
   返回最早的 queued 章节。

2. 如果没有任务，输出"暂无待处理章节"，结束。

3. PATCH 该章节 status='fetching'。

4. 用 browser_navigate 访问 chapter_url，提取所有图片 URL，按顺序排列。
   失败 → PATCH status='failed', error=<原因>，结束。

5. 下载图片到本地 images/<chapter_id>/ 目录。

6. PATCH status='ocr_processing', pages=<图片列表>。

7. 对每张图片，用 execute_code 调 Ollama Vision 模型：
   curl http://localhost:11434/api/generate -d '{
     "model": "<VISION_MODEL>",
     "prompt": "<见 2.3 Vision prompt>",
     "images": ["<base64>"]
   }'
   解析返回的 JSON screenplay。

8. PATCH status='ready', screenplay=<全部页的screenplay>, page_count=<N>,
   ocr_completed_at=now(), fetched_at=now()。

9. 输出处理结果：章节标题、页数、screenplay 摘要。
```

### 2.3 Vision 提取 prompt

这是单个 page 的提取 prompt（注入 Ollama API 的 `prompt` 字段）：

```
你是一个漫画分镜分析器。请分析这张漫画图片，输出严格的 JSON（不要输出其他文本）。

输出格式：
{
  "page_num": <页码>,
  "panels": [
    {
      "panel_id": <格子序号，从1开始>,
      "speaker": "说话者名称或描述（如不知道用'旁白'、'角色A'）",
      "text": "气泡中的台词原文",
      "panel_desc": "这一格画面的简短描述（1-2句）"
    }
  ]
}

规则：
- 按阅读顺序（从右到左、从上到下，日式漫画）排列 panels。
- 气泡外的旁白用 speaker="旁白"。
- 无法识别的文字用 "[模糊]" 占位。
- 画面描述包含人物动作、表情、场景，但保持简短。
- 如果是 NSFW 画面，如实描述，不要回避。
```

### 2.4 Ollama Vision 模型选型（已完成 benchmark）

**选定模型：`qwen2.5vl:7b`**（2026-07-25 benchmark 确认）

Benchmark 结果（9 张代表性漫画页，含 NSFW/中文/韩文 webtoon）：

| 模型 | JSON 有效 | 平均耗时 | 说话者归属 | 分镜拆分 | 画面描述 | 结论 |
|---|---|---|---|---|---|---|
| `qwen2.5vl:7b` + v2 prompt | **9/9 (100%)** | 9.3s | "黑发男"/"棕发女" ✓ | 多 panel ✓ | 每格完整 ✓ | **选定** |
| `minicpm-v` | 8/9 (89%) | 12.4s | "角色A" ✗ | 漏分镜 ✗ | 多格缺失 ✗ | 淘汰 |

minicpm-v 致命问题：JSON 格式控制差（字段名不一致 `dialogue` vs `text`、引号不闭合），NSFW 页输出 6909 字符垃圾。

qwen2.5vl:7b + v2 prompt 改进效果（对比 v1 prompt）：
- 说话者从 "角色A" → "黑发男"/"棕发女"（利用外貌描述）
- 分镜从 1 panel → 2-3 panels（识别更多气泡）
- 画面描述更细致
- sfx 字段全留空（模型不理解该字段，但拟声词仍进 text，对共读够用）

**硬件约束**：RTX 5060 Laptop 8GB VRAM，只能跑 7-8B 量化模型。32B+ 需 CPU offload，每页 2-5 分钟不现实。

### 2.5 manwa.me 爬虫实现（已验证）

**站点特征**（2026-07-25 实测）：
- Cloudflare 防护 + 反调试 `debugger` 死循环 + 混淆 JS（`ch.js`）
- 移动优先站：完整 UI 只在移动视口下渲染
- 图片加密：真实文件从 `mwappimgs.cc` 下载但字节加密，运行时由 `ch.js` 解密后用 `createObjectURL` 生成 `blob:` URL
- 无干净章节 API：章节列表在 SSR HTML 里，图片 URL 在混淆 JS 运行时解密

**爬虫路线**：Playwright 浏览器自动化 + canvas 导出（不逆向加密）

```
crawler_manwa.mjs (Playwright)
  1. 复用登录 profile（.manwa_profile/，用户手动登录一次）
  2. 移动视口 + stealth 反检测
  3. 打开 book 页 → DOM 抓章节列表（/chapter/NNNN + "第XX话"）
  4. 对比本地 chapters/ → 只爬新章节
  5. 打开 chapter 页 → 滚到底 → 等解密稳定（blob img 计数不变）
  6. canvas.drawImage → toDataURL('image/png') 导出全部解密图
     （只收 naturalWidth>200 的大图，自动排除广告/头像/占位图）
  7. 逐页调 Ollama Vision（qwen2.5vl:7b）→ screenplay JSON
  8. 写 chapters/<id>.json + images/<id>/NNN.png
```

**端到端验证**（book 513361 第01话）：
- 52 张解密图 → 50 张 PNG 导出（2 张 tainted canvas = 跨域广告图，可忽略）
- Vision 提取确认工作（pages 2-4 ✓，page 1 瞬态失败 = Ollama 冷启动）
- 50 页 Vision 总耗时 ~6 分钟（7s/页），适合 cronjob 后台跑

**频率控制**：
- 每章之间 30-90s 随机间隔
- 每轮最多 N 章（`--max-chapters`，默认 2）
- 只爬本地不存在的新章节
- 浏览器路线本身慢（渲染+解密），天然低频

---

## 3. 手机端 Drift 数据模型

### 3.1 表定义

新建文件 `lib/db/comic_tables.dart`（参照 `dev_agent_tables.dart` 按域分文件的模式）。

```dart
// lib/db/comic_tables.dart

/// 用户关注的漫画。
class ComicMangas extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get characterId => text()(); // 关联角色

  TextColumn get sourceSite => text()(); // 'manga_site_a' 等
  TextColumn get comicUrl => text()(); // 漫画主页 URL
  TextColumn get title => text()(); // 漫画标题
  TextColumn get coverUrl => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('active'))();
  // 'active' | 'paused' | 'removed'

  IntColumn get createdAt => integer()(); // seconds since epoch
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 漫画章节。
class ComicChapters extends Table {
  TextColumn get id => text()(); // UUID v4，与 Hermes 章节记录 id 一致
  TextColumn get mangaId => text()(); // → ComicMangas.id（软引用，无 FK 约束）

  IntColumn get chapterNumber => integer()();
  TextColumn get chapterTitle => text().nullable()();
  TextColumn get chapterUrl => text()(); // 来源 URL

  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  TextColumn get pagesJson => text().nullable()();
  // JSON: [{page_num, image_url, width, height}]

  TextColumn get coverUrl => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('pending'))();
  // 'pending'（元数据已拉，图片未下载）| 'ready'（图片+screenplay 就绪）| 'failed'

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 单页的结构化剧本（Vision 提取成果）。
class ComicPageScreenplays extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get chapterId => text()(); // → ComicChapters.id（软引用）
  IntColumn get pageNum => integer()(); // 页码，从 1 开始

  TextColumn get screenplayJson => text()();
  // JSON: {panels: [{panel_id, speaker, text, panel_desc}]}

  TextColumn get imageUrl => text().nullable()(); // 对应的图片 URL

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  TextColumn get generatedByModel => text().nullable()(); // Vision 模型名

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 阅读进度。
class ComicReadingProgress extends Table {
  TextColumn get mangaId => text()(); // → ComicMangas.id
  TextColumn get chapterId => text().nullable()(); // → ComicChapters.id
  IntColumn get page => integer().withDefault(const Constant(1))(); // 当前页，从 1 开始

  IntColumn get readAt => integer()(); // seconds since epoch

  @override
  Set<Column> get primaryKey => {mangaId};
  // 每个漫画一行进度，更新而非追加
}

/// 同步游标（参照 ConversationCaptureCursors 模式）。
class ComicSyncCursor extends Table {
  TextColumn get mangaId => text()(); // → ComicMangas.id
  TextColumn get lastSyncedChapterId => text().nullable()();
  IntColumn get lastSyncedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {mangaId};
}
```

### 3.2 迁移

`lib/db/app_database.dart`：

```dart
@DriftDatabase(
  tables: [
    // ... 现有表
    ComicMangas, ComicChapters, ComicPageScreenplays,
    ComicReadingProgress, ComicSyncCursor,
  ],
)
class AppDatabase extends _$AppDatabase {
  @override
  int get schemaVersion => 45; // 44 → 45

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // ...
    onUpgrade: (Migrator m, int from, int to) async {
      // ... 现有迁移
      if (from < 45) {
        await m.createTable(ComicMangas());
        await m.createTable(ComicChapters());
        await m.createTable(ComicPageScreenplays());
        await m.createTable(ComicReadingProgress());
        await m.createTable(ComicSyncCursor());
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_comic_chapters_manga '
          'ON comic_chapters(manga_id, status)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_comic_screenplay_chapter '
          'ON comic_page_screenplays(chapter_id, page_num)',
        );
      }
    },
  );
}
```

跑 `dart run build_runner build --delete-conflicting-outputs` 重新生成。

### 3.3 架构合规性自检

| 红线 | 本设计如何遵守 |
|---|---|
| 不 import MemexRouter | ComicService 用构造注入 db，不通过 MemexRouter 访问 |
| 不与 Memex 卡片建 FK | 所有 `mangaId` / `chapterId` 都是软引用，无 `.references()` |
| 不扩大 Memex 耦合面 | 不碰 CardCache / KnowledgeInsight / PkmAgent |
| 构造注入 db | `ComicService({required AppDatabase db})` |
| 一句话自检 | comic_tables.dart + comic service 复制到无 Memex 项目能跑 ✅ |

---

## 4. 手机端 Service 层

### 4.1 文件结构

```
lib/data/services/comic/
├── comic_library_service.dart      # 本地库 CRUD + HTTP 同步拉取
├── comic_screenplay_service.dart   # screenplay 读写
├── comic_reading_progress_service.dart  # 进度记录
└── comic_remote_service.dart       # Hermes HTTP 客户端（参照 Dev Agent Bridge Dart 客户端）
```

### 4.2 ComicRemoteService（Hermes HTTP 客户端）

参照 `RemoteTaskService`（`lib/data/services/remote_task_service.dart`）的 HTTP 客户端模式，但目标是 Hermes HTTP API 而非 Supabase：

- 用 `http` 包直接调 Hermes HTTP API（`<BASE>/v1/comic/...`）
- Hermes base URL 存 `KvStore`（key: `comic.hermes_url`，如 `https://host.example.invalid`）
- 不需要 anon key（Tailscale 网络层已做信任边界，与 Dev Agent Bridge 一致）
- 方法：`upsertWatch(...)` / `getNewChapters(mangaId, since)` / `getChapterScreenplay(chapterId)` / `getImageUrl(chapterId, pageNum)`

图片 URL 构造：`<BASE>/v1/comic/images/<chapter_id>/<page_num>`——手机端图片加载走 Hermes 代理，不直连盗版站。

### 4.3 ComicLibraryService

```dart
/// Constructor-injected dependencies: no AppDatabase.instance, no
/// MemexRouter, per the architecture guard rules in AGENTS.md.
class ComicLibraryService {
  final AppDatabase _db;
  final ComicRemoteService _remote;

  ComicLibraryService({
    required AppDatabase db,
    required ComicRemoteService remote,
  })  : _db = db,
        _remote = remote;

  // 关注漫画
  Future<String> addWatch({required String characterId, ...});
  Future<void> pauseWatch(String mangaId);
  Future<void> removeWatch(String mangaId);

  // 同步拉取（Companion 轮询时调用）
  Future<List<ComicChaptersData>> syncNewChapters(String mangaId) async {
    // 1. 查 ComicSyncCursor 获取 lastSyncedAt
    // 2. GET <BASE>/v1/comic/chapters?manga_id=X&since=<lastSyncedAt>
    // 3. 本地 upsert ComicChapters + ComicPageScreenplays
    // 4. 更新 ComicSyncCursor.lastSyncedAt
    // 5. 返回新章节列表
  }

  // 本地查询
  Future<List<ComicMangasData>> getLibrary();
  Future<ComicChaptersData> getChapter(String chapterId);
  Future<List<ComicPageScreenplaysData>> getChapterScreenplay(String chapterId);
}
```

### 4.4 ComicReadingProgressService

```dart
class ComicReadingProgressService {
  final AppDatabase _db;
  ComicReadingProgressService({required AppDatabase db}) : _db = db;

  /// 翻页时调用。更新 ComicReadingProgress（upsert by mangaId）。
  Future<void> recordProgress({
    required String mangaId,
    String? chapterId,
    required int page,
  }) async {
    await _db.into(_db.comicReadingProgress).insertOnConflictUpdate(
      ComicReadingProgressCompanion.insert(
        mangaId: mangaId,
        chapterId: Value(chapterId),
        page: Value(page),
        readAt: DateTime.now().secondsSinceEpoch,
      ),
    );
  }

  /// 林埃查询用户进度。
  Future<ComicReadingProgressData?> getProgress(String mangaId);
}
```

### 4.5 装配点

在 `MemexRouter._init()`（`lib/data/repositories/memex_router.dart`）里添加：

```dart
// 在 SharedLifeMemoryService.init 等之后
final comicRemote = ComicRemoteService(db: AppDatabase.instance);
ComicLibraryService.init(db: AppDatabase.instance, remote: comicRemote);
ComicReadingProgressService.init(db: AppDatabase.instance);
```

采用 `SharedLifeMemoryService` 的混合模式：构造注入 + 静态 `init`/`instance`，因为阅读器 UI 和 Companion agent 工具都需要访问。

**不要**改 `lib/config/dependencies.dart`（那不是 service 注册点）。

---

## 5. 漫画阅读器 UI

### 5.1 最薄起步版

**Phase 1 只做：图片流翻页 + 进度记录**。不做双页、缩放、缓存优化、连载目录树。

```
lib/ui/comic/
├── view_models/
│   ├── comic_library_view_model.dart     # 书架
│   └── comic_reader_view_model.dart       # 阅读器
└── widgets/
    ├── comic_library_screen.dart           # 书架页
    └── comic_reader_screen.dart            # 阅读器页
```

#### 书架页 `ComicLibraryScreen`

- 列出 `ComicMangas`（status='active'）
- 显示封面、标题、最新未读章节
- 点击进入阅读器，从上次进度继续
- 支持添加关注（输入漫画 URL → 调 `ComicLibraryService.addWatch`）

#### 阅读器页 `ComicReaderScreen`

- 全屏图片流，左右滑动翻页
- 当前页 = `ComicReaderViewModel.currentPage`
- 每次翻页 → `ComicReadingProgressService.recordProgress`
- 翻页事件同时 → 注入当前页 screenplay 到 Companion 上下文（见 6.1）
- 顶栏：章节标题、页码 N/Total
- 底栏：进度条

### 5.2 进入入口

从 Chat 的生活空间观察面进入。按 PRODUCT_ROADMAP 规则，漫画归 Interests 层：

```
生活空间 → Interests → 漫画（书架）
```

不在首页 Chat 直接暴露入口；林埃可以在聊天中提到"你想看漫画了吗"时提供入口。

---

## 6. 林埃共读设计

### 6.1 边看边聊：上下文注入

**核心机制**：用户翻页时，当前页的 `screenplayJson` 被注入 Companion Agent 的运行时上下文。

#### Companion Agent 工具

新增 built-in tool（`lib/agent/built_in_tools/`）：

```dart
// lib/agent/built_in_tools/comic_tools.dart

/// 获取用户当前正在看的漫画页内容。
/// Companion Agent 在聊天中自动调用，无需用户显式触发。
class ComicCurrentPageTool implements BuiltInTool {
  final ComicLibraryService _library;
  final ComicReadingProgressService _progress;

  @override
  String get name => 'comic_current_page';

  @override
  String get description => '获取用户当前正在阅读的漫画页内容（台词、画面描述）。'
      '用户在看漫画时调用，用于理解当前剧情。';

  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> args) async {
    // 1. 找最近活跃的 manga（有进度记录且 readAt 在最近 30 分钟内）
    // 2. 取当前 chapter + page 的 screenplay
    // 3. 返回结构化上下文
    return {
      'manga_title': ...,
      'chapter_title': ...,
      'page_num': ...,
      'panels': [...],  // 从 screenplayJson 解析
      'image_url': ..., // 如果模型支持 vision，可附带
    };
  }
}
```

#### 上下文注入策略

不是每次翻页都发消息——这会刷屏。两种模式：

**模式 A：用户主动开口**（默认）
- 用户在阅读器里说话（聊天框始终可见）
- Companion 处理用户消息时，`comic_current_page` 工具被自动调用
- 林埃回复时已经知道当前页内容

**模式 B：林埃轻量反应**（可选开关）
- 翻页时，如果当前页有值得评论的内容（笑点、名场面、剧情转折），林埃发一条轻量消息
- 需要一个轻量判断：调小模型判断"这一页值不值得说一句"
- Phase 1 不做，Phase 4 再考虑

### 6.2 林埃主动评论（读完一章后）

**核心机制**：用户读完一章（翻到最后一页 + 停留 > 10 秒）→ 触发 Companion Checkin Agent。

```dart
// 在 ComicReaderViewModel 里
void _onChapterComplete(String mangaId, String chapterId) {
  // 1. 标记进度为"已读完本章"
  // 2. 投递 checkin 任务给 CheckinService
  CheckinService.instance.enqueueComicReviewCheckin(
    mangaId: mangaId,
    chapterId: chapterId,
    characterId: currentCharacterId,
  );
}
```

Checkin Agent 收到任务后：
1. 取整章所有页的 screenplay（`ComicScreenplayService.getChapterScreenplay`）
2. 取用户的历史偏好（从过往聊天中林埃已经知道的）
3. 生成一条自然评论（不是剧情摘要，是林埃的个人反应）
4. 通过 `PersonaChatService.instance.addCharacterMessage` 发到聊天

评论风格示例：
- "刚才那章 XXX 居然死了，你没想到吧？"
- "这一章画得特别好，尤其是那个分镜..."
- "你看完了？要不要聊聊？"

### 6.3 进度同步给林埃（日常聊天中）

林埃在普通聊天中可以通过 `comic_current_page` / `comic_reading_progress` 工具查询：
- 用户最近在看什么漫画
- 看到第几章第几页
- 上次阅读是什么时候

这让林埃能在日常对话中自然提起："你昨天那本《XXX》看到哪了？"

---

## 7. 分阶段实施计划

| 阶段 | 内容 | 状态 | 验证标准 |
|---|---|---|---|
| **0. Vision 模型 benchmark** | qwen2.5vl:7b vs minicpm-v 对比 | ✅ 完成 | qwen 9/9 JSON 100%，minicpm 89%+格式差，选 qwen |
| **1. 数据地基** | Drift 5 表 + migration 45 + 4 service + MemexRouter 注册 | ✅ 完成 | flutter analyze 零错误，build_runner 生成通过 |
| **1b. 爬虫验证** | manwa.me 结构探测 + 解密导出 + 端到端 crawl | ✅ 完成 | 52 张解密→50 PNG 导出→Vision 提取确认工作 |
| **2. 完整爬虫** | crawler_manwa.mjs（爬取+解密+Vision+存储+节流） | ✅ 完成 | 端到端跑通 1 章 50 页 |
| **3. 阅读器最薄版** | 书架页 + 阅读器页 + 进度记录 | ⬜ 待做 | 能看完一章，进度入库，重开从上次继续 |
| **4. 边看边聊** | `comic_current_page` 工具 + 上下文注入 | ⬜ 待做 | 翻页后说话，林埃回复内容对应当前页 |
| **5. 林埃主动评论** | 读完一章触发 Checkin + 整章评论生成 | ⬜ 待做 | 读完整章 10 秒后收到林埃评论消息 |
| **6. 体验迭代** | 缓存优化、双页、缩放、连载目录树 | ⬜ 待做 | 按使用反馈定 |

---

## 8. 遗留待决项

| 项 | 说明 | 状态 |
|---|---|---|
| ~~漫画站具体是哪个~~ | manwa.me，已实测结构 | ✅ 已确认 |
| ~~Vision 模型选型~~ | qwen2.5vl:7b 胜出 | ✅ 已确认 |
| ~~图片存储方案~~ | Hermes 本地 `data/images/<chapter_id>/` | ✅ 已确认 |
| 离线阅读 | 手机端是否缓存图片到本地 | Phase 3 定 |
| NSFW 内容分级 | 漫画是否标记 NSFW，林埃评论时是否区别对待 | Phase 5 定 |
| 多漫画站支持 | 当前 `sourceSite` 字段预留，只实现 manwa | 视需求 |
| tainted canvas 过滤 | 2/52 页跨域广告图导出失败，需收紧 filter | 低优先 |

---

## 9. 参考文档

- `.claude/references/hermes-shopping-pipeline.md` — Hermes cronjob 模式参考（本设计改用 HTTP API 而非 Supabase）
- `tools/dev_agent_bridge/dev_agent_bridge.mjs` — Node HTTP server + Tailscale 模式（漫画 HTTP server 直接参照）
- `tools/dev_agent_bridge/README.md` — Tailscale Serve 配置说明
- `.claude/references/cyberboss-push-architecture.md` — 主动推送机制（林埃主动评论参考）
- `docs/companion-first/PRODUCT_ROADMAP.md` — 成果归属规则（Interests 层）
- `docs/companion-first/PRD_V2.md` — 产品设计哲学
- `lib/data/services/remote_task_service.dart` — HTTP 远程客户端模式参考（目标改为 Hermes API）
- `tools/comic_server/comic_server.mjs` — Hermes 漫画 HTTP server
- `tools/comic_server/crawler_manwa.mjs` — manwa.me 完整爬虫（爬取+解密+Vision+存储）
- `tools/comic_server/benchmark_vision.mjs` — Ollama Vision 模型 benchmark 脚本
- `tools/comic_server/probe_manwa.mjs` — manwa.me 结构探测脚本
- `lib/data/services/shared_life_memory_service.dart` — 构造注入 + event sourcing 范例
- `lib/db/dev_agent_tables.dart` — 域分文件表定义范例