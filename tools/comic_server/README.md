# Hermes Comic + Book Server

Hermes 侧共读 pipeline 的 HTTP server。**漫画和小说共用一个进程**：漫画走 `/v1/comic/*`，小说走 `/v1/book/*`，手机端通过同一个 Tailscale HTTPS 端口直连。

## 启动

```powershell
node tools/comic_server/comic_server.mjs
```

默认端口 `47840`，数据目录 `tools/comic_server/data/`（漫画：`chapters/`、`images/`、`covers/`、`watches.json`；小说：`books/<id>/{meta.json, chapters/, notes/}`）。

## Tailscale 暴露

```powershell
tailscale serve --bg --https=8443 http://127.0.0.1:47840
```

手机端 App 配置 URL 为 `https://<your-tailnet>.ts.net:8443`。漫画和小说共用这个 URL（小说 `BookRemoteService` 在 `book.hermes_url` 为空时自动 fallback 到 `comic.hermes_url`）。

## Vision 模型 Benchmark

```powershell
# 先拉取候选模型
ollama pull minicpm-v
ollama pull llava
ollama pull qwen2-vl

# 准备 5-10 张代表性漫画页（含 NSFW/中文/日文/竖排）
# 放到某个目录，然后跑 benchmark
node tools/comic_server/benchmark_vision.mjs --dir <image-dir> --models minicpm-v,llava,qwen2-vl
```

输出对比表 + 详细 JSON 结果。选型决策记录到 DEVLOG。

## API 端点

### 漫画 (`/v1/comic/*`)

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/v1/comic/health` | 健康检查 |
| `POST` | `/v1/comic/watches` | 注册/更新关注漫画 |
| `GET` | `/v1/comic/watches?status=active` | 列出关注列表 |
| `PATCH` | `/v1/comic/watches/:id` | 更新（pause/resume/last_chapter_url） |
| `DELETE` | `/v1/comic/watches/:id` | 删除关注（软删除 status=removed） |
| `POST` | `/v1/comic/chapters` | 新建章节记录（cronjob 投递） |
| `GET` | `/v1/comic/chapters?manga_id=X&status=ready&since=Y` | 增量拉取章节 |
| `GET` | `/v1/comic/chapters/:id` | 单章详情 |
| `PATCH` | `/v1/comic/chapters/:id` | 更新章节（status/screenplay） |
| `GET` | `/v1/comic/images/:chapter_id/:page_num` | 图片代理（从本地读取） |

### 小说 (`/v1/book/*`)

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/v1/book/health` | 健康检查 |
| `POST` | `/v1/book/import` | 导入 TXT（multipart 或 raw body） |
| `GET` | `/v1/book/books` | 列出书籍 |
| `GET` | `/v1/book/books/:id` | 书籍详情（含章节索引） |
| `DELETE` | `/v1/book/books/:id` | 删除书籍 |
| `GET` | `/v1/book/books/:id/chapters` | 章节列表 |
| `GET` | `/v1/book/books/:id/chapters/:num` | 单章正文 |
| `GET` | `/v1/book/books/:id/notes` | AI 预读笔记列表 |
| `POST` | `/v1/book/books/:id/notes` | 写入某章 AI 笔记 |

## 数据目录结构

```
tools/comic_server/data/
├── watches.json                  # 漫画关注列表
├── chapters/                     # 漫画章节
│   ├── <chapter_id>.json
│   └── ...
├── images/                       # 漫画图片
│   └── <chapter_id>/
├── covers/                       # 漫画封面
│   └── <manga_id>.jpg
└── books/                        # 小说
    └── <book_id>/
        ├── meta.json
        ├── chapters/
        │   └── 0001.txt
        └── notes/
            └── 0001.json
```

## 设计文档

`docs/companion-first/COMIC_CO_READING_PLAN.md`