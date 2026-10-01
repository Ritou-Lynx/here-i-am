# UI-0 — Whiteboard Desktop M0/M1 handoff

> 工作流：UI-0（Whiteboard Desktop · M0 shared foundation + M1 home / Lin Ai entry）
> 状态：M0、M1 均已完成并集成；M1 林埃浮层与 Desktop 独立产品边界于 2026-08-21 返修
> 集成分支：`v3-lab`
> 开工基线：`4191c124`（与当时 `origin/v3-lab` 一致，且包含 `a0e28893`）
> 集成提交：M0 `88a6b5b`；M1 `cbb1308`（来源提交 `229a0d6`）

## 1. 交付闭环

1. 新增桌面作用域 `DesktopWorkspaceTokens.lieflatPalm`，工作面固定 `#F0EFEB`；通过局部 `ThemeExtension` 安装，不修改全局 Spring Rain 手机主题。
2. 新增 `DesktopWorkspaceShell` 两种模式：
   - `standard`：148px 侧栏 + 34px 把手 + 可选共享页面标题；
   - `immersive`：只渲染业务工作面，不添加常驻侧栏、把手或页标题。
3. 侧栏收起后内容本体为 0px、品牌与导航完全离树，只保留 34px 把手；再次点击可恢复 148px 侧栏。
4. 新增正式植物 i 品牌组件 `DesktopBrandMark` / `DesktopBrandLockup`，复用正式资产 `assets/branding/hereiam_v3_logo/logo_foreground_1024.png`。
5. 新增共享 `DesktopPageTitle`，首页工作台改为消费共享壳；没有迁移任何具体白板、卡片、阅读或导入页面内容。
6. 冻结路由的路径和参数签名保持不变；仅在桌面路由出口选择普通壳或沉浸壳。

## 2. 路由壳模式

| 路径 | 模式 | 参数 |
|---|---|---|
| `/whiteboard` | standard | 无变化 |
| `/whiteboard/:boardId` | immersive | `boardId` 原样透传 |
| `/cards` | standard | 无变化 |
| `/cards/:cardId` | standard | `cardId` 原样透传 |
| `/sources/:sourceId` | immersive | `sourceId` 原样透传 |
| `/import` | standard | 无变化 |

具体 F0–F4 页面仍保留本阶段之前的页面内控件；UI-0 只保证共享壳在沉浸路由不叠加常驻导航或顶栏。

## 3. 拥有路径与改动

| 路径 | 内容 |
|---|---|
| `lib/ui/desktop/desktop_workspace_tokens.dart` | Lieflat Palm 桌面语义 token 与局部主题 |
| `lib/ui/desktop/desktop_workspace_shell.dart` | 普通 / 沉浸共享壳与侧栏状态 |
| `lib/ui/desktop/widgets/desktop_brand_mark.dart` | 正式植物 i 品牌组件 |
| `lib/ui/desktop/widgets/desktop_page_title.dart` | 共享页面标题 |
| `lib/ui/desktop/widgets/desktop_sidebar.dart` | 148px 导航、活动路由、正式品牌、完全退场 |
| `lib/ui/desktop/desktop_workbench_shell.dart` | 首页消费共享壳 |
| `lib/ui/desktop/widgets/desktop_chat_overlay.dart`、`desktop_persona_chat_view.dart` | 常驻品牌球与 Web 式无外框林埃对话呈现 |
| `lib/ui/desktop/widgets/global_desktop_chat_overlay.dart`、`lib/ui/character/widgets/persona_chat_screen.dart` | primary character 重试与同一会话状态的桌面呈现选择 |
| `lib/routing/desktop_route_wrapper.dart`、`lib/routing/router.dart` | 桌面壳模式接线；路径和参数未变 |
| `pubspec.yaml` | 仅新增一次正式品牌资产目录声明 |
| `test/ui/desktop/desktop_workspace_shell_test.dart` | M0 新增验收测试 |
| `test/routing/whiteboard_routes_test.dart`、`test/ui/desktop/desktop_workbench_shell_test.dart` | 路由 / 旧工作台回归与可靠异步等待 |

## 4. 共享契约影响

**零领域、数据库与 repository 契约变更。**

