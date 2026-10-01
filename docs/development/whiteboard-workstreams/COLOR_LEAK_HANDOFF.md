# 白板工作台颜色泄漏问题交接

> 日期：2026-08-22
> 来源：OpenCode (glm-5.2) 颜色迁移会话
> 提交基线：`f9557283`（手机 App 已迁移到春雨昼眠，白板未动）

---

## 一、问题现象

白板工作台的**次级弹窗**（SnackBar、Dialog 里的 TextField 边框、OutlinedButton 边框、PopupMenu 文字、未设色的 IconButton）仍然显示白紫色/indigo 配色，而不是桌面 Lieflat Palm palette 的奶白/苔绿色。

## 二、根因

`DesktopWorkspaceTheme`（`lib/ui/desktop/desktop_workspace_tokens.dart:124-155`）只 override 了 `ColorScheme` 的 **4 个字段**：

```
surface, primary, onPrimary, error
```

其余全部通过 `base.colorScheme.copyWith(...)` 继承上层全局 Theme。在 `f9557283` 之前，全局 Theme 是 indigo `ColorScheme.fromSeed(0xFF6366F1)`，所以未覆盖字段全是紫蓝派生色。

`f9557283` 已把全局 Theme 改为春雨昼眠，所以继承字段不再是紫——但 `DesktopWorkspaceTheme` 仍然**没有显式覆盖**这些字段，属于脆弱设计：只要上层 theme 变化，次级弹窗颜色就会跟着漂。

### 未被覆盖的 ColorScheme 字段清单

| 字段 | 谁会读它 | 当前继承值（春雨昼眠） | 风险 |
|------|---------|---------------------|------|
| `secondary` | Dialog 次要按钮 | 苔绿 gold | 脆弱 |
| `tertiary` | Info 色调 | info teal | 脆弱 |
| `primaryContainer` | Chip 选中态、按钮填充 | accentSoft | 脆弱 |
| `onPrimaryContainer` | primaryContainer 上的文字 | textPrimary | 脆弱 |
| `secondaryContainer` | 次级容器 | goldSoft | 脆弱 |
| `onSecondaryContainer` | | textPrimary | 脆弱 |
| `onSurfaceVariant` | **IconButton 默认色、TextField hint/label** | textSecondary | 脆弱 |
| `surfaceContainerHighest` | **TextField fill（未设 fillColor 时）** | surfaceMuted | 脆弱 |
| `outline` | **OutlinedButton 边框、OutlineInputBorder 默认边框** | outline | 脆弱 |
| `outlineVariant` | 细分隔线 | divider | 脆弱 |
| `inverseSurface` | **SnackBar 默认背景** | textPrimary (深绿) | 脆弱 |
| `onInverseSurface` | **SnackBar 默认文字** | textOnAccent (暖白) | 脆弱 |
| `shadow` | 阴影色 | 0xFF293025 | 脆弱 |
| `scrim` | 遮罩 | scrim | 脆弱 |

## 三、泄漏的具体路径（9 类，带精确行号）

### 泄漏 1：SnackBar（9 处）— 最明显的"白紫弹窗"

所有 9 处都是裸 `SnackBar(content: Text(...))`，没设 `backgroundColor`。背景回退到 `Theme.snackBarTheme.backgroundColor` 或 `colorScheme.inverseSurface`；文字回退到 `onInverseSurface`。

| # | 文件 | 行号 | 文案 |
|---|------|------|------|
| 1 | `lib/ui/whiteboard/card_library_screen_v2.dart` | 218-219 | "新建失败：$error" |
| 2 | `lib/ui/whiteboard/card_library_screen_v2.dart` | 275-276 | "已放入"$boardName"" |
| 3 | `lib/ui/whiteboard/card_library_screen_v2.dart` | 281-282 | "放入白板失败：$error" |
| 4 | `lib/ui/whiteboard/whiteboard_index_screen.dart` | 133-134 | "创建失败：$error" |
| 5 | `lib/ui/whiteboard/whiteboard_canvas_route_screen.dart` | 227-228 | "白板已保存" / $_saveError |
| 6 | `lib/ui/whiteboard/editor/card_rich_text_editor_screen.dart` | 127-128 | "已保存" |
| 7 | `lib/ui/whiteboard/editor/card_rich_text_editor_screen.dart` | 133-134 | "保存失败：$error" |
| 8 | `lib/ui/whiteboard/editor/card_rich_text_editor.dart` | 880-881 | "仅支持 http / https / mailto 链接" |
| 9 | `lib/ui/whiteboard/video/video_study_screen.dart` | 485-487 | "无法打开原链接，请复制链接后重试。" |

