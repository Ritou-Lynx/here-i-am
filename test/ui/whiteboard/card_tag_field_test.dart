import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/widgets/card_tag_field.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    List<String> tags = const [],
    List<String> suggestions = const [],
    required ValueChanged<List<String>> onChanged,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: DesktopWorkspaceTheme(
            child: Scaffold(
              body: SizedBox(
                width: 520,
                child: CardTagField(
                  tags: tags,
                  suggestions: suggestions,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('explicit confirmation strips # and ignores blank or case dupes',
      (tester) async {
    var value = <String>[];
    await pumpField(tester, onChanged: (tags) => value = tags);

    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      '  #Focus  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(value, ['Focus']);
    expect(find.text('#Focus'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      'focus',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(value, ['Focus']);

    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      '###   ',
    );
    await tester.tap(find.byKey(const ValueKey('card-tag-add')));
    await tester.pump();
    expect(value, ['Focus']);
  });

  testWidgets('suggestions, delete button and keyboard backspace are supported',
      (tester) async {
    var value = <String>[];
    await pumpField(
      tester,
      suggestions: const ['研究', '阅读'],
      onChanged: (tags) => value = tags,
    );

    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      '研',
    );
    await tester.pump();
    await tester.tap(find.text('#研究'));
    await tester.pump();
    expect(value, ['研究']);

    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      '临时',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(value, ['研究', '临时']);

    await tester.tap(find.byKey(const ValueKey('card-tag-input')));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(value, ['研究']);

    await tester.tap(
      find.byKey(const ValueKey('card-tag-delete-研究')),
    );
    await tester.pump();
    expect(value, isEmpty);
  });
}