- 未修改 schema、迁移、F0–F4 repository/domain、Card / Source / Anchor / Snapshot / PlayerAdapter 语义。
- 未修改全局 Spring Rain token；Lieflat Palm 只在桌面共享壳子树生效。
- `pubspec.yaml` 只增加 `assets/branding/hereiam_v3_logo/`，没有新增依赖或字体。
- 测试夹具补齐统一 Card 所需的既有 `WhiteboardCardExtras` backfill；生产实现未变。

## 5. 验证结果

- `test/ui/desktop/desktop_workspace_shell_test.dart`：6/6 通过（普通 / 沉浸、148→0px 收起、34px 把手、活动路由、1280×720、1440×900、正式资产解码）。
- `test/routing/whiteboard_routes_test.dart`：8/8 通过（冻结路径 / 参数、普通 / 沉浸壳接线、保存回归）。
- `test/ui/desktop/desktop_workbench_shell_test.dart`：6/6 通过（原有首页、导航、悬浮对话、侧栏恢复不退化）。
- 精确改动范围 `flutter analyze`：No issues found。
- `scripts/verify_critical_fixes.ps1`：3/3 通过。
- `flutter build windows --debug`：成功，产物 `build/windows/x64/runner/Debug/memex.exe`。
- Windows 产物内正式品牌资产存在；源文件与打包文件 SHA-256 均为 `D7631B9771676F9914F33FC77E8B180A900A56DDC20645B8BD9AE870C8D46300`。
- `git diff --check`：通过。

## 6. 未实现范围 / 下一接入点

- 本轮未迁移具体白板、卡片库、编辑器、阅读、视频或导入页的内部视觉；后续 UI 阶段应逐页改为消费共享标题 / 控件，并删除页面内部的旧壳重复项。
- 沉浸模式保证共享壳不增加常驻 UI；具体阅读页已有的上下文控制仍归对应业务页面工作流处理。
- 后续集成更新：汇文明朝体已注册；Cascadia Code 已由 W0 在 M5B-5 以 Microsoft 官方 2407.24 Regular + OFL 许可完成接入，注册名与 `fonts.dart` token 一致。汇文明朝体全量文件的子集化仍是独立包体优化。
- M0 实现窗口未修改 DEVLOG 与 `I_PROJECT_STATE.md`；M1 集成完成后已由本集成窗口统一更新。

## 7. M1 — 首页与林埃入口

### 7.0.1 2026-08-22 真人验收修订（取代“两模块首页”）

- 侧栏仍只保留「首页」「卡片库」「白板」，Desktop 与手机继续保持独立页面壳。
- 用户确认首页不能只有两张列表；第一阶段改为六块真实白板数据模块：30 天卡片活动、卡片角色 / 媒介构成、上板比例、白板增长、最近白板、待整理卡片。
- 六块数据全部来自统一 Card / Source / Board 投影；不恢复旧八模块中的手机生活入口，也不伪造健康、财务、阅读、记忆或任务数据。
- 7.0 下方“两模块”描述只保留为 2026-08-21 的历史校正记录，不再代表当前首页结构。

### 7.0 2026-08-21 产品边界校正（取代旧八模块信息架构）

- 用户确认 Desktop/Web 与手机是两个独立 App。二者可以共享已明确约定的林埃身份与 Card / Source / Board 等内容对象，但不直接复用页面、信息架构、导航或视觉壳。
- 桌面侧栏当前只保留「首页」「卡片库」「白板」；首页只保留「最近白板」「待上板卡片」两个桌面原生工作模块。
- 记忆、阅读、任务中心以及观察面、日程等手机生活页面已从桌面首页与侧栏撤下。它们未来若进入桌面，必须先有用户确认的独立桌面需求与视觉方案，不得恢复本节下方历史记录中的八模块实现。
- `DesktopHomeViewModel` 仍从统一 Card / Board 数据源投影白板工作数据；没有新建第二套页面数据源，也没有修改手机页面、数据库、Repository、domain、schema 或冻结路由。
- 本轮桌面首页、共享壳与冻结路由回归 32/32；完整画布回归见 `W1_CANVAS.md`。

### 7.1 交付闭环

> 以下 1–3 项记录初始 M1 历史实现，其中“4×2 八模块、任务/阅读入口”已由 7.0 的产品边界校正取代；其余林埃浮层结论继续有效。

