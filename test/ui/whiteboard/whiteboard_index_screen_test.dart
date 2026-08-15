import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/ui/whiteboard/whiteboard_index_screen.dart';

/// W6 v2 — whiteboard index route target is a minimal placeholder
/// (real board-list surface belongs to Task S; nothing product-shaped here).
void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('index renders gray-paper placeholder with page name',
      (tester) async {
    await tester.pumpWidget(wrap(const WhiteboardIndexScreen()));

    expect(find.text('白板'), findsWidgets);
    expect(find.textContaining('占位'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
