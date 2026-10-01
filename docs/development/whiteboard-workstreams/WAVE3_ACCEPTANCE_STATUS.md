# Wave 3 白板真人验收状态表

> 验收主窗口：`codex/whiteboard-wave3-acceptance`
> 起点：`65735eef`（产品修复基线 `fe598eec`，其后只新增 Wave 3 任务书与状态记录）
> 首次只读复现：2026-08-22

## 1. 边界

- 主工作区 `D:\memex` 与 W5 文件只读；不 stash / reset / checkout / commit / format / build_runner。
- 第一波只处理 A（RT-01～03）、B（CV-01～03）、C（VD-01～03）；LK-01 与全部 P2 不启动。
- `Card / Source / Anchor / Snapshot / PlayerAdapter / TimedTextTrack` 语义保持兼容；schema、依赖和生成文件不由功能包单独修改。
- 集成顺序固定为 A → B → C；不合并 `v3-lab`、不 push，直到用户完成第一波真人验收。

## 2. P0 只读复现

| ID | 当前状态 | 只读证据 | 第一波验收门槛 |
|---|---|---|---|
| RT-01 | 已确认 | `card_rich_text_editor.dart` 为每个块建立独立 `TextField`，聚焦块显示 Palm 绿完整矩形边框；这不是块级链接语义。 | 无常驻绿色矩形；焦点仍可辨认。 |
| RT-02 | 已确认 | 每块拥有独立 controller / focus node / selection；现有键盘处理只覆盖 Enter、Tab、撤销重做、保存和粘贴，没有跨块 Backspace / Delete / 拖选 / Ctrl+A 文档选择。 | 五块中文文档可跨块拖选替换、合并、全文选择；IME 组合态安全。 |
| RT-03 | 已确认 | 工具栏只有 H1、H2；没有 Paragraph 与 H3～H6 的可见入口。 | Paragraph ↔ H1～H6 全部可切换并持久化恢复。 |
| CV-01 | 已确认 | 双击卡片调用 `_openCompactEditor`，随后在 Stack 顶层渲染 `_CompactEditorPositioned + CompactCardEditor`；新卡也在 1×1 屏幕锚点旁打开浮层，不是卡面编辑。 | 双击空白/普通卡均在 BoardItem 表面输入；放大动作才进入全屏编辑。 |
| CV-02 | 用户已复现；缺测试 | `BoardEdge` 身份正确绑定 `from_item_id / to_item_id`，但 painter 与端点 handle 都取 BoardItem 中心点；没有“移动/缩放后端点仍吸附边界”的 Widget/像素级回归测试，也没有四向 anchor side。 | 四向锚点；移动、缩放、撤销重做、重启后实时吸附且方向稳定。 |
| LK-01 | 已确认缺失；本波冻结 | 当前只有白板内 `BoardEdge`；没有稳定 CardLink / BlockReference、反链查询或恢复验收。 | 留待第一波通过后的 E 契约，不以 BoardEdge 冒充双链。 |
| VD-01 | 已确认 | `BilibiliPlayerAdapter` 是空实现；Desktop `_runtimePlayerAvailable` 对它恒 false，研读页进入“链接模式”，只能外部浏览器打开。 | Windows 内至少平台允许的嵌入播放；若无时间控制，明确“可播放但时间研读受限”。 |
| VD-02 | 领域部分已有，入口需验收 | ViewModel 的 `beginAnnotation(startMs/endMs)` 与空字幕 position sync 已支持无字幕点 Anchor；但需确认真实 Windows 播放器始终提供独立“当前位置标注”入口和重启回跳。 | 无字幕视频不经过 cue 即可建点/区间标注，重启点击回到时间。 |
| VD-03 | 已确认 | `YouTubeTimedTextService` 用正则抽取 `captionTracks`；失败被压成“无字幕或网络/跨域限制”，轨道发现、地区/权限、网络、解析器失效没有可区分结果。 | 有 CC 样例发现/选择轨道；失败原因分类；SRT/VTT 导入仍可用。 |

## 3. 现有测试状态

- 已发起富文本、画布和视频现有定向测试；因另一窗口已有 Flutter/Dart 进程占用全局工具链，本窗口等待超过两分钟仍无任何输出，已安全中止本次等待。
- 这不是测试通过或失败。分支任务返回后，在单一 Flutter 执行窗口重新运行；不得与 W5 构建并发争用全局缓存/锁。
- 当前测试覆盖明显缺口：连续文档跨块选择、卡面原位编辑、边线随移动/缩放的可视端点、真实 Bilibili Desktop 嵌入、YouTube 字幕失败分类。

