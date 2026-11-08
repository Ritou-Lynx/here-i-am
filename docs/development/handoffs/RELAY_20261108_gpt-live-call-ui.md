<!-- relay:contract v1 -->
## 目标
把 GPT-Live 通话页从“纯黑底 + 一行字幕”改成像样的来电界面：头像、呼吸光环、状态、两行字幕、结束卡片、催睡标签。只改界面和少量只读字段，不改通话协议。

## 背景
- 页面：`lib/ui/character/widgets/gpt_live_call_screen.dart`；通话逻辑：`lib/data/services/gpt_live/gpt_live_call.dart`。
- #107 已合入：`GptLiveCall` 内部记了 `_endReason` / `_lastServerError`，`GptLiveSettings` 有 `GptLiveCallRecord.reasonText`（原因转中文）。本轮要复用这套文字，不要另写一份。
- #108 已合入（删了旧人设字段），不要引用已删字段。
- 头像组件现成：`lib/ui/core/widgets/character_avatar.dart` 的 `CharacterAvatar(avatar:, name:, size:)`。

## 完成标准
- [ ] **背景**：不再是纯色 `0xFF1B1D1A`。有头像时用头像放大 + `ImageFiltered`/`BackdropFilter` 模糊，再叠一层暖色深色渐变（上浅下深）；没有头像或加载失败时只用渐变。文字对比度保持可读。
- [ ] **中央头像**：约 128–144 dp 的 `CharacterAvatar`，外圈一层柔和光环做“呼吸”动画（单个 `AnimationController`，约 2.5–3 秒一周期，repeat reverse）。只在 `live` 阶段呼吸，`connecting` 时光环转为较慢的脉冲或静止，`ending/ended/failed` 停止。**不做**说话方识别、不读音量、不调用 getStats、不加任何轮询。
- [ ] **头像数据**：`GptLiveCall` 在已有读取 character 的地方顺带保存 `characterAvatar`（只读 `String?`，与 `characterName` 同处赋值），页面用它。
- [ ] **名字 + 状态行**：名字大字；下方状态依次为「正在接通…」、计时 `mm:ss`（满 1 小时显示 `h:mm:ss`）、「已静音」（live 且 muted 时显示在计时旁，如 `03:12 · 已静音`）、「正在挂断…」。
- [ ] **字幕**：显示本通最近两句（来自 `transcript`），她的话白色较大字，用户的话灰色较小字；没有内容时显示一行很淡的占位（如「说点什么吧」），避免页面空。字幕区可向上滑动查看本通完整转写（`ListView` 反向或滚到底，限制在页面中部区域，不挤压按钮）。如 `GptLiveTranscript` 需要暴露带角色的最近若干条，只加只读 getter。
- [ ] **按钮**：保留静音 / 挂断 / 扬声器三个，挂断键居中且更大（约 76 dp），三个按钮点按都调用 `HapticFeedback.lightImpact()`（挂断用 `mediumImpact()`）。现有静音/扬声器逻辑不变。
- [ ] **结束卡片**：
  - 正常结束（`ended`）时不再立刻 `pop`：显示结束卡片「通话结束 · X 分 Y 秒 · 原因」，原因文字用 `GptLiveCallRecord.reasonText` 同一套规则（可在 `GptLiveCall` 暴露只读 `endReason` 与 `lastServerError`，并把原因转文字的逻辑抽成可复用的静态函数，`GptLiveCallRecord.reasonText` 改为调用它，行为不变）。停 2 秒后自动退出；点卡片任意处立即退出；期间返回键也可直接退出。
  - 用户自己按挂断或返回时同样显示卡片 2 秒（原因为「你挂断」）。注意 `_hangUpAndLeave` 现在 `await hangUp()` 后直接 `pop`，要改成走同一个结束卡片流程，且只 `pop` 一次（保留 `_leaving` 之类的防重入）。
  - 失败（`failed`）：显示「没接通」+ 错误原因，按钮为「重拨」和「返回」。「重拨」用 `pushReplacement` 打开一个参数相同的新 `GptLiveCallScreen`（不要在同一个 `GptLiveCall` 实例上重复 `start()`）。
- [ ] **催睡来电**：`widget.callReason` 非空时，顶部显示小标签「林埃来电 · 催睡」（名字取 `characterName`，缺省「林埃」）；若 `maxDuration` 非空，标签旁显示剩余时间 `剩 mm:ss`。
- [ ] **来源标签**：原来居中的「GPT-Live 备选通话」改成右上角很小的半透明标签「GPT-Live」。
- [ ] 锁屏显示（`showWhenLocked`）、`dispose` 兜底挂断、`max_duration` 自动挂断、`PopScope` 行为保持不变（只是在挂断后多了结束卡片）。
- [ ] 不新增依赖（`pubspec.yaml` 不变）。
- [ ] 新增/更新测试：
  - `test/ui/character/widgets/gpt_live_call_screen_test.dart`（或抽出的纯组件测试）：至少覆盖结束卡片文案（时长 + 原因）、失败态出现「重拨」「返回」、催睡标签与剩余时间格式。为避免真实 WebRTC，可把结束卡片、状态文字格式化、剩余时间格式化抽成纯函数或无状态组件单测。
  - 原因转文字抽出后，`test/data/services/gpt_live/gpt_live_protocol_test.dart` 里现有的 `reasonText` 断言保持通过。
- [ ] 新增的界面代码可以放在 `lib/ui/character/widgets/gpt_live_call/` 子目录（如 `call_background.dart`、`breathing_avatar.dart`、`call_end_card.dart`），通话页主文件保持可读。

## 允许修改的路径
- lib/ui/character/widgets/gpt_live_call_screen.dart
- lib/ui/character/widgets/gpt_live_call/（新建）
- lib/data/services/gpt_live/gpt_live_call.dart（只加只读字段/getter，不改连接、协议、写回逻辑）
- lib/data/services/gpt_live/gpt_live_protocol.dart（只允许给 `GptLiveTranscript` 加只读 getter）
- lib/data/services/gpt_live/gpt_live_settings.dart（只允许抽出原因转文字的函数，行为不变）
- test/ui/character/widgets/
- test/data/services/gpt_live/
- docs/development/handoffs/RELAY_20261108_gpt-live-call-ui.md（本文，只追加执行记录）

## 不做 / 边界
- 不做说话方识别、音量波形、getStats 或任何定时轮询（用户明确说影响性能的先不加）。
- 不改 GPT-Live 协议、会话参数、转写写回、设置页。
- 不改 ElevenLabs 通话或其他页面。
- 不构建、不安装 App，不碰真实账户、令牌、数据库。仓库公开，不写本机路径和任何密钥。

## 验证命令
- `flutter analyze lib/ui/character/widgets/ lib/data/services/gpt_live/ test/ui/character/widgets/ test/data/services/gpt_live/`
- `flutter test test/ui/character/widgets/ test/data/services/gpt_live/`
- 本机沙箱跑不了 Flutter 时，在结果里写明，以 CI 为准。

## 需要真人的部分
- 用户本机从 v3-lab 编译安装后实拨一通，看界面、结束卡片、催睡来电标签。
