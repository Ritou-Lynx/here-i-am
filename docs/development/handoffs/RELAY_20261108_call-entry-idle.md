<!-- relay:contract v1 -->
# RELAY 2026-11-08：通话入口合并 + GPT-Live 静音自动挂断

## 目标
1. 聊天页只保留一个通话入口：底部输入框最右边的通话按钮。设置里的“通话引擎”决定它走哪一套：原通话（STT → App 聊天模型 → TTS），或者 GPT-Live。右上角菜单里的“GPT-Live 通话（备选）”删掉。催睡来电也改用同一个引擎设置。
2. GPT-Live 加静音自动挂断：通话中双方都持续 N 分钟没说话（默认 5），先让林埃问一句，再等 20 秒仍没人说话就挂断。N 为 0 表示关闭。

## 完成标准
- [ ] 新建 `lib/data/services/call_engine_settings.dart`：
  - `enum CallEngine { classic('classic'), gptLive('gpt_live') }`，带 `parse`。
  - `CallEngineSettings.get()` / `set()`，SharedPreferences 键为 `call.engine`。
  - 迁移规则：没有 `call.engine` 时，读旧键 `sleep_nudge.engine`（值 `gpt_live` / `classic`），读到就用它，否则默认 `gptLive`。只读旧键，不删。
- [ ] 聊天页 `lib/ui/character/widgets/persona_chat_screen.dart`：
  - `_toggleGlobalCallFromChat()`：引擎为 `gptLive` 时调用现有的 `_openGptLiveCall()`，否则保持原逻辑（包括通话中再点一次挂断）。
  - 删除右上角菜单中“GPT-Live 通话（备选）”这一项（`_HeaderActionButton`，`icon: Icons.phone_in_talk_outlined`）。`_openGptLiveCall` 和 `_gptLiveCallOpen` 保留，底部按钮还要用。
  - 文件是 CRLF，保持 CRLF。
- [ ] 催睡：`SleepNudgeConfig.engine` 不再单独存储，改为从 `CallEngineSettings` 取值（`SleepNudgeEngine` 可以删掉，换成 `CallEngine`，也可以保留为映射）。`sleep_nudge_service.dart` 与 `main.dart` 中按引擎分支的行为保持不变。
- [ ] 设置页 `lib/ui/settings/widgets/personal_center_detail_pages.dart`：
  - GPT-Live 区块上方（或区块内最前面）加下拉框“通话引擎”，选项为“GPT-Live”和“原通话（用聊天模型 + 所选声音）”，保存时写入 `CallEngineSettings`。
  - 删除催睡区块里的“接听后用”下拉框，在原位置加一行说明：“接听后用上面的通话引擎”。
  - GPT-Live 区块加数字输入框“静音自动挂断（分钟）”，helper 文案为“双方都没说话超过这么久就挂断，0 表示不自动挂”，默认 5。
- [ ] 静音自动挂断（GPT-Live）：
  - `gpt_live_settings.dart` 加 `getIdleHangupMinutes()` / `setIdleHangupMinutes(int)`，键为 `gpt_live.idle_hangup_minutes`，默认 5，负数按 0 处理。
  - 计时逻辑写在新文件 `lib/data/services/gpt_live/gpt_live_idle_watch.dart` 里，做成可单测的纯逻辑：输入“最后一次有转写增量的时间”和“当前时间”，输出 `none` / `prompt` / `hangup`。到 N 分钟输出 `prompt`；`prompt` 之后 20 秒内仍无转写增量，输出 `hangup`；期间有增量就重置。
  - `GptLiveCall` 只做最小接入：`live` 阶段启动一个 1 秒的 Timer；每次收到 `GptLiveTranscriptDelta`（双方都算）时记下时间。`prompt` 时通过数据通道发一次 commentary，复用 `_greetIfNudge` 里的发送方式，内容为“对方已经好几分钟没说话了。轻声问一句还在不在，如果没回应你就说先挂了。”；`hangup` 时调用 `hangUp(reason: 'idle')`。在 `ending` / `ended` / `failed` 或 `dispose` 时取消 Timer。
  - `GptLiveCallRecord.reasonText` 的映射里加 `idle` → “太久没人说话，自动挂断”。如果 #111 已把原因转文字抽成共享函数，就加在那个函数里。
- [ ] 测试：
  - `test/data/services/gpt_live/` 下新增 idle watch 单测，覆盖：未到时间、到时间提示、提示后有声音被重置、提示后 20 秒挂断、N=0 永不触发。
  - `CallEngineSettings` 迁移单测：没有新键时读旧键，旧键也没有时默认 gptLive。
  - `reasonText('idle')` 断言。
  - 只在原有测试文件里追加用例，不改原有断言。
- [ ] `flutter analyze` 对改动文件不新增 error / warning。

## 允许修改的路径
- `lib/data/services/call_engine_settings.dart`（新建）
- `lib/data/services/gpt_live/gpt_live_idle_watch.dart`（新建）
- `lib/data/services/gpt_live/gpt_live_call.dart`（只加 idle 接入，不改其他逻辑）
- `lib/data/services/gpt_live/gpt_live_settings.dart`（只加 idle 设置，加 `idle` 原因文字）
- `lib/data/services/sleep_nudge/`（只改引擎来源）
- `lib/main.dart`（只在引擎来源需要时改动）
- `lib/ui/character/widgets/persona_chat_screen.dart`（只改上述入口两处）
- `lib/ui/settings/widgets/personal_center_detail_pages.dart`（只改上述设置项）
- `test/data/services/`、`test/ui/settings/`、`test/ui/character/widgets/`（只追加或新建）
- 本合同文件

## 不做 / 边界
- **不改 `lib/ui/character/widgets/gpt_live_call_screen.dart` 和 `lib/ui/character/widgets/gpt_live_call/`**（PR #111 正在改通话页）。`GptLiveCallScreen` 的构造参数不变。
- 不改原通话（CallVoiceRouter、CallVoiceSession、TTS、STT）的内部实现，不改 GPT-Live 协议和写回。
- 不加依赖，不构建、不安装 App，不碰真实账户、令牌和数据；不写本机路径和密钥。

## 验证命令
- `flutter analyze lib/data/services/ lib/ui/character/widgets/persona_chat_screen.dart lib/ui/settings/widgets/personal_center_detail_pages.dart test/data/services/`
- `flutter test test/data/services/gpt_live test/data/services/sleep_nudge test/ui/settings/widgets/personal_center_screen_test.dart`，再加上新建的测试文件
- 沙箱里跑不了 Flutter 时在结果里写明，以 CI 为准。

## 需要真人的部分
- 合并 PR；从 v3-lab 编译安装后验收：切换引擎各打一通；GPT-Live 静音 5 分钟后会先问一句，再自动挂断，设置里“上次通话”显示“太久没人说话，自动挂断”。**审核通过前请勿合并。**
