import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/card_library_screen.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';

class _CountingThumbnailResolver implements ThumbnailResolver {
  final List<ThumbnailResolveRequest> requests = [];

  @override
  Future<ResolvedThumbnail> resolve(ThumbnailResolveRequest request) async {
    requests.add(request);
    return const ResolvedThumbnail.missing();
  }
}

void main() {
  late Directory root;
  late File dbFile;
  late AppDatabase db;
  late UnifiedCardRepository repository;
  late WhiteboardDriftStore boardStore;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('f2_card_library_');
    dbFile = File('${root.path}${Platform.pathSeparator}whiteboard.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    boardStore = WhiteboardDriftStore(db);
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
  });

  tearDown(() async {
    CardRichTextEditorScreen.setRepositoryForTesting(null);
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    bool settle = true,
  }) async {
    final router = GoRouter(
      initialLocation: AppRoutes.cardLibrary,
      routes: [
        GoRoute(
          path: AppRoutes.cardLibrary,
          builder: (_, __) => CardLibraryScreen(
            repository: repository,
            boardStore: boardStore,
          ),
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
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
    expect(find.text('导入链接 / 视频'), findsOneWidget);
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

  testWidgets('desktop scope is explicit and mobile keeps Spring Rain',
      (tester) async {
    await repository.createTextCard(
      cardId: 'platform_scope_card',
      title: '平台作用域卡片',
      body: '移动端继续使用春雨昼眠。',
    );
    await pumpApp(tester);

    expect(find.byKey(const ValueKey('card_library_mobile')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('card-library-mobile-list')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('desktop_page_title')), findsNothing);
    expect(find.byKey(const ValueKey('card-library-grid')), findsNothing);
    expect(
      tester
          .widget<Scaffold>(
            find.byKey(const ValueKey('card_library_mobile')),
          )
          .backgroundColor,
      SpringRainUiTokens.daylightCanvas,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopWorkspaceTheme(
          child: CardLibraryScreen(
            repository: repository,
            boardStore: boardStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('card_library_desktop')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_page_title')), findsOneWidget);
    expect(find.byKey(const ValueKey('card-library-grid')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('card-library-mobile-list')), findsNothing);
    expect(
      tester
          .widget<Scaffold>(
            find.byKey(const ValueKey('card_library_desktop')),
          )
          .backgroundColor,
      DesktopWorkspaceTokens.lieflatPalm.canvas,
    );
  });

  testWidgets(
      'untrusted thumbnail metadata never creates network or file images',
      (tester) async {
    final candidates = <String, String>{
      'loopback': 'http://127.0.0.1/private.png',
      'private': 'http://192.168.1.20/cover.png',
      'https': 'https://example.com/cover.png',
      'file_uri': 'file:///C:/Windows/System32/drivers/etc/hosts',
      'absolute': r'C:\Windows\System32\drivers\etc\hosts',
      'traversal': '../outside.png',
    };
    final cards = <CardContract>[];
    for (final entry in candidates.entries) {
      cards.add(await _createSourceCard(
        repository,
        sourceId: 'src_unsafe_${entry.key}',
        type: SourceMediaType.web,
        title: 'unsafe ${entry.key}',
        metadata: {'thumbnail_url': entry.value},
      ));
    }

    var createHttpClientCount = 0;
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await HttpOverrides.runZoned(
      () async {
        await pumpApp(tester);

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                (widget.image is NetworkImage || widget.image is FileImage),
          ),
          findsNothing,
        );
        for (final card in cards) {
          final cardFinder =
              find.byKey(ValueKey('card-library-card-${card.cardId}'));
          final preview = find.descendant(
            of: cardFinder,
            matching: find.byWidgetPredicate(
              (widget) => widget is Expanded && widget.flex == 7,
            ),
          );
          expect(preview, findsOneWidget);
          expect(
            find.descendant(of: preview, matching: find.text('暂无网页预览')),
            findsOneWidget,
          );
        }
      },
      createHttpClient: (_) {
        createHttpClientCount++;
        throw StateError('Card library must not create an HTTP client');
      },
    );
    expect(createHttpClientCount, 0);
  });

  testWidgets('only an integrity-checked thumbnail_ref creates a local preview',
      (tester) async {
    const candidate = 'https://example.com/cover.png';
    const sourceId = 'src_safe_cached';
    const versionId = 'ver_${sourceId}_v1';
    final image = img.Image(width: 48, height: 32);
    img.fill(image, color: img.ColorRgb8(67, 89, 59));
    final bytes = img.encodePng(image);
    final contentHash = sha256.convert(bytes).toString();
    final candidateHash = sha256.convert(candidate.codeUnits).toString();
    final objectRef = 'objects/thumbnails/$contentHash.png';
    final cacheDir = Directory(
      '${root.path}${Platform.pathSeparator}objects'
      '${Platform.pathSeparator}thumbnails',
    );
    await tester.runAsync(() async {
      await cacheDir.create(recursive: true);
      await File(
        '${cacheDir.path}${Platform.pathSeparator}$contentHash.png',
      ).writeAsBytes(bytes, flush: true);
    });
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: root,
      thumbnailResolver: SafeThumbnailResolver(whiteboardRoot: root),
    );
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
    await _createSourceCard(
      repository,
      sourceId: sourceId,
      type: SourceMediaType.web,
      title: '可信缓存网页',
      metadata: const {
        'canonical_url': 'https://example.com/article',
        'og_image': candidate,
      },
      presentation: {
        'thumbnail': candidate,
        'thumbnail_ref': objectRef,
        'thumbnail_version_id': versionId,
        'thumbnail_candidate_hash': candidateHash,
      },
    );

    await pumpApp(tester, settle: false);
    final thumbnail = find
        .byKey(const ValueKey('card-library-thumbnail-card_src_safe_cached'));
    await _pumpUntilFound(tester, thumbnail);

    final widget = tester.widget<Image>(thumbnail);
    expect(widget.image, isA<ResizeImage>());
    final provider = (widget.image as ResizeImage).imageProvider;
    expect(provider, isA<FileImage>());
    final file = (provider as FileImage).file;
    expect(file.path, startsWith(cacheDir.path));
    expect(find.text('暂无网页预览'), findsNothing);
    expect(find.byType(NetworkImage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('untrusted thumbnail resolver is never called by render paths',
      (tester) async {
    final resolver = _CountingThumbnailResolver();
    repository = UnifiedCardRepository(
      db: db,
      whiteboardRoot: root,
      thumbnailResolver: resolver,
    );
    CardRichTextEditorScreen.setRepositoryForTesting(repository);
    for (var index = 0; index < 12; index++) {
      await _createSourceCard(
        repository,
        sourceId: 'src_lazy_$index',
        type: SourceMediaType.web,
        title: '惰性缩略图 $index',
        metadata: {
          'canonical_url': 'https://example.com/article/$index',
          'og_image': 'https://example.com/cover/$index.png',
        },
      );
    }

    await pumpApp(tester, settle: false);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('card-library-mobile-list')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(resolver.requests, isEmpty);

    await tester.drag(
      find.byKey(const ValueKey('card-library-mobile-list')),
      const Offset(0, -1600),
    );
    await tester.pump();
    expect(resolver.requests, isEmpty);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(resolver.requests, isEmpty);
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
    await boardStore.createBoard(name: '筛选目标板');
    await pumpApp(tester);

    expect(find.textContaining('卡片角色：'), findsOneWidget);
    expect(find.textContaining('媒介类型：'), findsOneWidget);

    final placeButton =
        find.byKey(const ValueKey('card-library-place-note_filter'));
    await tester.scrollUntilVisible(
      placeButton,
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('card-library-mobile-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(placeButton);
    await tester.pumpAndSettle();
    expect(find.text('最近白板'), findsOneWidget);
    await tester.tap(find.text('筛选目标板'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('card-library-kind-filter')));
    await tester.pumpAndSettle();
    expect(find.text('原件卡'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('card-library-placed-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已上板').last);
    await tester.pumpAndSettle();
    expect(find.text('河边笔记'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('card-library-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('card-library-placed-filter')));
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

  testWidgets(
      'target picker searches all boards and one card can enter multiple boards',
      (tester) async {
    final card = await repository.createTextCard(
      cardId: 'note_multi_board',
      title: '只保留一个身份',
      body: '同一张卡可以进入多个白板。',
    );
    final firstBoardId = await boardStore.createBoard(name: '最近白板 A');
    final secondBoardId = await boardStore.createBoard(name: '远端检索目标');
    for (var i = 0; i < 5; i++) {
      await boardStore.createBoard(name: '占位白板 $i');
    }
    await pumpApp(tester);

    Future<void> placeInto(String boardName, {String? search}) async {
      await tester.tap(
        find.byKey(const ValueKey('card-library-place-note_multi_board')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('board-target-search')),
      );
      if (search != null) {
        await tester.enterText(
          find.byKey(const ValueKey('board-target-search')),
          search,
        );
        await tester.pumpAndSettle();
        expect(find.text('全部白板'), findsOneWidget);
      }
      await tester.tap(find.text(boardName).last);
      await _pumpUntilGone(
        tester,
        find.byKey(const ValueKey('board-target-search')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('card-library-card-note_multi_board')),
      );
    }

    await placeInto('最近白板 A', search: '最近白板 A');
    await placeInto('远端检索目标', search: '远端检索');

    final first = (await boardStore.load(firstBoardId)).snapshot!;
    final second = (await boardStore.load(secondBoardId)).snapshot!;
    expect(
      first.boardItems.where((item) => item.cardId == card.cardId),
      hasLength(2),
      reason: 'the global snapshot keeps both independent BoardItems',
    );
    expect(
      second.boardItems.where((item) => item.cardId == card.cardId),
      hasLength(2),
    );
    expect(await repository.listCards(), hasLength(1));

    // Finish the UI portion before directly mutating the snapshot below. This
    // avoids racing the screen's post-placement refresh on the same executor.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final withoutFirstPlacement = WhiteboardSnapshot(
      schemaVersion: first.schemaVersion,
      sources: first.sources,
      sourceVersions: first.sourceVersions,
      cards: first.cards,
      boards: first.boards,
      boardItems: first.boardItems
          .where((item) => item.boardId != firstBoardId)
          .toList(),
      groups: first.groups,
      groupMembers: first.groupMembers,
      edges: first.edges,
      viewport: first.viewport,
      updatedAt: DateTime.now().toUtc(),
    );
    expect(await boardStore.save(firstBoardId, withoutFirstPlacement), isTrue);
    expect(
      await repository.getCard(card.cardId, loadDocument: false),
      isNotNull,
    );
  });

  testWidgets('new-board target creates a board and only adds a BoardItem',
      (tester) async {
    final card = await repository.createTextCard(
      cardId: 'note_new_board',
      title: '新板目标卡',
    );
    await pumpApp(tester);

    await tester.tap(
      find.byKey(const ValueKey('card-library-place-note_new_board')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建白板'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('board-target-new-name')),
      '从卡片库新建',
    );
    await tester.tap(find.text('创建并放入'));
    await tester.pumpAndSettle();

    final boards = await boardStore.listBoards();
    expect(boards, hasLength(1));
    expect(boards.single.name, '从卡片库新建');
    final snapshot = (await boardStore.load(boards.single.boardId)).snapshot!;
    expect(
      snapshot.boardItems
          .singleWhere((item) => item.cardId == card.cardId)
          .boardId,
      boards.single.boardId,
    );
    expect(await repository.listCards(), hasLength(1));
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
    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      '#闭环标签',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '重启恢复标题\n搜索闭环关键词');
    await tester.tap(find.text('保存').first);
    await _pumpUntilFound(tester, find.text('已保存'));
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('重启恢复标题'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('card-library-tag-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('闭环标签').last);
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
    await repository.updateCardMetadata(
      created.cardId,
      tags: const ['重启标签'],
    );
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(dbFile));
    repository = UnifiedCardRepository(db: db, whiteboardRoot: root);
    boardStore = WhiteboardDriftStore(db);
    CardRichTextEditorScreen.setRepositoryForTesting(repository);

    final recovered = await repository.getCard(created.cardId);
    expect(recovered!.documentState, CardDocumentState.available);
    expect(recovered.card.title, '重启恢复标题');
    expect(recovered.card.body, contains('搜索闭环关键词'));
    expect(recovered.document!.toPlainText(), contains('搜索闭环关键词'));
    expect(recovered.card.tags, ['重启标签']);
    expect(
      await repository.listCards(
        const CardLibraryQuery(tags: {'重启标签'}),
      ),
      hasLength(1),
    );
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

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) return;
  }
  expect(finder, findsNothing, reason: 'widget did not close after 4 seconds');
}

Future<CardContract> _createSourceCard(
  UnifiedCardRepository repository, {
  required String sourceId,
  required SourceMediaType type,
  required String title,
  Map<String, dynamic> metadata = const {},
  Map<String, dynamic> presentation = const {},
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
    metadata: metadata,
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
    presentation: presentation,
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
