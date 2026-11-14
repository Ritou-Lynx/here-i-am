<!-- relay:contract v1 -->
# RELAY 2026-11-11：GPT-Live 后台委托（联网搜索）

## 目标
GPT-Live 通话中遇到要查资料或要仔细想的问题时，交给 OpenAI Responses 后端模型处理（带联网搜索），林埃再用自己的口吻说出结果。设置里可选后端模型，默认用最便宜的 `gpt-5.6-luna`，也可以选“不委托”。

参考：OpenAI 文档 “Delegation and tools in GPT-Live”（developers.openai.com/api/docs/guides/live-delegation）。

## 完成标准
- [ ] `lib/data/services/gpt_live/gpt_live_settings.dart`：
  - 新增 `getDelegateModel()` / `setDelegateModel(String)`，SharedPreferences 键为 `gpt_live.delegate_model`，默认 `gpt-5.6-luna`。
  - 空字符串表示不委托。
  - 新增常量 `delegateModelOptions`（有序，值 → 显示文字）：
    - `''` → 不委托（只用通话模型自己）
    - `gpt-5.6-luna` → gpt-5.6-luna（最便宜，默认）
    - `gpt-5.6-terra` → gpt-5.6-terra
    - `gpt-5.6-sol` → gpt-5.6-sol（最强，最贵）
  - 读到不在选项里的值时，按默认值处理。
- [ ] `lib/data/services/gpt_live/gpt_live_protocol.dart`：
  - `buildSessionRequest` 加可选参数 `String? delegateModel`。非空时在 `session` 里加入下面的结构；为空或 null 时完全不出现 `delegation` 键（保证现有请求字节不变）：
    ```json
    "delegation": {
      "type": "responses",
      "responses": {
        "model": "<delegateModel>",
        "instructions": "<GptLiveProtocol.delegateInstructions>",
        "tools": [{"type": "web_search"}],
        "tool_choice": "auto"
      }
    }
    ```
  - 新增常量 `delegateInstructions`（中文），内容为：你是语音通话的后台助手，结果会被前台转述给用户；用中文；先给结论，控制在 3 到 5 句；不要列表、Markdown 和链接；需要最新信息时用联网搜索；查不到就直说，不编造。
- [ ] `lib/data/services/gpt_live/gpt_live_call.dart`（最小改动）：
  - `start()` 读取 `GptLiveSettings.getDelegateModel()`，传给 `buildSessionRequest`。
  - `buildInstructions` 加可选参数 `bool canDelegate = false`。为 true 时在 `## 通话规则` 末尾加一行：“- 用户问到需要查最新信息、核对事实或仔细想的问题时，交给后台去查，先自然地应一声；拿到结果再用你自己的话说，不要编。”
  - 不改其他逻辑。数据通道中的 `session.delegation.created`、`response.event` 等新事件保持现状，由 `parse` 返回 null 忽略即可。`error` 事件（例如 `responses_validation_failed`）已经会写进 `_lastServerError`，不用另外处理。
- [ ] `lib/ui/settings/widgets/personal_center_detail_pages.dart`：在 GPT-Live 区块的“静音自动挂断”下面加一个下拉框：
  - 标签为“后台模型（查资料 / 深度思考）”。
  - helper 文案为“通话中需要联网或仔细想时交给它；只在用到时另外计费”。
  - 选项来自 `delegateModelOptions`，保存时写入 `setDelegateModel`。
- [ ] 测试（只追加，不改原有断言）：
  - protocol：`delegateModel` 为 null 或空时，请求里没有 `delegation`；非空时结构与上面一致，包括 `tools` 里的 `web_search`。
  - settings：默认值为 `gpt-5.6-luna`；可以存空串；读到非法值时回退到默认。
  - `buildInstructions(canDelegate: true)` 含“交给后台”那一行，false 时不含。
- [ ] `flutter analyze` 对改动文件不新增 error / warning。

## 允许修改的路径
- `lib/data/services/gpt_live/gpt_live_settings.dart`
- `lib/data/services/gpt_live/gpt_live_protocol.dart`
- `lib/data/services/gpt_live/gpt_live_call.dart`（只做上述改动）
- `lib/ui/settings/widgets/personal_center_detail_pages.dart`（只加这个下拉框）
- `test/data/services/gpt_live/`、`test/ui/settings/`（只追加）
- 本合同文件

## 不做 / 边界
- 不改 `lib/ui/character/widgets/gpt_live_call_screen.dart` 和 `lib/ui/character/widgets/gpt_live_call/`。
- 不做 client delegation，不加自定义 function 工具，不改原通话、写回和静音挂断逻辑。
- 不加依赖，不构建、不安装 App，不碰真实账户、令牌和数据；不写本机路径和密钥。

## 验证命令
- `flutter analyze lib/data/services/gpt_live/ lib/ui/settings/widgets/personal_center_detail_pages.dart test/data/services/gpt_live/`
- `flutter test test/data/services/gpt_live test/ui/settings/widgets/personal_center_screen_test.dart`
- 沙箱里跑不了 Flutter 时在结果里写明，以 CI 为准。

## 需要真人的部分
- 合并 PR；从 v3-lab 装机后实测：通话中问一个需要联网的问题（比如今天的新闻、天气），林埃先应一声，再说出查到的结果。
- 如果“上次通话”显示 `responses_validation_failed`，说明 `gpt-5.6-luna` 不支持委托或联网搜索，换成 terra 再试。
- **审核通过前请勿合并。**
