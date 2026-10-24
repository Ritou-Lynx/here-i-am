<!-- relay:contract v1 -->
# E0 合同：ElevenLabs 语音 Agent 技术验证（App 调试页测试通话）

> 2026-10-24。方案与用户决定见项目线程“接入 ElevenLabs 语音 Agent”：子 key 放手机安全存储、上下文由 App 注入、单次 10 分钟/每日 30 分钟。本合同只做 E0 验证，不接 CallKit、不改现有通话。

## 背景
- 现有通话：CallKit 接起 → `CallVoiceRouter.startCall` → 前台服务 isolate 的 `CallVoiceSession`（阿里 NLS ASR + 伴侣 Agent + 流式 TTS，半双工）。放前台服务 isolate 是因为主 isolate 锁屏/后台会被挂起。
- 目标引擎：官方 Flutter SDK `elevenlabs_agents`（pub.dev，0.6.1，底层 LiveKit/WebRTC，全双工）。私有 Agent 需要先用 API key 换 conversation token。
- Agent 已由 Claude 在用户 ElevenLabs 账号里建好：私有（enable_auth）、中文、并发 1、单次上限 600 秒、允许 App 覆盖 prompt / first_message / language / voice_id / stability / speed / max_duration_seconds。agent id 与子 key 由用户在调试页手动填写，**不入库**。
- 最大未知：WebRTC 能否在前台服务 isolate 里跑、锁屏后能否保持；国内网络走代理时的连通和延迟。

## 目标
在 App 调试页加“ElevenLabs Agent 测试通话”，能分别在**主 isolate**和**前台服务 isolate**里发起一次真实通话，并在页面和日志里给出可比对的时序与断线记录，供用户在三星真机上验收。

## 完成标准

**依赖**
- [ ] `pubspec.yaml` 加 `elevenlabs_agents`，锁定确切版本（不用 `^`），`flutter pub get` 通过、`pubspec.lock` 同步。若与现有依赖（Dart `>=3.6.0`、`record`、`audio_session`、`flutter_callkit_incoming` fork 等）冲突无法解决，回 `blocked` 并贴冲突输出，不要降级/升级其他包。
- [ ] Android 权限按 SDK 说明补齐（现有 `RECORD_AUDIO`、`FOREGROUND_SERVICE_MICROPHONE` 已在）；只补 SDK 要求且缺的。`CAMERA` 先不加（纯语音用不到）；若不加就编译或运行失败，回 `blocked` 说明。

**配置与鉴权 `lib/data/services/elevenlabs_agent/`**
- [ ] `elevenlabs_agent_settings.dart`：用 `flutter_secure_storage` 存取三项：子 API key、agent id、启用开关（E0 只给调试页用）。不读写、不迁移现有 TTS 的 `elevenlabs_api_key`（SharedPreferences），两者互不影响。
- [ ] `elevenlabs_token_client.dart`：`GET https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=<id>`，请求头 `xi-api-key`，返回 token；超时 10 秒；非 200 抛带状态码的类型化异常，异常文本和日志里**不得出现 key 或 token 原文**（只记长度或前 4 位掩码）。HTTP 客户端可注入，便于测试。
- [ ] `elevenlabs_agent_call_session.dart`：封装 SDK 会话。`start({required String token, String? firstMessage, String? promptAppend, String? voiceId})`、`end()`、`setMuted(bool)`；overrides 固定带 `max_duration_seconds = 600`、`language = zh`；`voiceId` 取 `UserStorage.getElevenLabsVoiceId()`，为空则不覆盖。对外暴露状态流（connecting / connected / agentSpeaking / listening / ended(reason) / error）和逐句字幕（user / agent）。
- [ ] 时序记录：每次通话记 `token_ms`（换 token 耗时）、`connect_ms`（startSession 到 connected）、`first_agent_audio_ms`（connected 到首次 agent 说话）、通话总时长、断线/重连次数和原因、结束原因；写入现有 logger，标签 `ElevenLabsAgentSpike`，并在调试页显示最近 5 次。

