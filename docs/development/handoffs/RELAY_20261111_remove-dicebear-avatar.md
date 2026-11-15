<!-- relay:contract v1 -->
## 目标
彻底移除上游 memex 遗留的 DiceBear 在线卡通头像（Notionists 线稿风格）。没有自定义头像、或头像还没加载出来时，统一显示“暖色圆形 + 名字首字”的本地占位。打开通话页时不再先闪一张卡通图。

## 背景
- `lib/ui/core/widgets/dicebear_avatar.dart`：按种子去 api.dicebear.com 拉 SVG，缓存到应用支持目录 `avatar_<md5>.svg`。
- `lib/ui/core/widgets/character_avatar.dart`：头像不是图片路径时（包括 null 和种子字符串）走 DiceBear；图片加载失败也回退到 DiceBear。聊天页、GPT-Live 通话页、通话悬浮窗（`global_call_overlay.dart`）、「关于 i」都经过它。
- `lib/ui/core/widgets/avatar_picker.dart`：换头像弹窗有 5 个 DiceBear 随机选项和一个“从相册选”。
- `lib/utils/user_storage.dart`：`defaultAvatarSeed = 'Felix'`、`avatarOptions`、旧 emoji 头像迁移成种子、`saveUserAvatar` 里 `cacheAvatarSvg`。
- `lib/data/services/character_service.dart`：内置 i 角色 seed 时写 `'avatar': 'i'`（种子），并 `existing['avatar'] ??= 'i'`。
- `lib/ui/character/widgets/persona_chat_screen.dart` 约 8866 行：用户头像为 null 时拿名字或 `defaultAvatarSeed` 当种子。
- `lib/ui/settings/widgets/personal_center_screen.dart`：用户头像默认 `UserStorage.defaultAvatarSeed`。
- `lib/data/services/callkit_service.dart`：种子已经映射成 null（用插件自带默认头像），本轮只改注释里的 DiceBear 字样，逻辑不变。

## 完成标准
- [ ] 删除 `lib/ui/core/widgets/dicebear_avatar.dart`，`lib/` 和 `test/` 里不再出现 `dicebear` / `DiceBear` / `api.dicebear.com`（大小写不敏感 grep 为 0；本合同文件和 DEVLOG 除外）。
- [ ] `CharacterAvatar`：
  - 图片路径（沿用现有 `isImageAvatar` 判断）照旧用 `LocalImage` 圆形显示；图片加载中和加载失败都显示占位，不再回退 DiceBear。
  - 非图片（null、空串、任何旧种子字符串）一律显示占位：圆形，背景用 `backgroundColor`，没有就用暖色（例如 `Color(0xFFE9D8C8)`），中间是 `name` 的第一个字符（按 `characters` 取第一个字素，拉丁字母转大写），字号约为直径的 0.42，颜色深暖色（例如 `Color(0xFF6B4F3A)`）。`name` 为空时显示 `Icons.person`。
  - 占位做成同文件内可复用的公开小组件（例如 `AvatarInitialPlaceholder`），方便测试。
