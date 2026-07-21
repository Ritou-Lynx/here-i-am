import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/asr/voice_input_controller.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/utils/user_storage.dart';

void main() {
  setUpAll(UserStorage.initL10n);

  test('image attachment recovery keeps source-path-only images recordable',
      () {
    expect(
      personaChatImageAttachmentCanBeRecorded({
        'mimeType': 'image/webp',
        'base64': 'encoded-image',
      }),
      isTrue,
    );
    expect(
      personaChatImageAttachmentCanBeRecorded({
        'mimeType': 'image/jpeg',
        'base64': '',
        'sourcePath': '/storage/emulated/0/Pictures/second.jpg',
      }),
      isTrue,
    );
    expect(
      personaChatImageAttachmentCanBeRecorded({
        'path': '/storage/emulated/0/Pictures/third.png',
      }),
      isTrue,
    );
    expect(
      personaChatImageAttachmentCanBeRecorded({
        'mimeType': 'image/jpeg',
        'base64': '',
      }),
      isFalse,
    );
  });

  Widget buildSubject({
    required TextEditingController controller,
    required bool isStreaming,
    required VoidCallback onSend,
    VoidCallback? onAddTap,
    VoidCallback? onVoiceModeTap,
    VoiceInputController? voiceController,
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
          voiceController: voiceController,
          isVoiceModeActive: isVoiceModeActive,
          hintText: 'Message...',
        ),
      ),
    );
  }

  testWidgets('empty input shows voice actions until the user enters text',
      (tester) async {
    final controller = TextEditingController();
    final voiceController = VoiceInputController();
    var sends = 0;
    var voiceModeStarts = 0;
    addTearDown(controller.dispose);
    addTearDown(voiceController.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: false,
      onSend: () => sends++,
      onVoiceModeTap: () => voiceModeStarts++,
      voiceController: voiceController,
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
    final voiceController = VoiceInputController();
    var exits = 0;
    addTearDown(controller.dispose);
    addTearDown(voiceController.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: false,
      isVoiceModeActive: true,
      onSend: () {},
      onVoiceModeTap: () => exits++,
      voiceController: voiceController,
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
    final voiceController = VoiceInputController();
    var exits = 0;
    addTearDown(controller.dispose);
    addTearDown(voiceController.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: true,
      isVoiceModeActive: true,
      onSend: () {},
      onVoiceModeTap: () => exits++,
      voiceController: voiceController,
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

  test('composer stale guard detects full or trailing sent remnants', () {
    const sent = '我前面说了一整段。最后一句话还留在这里';

    expect(
      personaChatComposerTextLooksLikeSentRemnant(
        currentText: sent,
        sentText: sent,
      ),
      isTrue,
    );
    expect(
      personaChatComposerTextLooksLikeSentRemnant(
        currentText: '最后一句话还留在这里',
        sentText: sent,
      ),
      isTrue,
    );
    expect(
      personaChatComposerTextLooksLikeSentRemnant(
        currentText: '这是新输入',
        sentText: sent,
      ),
      isFalse,
    );
    expect(
      personaChatComposerTextLooksLikeSentRemnant(
        currentText: '好',
        sentText: sent,
      ),
      isFalse,
    );
  });

  test('composer stale guard survives empty callbacks until a late IME commit',
      () {
    final guard = PersonaChatComposerStaleGuard();
    const sent = '我现在在回去的路上嘛，我不是从公司到地铁站要走一段嘛，'
        '现在路上感觉吹吹风还挺舒服的，但是今天不像前几天，一到傍晚就下雨，今天居然没有下雨';

    guard.arm(sent);

    // Clearing the controller and subsequent frames can emit empty values for
    // an arbitrary amount of time. They must not expire the quarantine.
    expect(guard.shouldClear(''), isFalse);
    expect(guard.shouldClear('   '), isFalse);
    expect(guard.isArmed, isTrue);

    // This is the exact delayed suffix observed on the affected Android IME.
    expect(
      guard.shouldClear('公司到地铁站要走一段。现在路上感觉吹吹风还挺舒服的，'
          '但是今天不像前几天，一到傍晚就下雨，今天居然没有下雨'),
      isTrue,
    );
    expect(guard.isArmed, isTrue);

    // A distinct edit starts a new input session and ends the quarantine.
    expect(guard.shouldClear('这是下一条消息'), isFalse);
    expect(guard.isArmed, isFalse);
    expect(guard.shouldClear(sent), isFalse);
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

  test('split character messages use message id for TTS playback', () {
    final message = _chatMessage(
      id: 7,
      content: '*she nods* I am here.\n*she smiles* Still here.',
      timestamp: DateTime(2026, 6, 17, 9),
    );

    // TTS plays the entire content as one clip; bubble split is UI-only, so
    // every bubble in a split message shares the message id as playback key.
    expect(personaChatTtsPlaybackIdForMessage(message), '7');
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
        now: lastSpeechAt.add(const Duration(milliseconds: 1500)),
        startedAt: startedAt,
        lastSpeechAt: lastSpeechAt,
        heardSpeech: true,
      ),
      isTrue,
    );
  });

  test('voice endpoint supports longer initial silence for voice mode', () {
    final startedAt = DateTime(2026, 6, 19, 9);

    expect(
      voiceInputShouldAutoStop(
        now: startedAt.add(const Duration(seconds: 59)),
        startedAt: startedAt,
        lastSpeechAt: null,
        heardSpeech: false,
        initialSilenceTimeout: const Duration(seconds: 60),
        maxRecordingDuration: const Duration(seconds: 120),
      ),
      isFalse,
    );
    expect(
      voiceInputShouldAutoStop(
        now: startedAt.add(const Duration(seconds: 60)),
        startedAt: startedAt,
        lastSpeechAt: null,
        heardSpeech: false,
        initialSilenceTimeout: const Duration(seconds: 60),
        maxRecordingDuration: const Duration(seconds: 120),
      ),
      isTrue,
    );
  });

  test('voice idle follow-up closes on the eighth silent turn', () {
    expect(personaChatVoiceIdleFollowUpShouldForceClose(7), isFalse);
    expect(personaChatVoiceIdleFollowUpShouldForceClose(8), isTrue);

    final prompt = personaChatVoiceIdleFollowUpPrompt(
      followUpIndex: 8,
      forceClose: true,
    );
    expect(prompt, contains('60 seconds'));
    expect(prompt, contains('end_voice_mode'));
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
