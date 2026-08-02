import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/ui/settings/widgets/task_model_assignment_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  testWidgets('personal center renders the confirmed spring-rain structure',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PersonalCenterScreen(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('personal_center_profile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('personal_center_rain_glass_background')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('personal_center_warm_surface')),
      findsOneWidget,
    );
    expect(find.text('AI 与模型'), findsOneWidget);
    expect(find.text('声音与互动'), findsOneWidget);
    expect(find.text('设备与连接'), findsOneWidget);
    expect(find.text('数据与安全'), findsOneWidget);
    expect(find.text('应用设置'), findsOneWidget);
    expect(find.text('开发与诊断'), findsOneWidget);

    // Deprecated peer entries are no longer the information architecture.
    expect(find.text('Debugging'), findsNothing);
    expect(find.text('Agent 配置'), findsNothing);
  });

  testWidgets('AI group opens task-oriented model settings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PersonalCenterScreen()),
    );

    await tester.tap(find.text('AI 与模型'));
    await tester.pumpAndSettle();

    expect(find.text('聊天对话'), findsOneWidget);
    expect(find.text('记忆整理'), findsOneWidget);
    expect(find.text('日程分析'), findsOneWidget);
    expect(find.text('内容分析'), findsOneWidget);
    expect(find.text('游戏与角色扮演'), findsOneWidget);
  });

  testWidgets('image generation opens its focused spring-rain settings page',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PersonalCenterScreen()),
    );

    await tester.tap(find.text('AI 与模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片生成'));
    await tester.pumpAndSettle();

    expect(find.text('当前服务'), findsOneWidget);
    expect(find.text('通义万相'), findsWidgets);
    expect(find.text('MiniMax'), findsOneWidget);
    expect(find.text('OpenAI 兼容服务'), findsOneWidget);
    expect(find.text('本地 ComfyUI'), findsOneWidget);

    final pageContext = tester.element(find.byType(Scaffold).last);
    expect(
      Theme.of(pageContext).extension<SpringRainUiTokens>(),
      isNotNull,
    );
  });

  testWidgets('application preferences open focused pages, not legacy settings',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PersonalCenterScreen()),
    );

    await tester.tap(find.text('应用设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('TTS 语音'), findsNothing);
    expect(find.text('视觉主题'), findsNothing);
    expect(find.text('暮雨玫瑰'), findsNothing);
    expect(find.text('玫瑰雾'), findsNothing);
  });

  testWidgets('high-frequency model switcher exposes active agents',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TaskModelAssignmentPage(
          initialMode: ModelAssignmentMode.agents,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('按用途'), findsOneWidget);
    expect(find.text('按 Agent'), findsOneWidget);
    expect(find.text('林埃聊天'), findsOneWidget);
    expect(find.text('记录整理'), findsOneWidget);
    expect(find.text('主动联系'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('媒体分析'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('媒体分析'), findsOneWidget);
    expect(find.text('PKM'), findsNothing);
    expect(find.text('Cards'), findsNothing);
  });
}