- [ ] 通话页不闪：`lib/ui/character/widgets/gpt_live_call/breathing_avatar.dart` 和 `call_background.dart` 在头像从 null 变成图片路径时用 `AnimatedSwitcher`（约 250ms 淡入）切换，key 用头像值。背景在头像为 null 时只显示渐变（现在已经如此，确认即可），不要用占位字放大当背景。
- [ ] 换头像弹窗：删掉 DiceBear 随机选项、种子词表和“换一批”等相关 UI 与状态，只保留“从相册选”（保留 `pickAvatarImageFromGallery` 和 `showAvatarPicker` 的签名与返回值语义，调用方不用改，或同步改两个调用方）。弹窗可以继续显示当前头像预览（走 `CharacterAvatar`）。
- [ ] `UserStorage`：删 `defaultAvatarSeed`、`avatarOptions`、`_isLegacyEmoji` 迁移逻辑和所有 `cacheAvatarSvg` 调用；`getUserAvatar` 直接返回存的值（可能为 null 或旧种子，显示层会按占位处理）；`saveUserAvatar` 只保存。所有引用 `defaultAvatarSeed` 的地方改为传 null 或用户名字，交给占位显示。
- [ ] `CharacterService`：新 seed 的 i 角色不再写 `'avatar': 'i'`（不写 avatar 字段）；删除 `existing['avatar'] ??= 'i'`。已有数据不迁移、不改写。
- [ ] 缓存清理：App 启动后（找现有的启动初始化处，例如 `main.dart` 里初始化完成后）异步、只做一次地删除应用支持目录下匹配 `avatar_*.svg` 的文件。用 SharedPreferences 标记 `legacy_dicebear_cache_cleared` 防止重复扫描；任何异常吞掉只记日志，不能阻塞启动。逻辑放在一个小的纯函数/类里（参数为目录），便于测试。
- [ ] `flutter_svg` 依赖还被其他文件使用，`pubspec.yaml` 不改。
- [ ] 测试：
  - `CharacterAvatar` 在 avatar 为 null、旧种子（如 `'Felix'`、`'i'`）时显示名字首字占位，不包含 `SvgPicture`；name 为空时显示 `Icons.person`；英文名首字母大写。
  - 缓存清理：在临时目录放 `avatar_abc.svg`、`avatar_def.svg`、`other.svg`，清理后只剩 `other.svg`。
  - 换头像弹窗打开后只有“从相册选”入口（如现有测试结构允许）。
  - 原有涉及头像、avatar_picker、user_storage 的测试若断言了 DiceBear 行为，按新行为更新，不许删除测试来变绿。

## 允许修改的路径
- lib/ui/core/widgets/dicebear_avatar.dart（删除）
- lib/ui/core/widgets/character_avatar.dart
- lib/ui/core/widgets/avatar_picker.dart
- lib/ui/character/widgets/gpt_live_call/breathing_avatar.dart
- lib/ui/character/widgets/gpt_live_call/call_background.dart
- lib/ui/character/widgets/persona_chat_screen.dart（只改用户头像默认种子那一处）
- lib/ui/character/widgets/about_i_screen.dart（仅当 showAvatarPicker 调用需要调整）
- lib/ui/settings/widgets/personal_center_screen.dart（只改默认头像种子相关）
- lib/ui/companion/widgets/global_call_overlay.dart（只改注释）
- lib/data/services/callkit_service.dart（只改注释）
- lib/data/services/character_service.dart（只改默认 avatar 种子两处和相关注释）
- lib/utils/user_storage.dart（只改头像相关）
- lib/main.dart 或现有启动初始化文件（只加一次性缓存清理调用）
- lib/utils/legacy_avatar_cache_cleaner.dart（新建，或放在同等合适位置）
- test/ 下与上述文件对应的测试（新增或更新）
- DEVLOG.md（追加一条）
- docs/development/handoffs/RELAY_20261111_remove-dicebear-avatar.md（本文，只追加执行记录）

## 不做 / 边界
- 不改数据库、不迁移已有角色和用户数据；旧种子值留在数据里，显示时自动走占位。
- 不改 CallKit 插件（packages/flutter_callkit_incoming）和原生资源。
- 不动 `pubspec.yaml` / `pubspec.lock`。
- 不改通话逻辑和 #111 的结束卡片流程，只在头像/背景切换处加淡入。
- 不构建、不安装 App，不碰真实账户、令牌、数据库。仓库公开，不写本机路径和密钥。

## 验证命令
- `grep -rni "dicebear" lib test` → 无结果
- `flutter analyze` 改动的文件
- `flutter test` 新增/更新的测试文件，以及 `test/ui/character/widgets/`
- 本机跑不了 Flutter 时在结果里写明，以 CI 为准。

## 需要真人的部分
- 用户本机从 v3-lab 编译安装后，打开通话页、聊天页、个人中心、「关于 i」看头像，确认不再出现卡通图。