1. 首页在 1280×720 和 1440×900 均固定为 4×2 八模块首屏；模块骨架在加载、空态、错误和真实数据态下不漂移。
2. 首页继续复用现有 `WhiteboardDriftStore`、`TaskRoomService`、`MemoryCardQueryService` 与 `UnifiedCardRepository`；`activeTaskCount` 不再被展示列表上限截断。
3. 「继续阅读」在没有真实进度来源时显示诚实空态；空白板、卡片库、任务等入口均走现有真实路由；「继续对话」接全局林埃控制器。
4. 林埃仍由 `CharacterService` 解析同一 primary characterId，并复用 `PersonaChatScreen`，没有创建第二份角色或聊天数据。
5. 全局入口使用 50px 正式 plant-i 品牌球；展开后球仍常驻并作为同一个开关，关闭可恢复焦点，页面宽度与底层点击均不受影响。
6. 展开态按 `desktop/whiteboard_mvp/` 定稿改为无外框气泡组：上下文小标签、真实消息气泡和独立输入面各自悬浮，不再显示 400px 矩形面板、标题栏、手机背景或 TaskStrip。
7. `PersonaChatScreen` 只新增桌面呈现模式，继续持有同一消息列表、输入控制器、streaming 与 `_sendMessage` 链；手机默认呈现不变，没有第二套聊天 service 或持久化。
8. 全局入口只在真实用户就绪后挂载；primary character 首次解析为空或异常时会定时重试并监听角色更新，不再因启动时序竞态永久隐藏悬浮球。
9. Windows 普通构建没有原生 flavor 值时，正式启动默认使用 Here I am V3；Android / iOS 显式 flavor 仍优先，其他移动默认语义不变。
10. 小红书后台隐藏 WebView 只在移动端挂载，不再让 Windows 因缺少 `webview_flutter` 平台实现阻断首帧。
11. 根 `MaterialApp.router.builder` 外层的全局入口使用独立 Overlay host，Tooltip 与聊天瞬态控件不再依赖路由 Navigator 的下层 Overlay。

### 7.2 路径与契约边界

- 初始 M1 修改 desktop 工作台、ViewModel、模块网格与浮层；2026-08-21 返修新增 `desktop_persona_chat_view.dart`，并更新 `desktop_chat_overlay.dart`、`global_desktop_chat_overlay.dart`、`PersonaChatScreen` 的呈现选择及根入口用户就绪守卫。
- 更新范围包含 `test/ui/desktop/**` 与固定视口 Windows 集成脚本；未修改 M0 shell/token、router、pubspec、数据库、service、F0–F4 domain/repository 或手机 Spring Rain 视觉。
- 没有新增依赖、路由、表、迁移或角色身份语义。

### 7.3 集成验证

- 来源分支：`codex/whiteboard-ui0-m1`，基线 `057da4b32bb9`，来源提交 `229a0d6`。
- `v3-lab` 集成提交：`cbb1308`。
- 初始集成 4 个定向测试文件 20/20；返修后正式入口身份边界、手机聊天默认呈现、桌面浮层、工作台和冻结路由组合回归 62/62，原三视口链保持 1/1。
- 新增覆盖真实消息气泡、发送回调、同 characterId、启动解析重试、350px 最大宽度、底层点击穿透、常驻品牌球、开合焦点与“无旧面板”守门。
- 精确 6 个改动 / 验收目标 `flutter analyze`：No issues found；关键修复守门 3/3。
- Windows Debug 原生构建成功；1440×900、1280×720、1024×768 固定视口集成 1/1，三张展开态截图逐张确认只有独立上下文标签 / 消息气泡 / 输入面 / 常驻品牌球，内容高度按真实消息增长并在 480px 封顶滚动。

### 7.4 下一接入点

- M2 及后续页面视觉迁移继续消费 M0 共享 token/shell，不在业务页面复制桌面壳。
- TaskStrip 已从林埃浮层移除；任务编辑、编排、Codex Runtime 与任何行动卡片仍单独属于 W5 / AI 原生工作台范围，不混入本轮聊天视觉。
- M1 不声明阅读进度数据已经接通；获得真实来源前继续保持诚实空态。
