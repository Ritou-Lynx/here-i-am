import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/ui/character/widgets/chat_message_source_label.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/core/themes/chat_view_mode_controller.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_color_controller.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await UserStorage.initL10n();
    await initializeDateFormatting();
  });

  testWidgets(
    'phone timeline labels ChatGPT and Claude but not local messages',
    (tester) async {
      _stubAudioPlugins();
      tester.view.physicalSize = const Size(440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fetching = GoogleFonts.config.allowRuntimeFetching;
      GoogleFonts.config.allowRuntimeFetching = false;
      addTearDown(() => GoogleFonts.config.allowRuntimeFetching = fetching);
      SharedPreferences.setMockInitialValues({
        'user_id': 'synthetic-widget-user',
      });
      DeviceIdentityService.resetForTesting();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
      final character = CharacterModel(
        id: 'synthetic-source-label-character',
        name: 'Synthetic character',
        tags: const [],
        persona: 'Synthetic test persona',
        enabled: true,
      );
      final origins = [
        'frontend:chatgpt_web',
        'frontend:claude_web',
        'synthetic-local-installation',
      ];
      await tester.runAsync(() async {
        for (var index = 0; index < origins.length; index++) {
          await db.into(db.personaChatMessages).insert(
                PersonaChatMessagesCompanion.insert(
                  characterId: character.id,
                  isFromCharacter: index == 1,
                  content: 'Synthetic phone message $index',
                  timestamp: DateTime(2026, 10, 23, 12, 0, index),
                  originDeviceId: Value(origins[index]),
                  isRead: const Value(true),
                ),
              );
        }
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ChatViewModeController()),
            ChangeNotifierProvider(
              create: (_) => SpringRainChatColorController(),
            ),
          ],
          child: MaterialApp(
            home: PersonaChatScreen(
              characterId: character.id,
              initialCharacterForTesting: character,
            ),
          ),
        ),
      );
      await EventBusService.instance.connect();
      EventBusService.instance.emitEvent(
        PersonaChatMessageAddedMessage(characterId: character.id),
      );
      for (var index = 0; index < 100; index++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        if (find.text('ChatGPT').evaluate().isNotEmpty &&
            find.text('Claude').evaluate().isNotEmpty) break;
      }
      expect(find.text('ChatGPT'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('网页端'), findsNothing);
      expect(find.text('Synthetic phone message 2'), findsOneWidget);
      final labels = tester.widgetList<ChatMessageSourceLabel>(
        find.byType(ChatMessageSourceLabel),
      );
      expect(labels, hasLength(3));
      final localLabel = find.byWidgetPredicate(
        (widget) =>
            widget is ChatMessageSourceLabel &&
            widget.message.originDeviceId == origins[2],
      );
      expect(localLabel, findsOneWidget);
      expect(
        find.descendant(of: localLabel, matching: find.byType(Text)),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      await EventBusService.instance.disconnect();
      await tester.runAsync(db.close);
    },
  );
}

// Match the existing acceptance harness: this screen creates recorder and
// audio-player objects even though this test never records or plays audio.
void _stubAudioPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'com.llfbandit.record/messages',
    'xyz.luan/audioplayers.global',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (call) async {
      final playerId = (call.arguments as Map?)?['playerId'];
      if (call.method == 'create' && playerId is String) {
        messenger.setMockStreamHandler(
          EventChannel('xyz.luan/audioplayers/events/$playerId'),
          MockStreamHandler.inline(onListen: (_, __) {}),
        );
      }
      return null;
    },
  );
  messenger.setMockStreamHandler(
    const EventChannel('xyz.luan/audioplayers.global/events'),
    MockStreamHandler.inline(onListen: (_, __) {}),
  );
}
