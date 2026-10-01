# Wave 2：真人反馈第二波集成交接

## 集成范围

- 集成分支：`codex/whiteboard-wave2-integration`
- 基线：Wave 1 集成 `c15a3eb9`
- 不触碰主工作树中并行进行的 W5 Runtime / Task Center 改动。
- schema 保持 60；未改 Card / Source / Board / Anchor 身份、冻结路由或生成文件。

## 用户现场问题与归因

| 现场问题 | 根因 | 本轮结果 |
|---|---|---|
| 首页、卡片库、白板同时加载失败 | 同用户顺序二次 `AppDatabase.init()` 关闭旧 Drift isolate，长期缓存的 Repository 仍握旧连接 | 修复共享数据库生命周期 |
| Bilibili 预览偶发失败、保存报 SQL / isolate closed | link-only 预览已成功，随后“是否已导入”查询碰到失效连接，UI 又把它误标为抓取失败 | 预览与存储核对解耦；保存错误可读且保留预览 |
| 本次小红书链接提示抓取失败 | 该公开链接真实匿名抓取可成功，失败同样来自预览后的失效数据库查询 | 保留真实 provider 结果，不再被存储异常连坐 |
| 侧栏收起按钮上下有矩形阴影 | seam painter 额外绘制了纵向渐变矩形 | 删除阴影，保留命中区与箭头 |

现场当时运行的是主工作树 `D:\memex\build\windows\x64\runner\Debug\memex.exe`，不是 Wave 1 集成构建。W5 并行代码没有修改数据库生命周期；另一个进程也不能关闭当前进程内的 Drift isolate。问题来自当前 App 自己的顺序重复初始化，两个构建都继承了旧缺陷。

## 生命周期裁决

1. 已完成的同用户 `AppDatabase.init(userId)` 必须复用当前连接。
2. 所有用户初始化串行；只有真实 user switch 才关闭旧库并建立新库。
3. `WhiteboardDataBootstrap` 以实际 `AppDatabase` 实例身份判断缓存是否仍有效。
4. 并发 `close()` 调用共享同一个完成 Future；所有调用者都等到真实关闭完成。
5. 页面、ViewModel 与 Repository 不拥有生产共享数据库的关闭权。

## 验证

- 相关集成回归覆盖数据库生命周期、冻结路由、Desktop 首页与壳、统一 Repository、URL canonicalization、link ingestion、导入 UI、卡片库和白板入口。
- 旧 `whiteboard_index_screen_test.dart` 已补 desktop platform fixture；没有修改产品路由。
- 改动范围定向 analyze 零 issue，`git diff --check` 通过。
- 联合回归首轮 126 项通过，唯一 5 项失败均来自旧 `whiteboard_index_screen_test.dart` 未注入 Desktop platform；修复夹具后该文件 6/6，新生命周期文件 5/5。尝试把全部 10 个文件再次放进单次 Flutter 命令时，Windows 测试外壳在 Dart 子进程结束后未回收且没有交回输出，因此不虚构“单次 131/131”；产品断言没有新增失败。

## 仍未完成

- 小红书图片安全缓存、OCR 与重要评论证据提取不在本轮；当前只证明用户给出的公开链接可解析标题、正文与媒体候选。
- Bilibili 仍为诚实 link-only；播放器与字幕能力不在本轮扩张。
- 语义双链仍不是视觉 `BoardEdge`，留后续独立设计。
- 本分支完成前不会强行合入含 W5 未提交改动的主工作树。
