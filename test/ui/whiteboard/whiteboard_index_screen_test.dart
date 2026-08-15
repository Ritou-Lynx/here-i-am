import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/ui/whiteboard/whiteboard_index_screen.dart';

/// W6 — whiteboard index screen widget tests (in-memory Drift store).
void main() {
  late AppDatabase db;
  late WhiteboardDriftStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = WhiteboardDriftStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('empty state renders create hint', (tester) async {
    await tester.pumpWidget(wrap(WhiteboardIndexScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('白板'), findsOneWidget);
    expect(find.textContaining('还没有白板'), findsOneWidget);
    expect(find.text('新建白板'), findsOneWidget);
  });

  testWidgets('boards from store are listed and openable', (tester) async {
    await store.createBoard(name: '舞台灯光研究');
    await store.createBoard(name: '架构笔记');

    final opened = <String>[];
    await tester.pumpWidget(wrap(WhiteboardIndexScreen(
      store: store,
      onOpenBoard: (boardId) => opened.add(boardId),
    )));
    await tester.pumpAndSettle();

    expect(find.text('舞台灯光研究'), findsOneWidget);
    expect(find.text('架构笔记'), findsOneWidget);
    expect(find.textContaining('还没有白板'), findsNothing);

    await tester.tap(find.text('舞台灯光研究'));
    expect(opened, hasLength(1));
    final boards = await store.listBoards();
    expect(opened.single, boards.firstWhere((b) => b.name == '舞台灯光研究').boardId);
  });

  testWidgets('create board flow creates and opens a new board',
      (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(wrap(WhiteboardIndexScreen(
      store: store,
      onOpenBoard: (boardId) => opened.add(boardId),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建白板'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新白板一号');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    final boards = await store.listBoards();
    expect(boards.single.name, '新白板一号');
    expect(opened.single, boards.single.boardId);
  });

  testWidgets('load failure shows retry', (tester) async {
    // A store that throws on list reports the error state.
    final failing = _FailingListStore(db);
    await tester.pumpWidget(wrap(WhiteboardIndexScreen(store: failing)));
    await tester.pumpAndSettle();

    expect(find.textContaining('加载白板失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}

class _FailingListStore extends WhiteboardDriftStore {
  _FailingListStore(super.db);

  @override
  Future<List<WhiteboardIndexEntry>> listBoards() async {
    throw StateError('list failed');
  }
}
