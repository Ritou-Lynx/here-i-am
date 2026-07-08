# Chat Liquid Glass 借鉴方案

## 背景

当前 Chat 已经从整条顶栏/底栏改为全屏消息滚动层 + 顶部头像、右上按钮、任务胶囊、媒体托盘、输入框、悬浮球等独立悬浮层。视觉方向也已经进入“暮雨玫瑰玻璃”阶段，但各组件的玻璃材质仍然是分散实现：

- `PersonaChatScreen` 里已有 `_FloatingGlassCircle`、`_FrostedCircleButton`、`_FloatingGlassInputCapsule`、`_FrostedChatBubbleSurface`。
- `VoiceInputButton`、发送按钮、加号按钮都各自写了 `BackdropFilter`、渐变、边框和阴影。
- `FloatingRecordBall` 已经是自绘液态水滴，但材质语言与 Chat 顶部/输入区还没有统一。

因此现在的问题不是“没有玻璃”，而是缺少一套统一的玻璃材料系统：组件边缘、高光、折射感、模糊强度、阴影高度和交互反馈没有形成同一种物理质感。

## 参考对象

参考 `liquid_glass_renderer` 的设计语言，但不在第一阶段把主 Chat 界面完全绑定到该 pre-release 包。

官方页面关键信息：

- 包名：`liquid_glass_renderer`
- 当前参考版本：`0.2.0-dev.4`
- 许可证：MIT
- 支持平台：Android / iOS / macOS
- 官方定位：experimental，需要谨慎用于生产环境
- 性能约束：建议使用 Impeller；移动端液态玻璃计算成本高；应限制 layer 覆盖面积、动画数量和 blended shape 数量；低端和中端设备需要真机测试
- 可借鉴能力：`LiquidGlassLayer`、`LiquidGlass`、`LiquidGlassBlendGroup`、`FakeGlass`、`GlassGlow`、`LiquidStretch`

## 核心策略

采用“两层实现，一套审美”的方式。

1. 默认实现：项目内自建 `HereIamGlassSurface`
   - 用现有 Flutter 能力实现：`BackdropFilter`、渐变叠层、边缘描线、内高光、暗部投影、轻微噪声/雨痕。
   - 不新增运行时风险，适合输入框、媒体托盘、toast、普通按钮等常驻 UI。
   - 参数模型借鉴 `LiquidGlassSettings`：`thickness`、`blur`、`glassColor`、`outlineIntensity`、`lightIntensity`、`saturation`，但映射到本项目的 `HereIamThemeTokens`。

2. 实验实现：少量焦点组件可接 `liquid_glass_renderer`
   - 只在视觉焦点上试：角色头像外框、右上按钮组、悬浮球、回到最新胶囊。
   - 只在 Android/iOS + Impeller + 性能白名单设备上开启。
   - 不用于长列表气泡、整条输入区背景、全屏覆盖层或频繁移动的大面积区域。

3. 统一入口
   - 所有 Chat 玻璃控件只依赖项目内 `HereIamGlassSurface` / `HereIamGlassButton` / `HereIamLiquidOrb`。
   - 是否使用真实 `LiquidGlass` 作为内部实现，由一个实验开关决定，业务组件不直接 import 第三方包。

## 组件映射

| 组件 | 当前位置 | 借鉴方式 | 第一阶段实现 |
|---|---|---|---|
| 角色头像外框 | `_buildHeader` / `_FloatingGlassCircle` | `LiquidRoundedSuperellipse` + edge highlight | 改成 `HereIamGlassSurface(level: hero, shape: circle)`，增强边缘和上左高光 |
| 右上角更多按钮 | `_FrostedCircleButton` / `_HeaderActionButton` | `GlassGlow` + grouped button feel | 抽为 `HereIamGlassButton`，统一圆形按钮、菜单按钮、active 状态 |
| 输入框 | `PersonaChatInputBar` / `_FloatingGlassInputCapsule` | `FakeGlass` 思路，不用真实折射 | 保留 `BackdropFilter`，降低黑底糊感，增加清晰边缘、内层乳白雾面和底部阴影 |
| 加号/语音/发送按钮 | `_AddButton` / `_VoiceModeButton` / `_SendButton` / `VoiceInputButton` | 小尺寸 `LiquidGlass` / `GlassGlow` | 先共用 `HereIamGlassButton` 参数，active 时加触摸 glow |
| 媒体托盘 | `CompanionMediaTray` | `FakeGlass` + 独立 layer | 改成同一 glass surface，避免像普通深色面板 |
| 悬浮球 | `FloatingRecordBall` | `LiquidStretch` + touch glow + liquid edge | 保留自绘水滴，增加 shared glass token；后续可做真实 `LiquidGlass` 实验版 |
| 回到最新胶囊 | `_buildJumpToLatestPill` | 小型 `FakeGlass` | 改为半透明玻璃胶囊，弱化填充，强化边缘 |
| 消息气泡 | `_FrostedChatBubbleSurface` | 不接真实 LiquidGlass | 只保留现有 frosted bubble，避免长列表性能风险 |

