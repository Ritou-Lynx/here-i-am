import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/asr/voice_input_controller.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/utils/user_storage.dart';

void main() {
  setUpAll(UserStorage.initL10n);

  Widget buildSubject({
    required TextEditingController controller,
    required bool isStreaming,
    required VoidCallback onSend,
    VoidCallback? onAddTap,
    VoidCallback? onVoiceModeTap,
    bool isVoiceModeActive = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PersonaChatInputBar(
          controller: controller,
          isStreaming: isStreaming,
          onSend: onSend,
          onAddTap: onAddTap,
          onVoiceModeTap: onVoiceModeTap,
          isVoiceModeActive: isVoiceModeActive,
          hintText: 'Message...',
        ),
      ),
    );
  }

  testWidgets('empty input shows voice actions until the user enters text',
      (tester) async {
    final controller = TextEditingController();
    var sends = 0;
    var voiceModeStarts = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: false,
      onSend: () => sends++,
      onVoiceModeTap: () => voiceModeStarts++,
    ));

    expect(find.bySemanticsLabel('Send message'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Start voice mode'));
    await tester.pump();
    expect(sends, 0);
    expect(voiceModeStarts, 1);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    expect(sends, 1);
  });

  testWidgets('active voice mode stays in the chat input bar', (tester) async {
    final controller = TextEditingController();
    var exits = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: false,
      isVoiceModeActive: true,
      onSend: () {},
      onVoiceModeTap: () => exits++,
    ));

    expect(find.bySemanticsLabel('Start voice mode'), findsNothing);
    await tester.tap(find.bySemanticsLabel('End voice mode'));
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('active voice mode keeps end action visible while typing',
      (tester) async {
    final controller = TextEditingController(text: 'typed reply');
    var sends = 0;
    var exits = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: false,
      isVoiceModeActive: true,
      onSend: () => sends++,
      onVoiceModeTap: () => exits++,
    ));

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    expect(sends, 1);

    await tester.tap(find.bySemanticsLabel('End voice mode'));
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('active voice mode can be ended while streaming', (tester) async {
    final controller = TextEditingController();
    var exits = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: true,
      isVoiceModeActive: true,
      onSend: () {},
      onVoiceModeTap: () => exits++,
    ));

    await tester.tap(find.bySemanticsLabel('End voice mode'));
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('streaming state allows sending into the pending queue',
      (tester) async {
    final controller = TextEditingController(text: 'hello');
    var sends = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: true,
      onSend: () => sends++,
    ));

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.enabled, isNot(false));

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    expect(sends, 1);
  });

  testWidgets('input uses newline action instead of keyboard send',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: false,
      onSend: () {},
    ));

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.keyboardType, TextInputType.multiline);
    expect(textField.textInputAction, TextInputAction.newline);
    expect(textField.onSubmitted, isNull);
  });

  testWidgets('rich capture entry is opt-in and invokes its callback',
      (tester) async {
    final controller = TextEditingController();
    var opens = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: false,
      onSend: () {},
      onAddTap: () => opens++,
    ));

    await tester.tap(find.bySemanticsLabel('Add attachment'));
    await tester.pump();
    expect(opens, 1);
  });

  testWidgets('remembered notice is a floating capsule with undo action',
      (tester) async {
    var undos = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ConversationCaptureRememberedNotice(onUndo: () => undos++),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(UserStorage.l10n.companionRemembered), findsOneWidget);
    expect(find.text(UserStorage.l10n.undo), findsOneWidget);

    await tester.tap(find.text(UserStorage.l10n.undo));
    await tester.pump();
    expect(undos, 1);
  });

  testWidgets('auto read toggle persists as a mode switch', (tester) async {
    var enabled = false;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: PersonaAutoReadToggle(
                enabled: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
            );
          },
        ),
      ),
    );

    expect(_findSemanticsLabel('开启自动朗读'), findsOneWidget);

    await tester.tap(find.byType(PersonaAutoReadToggle));
    await tester.pump();

    expect(enabled, isTrue);
    expect(_findSemanticsLabel('关闭自动朗读'), findsOneWidget);
    semantics.dispose();
  });

  test('reversed chat list reserves index zero for streaming content', () {
    expect(
      personaChatMessageIndexForReversedList(
        listIndex: 1,
        extraItems: 1,
      ),
      0,
    );
    expect(
      personaChatMessageIndexForReversedList(
        listIndex: 0,
        extraItems: 0,
      ),
      0,
    );
  });

  test('search snippet keeps the matched text in view', () {
    final snippet = personaChatSearchSnippet(
      '${List.filled(20, 'early context').join(' ')} '
          'needle message details '
          '${List.filled(20, 'late context').join(' ')}',
      'needle',
    );

    expect(snippet, contains('needle'));
    expect(snippet.length, lessThan(140));
  });

  test('first new character message picks the earliest generated item', () {
    final base = DateTime(2026, 6, 17, 9);
    final previous = [
      _chatMessage(
        id: 1,
        content: 'user',
        timestamp: base,
        isFromCharacter: false,
      ),
    ];
    final updated = [
      _chatMessage(
        id: 3,
        content: 'spoken reply',
        timestamp: base.add(const Duration(milliseconds: 2)),
      ),
      _chatMessage(
        id: 2,
        content: '*looks over*',
        timestamp: base.add(const Duration(milliseconds: 1)),
        messageType: 'action',
      ),
      ...previous,
    ];

    expect(
      personaChatFirstNewCharacterMessageId(
        previousMessages: previous,
        updatedMessages: updated,
      ),
      2,
    );
  });

  test('generated readable messages are ordered from first to last', () {
    final base = DateTime(2026, 6, 17, 9);
    final previous = [
      _chatMessage(
        id: 1,
        content: 'user',
        timestamp: base,
        isFromCharacter: false,
      ),
    ];
    final updated = [
      _chatMessage(
        id: 4,
        content: 'third spoken',
        timestamp: base.add(const Duration(milliseconds: 3)),
      ),
      _chatMessage(
        id: 2,
        content: '*first action*',
        timestamp: base.add(const Duration(milliseconds: 1)),
        messageType: 'action',
      ),
      _chatMessage(
        id: 3,
        content: 'first spoken',
        timestamp: base.add(const Duration(milliseconds: 2)),
      ),
      ...previous,
    ];

    final ordered = personaChatGeneratedReadableMessagesInOrder(
      previousMessages: previous,
      updatedMessages: updated,
    );

    expect(ordered.map((message) => message.id), [3, 4]);
  });

  test('split character messages use first segment playback id', () {
    final message = _chatMessage(
      id: 7,
      content: '*she nods* I am here.\n*she smiles* Still here.',
      timestamp: DateTime(2026, 6, 17, 9),
    );

    expect(personaChatTtsPlaybackIdForMessage(message), '7:0');
  });

  test('voice endpoint treats quiet input as silence', () {
    expect(voiceInputAmplitudeIsSpeech(-30), isTrue);
    expect(voiceInputAmplitudeIsSpeech(-60), isFalse);
  });

  test('voice endpoint stops after blank or trailing silence', () {
    final startedAt = DateTime(2026, 6, 19, 9);

    expect(
      voiceInputShouldAutoStop(
        now: startedAt.add(const Duration(seconds: 3)),
        startedAt: startedAt,
        lastSpeechAt: null,
        heardSpeech: false,
      ),
      isFalse,
    );
    expect(
      voiceInputShouldAutoStop(
        now: startedAt.add(const Duration(seconds: 4)),
        startedAt: startedAt,
        lastSpeechAt: null,
        heardSpeech: false,
      ),
      isTrue,
    );

    final lastSpeechAt = startedAt.add(const Duration(seconds: 2));
    expect(
      voiceInputShouldAutoStop(
        now: lastSpeechAt.add(const Duration(milliseconds: 1000)),
        startedAt: startedAt,
        lastSpeechAt: lastSpeechAt,
        heardSpeech: true,
      ),
      isFalse,
    );
    expect(
      voiceInputShouldAutoStop(
        now: lastSpeechAt.add(const Duration(milliseconds: 1100)),
        startedAt: startedAt,
        lastSpeechAt: lastSpeechAt,
        heardSpeech: true,
      ),
      isTrue,
    );
  });
}

Finder _findSemanticsLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
}

PersonaChatMessage _chatMessage({
  required int id,
  required String content,
  required DateTime timestamp,
  bool isFromCharacter = true,
  String messageType = 'chat',
}) {
  return PersonaChatMessage(
    id: id,
    characterId: 'luna',
    isFromCharacter: isFromCharacter,
    content: content,
    isRead: true,
    timestamp: timestamp,
    messageType: messageType,
  );
}
