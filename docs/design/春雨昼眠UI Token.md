# 春雨昼眠 · 应用级 UI Token

> 状态：2026-08-02 已落 Flutter。适用于个人中心、设置、表单、详情页、弹窗与系统反馈；Chat 继续使用独立的 `SpringRainChatTokens`。

## 为什么分成两套

「春雨昼眠」有两个不同亮度的产品空间：Chat 是近黑绿雨夜，普通功能页是偏白偏黄的暖雾昼面。`HereIamThemeTokens` 继续描述雨窗、玻璃和角色世界；`SpringRainUiTokens` 描述可操作的应用界面。两者共享苔绿与暖金关系，但不强行共用背景色。

## 语义色

| 类别 | Token | 用途 |
|---|---|---|
| 页面 | `canvas` | 暖象牙页面底色 |
| 承载 | `surface` / `surfaceRaised` / `surfaceMuted` | 普通卡片、浮起层、输入或图标底 |
| 选择 | `surfaceSelected` | 当前选项，不使用高饱和实色铺满 |
| 玻璃 | `glassFill` / `glassStroke` | 雨图上的局部浅雾，不做全屏蒙版 |
| 文字 | `textPrimary` / `textSecondary` / `textTertiary` | 标题、说明、弱提示 |
| 主操作 | `accent` / `accentPressed` / `accentSoft` | 苔绿主动作、按下态和低浓度选中态 |
| 陪伴强调 | `gold` / `goldSoft` | 需要注意但不危险的提醒与 Chat 呼应 |
| 状态 | `success` / `warning` / `error` / `info` 及各自 `Soft` | 每种状态都必须同时有文字色和低浓度承载色 |
| 边界 | `outline` / `divider` / `focus` / `disabled` | 控件边框、列表分割、焦点和不可用态 |
| 覆盖 | `scrim` | 模态层；非模态阅读聊天不得使用 |

## 尺寸系统

- 间距只使用 2 / 4 / 6 / 8 / 12 / 16 / 20 / 24 / 32 / 40。
- 圆角只使用 6 / 10 / 14 / 18 / 24 / 28；胶囊使用 `radiusPill`。
- 控件高度使用 36 / 44 / 52；图标使用 16 / 20 / 24。
- 动效使用 120 / 220 / 360ms，分别对应即时反馈、控件切换、页面内展开。
- 阴影只有 `shadowLow` 和 `shadowMedium` 两级；普通列表行不加阴影。

## 字体层级

Material `TextTheme` 是唯一文字入口：

- `headlineMedium`：页面核心标题，24px。
- `titleLarge`：AppBar 与大区块标题，18px。
- `titleMedium`：设置项与卡片标题，15.5px。
- `titleSmall`：分组标签，13px。
- `bodyLarge` / `bodyMedium` / `bodySmall`：正文、说明、元信息。
- `labelLarge` / `labelMedium`：按钮、Chip 与状态标签。

业务页面不得为了“看起来差不多”重新写字号和字色组合；确有新层级时先补语义 token。

## Material 组件映射

`SpringRainUiTheme.build` 已统一映射：AppBar、Card、ListTile、Input、Filled / Outlined / Text / Icon Button、Chip、Switch、Checkbox、Radio、Dialog、Bottom Sheet、SnackBar / Toast、Divider、Progress、Popup Menu、Tooltip。

个人中心使用 `SpringRainUiScope` 包裹所有向下路由，因此普通次级页会继承相同的背景、文字、控件、弹窗和反馈样式。仍然写死旧 `AppColors` 的历史页面需要逐页移除硬编码，但不再为每页发明新色板。

## 图片生成基准页

图片生成从旧 `SettingsPage` 中拆为独立 `ImageGenerationSettingsPage`，作为设置次级页迁移基准：

- 顶部只显示当前服务状态，不复刻个人中心的大图 Header。
- 四种真实后端用纵向选择卡呈现：通义万相、MiniMax、OpenAI 兼容、本地 ComfyUI。
- OpenAI 兼容只选择现有模型配置；ComfyUI 只编辑真实 URL 与基础模型。
- 保存和切换反馈统一走全局 SnackBar token，不自造悬浮提示。

## 迁移纪律

1. 新设置页先用 `SpringRainUiScope`，再用 `context.springRainUi` 读取业务语义色。
2. 禁止新增 `AppColors.primary`、靛蓝 `ColorScheme.fromSeed` 或裸 `Colors.grey[...]`。
3. 历史页迁移时先删除硬编码容器色，再让 Material 组件继承主题；不要把旧色值机械替换成另一组裸色值。
4. Chat、阅读器沉浸层和雨图页面有自己的场景 token；应用级 token 只负责普通可操作界面。
