import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/desktop/widgets/desktop_chat_overlay.dart';
import 'package:memex/ui/desktop/widgets/desktop_brand_mark.dart';
import 'package:memex/ui/desktop/widgets/desktop_persona_chat_view.dart';
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
    'workbench handoff releases the desktop composer before UI mutation',
    (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              focusNode: focusNode,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await releaseDesktopComposerForWorkbenchAction(
        focusNode,
        frameBarrier: () async {},
      );

      expect(focusNode.hasFocus, isFalse);
    },
  );

  testWidgets(
    'Web-style popover keeps page width, leaves orb visible, and restores focus',
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
      expect(
        find.byKey(const ValueKey('desktop_chat_popover')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop_chat_panel')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('desktop_floating_ball')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('desktop_chat_popover')))
            .width,
        lessThanOrEqualTo(350),
      );
      final chat = tester.widget<PersonaChatScreen>(
        find.byType(PersonaChatScreen),
      );
      expect(chat.characterId, 'character_primary');
      expect(chat.presentation, PersonaChatPresentation.desktopFloating);
      expect(find.text('当前 · 卡片库 · 仅本次上下文'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop_chat_input_surface')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('background_action')));
      expect(backgroundTaps, 1);

      await tester.tap(find.byKey(const ValueKey('desktop_floating_ball')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.byKey(const ValueKey('desktop_chat_popover')), findsNothing);
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
    'global entry retries startup resolution and opens the same primary chat',
    (tester) async {
      final controller = GlobalDesktopChatOverlayController.instance;
      var resolveAttempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              GlobalDesktopChatOverlay(
                controller: controller,
                characterIdResolver: () async {
                  resolveAttempts += 1;
                  return resolveAttempts == 1 ? null : 'character_primary';
                },
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('desktop_floating_ball')), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(resolveAttempts, 2);
      expect(
        find.byKey(const ValueKey('desktop_floating_ball')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('desktop_floating_ball')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final chat = tester.widget<PersonaChatScreen>(
        find.byType(PersonaChatScreen),
      );
      expect(chat.characterId, 'character_primary');
      expect(chat.presentation, PersonaChatPresentation.desktopFloating);
      expect(find.textContaining('仅本次上下文'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop_floating_ball')),
        findsOneWidget,
      );

      controller.close();
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.temporaryContextLabel, isNull);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'production host supplies an overlay outside the router navigator',
    (tester) async {
      final controller = GlobalDesktopChatOverlayController.instance;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Stack(
            children: [
              if (child != null) child,
              Positioned.fill(
                child: GlobalDesktopChatOverlayHost(
                  controller: controller,
                  characterIdResolver: () async => 'character_primary',
                ),
              ),
            ],
          ),
          home: const Scaffold(body: Text('工作台')),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('desktop_floating_ball')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('desktop_floating_ball')));
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('desktop_chat_popover')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'fixed Here I am identity shows the desktop entry without DB resolution',
    (tester) async {
      var resolutionCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Stack(
            children: [
              if (child != null) child,
              Positioned.fill(
                child: GlobalDesktopChatOverlayHost(
                  characterId: 'i',
                  characterIdResolver: () async {
                    resolutionCalls += 1;
                    return null;
                  },
                ),
              ),
            ],
          ),
          home: const Scaffold(body: Text('工作台')),
        ),
      );
      await tester.pump();

      expect(resolutionCalls, 0);
      expect(
        find.byKey(const ValueKey('desktop_floating_ball')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'desktop presentation renders real turns and uses supplied send',
    (tester) async {
      final controller = TextEditingController(text: '继续整理');
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      var sends = 0;
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 350,
            height: 480,
            child: DesktopPersonaChatView(
              loading: false,
              messagesNewestFirst: [
                PersonaChatMessage(
                  id: 2,
                  characterId: 'i',
                  isFromCharacter: true,
                  content: '我接着看这一页。',
                  isRead: true,
                  timestamp: DateTime(2026, 8, 21, 10, 1),
                  messageType: 'chat',
                ),
                PersonaChatMessage(
                  id: 1,
                  characterId: 'i',
                  isFromCharacter: false,
                  content: '先帮我理一下。',
                  isRead: true,
                  timestamp: DateTime(2026, 8, 21, 10),
                  messageType: 'chat',
                ),
              ],
              isStreaming: false,
              streamingText: '',
              controller: controller,
              composerFocusNode: focusNode,
              scrollController: scrollController,
              temporaryContextLabel: '来源研读',
              onSend: () async {
                sends += 1;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('我接着看这一页。'), findsOneWidget);
      expect(find.text('先帮我理一下。'), findsOneWidget);
      expect(
        find.byType(SelectionArea),
        findsOneWidget,
        reason: '桌面普通消息须支持鼠标选择与 Ctrl+C 复制。',
      );
      expect(find.text('当前 · 来源研读 · 仅本次上下文'), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop_chat_panel')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('desktop_chat_send')));
      await tester.pump();
      expect(sends, 1);
    },
  );

  testWidgets('desktop streaming state exposes stop without requiring text',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final scrollController = ScrollController();
    var stops = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 350,
          height: 480,
          child: DesktopPersonaChatView(
            loading: false,
            messagesNewestFirst: const [],
            isStreaming: true,
            streamingText: '正在回复',
            controller: controller,
            composerFocusNode: focusNode,
            scrollController: scrollController,
            onSend: () async {},
            onStop: () async {
              stops += 1;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('desktop_chat_send')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('desktop_chat_stop')));
    await tester.pump();
    expect(stops, 1);
  });
}
