import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/card_library_screen.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';

void main() {
  late Directory root;
  late File dbFile;
  late AppDatabase db;
  late UnifiedCardRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('f2_card_library_');
    dbFile = File('${root.path}${Platform.pathSeparator}whiteboard.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
  });

  tearDown(() async {
    CardRichTextEditorScreen.setRepositoryForTesting(null);
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.cardLibrary,
      routes: [
        GoRoute(
          path: AppRoutes.cardLibrary,
          builder: (_, __) => CardLibraryScreen(repository: repository),
        ),
        GoRoute(
          path: AppRoutes.cardEdit,
          builder: (_, state) => CardRichTextEditorScreen(
            cardId: state.pathParameters['cardId']!,
          ),
        ),
        GoRoute(
          path: AppRoutes.sourceStudy,
          builder: (_, state) => Scaffold(
            body: Text('source:${state.pathParameters['sourceId']}'),
          ),
        ),
        GoRoute(
          path: AppRoutes.linkImport,
          builder: (_, __) => const Scaffold(body: Text('import-route')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('empty repository shows honest state and both creation entries',
      (tester) async {
    await pumpApp(tester);

    expect(find.text('卡片库还是空的'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('card-library-create-text')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('card-library-import-link')), findsOneWidget);
  });

  testWidgets('default view lists real text and media cards with true previews',
      (tester) async {
    await repository.createTextCard(
      cardId: 'note_default',
      title: '研究随记',
      body: '正文才是文字卡的预览主体',
      tags: const ['研究'],
    );
    final web = await _createSourceCard(
      repository,
      sourceId: 'src_web_default',
      type: SourceMediaType.web,
      title: '没有封面的网页',
    );

    await pumpApp(tester);

    expect(find.byKey(const ValueKey('card-library-card-note_default')),
        findsOneWidget);
    expect(find.text('正文才是文字卡的预览主体'), findsOneWidget);
    expect(
      find.byKey(ValueKey('card-library-card-${web.cardId}')),
      findsOneWidget,
    );
    expect(find.text('暂无网页预览'), findsOneWidget);
  });

  testWidgets('type, source, tag and keyword filters compose', (tester) async {
    await repository.createTextCard(
      cardId: 'note_filter',
      title: '河边笔记',
      body: '可搜索的散步关键词',
      tags: const ['研究'],
    );
    final annotation = await repository.createTextCard(
      cardId: 'annotation_filter',
      title: '批注内容',
      body: '另一条记录',
      tags: const ['批注'],
    );
    await repository.updateCardMetadata(
      annotation.cardId,
      cardKind: CardKind.annotation,
    );
    await _createSourceCard(
      repository,
      sourceId: 'src_web_filter',
      type: SourceMediaType.web,
      title: '筛选网页',
    );
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('card-library-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文字').last);
    await tester.pumpAndSettle();
    expect(find.text('河边笔记'), findsOneWidget);
    expect(find.text('批注内容'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('card-library-tag-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('研究').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('card-library-search')),
      '散步关键词',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('河边笔记'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('card-library-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('card-library-tag-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('card-library-search')),
      '',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('card-library-source-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网页').last);
    await tester.pumpAndSettle();
    expect(find.text('筛选网页'), findsOneWidget);
    expect(find.text('河边笔记'), findsNothing);
  });

  testWidgets('text opens editor, source opens study, import only navigates',
      (tester) async {
    await repository.createTextCard(
      cardId: 'note_route',
      title: '文字路由',
    );
    final source = await _createSourceCard(
      repository,
      sourceId: 'src_route',
      type: SourceMediaType.video,
      title: '视频路由',
    );
    final router = await pumpApp(tester);

    tester
        .widget<InkWell>(find.descendant(
          of: find.byKey(const ValueKey('card-library-card-note_route')),
          matching: find.byType(InkWell),
        ))
        .onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(CardRichTextEditorScreen), findsOneWidget);

    router.go(AppRoutes.cardLibrary);
    await tester.pumpAndSettle();
    tester
        .widget<InkWell>(find.descendant(
          of: find.byKey(ValueKey('card-library-card-${source.cardId}')),
          matching: find.byType(InkWell),
        ))
        .onTap!();
    await tester.pumpAndSettle();
    expect(find.text('source:src_route'), findsOneWidget);

    router.go(AppRoutes.cardLibrary);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('card-library-import-link')));
    await tester.pumpAndSettle();
    expect(find.text('import-route'), findsOneWidget);
  });

  testWidgets('create, rich edit, save, search and reopen through the library',
      (tester) async {
    final router = await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('card-library-create-text')));
    await tester.pumpAndSettle();
    final created = (await repository.listCards()).single.card;
    expect(find.byType(CardRichTextEditorScreen), findsOneWidget);

    await _pumpUntilFound(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField).first, '重启恢复标题\n搜索闭环关键词');
    await tester.tap(find.text('保存').first);
    await _pumpUntilFound(tester, find.text('已保存'));
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('重启恢复标题'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('card-library-search')),
      '搜索闭环关键词',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('重启恢复标题'), findsOneWidget);

    tester
        .widget<InkWell>(find.descendant(
          of: find.byKey(ValueKey('card-library-card-${created.cardId}')),
          matching: find.byType(InkWell),
        ))
        .onTap!();
    await _pumpUntilFound(tester, find.byType(TextField));
    expect(find.textContaining('搜索闭环关键词'), findsAtLeastNWidgets(1));
  });

  test('saved rich text and projections survive a database restart', () async {
    final created = await repository.createTextCard(cardId: 'restart_card');
    await repository.saveRichText(
      created.cardId,
      const RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '重启恢复标题'),
        RichTextBlock(type: BlockType.paragraph, text: '搜索闭环关键词'),
      ]),
    );
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    CardRichTextEditorScreen.setRepositoryForTesting(repository);

    final recovered = await repository.getCard(created.cardId);
    expect(recovered!.documentState, CardDocumentState.available);
    expect(recovered.card.title, '重启恢复标题');
    expect(recovered.card.body, contains('搜索闭环关键词'));
    expect(recovered.document!.toPlainText(), contains('搜索闭环关键词'));
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'widget did not appear after 2 seconds');
}

Future<CardContract> _createSourceCard(
  UnifiedCardRepository repository, {
  required String sourceId,
  required SourceMediaType type,
  required String title,
}) async {
  final now = DateTime.utc(2026, 8, 19, 12);
  final versionId = 'ver_${sourceId}_v1';
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: type,
    title: title,
    origin: SourceOrigin.externalLink,
    provider: type.name,
    canonicalId: sourceId,
    currentVersionId: versionId,
    contentHash: 'hash_$sourceId',
    objectRef: 'objects/sources/$sourceId/$versionId.json',
    createdAt: now,
    updatedAt: now,
  );
  final version = SourceVersion(
    versionId: versionId,
    sourceId: sourceId,
    contentHash: 'hash_$sourceId',
    objectRef: source.objectRef!,
    parserVersion: 'f2-test',
    createdAt: now,
  );
  final card = CardContract(
    cardId: 'card_$sourceId',
    cardKind: CardKind.source,
    sourceId: sourceId,
    title: title,
    body: '$title 摘要',
    createdAt: now,
    updatedAt: now,
  );
  await repository.importLegacyIngestion(
    source: source,
    versions: [version],
    card: card,
  );
  return card;
}