## 4. 第一波返回审计列

| 工作包 | 分支 / commit | 身份与契约 | 单测 / Widget / 恢复 | 真实窗口 | 失败状态 | 集成结论 |
|---|---|---|---|---|---|---|
| A 连续富文本 | `825fcb50` + `f2c90c24` + `bf113a3d` | Paragraph / H1～H6 共用连续文本面；内部块存储兼容；800ms 历史合并；IME composing 不被强制提交。 | 集成态 46/46；返修锁住工具栏撤销、链接选择与切换 legacy block 后的焦点交接。 | 待统一 Windows 窗口 | 任意混合非连续块回退旧块面；mark 任意编辑沿用旧 clamp 语义，已在 handoff 明示。 | 自动门禁通过，待真人验收。 |
| B 画布正确性 | `8c10c7ff` + `ff5b1282` | 原位编辑按 `item_id` 定位、内容按 `card_id` 共享；边线端点按旋转后边界计算；side 只进 `BoardEdge.style`，不冒充双链。 | 集成态 69/69；覆盖同 Card 双摆放身份、边线移动/缩放/撤销/重启与产品闭环；已接 A compact surface。 | 待统一 Windows 窗口 | 小视口、非 100% 缩放、中文 IME、脏关闭和边缘卡片遮挡需真人验收。 | 自动门禁通过，待真人验收。 |
| C Desktop 视频 | `7f375664` + `116e14e5` + `2d8e67c3` | Windows Bilibili 使用官方外嵌播放器；时间能力不可读时明确受限；时间 Anchor 入口与字幕解耦；确认提示 Timer 可取消。 | 集成态 43/43；覆盖 BV adapter、字幕失败分类、无字幕点/区间标注、Repository 重启。 | 待真实 BV Windows 窗口 | transport 无 HTTP status，纯 403 无正文时只能归为 network；WebView2 真实播放与失败恢复需真人验收。 | 自动门禁通过，待真人验收。 |

## 5. 集成状态

- A → B → C 已按固定顺序无冲突集成到 `codex/whiteboard-wave3-acceptance`；未合并 `v3-lab`，未 push。
- A/B 接缝已补：卡面 `CompactCardEditor` 显式启用连续富文本的 `compact + no-toolbar + readOnly` 参数，并在产品闭环测试中断言。
- A/B/C 集成态定向回归共 158/158；26 个实际源码/测试文件精确 analyze 零问题；`git diff --check` 与 `scripts/verify_critical_fixes.ps1` 3/3 通过。
- 唯一 Windows Debug 验收产物构建成功：`build/windows/x64/runner/Debug/memex.exe`，SHA-256 `5F313E727050E908D2B1E95F191C4F5362654149EEB15465642E2AE047EC7A3D`；启动前确认无旧 `memex.exe`。
- P2、LK-01、D/E/F 均未启动；当前停点是 Windows 真人验收，不合并 `v3-lab`、不 push。

## 6. 真人反馈追加修复（旧 A/B/C 验收继续保留为待验）

- 卡片原位编辑改为严格使用原 BoardItem 几何：无放大 surface、标题栏、叉号、保存/扩展 chrome 或额外外框；标题与连续正文直接在卡面编辑，内容过长在卡内滚动。
- 双击进入编辑，单击仍选择/拖动；编辑态隐藏旋转、缩放与四个连接点。卡外点击或 Esc 保存退出，保存失败保留编辑态；同 Card 双摆放继续按 `item_id` 隔离。
- 连线创建与 retarget 统一使用 28 屏幕像素最近合法四向 anchor；候选显示 22px Palm 实心 ring，预览线先吸附再落边。绘制与命中检测共用同一贝塞尔曲线，修复“看得见但点不中”。
- 依据只读 `D:\memex\docs\development\whiteboard-workstreams\COLOR_LEAK_HANDOFF.md` 在 `DesktopWorkspaceTheme` 一次补全 ColorScheme、SnackBar、输入框、四类按钮、Dialog 与 PopupMenu；未修改主工作区或 W5 文件。白板标题、工具和状态改走白板字体 token，缩放数字走 Cascadia 样式。
- 追加修复集成态联合回归 84/84；11 个实际源码/测试文件精确 analyze 零问题；关键修复守门 3/3、工作树 diff check 与 Windows Debug 构建通过。新版 `build/windows/x64/runner/Debug/memex.exe` SHA-256 为 `6DA7B6E0CD700AF400B25B655B07A0E51AD783DE0F634E5BF15F98C99A2C2428`。旧视频/Bilibili 等场景按用户要求留到下一轮一起验收，本节新反馈先真人复核。