**两种运行位置**
- [ ] 主 isolate 模式：调试页直接持有 `ElevenLabsAgentCallSession`。
- [ ] 前台服务 isolate 模式：通过现有 `FlutterForegroundTask` 数据通道发 `el_spike_start` / `el_spike_end`（新 type，不复用 `call_start`/`call_end`），在 `CompanionTaskHandler.onReceiveData` 里新增分支启动/结束会话；状态与时序用 `sendDataToMain` 回传。现有 `call_*`、`voice_*` 分支行为不变。若 SDK 在该 isolate 初始化失败，捕获并回传错误文本（这本身就是验证结论），不要崩溃前台服务。
- [ ] 任一模式进行中时，另一模式和现有 `CallVoiceSession` 的启动按钮/入口给出提示并拒绝（防止两路同时占麦）。

**调试页**
- [ ] 在 `sleep_takeover_debug_page.dart` 同级新建 `elevenlabs_agent_debug_page.dart`，从 `core_sync_settings_page.dart` 里调试入口旁边加一个入口（与 `SleepTakeoverDebugPage` 同样的入口方式）。
- [ ] 页面内容：子 key（遮蔽输入）、agent id 输入、保存；“主 isolate 测试通话”“前台服务测试通话”“挂断”“静音”；当前状态、实时字幕、最近 5 次时序记录；一个“复制诊断”按钮，复制不含 key/token 的时序与错误摘要。
- [ ] 开场白固定为中文测试句（如“喂，我是林埃，这是一次测试通话。”），通过 first_message override 下发。

**测试**
- [ ] `test/data/services/elevenlabs_agent/elevenlabs_token_client_test.dart`：成功、401、超时、非 JSON 四种情况；断言异常与日志文本不含 key/token 原文。
- [ ] `test/data/services/elevenlabs_agent/elevenlabs_agent_settings_test.dart`：用 secure storage 的 mock 覆盖存取与清空；断言不触碰 SharedPreferences 的 `elevenlabs_api_key`。
- [ ] 前台服务新分支：若现有测试结构允许，为 `el_spike_*` 分支的参数校验写单测；否则在结果中说明理由。

## 允许修改的路径
- `pubspec.yaml`、`pubspec.lock`
- `android/app/src/main/AndroidManifest.xml`（只补权限）
- `lib/data/services/elevenlabs_agent/**`（新建）
- `lib/data/services/companion_foreground_task.dart`（只加 `el_spike_*` 分支）
- `lib/ui/settings/widgets/elevenlabs_agent_debug_page.dart`（新建）
- `lib/ui/settings/widgets/core_sync_settings_page.dart`（只加入口）
- `test/data/services/elevenlabs_agent/**`（新建）
- `docs/development/handoffs/RELAY_20261024_e0-elevenlabs-agent-spike.md`（只由 Claude 改）

## 不做 / 边界
- 不改 `CallVoiceSession`、`CallVoiceRouter`、`callkit_service.dart`、CallKit 来电流程和现有 TTS 设置；不做引擎切换、不写回聊天时间线、不注入 i 上下文（E1/E2 再做）。
- 不构建、不安装 App，不发起真实通话，不连 ElevenLabs 真实接口（测试全部 mock）。
- 仓库、日志、评论里不出现 API key、token、agent id、voice id、本机路径。
- 止损：同一测试名或同一错误在连续两个提交上失败即判 blocked；最多 3 轮。

## 验证命令
- `flutter pub get`
- `flutter analyze lib/data/services/elevenlabs_agent lib/ui/settings/widgets/elevenlabs_agent_debug_page.dart lib/data/services/companion_foreground_task.dart lib/ui/settings/widgets/core_sync_settings_page.dart`（0 error、0 warning）
- `flutter test test/data/services/elevenlabs_agent/`
- `git status --short`（只出现允许修改的路径）

## 需要真人的部分（合并后，用户在三星上）
1. 在 ElevenLabs 后台新建子 API key：只开 Agents 权限、设额度上限；连同 agent id 填进调试页。
2. 构建前跑 `scripts/verify_critical_fixes.ps1`，用专用脚本装 `hereIAmV3`。
3. 验收 V2（主 isolate）：亮屏通话 1 分钟，记 connect / 首句延迟、能否打断；然后锁屏 5 分钟继续对话，看是否断。
4. 验收 V1（前台服务 isolate）：同上流程；若初始化报错，复制诊断贴回线程。
5. 两种模式各至少 2 次，“复制诊断”贴回线程；Claude 据此决定 E1 走主 isolate、前台 isolate，还是改 Kotlin 原生 SDK。

## 审核记录
（Claude 每轮审核结论追加于此）