## 材料等级

定义四个等级，避免每个组件单独调参：

- `subtle`：轻玻璃。用于菜单项、toast、回到最新胶囊。低 blur，低阴影。
- `raised`：常规悬浮玻璃。用于输入框、媒体托盘、普通圆形按钮。
- `hero`：视觉焦点玻璃。用于角色头像、主发送按钮、悬浮球静态外层。
- `liquid`：实验液态玻璃。只用于悬浮球、头像外框、右上按钮组等小面积焦点。

每个等级统一控制：

- 背景模糊强度
- 雾面填充透明度
- 边缘描线透明度
- 顶左高光 / 底右暗边
- 投影高度
- active / pressed glow
- 是否允许真实 liquid renderer

## 实施阶段

### Phase 1：统一材质，不引入第三方依赖

目标：先解决“糊在一起”和“各自为政”的问题。

- 新增 `lib/ui/core/widgets/here_iam_glass_surface.dart`
- 用 `HereIamThemeTokens.glassFill`、`glassFillSoft`、`glassStroke`、`glassEdge` 驱动统一玻璃外观
- 替换 Chat 里的头像外框、顶部按钮、输入框、发送/语音/加号按钮、回到最新胶囊、媒体托盘
- 保留悬浮球当前自绘，但改用同一套颜色和交互参数
- 真机观察：文字可读性、键盘弹起、滚动帧率、按钮点击反馈

### Phase 2：小面积实验接入 `liquid_glass_renderer`

目标：验证真实液态玻璃是否值得进入产品。

- 新增实验开关：默认关闭
- 添加第三方依赖，但只允许 core glass adapter import
- 在头像外框或悬浮球上做 A/B 对比
- 使用 `LiquidGlassLayer` 时限制覆盖区域，不做全屏 layer
- 优先使用 `FakeGlass` 或 `LiquidGlass.withOwnLayer`，避免大面积 blend group
- 不使用 `Glassify`

### Phase 3：交互细节

目标：让玻璃不像贴图，而像可触摸的物件。

- pressed 时短暂提高 outline / glow
- 拖动悬浮球时加入轻微 squash / stretch
- 右上按钮菜单打开时，按钮组可以有 grouped liquid feel
- 输入框聚焦时只增强边缘，不做剧烈形变，避免影响输入稳定性

## 性能与降级规则

- 默认路径必须不依赖真实 liquid shader。
- 真实 `LiquidGlass` 只允许小面积、低数量、少动画。
- 禁止在消息列表气泡上使用真实 liquid renderer。
- 禁止给整屏 Chat 放一个巨大 `LiquidGlassLayer`。
- 低端机、掉帧、发热或键盘动画不稳时，立即回退到 `FakeGlass` / `HereIamGlassSurface`。
- 所有实验实现必须保留同尺寸 fallback，避免切换时布局跳动。

## 验收标准

- 顶部头像、右上按钮、输入框、悬浮球看起来属于同一种玻璃材质。
- 组件之间有清晰层级：头像/悬浮球最强，输入框次之，普通按钮和提示胶囊更轻。
- 输入框文字、hint、图标在暗色背景和图片背景上都保持可读。
- 键盘弹起、媒体托盘展开、语音按钮切换、悬浮球拖动时不出现明显卡顿。
- 不牺牲 Chat 的长期可维护性：业务组件不直接依赖第三方液态玻璃包。

## 推荐下一步

先做 Phase 1。等统一材质稳定后，再只拿悬浮球或头像外框做 Phase 2 实验。这样能最快改善当前“糊在一起”的感受，同时保留真正液态玻璃的探索空间。
