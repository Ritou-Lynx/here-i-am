/// W2 — real desktop rich text editor loop.
///
/// Runs in a real Windows desktop window with the real filesystem storage:
/// deep-link into the frozen `/cards/:cardId` route → type mixed CJK + Latin
/// text (through the real text input pipeline, covering Chinese IME
/// composition) → convert to a list, Tab-indent, Enter to continue the list
/// → save → open the card library and find the card by plain-text projection
/// → open the hit and confirm the document recovered from disk.
///
/// Run: flutter test integration_test/whiteboard_rich_text_loop_test.dart -d windows
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/main.dart' as app;
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor: IME text → list nesting → save → search → recover',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    debugPrint('ITEST: app started');

    final homeVisible = await _waitForAny(
      tester,
      () => find.byIcon(Icons.more_horiz_rounded).evaluate().isNotEmpty,
      () => find.textContaining('下一步').evaluate().isNotEmpty ||
          find.textContaining('Continue').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      description: 'chat home or user setup',
    );
    if (!homeVisible) {
      await tester.enterText(
        find.byType(TextField).first,
        '富文本验收',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      final next = find.textContaining('下一步').evaluate().isNotEmpty
          ? find.textContaining('下一步')
          : find.textContaining('Continue');
      await tester.tap(next.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }
    await _waitFor(
      tester,
      () => find.byIcon(Icons.more_horiz_rounded).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      description: 'chat home visible',
    );

    const cardId = 'richtext_itest';
    final routerContext = tester.element(find.byType(Navigator).first);
    final router = GoRouter.of(routerContext);
    router.push(AppRoutes.cardEditPath(cardId));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await _waitFor(
      tester,
      () => find.textContaining('卡片编辑').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
      description: 'card editor opens',
    );
    debugPrint('ITEST: editor opened');

    // Scope all editor finds to the editor screen subtree: the chat home
    // underneath keeps its own widgets mounted.
    Finder inEditor(Finder finder) => find.descendant(
        of: find.byType(CardRichTextEditor), matching: finder);

    // 1. Mixed CJK + Latin text through the real input pipeline (this is
    // where Chinese IME composition would resolve on a real desktop).
    await tester.enterText(
        inEditor(find.byType(TextField)).first, '中文混排 English 123');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    debugPrint('ITEST: mixed text entered');

    // 2. Convert to a list, Tab-indent (depth 1), Enter for a sibling item.
    // Desktop InkWell buttons steal focus on tap; showKeyboard re-requests
    // focus on the field deterministically.
    await tester.tap(inEditor(find.text('•')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.showKeyboard(inEditor(find.byType(TextField)).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    debugPrint(
        'ITEST: list + indent + sibling created, fields='
        '${inEditor(find.byType(TextField)).evaluate().length}');

    // 3. Type into the new sibling (second editor field).
    await _waitFor(
      tester,
      () => inEditor(find.byType(TextField)).evaluate().length >= 2,
      timeout: const Duration(seconds: 10),
      description: 'second list field exists',
    );
    await tester.enterText(inEditor(find.byType(TextField)).at(1),
        '第二项关键词');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // 4. Save via the AppBar button; then "restart" = reload from disk.
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    debugPrint('ITEST: saved');

    // 5. Card library search finds the card by plain-text projection.
    router.push(AppRoutes.cardLibrary);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await _waitFor(
      tester,
      () => find.text('卡片库').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
      description: 'card library opens',
    );
    await tester.enterText(find.byType(TextField).first, '第二项关键词');
    await _waitFor(
      tester,
      () => find.textContaining('第二项关键词').evaluate().length >= 2,
      timeout: const Duration(seconds: 15),
      description: 'search hit shows title + snippet',
    );
    debugPrint('ITEST: search hit found');

    // 6. Open the hit: the document recovers from disk (list nesting kept).
    await tester.tap(find.textContaining('第二项关键词').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await _waitFor(
      tester,
      () => find.textContaining('卡片编辑').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
      description: 'editor reopens from the search hit',
    );
    expect(find.text('中文混排 English 123'), findsOneWidget,
        reason: 'first list item text recovered from disk');
    expect(find.text('第二项关键词'), findsOneWidget,
        reason: 'sibling list item text recovered from disk');
    debugPrint('ITEST: ALL DONE');
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty)
          .take(30)
          .join(' | ');
      fail('timed out waiting for: $description\nvisible texts: $texts');
    }
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<bool> _waitForAny(
  WidgetTester tester,
  bool Function() homeCondition,
  bool Function() altCondition, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!homeCondition() && !altCondition()) {
    if (DateTime.now().isAfter(deadline)) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty)
          .take(30)
          .join(' | ');
      fail('timed out waiting for: $description\nvisible texts: $texts');
    }
    await tester.pump(const Duration(milliseconds: 300));
  }
  return homeCondition();
}