## 7. 两轮真人验收合并裁决（2026-08-22）

- 用户明确：两轮反馈均建立在当前验收版之上；未再次指出的问题视为通过，不继续保留为泛化“待验”。
- **已通过**：连线吸附灵敏度与自动吸附；Desktop 二级面不再继承白板白紫色主题（后续仅观察回归）；其余两轮中未点名的问题。
- **真人已通过，底层实现已加固**：普通 Note 卡面只有一个无 InputDecoration 的连续文本面，双击不改变外形，空白双击直接创建并编辑；现以会话内 synthetic 首块保持标题边界，保存时再拆回 `Card.title` / 正文，不误拆正文 H1、不落盘 marker 或 block id。
- **已修复，待真人回归**：左上角卡片库行名与拖拽预览名称已统一使用白板字体 token；synthetic 标题边界、空标题、IME、撤销重做、保存失败和重启恢复已有自动门禁。
- **真人已通过**：视频笔记合为一个无边框连续文档；区间开始 / 结束分别直读播放器位置并显式保存 `is_point=false`。
- **新发现并已修复，待真人复核**：拖线先进入目标 Card body 时，源锚点 widget 因 hover 切换被移出树，手势 cancel 又被旧代码当作正常 end，可能提前提交为“死线”。现拖动期间冻结源 handle subtree，Card body 不作为落点，create / retarget cancel 独立回滚，raw PointerCancel 先清状态，后续 onPanEnd 成为 no-op。
- **新反馈并已调整，待真人复核**：删除右下角 96px 横向视频笔记 footer；ContextDock 主体改为“字幕 / 视频笔记”双 Tab，笔记为窄栏全宽纵向可滚动卡片，显示点 / 区间时间、标题和摘要，点击回跳；新建标注自动切入笔记 Tab，双空态诚实呈现。
- **视频方案已完成调研，尚未实现**：Bilibili 持久登录 profile、顶层页面时间桥、YouTube / Bilibili 分层字幕 resolver 与精细失败分类。
- **来源待排期**：小红书图片、OCR、重要评论与小红书视频；媒体必须能在白板卡面直接呈现，不能只显示文件名。其白板操作入口按下节 3.7 / F 约束实施，不另行猜测 FlexNote 行为。

## 8. 3.7 FlexNote 核心操作逐项状态（工作包 F 权威清单）

> 状态口径：**已实现**仅表示有当前代码与真人/自动证据；**受限**表示已有部分路径但未达到最终行为；**未实现**表示本轮尚无可验收闭环。分阶段只决定先后，不删除任何条目。后续每次 F handoff 必须更新本节。

### 8.1 单卡直接操作

| 最终行为 | 状态 | 当前差距 / 证据 |
|---|---|---|
| 双击空白创建真实 Note Card，卡面直接获得输入焦点，不弹窗 | 已实现，待真人复核 | 普通线性 Note 已使用一个连续无框卡面，首行/余文保存回既有 title/body；空白新卡不再预填“未命名卡片”并在下一帧聚焦。 |
| 单击选择；双击普通卡片表面原位编辑；放大仅由用户主动触发 | 已实现 | 真人反馈未再否定双击外形与二次跳跃问题；当前双击不放大。 |
| hover / 选中显示上、右、下、左四个锚点并可直接拖线 | 已实现 | 四向锚点与 28 屏幕像素吸附已完成；真人明确连线无需再改。 |
| 端点绑定 BoardItem 与 anchor side，移动/缩放/撤销/重做/重启后跟随 | 已实现 | 自动回归已覆盖，BoardEdge 仍只承担视觉布局。 |
| 悬浮“放大”在新标签 / 全屏工作面打开 | 未实现 | 尚无符合 3.7 的单卡悬浮快捷栏闭环。 |
| 悬浮“切换颜色”仅改 Card presentation | 未实现 | 尚未以统一命令接入快捷栏。 |
| 悬浮“添加到白板”打开 BoardTargetPicker，复用同一 Card | 未实现 | 最近白板、搜索、新建白板与复用语义尚未形成闭环。 |
| 悬浮“更多”与右键共享同一命令集合 | 未实现 | 尚未建立单一命令入口与一致撤销链。 |

### 8.2 右键 / 更多完整命令集合

