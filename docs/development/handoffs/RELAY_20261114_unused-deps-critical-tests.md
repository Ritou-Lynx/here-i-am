<!-- relay:contract v1 -->
## 目标
移除 5 个没有被引用的 Dart 依赖，并把 `scripts/verify_critical_fixes.ps1` 的三项检查改成随 `flutter test` 运行的正式测试，之后删除该脚本和“构建前必须运行”的要求。

## 完成标准
- [ ] `pubspec.yaml` 不再声明 `cupertino_icons`、`fl_chart`、`google_generative_ai`、`photo_view`、`timezone`；`pubspec.lock` 由 `flutter pub get` 重新生成并提交；`flutter pub get --enforce-lockfile` 通过。
- [ ] 其中某个包若被其他依赖传递需要而仍留在 lock 里属正常；若移除后 `flutter analyze` 或编译报缺包，说明它实际在用：保留该包并在回帖里写明是哪一处引用，不要为了删除去改业务代码。
- [ ] 新增 `test/guards/critical_fixes_test.dart`，用读取源码文件的方式覆盖原脚本三项检查，断言内容与原脚本一致：
  1. `lib/ui/character/widgets/persona_chat_screen.dart` 含 `Input stays enabled during streaming`。
  2. `lib/agent/built_in_tools/coros_mcp_tool.dart`、`lib/agent/skills/companion_agent/companion_agent_skill.dart`、`lib/agent/companion_agent/companion_agent.dart` 各自匹配 `WAKE-UP date|wake-up date|睡眠数据`。
  3. `lib/data/services/health_strategies.dart` 含 `WAKE UP (dateTo)`。
  每项失败信息要写明是哪一个文件缺了什么。
- [ ] 删除 `scripts/verify_critical_fixes.ps1`；`.github/workflows/ci.yml` 里两处 `Critical fixes check` 步骤删除（新测试已在 Linux 全量测试作业里运行，确认该作业会跑到 `test/guards/`，跑不到就把路径加进去）。
- [ ] `AGENTS.md`、`.claude/skills/agent-relay/SKILL.md`、`docs/development/MULTI_DEVICE_GITHUB_WORKFLOW.md` 里“构建前运行 verify_critical_fixes.ps1”的要求删掉或改为“关键修复由 `test/guards/critical_fixes_test.dart` 守护”。其余历史文档（goals、handoffs、whiteboard-workstreams、activity、companion-first、archive）里的提及不改。
- [ ] `flutter analyze` 不比基线多出新问题；`flutter test test/guards/critical_fixes_test.dart` 通过。

## 允许修改的路径
- pubspec.yaml
- pubspec.lock
- test/guards/
- scripts/verify_critical_fixes.ps1（删除）
- .github/workflows/ci.yml
- AGENTS.md
- .claude/skills/agent-relay/SKILL.md
- docs/development/MULTI_DEVICE_GITHUB_WORKFLOW.md

## 不做 / 边界
- 不升级任何其他依赖版本；lock 里除被移除包及其独占的传递依赖外不应有版本变化，有的话回帖说明原因。
- 不改 `lib/` 下的业务代码。
- 不构建 APK、不安装、不碰真实数据库与令牌。
- 不写 DEVLOG 和 I_PROJECT_STATE（由 Claude 收尾时统一写）。

## 验证命令
- flutter pub get --enforce-lockfile
- flutter analyze
- flutter test test/guards/critical_fixes_test.dart
- git diff --stat origin/v3-lab...HEAD

## 需要真人的部分
- 无。合并由用户决定。
