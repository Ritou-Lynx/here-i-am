# Chat 四件套 Liquid Glass 借鉴方案

## 范围

本轮只处理 Chat 首页里最容易建立层级、且面积可控的四个焦点组件：

1. 角色头像外框
2. 右上角“更多”按钮
3. 底部输入框
4. 悬浮记录球

不处理聊天气泡、消息列表、整屏背景、媒体托盘、toast、回到最新胶囊或其它普通按钮。它们后续可以沿用同一套材质 token，但不进入本轮液态玻璃试验范围。

## 为什么只做四件套

当前 Chat 已经从整条顶栏/底栏改为全屏消息滚动层 + 独立悬浮组件。新的问题是：背景、气泡、输入框、头像和悬浮球都在同一套深酒红半透明里，颜色和材质容易糊成一片。

四件套正好是最需要“浮起来”的控件：

- 头像外框是角色存在感的锚点。
- 右上角更多是顶部操作入口，需要和头像同属一套玻璃语言。
- 输入框是高频焦点，需要更清晰的边界和可读性。
- 悬浮球是记录入口，本来就适合做成活的水滴。

这样可以提升层级，但不把长列表和整屏都卷入高成本 shader。

## 参考对象

以开源 Liquid Glass 组件为视觉和参数参考，而不是一上来全量依赖第三方运行时。

- `liquid_glass_renderer`
  - 参考能力：`LiquidGlassLayer`、`LiquidGlass`、`LiquidGlassBlendGroup`、`FakeGlass`、`GlassGlow`、`LiquidStretch`
  - 适合实验：头像外框、更多按钮、悬浮球这类小面积焦点
  - 风险：experimental / pre-release，移动端真实液态玻璃计算成本高

- `liquid_glass_widgets`
  - 参考能力：玻璃组件参数、动态光照、jelly/pressed 反馈、降级策略
  - 适合借鉴：内部 `HereIamGlassSurface` 的 API 设计

- `liquid_glass_easy`
  - 参考能力：实时凸透镜、折射和液态边缘
  - 适合借鉴：悬浮球与头像外框的“水膜凸起”视觉

## 实现策略

采用“两层实现，一套审美”。

### 默认实现：项目内 Fake Liquid Glass

新增或统一项目内玻璃组件：

- `HereIamGlassSurface`
- `HereIamGlassButton`
- `HereIamLiquidOrb`

用现有 Flutter 能力实现：

- `BackdropFilter`
- 多层 `Stack`
- 深酒红半透明底
- 内层乳白雾面
- 顶左柔光
- 底右暗部压深
- 玫瑰铜边缘折射
- 柔和投影
- pressed / active glow

这条路径默认开启，适合输入框，也适合所有设备。

### 实验实现：小面积真实 Liquid Glass

如果接入第三方包，只允许在小面积焦点上试：

- 头像外框
- 右上角更多按钮
- 悬浮球

输入框默认不使用真实液态 shader。输入框有键盘、多行高度变化、输入法动画和图标切换，优先保持稳定，用 Fake Liquid Glass 做材质效果。

## 四件套映射

| 组件 | 当前位置 | 材质强度 | 第一阶段 | 第二阶段实验 |
|---|---|---|---|---|
| 角色头像外框 | `_buildHeader` / `_FloatingGlassCircle` | `hero` | 圆形液态玻璃外框，强化边缘折射、左上高光、右下暗边 | 可试真实 `LiquidGlass` 小层 |
| 右上角更多 | `_FrostedCircleButton` / `_HeaderActionButton` | `raised` | 统一为小圆形玻璃按钮，active 时轻 glow | 可和头像共用小型真实 layer |
| 输入框 | `PersonaChatInputBar` / `_FloatingGlassInputCapsule` | `raised` | Fake Liquid Glass，多层胶囊/钝角矩形，清晰边界但无硬白线 | 暂不接真实 shader |
| 悬浮球 | `FloatingRecordBall` | `liquid` | 保留自绘水滴，统一颜色、阴影和高光 token | 最适合试真实 liquid / stretch |

## 材料等级

本轮只需要三个等级：

- `raised`：右上角更多、输入框。清晰但不抢戏。
- `hero`：头像外框。比输入框更亮、更有折射。
- `liquid`：悬浮球。最有水滴生命感，允许轻微形变和呼吸。

共同参数：

- `blur`
- `baseOpacity`
- `edgeIntensity`
- `highlightIntensity`
- `shadowDepth`
- `warmGlow`
- `pressedGlow`
- `liquidDistortion`

## 视觉原则

- 不靠换成多种颜色解决区分度，主要靠材质层级。
- 不使用完整明显白边，边缘来自折射、高光和暗边。
- 头像和悬浮球可以最立体，输入框必须稳定、清晰、不过分变形。
- 右上角更多应像头像旁的一颗小玻璃珠，而不是默认 Material IconButton。
- 悬浮球内部只保留圆润加号，不放额外横线或复杂符号。

## 性能规则

- 禁止给整屏 Chat 放一个巨大 `LiquidGlassLayer`。
- 禁止在聊天气泡或长列表上使用真实 liquid renderer。
- 输入框默认使用 Fake Liquid Glass。
- 真实 liquid 只允许少量、小面积、低动画密度。
- 所有真实 liquid 实验必须保留同尺寸 fallback，避免切换时布局跳动。

## 验收标准

- 四件套看起来属于同一种液态玻璃材质。
- 头像外框和悬浮球有明显“浮起”的层级。
- 右上角更多与头像在同一视觉系统内，但更轻。
- 输入框边界更清楚，文字和图标更可读，不出现硬白边或平面黑底。
- 滚动、键盘弹起、多行输入和悬浮球拖动不掉帧、不闪烁。

## 推荐下一步

先用 HTML 样式板确认四件套方向，再落 Flutter Phase 1：

1. 抽 `HereIamGlassSurface` / `HereIamGlassButton` / `HereIamLiquidOrb`
2. 替换头像外框、更多按钮、输入框、悬浮球
3. 真机观察层级、可读性和性能
4. 再决定是否只给头像外框或悬浮球接真实 Liquid Glass 实验