| 最终行为 | 状态 | 当前差距 / 证据 |
|---|---|---|
| 切换颜色，与快捷栏共享预设和状态 | 未实现 | 工作包 F 尚未启动。 |
| 复制完整 Card 为新 Card，可跨白板粘贴 | 未实现 | 不得退化成复制 BoardItem 坐标。 |
| 复制稳定卡片链接；粘贴形成可点击引用并进入双链 / 反链 | 未实现 | 依赖工作包 E 的 CardLink / BlockReference 契约；BoardEdge 不替代。 |
| 侧边辅助面 ContextDock 打开 | 未实现 | 不恢复永久右侧栏。 |
| Pop 非模态可编辑悬浮窗打开并完整退场 | 未实现 | 尚无验收闭环。 |
| 新标签 / 全屏工作面打开 | 受限 | 全屏编辑能力已有，但尚未从统一右键 / 更多命令集合接入和验收。 |
| 查看创建/更新/标签/所属白板/历史版本，支持差异与显式恢复 | 未实现 | 信息与版本恢复尚未交付。 |
| 导出 Markdown | 未实现 | 必须产生真实可打开文件。 |
| 复制为 Markdown | 未实现 | 不能只放占位按钮。 |
| 导出 PDF | 未实现 | 必须验证真实产物。 |
| 导出 Word | 未实现 | 必须验证真实产物。 |
| 管理 Card 全局显式标签，与卡片库同 Repository / 词汇 | 未实现 | 尚无统一闭环。 |
| 添加到白板：同 Card 新 BoardItem | 未实现 | 与复制卡片严格区分。 |
| 从当前白板移除：只删当前 BoardItem | 受限 | 底层身份语义已有，尚未从完整命令集合验收。 |
| 删除：全局软删除 Card，明确影响并危险确认 | 未实现 | 不能用移除 BoardItem 冒充。 |

### 8.3 多选后的就地批量悬浮栏

| 最终行为 | 状态 | 当前差距 / 证据 |
|---|---|---|
| 框选、Shift/Ctrl 多选后在选择区域附近出现操作栏 | 受限 | 多选基础能力已有，3.7 规定的就地完整操作栏未交付。 |
| 分别统一修改填充色、文字色、文字背景色 | 未实现 | 三个目标必须明确，不能合并为含糊“颜色”。 |
| 聚焦视窗：按包围盒居中缩放并留安全边距 | 未实现 | 尚无验收闭环。 |
| 水平居中、垂直居中、顶部对齐、底部对齐 | 未实现 | “自动布局”不能替代明确命令。 |
| 创建半透明分组框并立即命名 | 未实现 | 尚无稳定分组对象闭环。 |
| 分组二级操作：改框色、重命名、添加到其他白板、解除分组 | 未实现 | 必须随分组一并追踪，不压缩成“分组”。 |
| 批量复制到其他白板：产生新 Card | 未实现 | 与批量添加严格区分。 |
| 批量添加到其他白板：同 Card 新 BoardItem | 未实现 | 需 BoardTargetPicker / 复用语义。 |
| 批量增加或移除显式标签，保持幂等 | 未实现 | 需与卡片库共享 Repository。 |

### 8.4 全局常驻悬浮工具

| 最终行为 | 状态 | 当前差距 / 证据 |
|---|---|---|
| 创建卡片：在当前 viewport 合理位置生成真实 Card 并直接输入 | 受限 | 双击创建路径已有；全局工具已新增“导入图片”并生成真实 Card + BoardItem，但通用文本 / 本地 / 链接统一创建面仍未完成。 |
| 画笔：可调粗细与颜色 | 未实现 | 不接受临时 painter 冒充交付。 |
| 荧光笔：独立透明度与混合语义 | 未实现 | 尚无稳定笔迹模型。 |
| 橡皮擦只删除笔迹对象，不误删 Card / BoardEdge | 未实现 | 依赖稳定笔迹身份与命中语义。 |
| 笔迹支持稳定身份、撤销重做、保存与重启恢复 | 未实现 | 共享契约裁决前不落不可恢复实现。 |

### 8.5 一致性守门

- 快捷按钮、右键 / 更多、键盘快捷键和批量栏必须调用同一业务命令、权限检查、Repository、操作审计与撤销链。
- 菜单、悬浮栏、ContextDock 与 Pop 关闭后完整退场；不新增永久顶栏、固定右侧栏或遮挡画布的兜底矩形。
- 以上状态已在同步提交 `8deaf6f3` 后建立；F 可分段交付，但任何 handoff 都不得遗漏本节条目。

## 9. 本轮卡片 / 视频集成与验证（2026-08-23）

