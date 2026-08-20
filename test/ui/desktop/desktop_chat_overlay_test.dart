import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/desktop/widgets/desktop_chat_overlay.dart';
import 'package:memex/ui/desktop/widgets/desktop_brand_mark.dart';
import 'package:memex/ui/desktop/widgets/global_desktop_chat_overlay.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppDatabase.setTestInstance(db);
    GlobalDesktopChatOverlayController.instance.reset();
  });

  tearDown(() async {
    GlobalDesktopChatOverlayController.instance.reset();
    await db.close();
  });

  testWidgets(
    'panel keeps page width, passes outside clicks, and restores focus',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var open = false;
      var backgroundTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: SizedBox.expand(
                      key: const ValueKey('desktop_page_under_overlay'),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: TextButton(
                          key: const ValueKey('background_action'),
                          onPressed: () => backgroundTaps += 1,
                          child: const Text('底层按钮'),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DesktopChatOverlay(
                      open: open,
                      characterId: 'character_primary',
                      initialVoiceMode: false,
                      temporaryContextLabel: '卡片库',
                      taskStrip: const DesktopTaskStripData(
                        title: '整理阅读笔记',
                        statusLabel: '进行中',
                      ),
                      onOpenTasks: () {},
                      onOpen: () => setState(() => open = true),
                      onClose: () => setState(() => open = false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final pageSize = tester.getSize(
        find.byKey(const ValueKey('desktop_page_under_overlay')),
      );
      expect(find.byType(DesktopBrandMark), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('desktop_floating_ball')));
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        tester.getSize(
          find.byKey(const ValueKey('desktop_page_under_overlay')),
        ),
        pageSize,
      );
      final chat = tester.widget<PersonaChatScreen>(
        find.byType(PersonaChatScreen),
      );
      expect(chat.characterId, 'character_primary');
      expect(find.textContaining('卡片库 · 仅本次上下文'), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop_task_strip')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PersonaChatScreen),
          matching: find.byKey(const ValueKey('desktop_task_strip')),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('background_action')));
      expect(backgroundTaps, 1);

      await tester.tap(find.byKey(const ValueKey('desktop_chat_close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.byKey(const ValueKey('desktop_chat_panel')), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop_floating_ball')),
        findsOneWidget,
      );
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'desktop-chat-trigger',
      );

      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'global entry opens PersonaChatScreen with the same characterId',
    (tester) async {
      final controller = GlobalDesktopChatOverlayController.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.into(db.taskRooms).insert(
            TaskRoomsCompanion.insert(
              id: 'active_task',
              title: '检查首页任务条',
              goal: '保持任务状态独立',
              taskType: 'whiteboard',
              status: 'waiting_for_user',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              GlobalDesktopChatOverlay(
                controller: controller,
                characterIdResolver: () async => 'character_primary',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('desktop_floating_ball')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final chat = tester.widget<PersonaChatScreen>(
        find.byType(PersonaChatScreen),
      );
      expect(chat.characterId, 'character_primary');
      expect(find.textContaining('仅本次上下文'), findsOneWidget);
      expect(find.text('检查首页任务条'), findsOneWidget);
      expect(find.text('等待确认'), findsOneWidget);

      controller.close();
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.temporaryContextLabel, isNull);
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
