# Hermes Comic Server

Hermes 侧漫画共读 pipeline 的 HTTP server 骨架。手机端通过 Tailscale HTTPS 直连。

## 启动

```powershell
node tools/comic_server/comic_server.mjs
```

默认端口 `47840`，数据目录 `~/.hermes/comic/`。

## Tailscale 暴露

```powershell
tailscale serve --https=8443 http://127.0.0.1:47840
```

手机端 App 配置 URL 为 `https://<your-tailnet>.ts.net:8443`。

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

## 数据目录结构

```
~/.hermes/comic/
├── watches.json                  # 关注列表
├── chapters/
│   ├── <chapter_id>.json          # 单章元数据 + pages + screenplay
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

## 设计文档

`docs/companion-first/COMIC_CO_READING_PLAN.md`