- 卡片修复：`7e601747`；视频闭环：`02ddc520`；无框返修：`bb7f92db`。均从 `693050e9` 后按拥有路径集成，无 schema / 依赖 / 生成文件变更。
- 联合定向回归 93/93：连续卡面、空白建卡、卡片库、BoardItem 身份与恢复、点 / 区间 Anchor、无字幕路径、视频连续笔记、链接保存 / 打开、Repository 重启。
- 13 个实际变更 Dart 文件精确 analyze：零问题；`git diff --check` 通过；关键修复守门 3/3。
- Windows Debug 构建通过并已启动：`build/windows/x64/runner/Debug/memex.exe`；runner SHA-256 `6DA7B6E0CD700AF400B25B655B07A0E51AD783DE0F634E5BF15F98C99A2C2428`，本轮 Dart kernel SHA-256 `5B47A01EF05EED691B01563EA8CF287F4EB3102AA64F6254BDE773013DB1C919`。
- 真人重点：空白双击后直接中文输入、第一行回车进入正文、卡片库字体；视频区间时间标签与重启回跳、字幕引用删除、保存后不跳转、显式打开研读。

## 10. 后续顺序

1. 先完成本节 Windows 真人复核；未通过项继续在原工作包返修。
2. 随后进入工作包 D（P1）：小红书安全原图缓存、卡面媒体预览、OCR 派生证据与公开重要评论。小红书视频按 `SourceContent.mediaType=video` 进入同一 W3 抓取 → W4 播放 / Anchor 管线，不另造平行“视频卡片”。
3. Bilibili 持久登录 / 时间桥与双平台字幕 resolver 作为视频适配下一段，先做能力验证与安全边界，再决定是否内置非官方 extractor。
4. 工作包 F 仍按第 8 节全清单分段交付；不因本轮只修卡面而宣称 FlexNote 核心操作已完成。

## 11. 连线连续拖拽与视频双 Tab 验收版（2026-08-23）

- 集成提交：视频双 Tab `c9094fa8`；连线拖拽连续性 `9863dc53`。原带格式器噪音的连线候选提交已拒绝，重新从基线制作最小语义提交后才集成。
- 连线回归覆盖：先碰 body 再到 anchor、body 内松手、create PointerCancel、retarget PointerCancel、四向边界、移动 / 缩放 / 撤销 / 重做 / JSON 重启；既有 28 屏幕像素吸附保持不变。
- 视频回归覆盖：双 Tab 切换、多卡纵向几何与滚动、无字幕 / 无笔记空态、点 / 区间时间、点击回跳、新建自动进入笔记上下文、Dock 完整退场与响应布局。
- 联合回归 78/78；4 个实际变更 Dart 文件精确 analyze 零问题；diff check、关键修复 3/3 与 Windows Debug 构建通过。
- 新验收版已启动：`build/windows/x64/runner/Debug/memex.exe`，PID `50848`，Dart kernel SHA-256 `802EC8E721214C87C028E059CC707DC2A0C56C968F755525493C085CFBA22E57`。

## 12. G1 卡面最终收口（2026-08-23）

- 卡内不再维护独立 title controller；标题与正文共用一个 `CardRichTextEditor` / 一个原生连续文本值，卡片 rect、圆角、旋转与手势边界不变。
- synthetic 首块只存在编辑会话；保存时依显式私有 marker 拆分，不把正文原 H1 误拆、不写入文档、不创建不稳定 block id。
- `saveRichText` 新增默认关闭的 `preserveEmptyTitle`，只供标题/正文同面编辑显式保留空标题；旧调用者仍沿用首个非空正文行投影规则。
- 左上卡片库的卡名 / 类型改走白板字体 token；未改 Card / Source / Anchor / Snapshot / PlayerAdapter schema、数据库迁移、W5 或视频。
- 定向 analyzer 6 文件零问题；卡面 + 直接交互 + 产品闭环 + 视觉字体 + 富文本 + Repository 联合回归 76/76。真实 Windows 字形、鼠标卡外退出与中文 IME 候选窗仍由集成窗口统一复核。

## 13. G1 视频最终集成（2026-08-23）