**修复方向**：在 `DesktopWorkspaceTheme` 的 `Theme.copyWith` 里加 `snackBarTheme`，用 `tokens.dark` / `tokens.canvas` 做背景，`tokens.canvas` / `tokens.surfaceRaised` 做文字。这样 9 处全部一次覆盖，无需逐个改调用点。

---

### 泄漏 2：AlertDialog 里的裸 TextField 边框（2 处）

`InputDecoration` 没设 `border`/`fillColor`/`enabledBorder`，边框和填充回退到 `inputDecorationTheme`（继承上层）或 `colorScheme.outline` / `surfaceContainerHighest`。

| # | 文件 | 行号 | 场景 |
|---|------|------|------|
| 1 | `lib/ui/whiteboard/whiteboard_index_screen.dart` | 94-105 | "新建白板" dialog 的 `TextField`，`InputDecoration(hintText: '白板名称')` 无 border |
| 2 | `lib/ui/whiteboard/video/widgets/subtitle_list_view.dart` | 334-340 | 字幕导入 dialog 的粘贴 `TextField`，`InputDecoration(border: OutlineInputBorder())` 无 borderSide 色 |

对比正面案例：`card_rich_text_editor.dart:842-854` 的链接插入 dialog 已显式设了 `fillColor: tokens.surface`、`focusedBorder`、`enabledBorder`——不泄漏。

**修复方向**：在 `DesktopWorkspaceTheme` 里加 `inputDecorationTheme`，用 `tokens.divider` 做默认边框、`tokens.action` 做 focus 边框、`tokens.surfaceRaised` 做 fill。

---

### 泄漏 3：OutlinedButton 边框（4 处）

`OutlinedButton` 没设 `style`，边框回退到 `colorScheme.outline`（继承上层）。

| # | 文件 | 行号 | 场景 |
|---|------|------|------|
| 1 | `lib/ui/whiteboard/video/widgets/subtitle_list_view.dart` | 321-325 | "选择 SRT / VTT 文件" `OutlinedButton.icon` |
| 2 | `lib/ui/whiteboard/card_library_screen_v2.dart` | 1154 | 空态/错误的 `OutlinedButton` |
| 3 | `lib/ui/whiteboard/whiteboard_index_screen.dart` | 613 | 空态的 `OutlinedButton` |
| 4 | `lib/ui/whiteboard/whiteboard_canvas_route_screen.dart` | 294-297 | 错误页"返回" `OutlinedButton` |

**修复方向**：在 `DesktopWorkspaceTheme` 里加 `outlinedButtonTheme`，用 `tokens.divider` / `tokens.outline` 做 side。

---

### 泄漏 4：未设色的 IconButton（1 处）

| 文件 | 行号 | 场景 |
|------|------|------|
| `lib/ui/desktop/widgets/workbench_action_card.dart` | 188-193 | 行动卡详情抽屉的关闭 `IconButton`，无 `color` 参数 |

图标静止色回退到 `iconTheme.color` → 默认 `colorScheme.onSurfaceVariant`（继承上层）。对比同文件其他 IconButton 和 `desktop_workspace_shell.dart:150` 都显式设了 `color: tokens.textFaint`。

**修复方向**：加 `color: tokens.textMuted` 或 `tokens.textFaint`，或在 `DesktopWorkspaceTheme` 里加 `iconButtonTheme`。

---

### 泄漏 5：PopupMenuButton 菜单项文字（1 处）

| 文件 | 行号 | 场景 |
|------|------|------|
| `lib/ui/whiteboard/card_library_screen_v2.dart` | 768-813 | `PopupMenuButton` 的 `PopupMenuItem` 文字无显式色 → `colorScheme.onSurface`（继承） |

菜单背景已设 `color: palette.surfaceRaised`（OK），但 item 文字回退到 `onSurface`。

**修复方向**：给 `PopupMenuItem` 的 `Text` 加显式 `color`，或在 `DesktopWorkspaceTheme` 加 `popupMenuTheme`。

---

### 泄漏 6：AlertDialog actions 里的 TextButton（多处）

Dialog 里的"取消" `TextButton` 没设 `foregroundColor`，文字色回退到 `colorScheme.primary`（已被 override = OK）或 `textButtonTheme`（继承上层）。

