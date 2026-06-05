import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/utils/user_storage.dart';

void main() {
  setUpAll(UserStorage.initL10n);

  Widget buildSubject({
    required TextEditingController controller,
    required bool isStreaming,
    required VoidCallback onSend,
    VoidCallback? onAddTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PersonaChatInputBar(
          controller: controller,
          isStreaming: isStreaming,
          onSend: onSend,
          onAddTap: onAddTap,
          hintText: 'Message...',
        ),
      ),
    );
  }

  testWidgets('send button is disabled until the user enters text',
      (tester) async {
    final controller = TextEditingController();
    var sends = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildSubject(
      controller: controller,
      isStreaming: false,
      onSend: () => sends++,
    ));

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    expect(sends, 0);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    expect(sends, 1);
  });

  testWidgets('streaming state disables text entry and sending',
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
    expect(textField.enabled, isFalse);

    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    expect(sends, 0);
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
}

Finder _findSemanticsLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
}
