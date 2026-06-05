import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/character/widgets/chat_task_capsule.dart';

void main() {
  testWidgets('expanded task detail scrolls instead of overflowing',
      (tester) async {
    final content = List.filled(
      80,
      'Long delegated task detail used to simulate streaming background output.',
    ).join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: ChatTaskCapsuleDetail(content: content),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);

    final detailHeight =
        tester.getSize(find.byType(ChatTaskCapsuleDetail)).height;
    expect(detailHeight, lessThanOrEqualTo(360));
  });
}
