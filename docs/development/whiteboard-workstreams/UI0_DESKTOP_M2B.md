# UI-0 Desktop M2B — 富文本编辑与链接导入

**状态**：实现与返修完成，已由 W0 集成到 `v3-lab`
**日期**：2026-08-20
**分支 / 基线**：`codex/whiteboard-ui0-m2b`，基于 `057da4b`；已确认包含 M0 `88a6b5b`
**功能提交**：`f48c2a7 feat(whiteboard): migrate editor and link import desktop UI`；返修以独立追加提交承载，不 amend
**工作区**：隔离 worktree；开始前工作树干净

## 本轮闭环

- 富文本编辑器迁移为紧凑纸面工作区：统一 M0 页头与桌面 token，主保存动作上收页头，工具栏改为 36px 紧凑控件，窄宽与桌面宽自适应。
- 保留 F2 既有输入与存储闭环：中文 IME composing 守卫、粘贴清洗、段落 / 列表 / 引用 / 代码、附件、撤销重做、`Ctrl+S`、脏状态退出拦截和保存失败不放行。
- 链接导入迁移为“URL 输入 → 零写入预览 → 取消或明确提交”的单页工作流；提交继续使用预览得到的同一份 `IngestionResult`，不二次抓取。
- 返修提交 single-flight：`commitResult` 未完成时 URL 输入、预览、取消和再次提交全部锁定，延迟提交不会再与第二次预览竞争覆盖结果或导航。
- 持久化成功与 recent 辅助刷新分离：提交成功立即固定真实 Card / SourceVersion 成功态；recent 刷新失败只显示非致命提示，不回滚成“存入卡片库失败”，也不诱导重复提交。
- 预览区诚实区分“预览成功 / 明确失败”和“链接级保存 / 研读级就绪”；缺失正文、封面、字幕只显示缺失，不生成占位内容，不加载远程主图。
- 补齐窄宽 / 桌面宽、URL→预览→取消→提交焦点顺序、预览取消数据库零变化等 UI 守门测试。

## 保持不变的契约

- 未修改数据层、ingestion service、`SafeHttpClient`、`UnifiedCardRepository`、router、共享 token 或 shell。
- canonical URL 去重、`SourceVersion` 追加、YouTube URL-native、SSRF / DNS pin 语义均由 F3 原实现继续负责。
- 路由签名和 F2 富文本 schema / object store / plain-text projection 均未改变。
- 未修改 `DEVLOG.md` 或 `I_PROJECT_STATE.md`；按并行开发契约留给 W0 集成窗口统一更新。

## 改动路径

- `lib/ui/whiteboard/card_rich_text_editor_screen.dart`
- `lib/ui/whiteboard/editor/**`
- `lib/ui/whiteboard/link_import_screen.dart`
- 对应 `test/ui/whiteboard/` 富文本、unsaved guard 与 link import 测试

## 验证

- F2 既有 16 个测试文件：**162 项通过**。
- F3 ingestion / repository / import UI 8 个测试文件：**110 项通过**。
- M2B 直接 UI 回归：**50 项通过**（原 48 项 + 2 项返修确定性测试）。
- 返修新增覆盖：延迟 commit 期间第二次 fetch / cancel / resubmit 均不可触发且 commit 仅一次；commit 成功后 recent 刷新失败仍保留唯一 Card、唯一版本、已保存身份和正确目标导航。
- 覆盖重启恢复、重复导入同卡新版本、预览后取消零数据库变化、520px 窄宽、1280px 桌面宽和键盘焦点顺序。
- 精确 `flutter analyze`（link import UI + 测试）零 issue；关键修复验证 **3/3**；`git diff --check` 通过。
- Windows Debug 已构建成功：`build/windows/x64/runner/Debug/memex.exe`。
- 2026-08-21 已由真人在普通 Windows 应用中使用真实中文输入法验收候选、组合态、混合上屏、`Ctrl+S`、脏状态退出取消与再次保存；随后关闭并重开临时 Drift 数据库，指定正文与可用富文本文档均恢复。可重复入口为 `integration_test/whiteboard_manual_chinese_ime_windows.dart`，不连接生产数据。

## 集成结果与保留项

- 本轮没有共享契约变更请求。
- 隔离分支 `f48c2a7` 与返修 `ed25a09` 已由 W0 分别作为主线提交 `99a4819`、`3f77add` 集成；Windows 生成文件未纳入提交，未 push。
- 后续集成更新：真人中文 IME、统一安全缩略图与 Cascadia Code 正式资产已分别在 M5B-3、M5B-4、M5B-5 完成，均不再是 UI-0 保留项。

## M5A 审计与 M5B-1 返修（2026-08-21）

- 修复导入页返回语义：从卡片库进入时返回原卡片库栈，直接打开 `/import` 时回唯一卡片库。
- 生产编辑器新增壳注入的退出回调；未保存确认仍由编辑器拥有，取消、保存失败和放弃语义不变，确认退出后才执行来源栈返回或深链 fallback。
- `/import` 继续是冻结独立路径，但桌面侧栏活动语义归入“卡片库”。
- 红测复现过固定回首页、无动作和 GoRouter 弹空最后一页；返修后路由 14/14、导入与共享壳 23/23、富文本与未保存保护 39/39，精确 analyze 与关键守门通过。
- 本轮未改 Repository、ingestion、schema、路由签名、共享 token 或数据身份；固定视口实窗截图与真人中文 IME 已分别由 M5B-2 / M5B-3 完成。
