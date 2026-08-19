import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/dev_agent_codex_options.dart';
import 'package:memex/ui/dev_agent/widgets/codex_options_editor.dart';

void main() {
  testWidgets('preset and advanced Fast control update Codex options',
      (tester) async {
    var value = DevAgentCodexOptions.inherited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CodexOptionsEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );

    expect(find.text('当前全部继承电脑上的 Codex 设置'), findsOneWidget);
    await tester.tap(find.text('快速'));
    await tester.pump();
    expect(value.reasoningEffort, 'low');
    expect(value.verbosity, 'low');
    expect(value.serviceTier, isNull);

    await tester.tap(find.text('高级设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(value.serviceTier, 'fast');
  });
}