| 文件 | 行号 | 场景 |
|------|------|------|
| `lib/ui/whiteboard/whiteboard_index_screen.dart` | 107-110 | "新建白板" dialog 的"取消" |
| `lib/ui/whiteboard/video/widgets/subtitle_list_view.dart` | 351-353 | 字幕导入 dialog 的"取消" |
| `lib/ui/whiteboard/editor/unsaved_exit_guard.dart` | 67-70 | "尚未保存" dialog 的"取消" |

对比正面案例：`unsaved_exit_guard.dart:75` 的"放弃"按钮已显式设 `foreground: tokens.error`。

**修复方向**：在 `DesktopWorkspaceTheme` 加 `textButtonTheme`，用 `tokens.textMuted` / `tokens.action` 做 foreground。

---

### 泄漏 7：AlertDialog 的 FilledButton（多处理论 OK，但需确认）

Dialog 里的"确认" `FilledButton` 没设 `style`，回退到 `filledButtonTheme`（继承上层春雨昼眠 = 苔绿 accent）。颜色不是紫，但不是 Lieflat Palm 的 `tokens.action`。

| 文件 | 行号 | 场景 |
|------|------|------|
| `lib/ui/whiteboard/whiteboard_index_screen.dart` | 111-118 | "新建白板" dialog 的"创建" |
| `lib/ui/whiteboard/video/widgets/subtitle_list_view.dart` | 355-361 | 字幕导入 dialog 的"导入" |

对比正面案例：`unsaved_exit_guard.dart:78-85` 已显式设 `backgroundColor: tokens.action`、`foregroundColor: tokens.canvas`。

**修复方向**：在 `DesktopWorkspaceTheme` 加 `filledButtonTheme`，用 `tokens.action` / `tokens.canvas`。

---

## 四、推荐的修复方案

### 方案 A（推荐）：在 `DesktopWorkspaceTheme` 补全 Material 组件主题

在 `lib/ui/desktop/desktop_workspace_tokens.dart` 的 `DesktopWorkspaceTheme.build()` 里，给 `Theme.copyWith` 追加：

1. **完整 `colorScheme` 覆盖**——用 `tokens` 值填充所有字段，不再 `copyWith` 只改 4 个
2. **`snackBarTheme`**——背景 `tokens.dark`，文字 `tokens.canvas`
3. **`inputDecorationTheme`**——fill `tokens.surfaceRaised`，border `tokens.divider`，focus `tokens.action`
4. **`outlinedButtonTheme`**——side `tokens.divider`
5. **`filledButtonTheme`**——bg `tokens.action`，fg `tokens.canvas`
6. **`textButtonTheme`**——fg `tokens.textMuted`
7. **`iconButtonTheme`**——fg `tokens.textMuted`
8. **`dialogTheme`**——bg `tokens.surfaceRaised`，shape 圆角
9. **`popupMenuTheme`**——bg `tokens.surfaceRaised`

这样所有次级弹窗一次性覆盖，9 处 SnackBar + 2 处裸 TextField + 4 处 OutlinedButton + 1 处 IconButton + 1 处 PopupMenu 全部不再依赖上层 theme。

### 方案 B（补丁式）：逐个调用点加显式色

在每个泄漏点加 `color` / `style` 参数。工作量大，且后续新增弹窗仍会泄漏。不推荐。

---

## 五、验证方法

1. 改完后 `flutter analyze lib/ui/desktop/ lib/ui/whiteboard/` 零 error
2. Windows 真窗口构建（需 `flutter clean` 清除旧 build 缓存）：
   ```
   flutter clean
   flutter build windows --debug
   ```
3. 逐个验证：
   - 触发每个 SnackBar（新建失败、保存成功、保存失败等）→ 应为 Lieflat Palm 深绿背景 + 奶白文字
   - 打开"新建白板"dialog → TextField 边框应为 `tokens.divider` 暖灰
   - 打开字幕导入 dialog → OutlinedButton 边框和 TextField 边框同上
   - 打开行动卡详情 → 关闭 IconButton 应为 `tokens.textMuted`
   - 打开筛选 PopupMenu → 菜单项文字应为 `tokens.textPrimary`

---

## 六、不在本次范围

- 手机 App 已在 `f9557283` 迁移完成，不需要动
- `AppColors` 已改为春雨昼眠转发壳，保留不删（175 处引用）
- `ToastHelper`（`toast_helper.dart`）用 `Colors.blue.shade600` / `Colors.green.shade600` 等独立值，不属于桌面 palette 泄漏