- 最终实现以最新验收分支为产品基线：单一无框视频笔记文档、“字幕 / 视频笔记”双 Tab 和纵向笔记列表全部保留；旧功能包的三栏及 title/body/quote 三输入未进入产品。
- pending 标注草稿、主动清空的字幕引用和最后焦点由 ViewModel 保持，可跨 1440 / 900 / 720 布局及 dock 关闭重开；已有 pending 时其他 cue 标注入口 fail-closed。
- `createVideoAnnotationCard` 原子校验 SourceVersion 归属、time-range Anchor、时间范围与 `is_point` 摘要；非法 position kind、负时间、反向区间和 point/range 不一致均零写入。
- Source 对象 final/tmp/bak 交换与数据库事务处于同一 objectRef 守卫；交换中断恢复精确前态，失败后重试只产生一个对象和一张标注卡。
- load / save / session restore / current-time 错误只展示固定安全文案；Windows Bilibili 保存后可显式进入 SourceStudy，但登录态、时间桥和字幕仍遵守公开能力边界。
- 独立二审补齐 canonical 并发与跨文件崩溃窗：相同 provider/canonicalId/URL 即使收到不同 sourceId 也按稳定 identity 串行，并在事务内复查，最终只有一套 Source/Version/Card/object。对象写入前落仓库私有 intent；启动时只清理 intent 明确声明且 DB 无引用的对象与 sidecar，已有引用只移除 intent，未被 journal 声明的合法文件不动。
- time-range 现在只接受整数毫秒，`1.2/1.8` 等小数在任何 Card 写入前拒绝；草稿焦点按 ViewModel 记录状态恢复，字幕文件与 AnnotationStore 失败均使用固定安全文案。纵向视频笔记回归真实制造 overflow、验证 `maxScrollExtent > 0` 并滚到末卡回跳。
- 第二轮数据复审将 intent 升级为携带 final/tmp/bak 精确前态的 v2 journal；DB 未提交的崩溃按 snapshot 原样恢复旧现场，DB 已提交后的普通 cleanup 失败越过补偿边界，只留待启动删除 intent。ingestion 改为工作区级单锁，同时覆盖 canonical URL/ID 等价类和同 objectRef；同 hash 的后到来料不改写首个已提交对象、canonical 身份或 Card 正文。
- 第三轮完整性返修为每份存在的 snapshot 增加 length + SHA-256，并对 schema/type/base64/length/hash 做严格恢复校验；损坏或未知 intent 保留诊断现场且不阻塞合法 intent。单文件 4 MiB、合计 8 MiB 上限在任何写入前拒绝不可安全恢复的大现场。
- 第四轮在读取前增加 12 MiB envelope 上限；截断/非 JSON main 可从强语义有效 tmp/bak 恢复，三份均不可识别则标记 unresolved 并冻结本轮全部通用 Source exchange。对象恢复前还需证明 whiteboard/sources/目标父目录真实路径 containment，symlink/junction 或无法证明时原样保留。SHA-256 仅检测偶发损坏，不作为本机恶意重签防护。
- 最终数据/视频联合定向回归 151/151，仓库专项 37/37；3 个本轮实际源码/测试文件 direct-dart analyze 零问题，关键修复守门 3/3，diff check 通过。Windows 真人复核仍按本节既有 Bilibili/YouTube 场景执行；通过前不合入 `v3-lab`，也不启动 W5 G2。
## 14. 第二波公开媒体 / 本地图片 / Bilibili 时间桥（2026-08-23）

| 范围 | 状态 | 自动化证据 / 明确边界 |
|---|---|---|
| XHS-01 安全原图与 OCR | 已实现（匿名公开页） | 只接受笔记主体或限定结构化 state；SafeHttpClient 逐跳安全边界后以 SHA-256 内容寻址，保存尺寸、MIME、原/终 URL、OCR 状态与稳定 evidence manifest；推荐、头像、站点 OG、伪造 PNG/GIF 与 symlink 越权均有负例。 |
| XHS-02 公开重要评论 | 受限实现 | 只保存匿名 HTML 已出现的顶层评论、作者、时间、顺序、selector 与来源，最多 10 条；不借登录态、不翻页、不把“前 10 条”伪称算法重要性。 |
| 小红书视频 | 受限 | 识别为 video Source 并保存 `link_only` / `stream_extraction=not_attempted`；未抽流、未提供时间 Anchor。 |
| 本地图片卡面与导入 | 已实现 | RichText 首图和安全缓存 Source 缩略图可在卡片库 / 多个 BoardItem 直接预览；全局“导入图片”创建真实 Card、当前 viewport BoardItem，并覆盖只读、快照失败、软删/对象清理重试。渲染路径不调用不可信 resolver、不触网。 |
| Bilibili 应用内播放与时间 Anchor | 条件实现，待真人 | Windows 顶层官方视频页只有完成标准 HTMLMediaElement 读取 + no-op seek + 回读才提升时间能力；换 BV、离页、刷新、video 替换、加载失败立即降级并清未完成 range / draft。真实页面是否暴露该元素待联网真人验证。 |
| Bilibili 自动字幕 | 未完成 | 默认生产 probe 明确 disabled / unsupported；只保留 SRT / VTT 导入与精细失败分类，没有调用未证明稳定的私有 WBI 接口。 |
| Bilibili 登录保持 | 待授权 / 待真人 | 当前只打开官方登录页并沿用插件默认 WebView 会话；未配置固定应用 profile，也未提供会同时影响同 profile 内 YouTube 的 Cookie/cache 清理。 |
| SourceVersion 证据回看 | 受限 | 实际媒体 SHA/OCR/评论参与稳定 version identity，同 URL 换 bytes 产生新版本且旧对象保留；现有 Drift SourceVersion 行无 metadata 字段，不能仅凭旧行直接还原当次 manifest，未私改 schema。共享 digest 只保守保留，引用表 / mark-sweep GC 待 W0。 |

