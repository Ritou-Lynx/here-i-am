# Wave 1：Desktop 外壳与首页

## 本轮裁决

- Windows / macOS / Linux 的 `/`、`/cards`、`/whiteboard` 共用一个持久 `DesktopWorkspaceShell`；三个同级页面使用 `NoTransitionPage`，侧栏收起状态跨页面保留，返回首页不再重建手机 `AppOpeningSplash`。
- 手机路由仍沿用原顶层页面和原启动页；本轮没有修改手机 Chat、春雨昼眠页面或全局页面转场。
- `/cards/:cardId`、`/import` 保持在 Desktop shell 之上的消费页：直达时返回卡片库，卡片库内 push 时返回仍存活的筛选现场。`/whiteboard/:boardId` 与 `/sources/:sourceId` 继续是无常驻导航的沉浸页。
- 修改冻结 `router.dart` 仅限 Desktop shell / `pageBuilder` 集成；路由路径和参数签名未变，schema、Repository、W5 Runtime 均未改。

## 视觉与信息结构

- 品牌标记改为仓库已有 `assets/images/logo_foreground_ink_green_1024.png`，不新增或复制 Logo 资产。
- 侧栏不再用硬直线切断主体；展开态由低对比纸张渐隐连接，收起态只保留独立手柄，不残留绿线或纸缝。
- 首页删除“工作面”状态徽标，结果数量使用高对比普通元信息。
- 首页在 Desktop 主流尺寸保持 3 × 2 紧凑首屏：近 30 天 Card 新增、Card 角色/来源媒介构成、已上板/待整理比例、白板累计增长、最近白板、待整理卡片。
- 所有指标只读 `UnifiedCardRepository` 与 `WhiteboardDriftStore` 真实数据；空数据诚实呈现，不虚构健康、账本或 W5 任务数据。
- 图表只复用本仓库 PalmChart 与 Lieflat Palm 的视觉语法（暖灰底、墨绿主色、克制金色提示）；没有复制 Lieflat Charts 非商业模板或代码。

## 主要接入文件

- `lib/routing/router.dart`：Desktop 专用持久 ShellRoute；同级无过渡；mobile 原路由保持。
- `lib/routing/desktop_route_wrapper.dart`：用 `defaultTargetPlatform` 安全判定平台；已在 shell 内时不重复包壳，Flutter Web 不读取 `dart:io Platform`。
- `lib/ui/desktop/desktop_workspace_shell.dart`：持久 scope、展开/收起、纸张渐隐衔接。
- `lib/ui/desktop/view_models/desktop_home_view_model.dart`：真实卡片、来源、摆放与白板时序投影。
- `lib/ui/desktop/widgets/desktop_home_charts.dart`：四类紧凑图表。
- `lib/ui/desktop/widgets/desktop_module_grid.dart`：六模块首屏编排与真实操作模块。

## 验证

- `test/routing/whiteboard_routes_test.dart`：16/16，通过 Desktop 与 mobile 路由、直达/Push 返回、筛选现场保留。
- `test/ui/desktop/desktop_workbench_shell_test.dart`：11/11，通过空/有数据、四类图表、1280×720 / 1440×900、无页面级 ScaleTransition、无 splash 重播、mobile root 不变。
- `test/ui/desktop/desktop_workspace_shell_test.dart`：7/7，通过 Logo 解码、侧栏展开/收起、标准/沉浸模式与双窗口尺寸。
- 定向 `flutter analyze`：零 issue；`git diff --check`：通过。
- 路由测试曾因卡片库 250ms 搜索防抖在页面返回后启动 Drift 查询，而测试立即关闭数据库导致挂起；验收现等待真实查询完成后再 teardown，产品逻辑未为测试改写。

## 集成注意与未完边界

- 本轮不更新共享 `I_PROJECT_STATE.md` / `DEVLOG.md`，由集成窗口统一写入，避免与其他 Wave 冲突。
- `TASK_S_DESKTOP_HOME.md` 仍描述旧的两模块首页；集成时应把其“当前 UI spine”说明更新为本轮六模块真实数据首页，历史决策可保留但不得继续作为现状。
- 仅做 Widget/路由/数据投影验收；没有声明真实 Windows 窗口视觉逐像素验收、500 卡帧率或手机视觉变更。