- 集成提交：XHS 原包 `e558a7ba` + 审计返修 `2e4f68a6`；Bilibili 原包 `6345377e` / `dd7697f6` + 状态隔离 `488a407d` / `52e64145`；本地媒体卡 `1402b41a` + 回滚守门 `8cb180c4`。
- 统一串行回归 **156/156**：XHS、对象存储、卡片库、媒体卡、画布直接交互、连线几何、Bilibili bridge / resolver / adapter、视频研读与 Source 消费面；29 个实际变更 Dart 文件精确 analyze 零问题。
- 集成回归另发现 800px 窗口悬浮工具条增加图片入口后横向溢出 0.75px，已改为窄窗口可横向容纳；失败项与正确 Source 测试路径复跑 30/30。
- 3.7 第 8 节仍为完整权威清单：本轮只把“导入图片”子入口标为已实现，不把单卡快捷栏、完整右键 / 更多、多选批量、分组二级操作、跨板复制 / 复用、标签或手绘工具冒充完成。

## 15. 第三轮真人反馈统一验收版（2026-08-23）

| 范围 | 当前状态 | 自动化 / 真人边界 |
|---|---|---|
| 连线连续性与吸附 | 真人通过，冻结 | 用户明确连线已无问题；本轮仍保留先碰 Card body、retarget、PointerCancel、四向几何与重启回归，不再调整 28px 吸附。 |
| 图片主卡 | 已实现，待真人复核 | image-only 卡面 80%–100% 为图片、最多一行元信息；双击为整图缩放查看 + 标签，不出现伪正文编辑；图文混排仍进入连续富文本。 |
| 卡片库删除与红卡 | 已实现，待真人复核 | 主卡片库和画布库均支持全局软删二次确认；所有 BoardItem 保留为失效引用。无 Source 的本地图片不再强解包，损坏对象降级占位并可删除。 |
| 真实小红书原图 | 已实现（匿名公开页），待真人复核 | 真实用户链接生产 smoke 1/1：exact-note SSR → 安全原图对象 → 本地 thumbnail_ref → Card/Source → 数据库重启；卡面渲染不触网。 |
| 小红书 OCR / 评论 | 受限且显式 | Windows ML Kit OCR 为 unavailable；匿名 SSR 未加载评论时为 0 并显示原因。不读取 Cookie、不调用私有/签名 API、不翻页。 |
| 视频区间语义 | 已实现，待真人复核 | 单击区间笔记从 start 播至 end 自动 pause；可切换循环片段。切标注/Tab、隐藏 Dock、能力降级、离页均取消，迟到 pause 不覆盖新播放。 |
| 视频笔记与 Dock | 已实现，待真人复核 | 按 start_ms、created_at、card_id 稳定排序；单击定位/播放，双击卡内无框编辑；标签动作并入 Dock header，右侧/底部/窄窗无 overflow。 |
| 自动字幕 | 未完成 | YouTube CC 与 Bilibili 自动字幕仍无已证明稳定、合规的生产 transport；SRT/VTT 导入继续可用。 |

- 本轮集成提交：图片 `0f81c013`、真实 XHS `b185f0a7`、视频 `0104835b`；均未改 schema、依赖、生成文件、W5/Bridge 或 AI write tools。
- 统一串行回归 **237/237**；22 个增量 Dart 文件 analyze 零问题；关键修复守门 3/3；`git diff --check` 待最终状态提交前复核。
- Windows Debug 构建并启动：`build/windows/x64/runner/Debug/memex.exe`，PID `3780`，Responding=true，runner SHA-256 `6DA7B6E0CD700AF400B25B655B07A0E51AD783DE0F634E5BF15F98C99A2C2428`，Dart kernel SHA-256 `1686E08484F124158A41035A9DF56D71250DE4E9B72C3ED13AEDD3F6DAC570FC`。
- 3.7 全清单继续有效：本轮只把标签/全局删除的 Repository 语义提升为“受限”，因为尚未进入统一单卡右键/更多命令；多选、分组二级、跨板复制/复用、四类导出和持久手绘仍未实现。

## 16. 第四轮真人返修：底部 Dock、轻量标签与全局连续编辑（2026-08-23）

| 范围 | 当前状态 | 自动化 / 真人边界 |
|---|---|---|
| 底部 Dock 纵向溢出 | 已修，待真人 | 时间轴与当前标注操作改为可收缩滚动区，标签页和正文共享剩余高度；640×360 极矮桌面回归无 overflow。 |
| 视频标签编辑 | 已修，待真人 | 从带全屏 modal barrier 的 Dialog 改为右上角 340px 轻量菜单浮层，点击外部即退出；标签仍写统一 Repository。 |
| 全局卡片编辑 | 已修，待真人 | 删除伪纸张底色、边框与聚焦框；非 compact 连续正文直接填满可用高度，不再默认 8 行后要求拖动扩展。 |
| 小红书封面 | 真人通过，冻结 | 用户确认封面已进入卡片，不再改动安全原图与本地缩略图链。 |
| 小红书 OCR / 评论 | 未完成（桌面能力缺口） | 安卓旧链路已核实为登录态隐藏 WebView 动态 DOM（评论最多 10 条）+ 移动端 ML Kit OCR；Hermes 是当时实现执行者，并不存在可复用的 Hermes 抓取服务。Windows 当前匿名 SSR 与移动 ML Kit 无法等价复用，后续必须补桌面登录容器和 Windows OCR 后端，不能把封面成功冒充完整复现。 |

- 定向回归 43/43；将既有底部 Dock 测试收紧到 640×360，并新增全局编辑面无框与正文高度断言；6 个相关文件定向 analyze 零问题。
- 未改 schema、依赖、生成文件、W5/Bridge 或共享 Card/Source/Anchor 语义；3.7 未实现项维持原状态。

## 17. 第五轮真人返修：编辑亮底、标签无路由浮层与提示文字溢出（2026-08-23）

| 范围 | 当前状态 | 自动化 / 真人边界 |
|---|---|---|
| 全局编辑移出亮底 | 已修，待真人 | `inlineSurface` 显式关闭主题继承的 filled / hoverColor，保持透明连续编辑面，不恢复卡片纸框。 |
| 视频标签打开时整页刷新 | 已修，待真人 | 移除 `showMenu` Navigator Route，改为当前路由内的 `OverlayEntry + TapRegion`；不重建或转场底层 Windows WebView，点击外部退出。 |
| 底部 Dock 提示文字 overflow | 已修，待真人 | “需要字幕”“空视频笔记”和保存确认提示均改为内部可滚动；640×360 下切换字幕 / 视频笔记无 RenderFlex overflow。 |

- 定向回归 43/43；6 个相关文件 analyze 零问题；`git diff --check` 通过。
- 未改 Card / Source / Anchor / PlayerAdapter 语义、schema、依赖或生成文件；不影响已真人通过的连线与图片封面。

## 18. 真人结论与 W0 G2 汇合状态（2026-08-23）

- 用户已明确确认 Wave 3 第五轮真人验收通过；验收分支最终记录为 `codex/whiteboard-wave3-acceptance@01213198`，对应产品代码截止 `b4ced67f`。
- 真人通过不等于可以只合产品分支：`codex/whiteboard-wave3-final-integration@ae3644b5` 仍包含对象恢复、并发、原子标注与错误边界等必须保留的安全语义。
- W0 已在 `codex/whiteboard-w0-g2@992578f3` 完成安全优先的语义汇合。95 个变更 Dart 文件 direct-dart analyze 零问题；关键修复 3/3；`git diff --check` 通过。
- Flutter 组合回归已在 G2 候选上真实执行并达到 269/269 通过。最初的等待不是另一开发窗口占锁，而是受限执行环境不能写 Flutter SDK cache lock；允许写入该缓存后恢复正常。
- 当前结论为“真人产品线通过、G2 代码候选已形成、动态组合 Gate 已过、Windows 联合构建与同版真人验收待补”；完成前不合入 `v3-lab`。
