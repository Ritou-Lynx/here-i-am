import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_asset_ref.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_screen.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_view_model.dart';
import 'package:memex/ui/whiteboard/widgets/card_local_media_preview.dart';
import 'package:memex/ui/whiteboard/card_library_screen_v2.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

class _Harness {
  _Harness(this.root, this.db, this.repository);

  final Directory root;
  final AppDatabase db;
  final UnifiedCardRepository repository;

  static _Harness create() {
    final root = Directory.systemTemp.createTempSync('wb_media_cards_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    return _Harness(
      root,
      db,
      UnifiedCardRepository(db: db, whiteboardRoot: root),
    );
  }

  Future<File> sourceImage(String name) async {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(base64Decode(_png), flush: true);
    return file;
  }

  Future<CardContract> imageCard(String id, File source) async {
    final objectStore = RichTextObjectStore(repository.richTextStorage.baseDir);
    final ref = await objectStore.importFile(
      source.path,
      alt: source.uri.pathSegments.last,
    );
    final card = await repository.createTextCard(cardId: id, title: '本地图片');
    return repository.saveRichText(
      card.cardId,
      RichTextDocument(
        blocks: [
          RichTextBlock(
            type: BlockType.image,
            attrs: {'asset_ref_id': ref.refId, 'alt': '本地图片'},
          ),
        ],
        assetRefs: [ref],
      ),
      title: '本地图片',
    );
  }

  Future<void> dispose() async {
    await db.close();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

class _FailingCleanupRepository extends UnifiedCardRepository {
  _FailingCleanupRepository({required super.db, required super.whiteboardRoot});

  int failures = 1;

  @override
  Future<bool> softDeleteCard(String cardId, {DateTime? at}) {
    if (failures > 0) {
      failures--;
      throw StateError('scripted cleanup failure');
    }
    return super.softDeleteCard(cardId, at: at);
  }
}

class _MidImportFailureRepository extends UnifiedCardRepository {
  _MidImportFailureRepository(
      {required super.db, required super.whiteboardRoot});

  int saves = 0;
  int cleanupFailures = 1;

  @override
  Future<CardContract> saveRichText(
    String cardId,
    RichTextDocument document, {
    String? title,
    bool preserveEmptyTitle = false,
  }) {
    if (++saves == 2) throw StateError(r'C:\private\should-not-leak.png');
    return super.saveRichText(
      cardId,
      document,
      title: title,
      preserveEmptyTitle: preserveEmptyTitle,
    );
  }

  @override
  Future<bool> softDeleteCard(String cardId, {DateTime? at}) {
    if (cleanupFailures-- > 0) throw StateError('scripted cleanup failure');
    return super.softDeleteCard(cardId, at: at);
  }
}

class _CountingCardRepository extends UnifiedCardRepository {
  _CountingCardRepository({required super.db, required super.whiteboardRoot});
  int reads = 0;

  @override
  Future<UnifiedCardRecord?> getCard(String cardId,
      {bool includeDeleted = false, bool loadDocument = true}) {
    reads++;
    return super.getCard(cardId,
        includeDeleted: includeDeleted, loadDocument: loadDocument);
  }
}

WhiteboardSnapshot _snapshot(CardContract card, {bool duplicate = false}) {
  final now = DateTime.utc(2026, 8, 23);
  return WhiteboardSnapshot(
    boards: [Board(boardId: 'board_media', name: '媒体卡', createdAt: now)],
    cards: [card],
    boardItems: [
      const BoardItem(
        itemId: 'item_media_a',
        boardId: 'board_media',
        cardId: 'card_media',
        x: -280,
        y: -100,
        width: 240,
        height: 220,
      ),
      if (duplicate)
        const BoardItem(
          itemId: 'item_media_b',
          boardId: 'board_media',
          cardId: 'card_media',
          x: 40,
          y: -100,
          width: 240,
          height: 220,
        ),
    ],
  );
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(finder, findsWidgets);
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isNotEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(finder, findsNothing);
}

void _disposeHarnessAfterTest(WidgetTester tester, _Harness harness) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(harness.dispose);
  });
}

void main() {
  testWidgets('已有 RichText 图片在多个 BoardItem 直接预览且重建后恢复', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    late final CardContract card;
    await tester.runAsync(() async {
      final source = await harness.sourceImage('camera.png');
      card = await harness.imageCard('card_media', source);
    });

    Future<void> pump(UnifiedCardRepository repository) async {
      final vm = WhiteboardCanvasViewModel(
        initialSnapshot: _snapshot(card, duplicate: true),
        boardId: 'board_media',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WhiteboardCanvasScreen(
            key: ValueKey(repository),
            viewModel: vm,
            cardRepository: repository,
          ),
        ),
      );
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('wb_local_media_item_media_a')),
      );
      expect(
        find.byKey(const ValueKey('wb_local_media_item_media_b')),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNWidgets(2));
      final libraryButton = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('wb_open_card_library_tool')),
          matching: find.byType(InkWell),
        ),
      );
      libraryButton.onTap!();
      await tester.pump();
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('wb_local_media_library_card_media')),
      );
      expect(find.byType(Image), findsNWidgets(3));
    }

    await pump(harness.repository);
    final restarted = UnifiedCardRepository(
      db: harness.db,
      whiteboardRoot: harness.root,
    );
    await pump(restarted);
  });

  testWidgets('本地图片对象缺失时诚实占位，不把文件名冒充预览', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    late final CardContract card;
    await tester.runAsync(() async {
      final source = await harness.sourceImage('missing.png');
      card = await harness.imageCard('card_media', source);
      final record = await harness.repository.getCard(card.cardId);
      final ref = record!.document!.assetRefs.single;
      final object = RichTextObjectStore(
        harness.repository.richTextStorage.baseDir,
      ).resolveFile(ref)!;
      await object.delete();
    });

    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(card),
      boardId: 'board_media',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasScreen(
          viewModel: vm,
          cardRepository: harness.repository,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('图片对象缺失'));
    expect(find.text('missing.png'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('Source 缓存证据只读本地哈希对象且渲染不触网', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    late final CardContract card;
    await tester.runAsync(() async {
      final bytes = base64Decode(_png);
      final hash = sha256.convert(bytes).toString();
      final cache = Directory(
        '${harness.root.path}${Platform.pathSeparator}objects'
        '${Platform.pathSeparator}thumbnails',
      );
      await cache.create(recursive: true);
      await File(
        '${cache.path}${Platform.pathSeparator}$hash.png',
      ).writeAsBytes(bytes, flush: true);
      final created = await harness.repository.createTextCard(
        cardId: 'card_media',
        title: '缓存图片来源',
      );
      card = await harness.repository.updateCardMetadata(
        created.cardId,
        cardKind: CardKind.source,
        presentation: {'thumbnail_ref': 'objects/thumbnails/$hash.png'},
      );
    });
    final repository = UnifiedCardRepository(
      db: harness.db,
      whiteboardRoot: harness.root,
      thumbnailResolver: SafeThumbnailResolver(
        whiteboardRoot: harness.root,
      ),
    );
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: _snapshot(card),
      boardId: 'board_media',
    );
    var httpClients = 0;
    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: WhiteboardCanvasScreen(
              viewModel: vm,
              cardRepository: repository,
            ),
          ),
        );
        await _pumpUntil(
          tester,
          find.byKey(const ValueKey('wb_local_media_item_media_a')),
        );
      },
      createHttpClient: (_) {
        httpClients++;
        throw StateError('viewport rendering must stay offline');
      },
    );
    expect(httpClients, 0);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('导入图片建立真实 Card、保存布局并在双击时打开完整编辑', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    late final File source;
    await tester.runAsync(() async {
      source = await harness.sourceImage('morning.png');
    });
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: WhiteboardSnapshot(
        boards: [
          Board(
            boardId: 'board_media',
            name: '媒体卡',
            createdAt: DateTime.utc(2026, 8, 23),
          ),
        ],
        viewport: const BoardViewport(centerX: 900, centerY: 700),
      ),
      boardId: 'board_media',
    );
    var persisted = 0;
    CardContract? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasScreen(
          viewModel: vm,
          cardRepository: harness.repository,
          imagePathPicker: () async => [source.path],
          onPersistSnapshot: () async {
            persisted++;
            return true;
          },
          onOpenCard: (card) => opened = card,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('wb_import_image_tool')));
    final importedPreview = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('wb_local_media_item_');
    });
    await _pumpUntil(tester, importedPreview);
    final records = (await tester.runAsync(
      () => harness.repository.listCards(
        const CardLibraryQuery(loadDocuments: true),
      ),
    ))!;
    expect(records, hasLength(1));
    expect(records.single.document!.blocks.single.type, BlockType.image);
    expect(vm.exportForSave().boardItems, hasLength(1));
    expect(vm.exportForSave().boardItems.single.x, closeTo(770, .01));
    expect(vm.exportForSave().boardItems.single.y, closeTo(600, .01));
    expect(persisted, 1);

    final cardFinder = find.byKey(
      Key('wb_card_${vm.exportForSave().boardItems.single.itemId}'),
    );
    await tester.tap(cardFinder);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(cardFinder);
    for (var i = 0; i < 50 && opened == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(opened?.cardId, records.single.card.cardId);
    expect(find.byKey(const ValueKey('wb_compact_card_editor')), findsNothing);
  });

  testWidgets('只读白板拒绝图片导入且不会调用 picker', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: WhiteboardSnapshot(
        boards: [
          Board(
            boardId: 'board_media',
            name: '只读媒体卡',
            createdAt: DateTime.utc(2026, 8, 23),
          ),
        ],
      ),
      boardId: 'board_media',
    )..setReadonly(true);
    var pickerCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasScreen(
          viewModel: vm,
          cardRepository: harness.repository,
          imagePathPicker: () async {
            pickerCalls++;
            return const [];
          },
        ),
      ),
    );
    final button = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('wb_import_image_tool')),
        matching: find.byType(InkWell),
      ),
    );
    expect(button.onTap, isNull);
    expect(pickerCalls, 0);
  });

  testWidgets('图片布局保存失败回滚 BoardItem、Card 与对象文件', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    late final File source;
    await tester.runAsync(() async {
      source = await harness.sourceImage('rollback.png');
    });
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: WhiteboardSnapshot(
        boards: [
          Board(
            boardId: 'board_media',
            name: '媒体回滚',
            createdAt: DateTime.utc(2026, 8, 23),
          ),
        ],
      ),
      boardId: 'board_media',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasScreen(
          viewModel: vm,
          cardRepository: harness.repository,
          imagePathPicker: () async => [source.path],
          onPersistSnapshot: () async => false,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('wb_import_image_tool')));
    await tester.pump(const Duration(milliseconds: 800));

    expect(vm.exportForSave().boardItems, isEmpty);
    expect(await tester.runAsync(harness.repository.listCards), isEmpty);
    final objects = RichTextObjectStore(
      harness.repository.richTextStorage.baseDir,
    ).objectsDirectory;
    expect(objects.existsSync() ? objects.listSync() : const [], isEmpty);
  });

  testWidgets('图片 Card 补偿失败保持可见重试，成功后再删除对象', (tester) async {
    final root = Directory.systemTemp.createTempSync('wb_media_retry_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = _FailingCleanupRepository(
      db: db,
      whiteboardRoot: root,
    );
    final harness = _Harness(root, db, repository);
    _disposeHarnessAfterTest(tester, harness);
    late final File source;
    await tester.runAsync(() async {
      source = await harness.sourceImage('retry.png');
    });
    final vm = WhiteboardCanvasViewModel(
      initialSnapshot: WhiteboardSnapshot(
        boards: [
          Board(
            boardId: 'board_media',
            name: '媒体补偿',
            createdAt: DateTime.utc(2026, 8, 23),
          ),
        ],
      ),
      boardId: 'board_media',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardCanvasScreen(
          viewModel: vm,
          cardRepository: repository,
          imagePathPicker: () async => [source.path],
          onPersistSnapshot: () async => false,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('wb_import_image_tool')));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('wb_pending_card_compensation')),
    );
    expect(await tester.runAsync(repository.listCards), hasLength(1));

    await tester.tap(
      find.byKey(const ValueKey('wb_retry_card_compensation')),
    );
    await _pumpUntilGone(
      tester,
      find.byKey(const ValueKey('wb_pending_card_compensation')),
    );
    expect(await tester.runAsync(repository.listCards), isEmpty);
    final objects = RichTextObjectStore(
      repository.richTextStorage.baseDir,
    ).objectsDirectory;
    expect(objects.existsSync() ? objects.listSync() : const [], isEmpty);
  });

  testWidgets('单项中途失败登记补偿且继续清理其余项', (tester) async {
    final root = Directory.systemTemp.createTempSync('wb_media_mid_fail_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository =
        _MidImportFailureRepository(db: db, whiteboardRoot: root);
    final harness = _Harness(root, db, repository);
    _disposeHarnessAfterTest(tester, harness);
    late final List<String> paths;
    await tester.runAsync(() async => paths = [
          (await harness.sourceImage('first.png')).path,
          (await harness.sourceImage('second.png')).path,
        ]);
    final vm = WhiteboardCanvasViewModel(
        initialSnapshot: WhiteboardSnapshot(
          boards: [
            Board(
                boardId: 'board_media',
                name: '补偿',
                createdAt: DateTime.utc(2026, 8, 23))
          ],
        ),
        boardId: 'board_media');
    await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasScreen(
      viewModel: vm,
      cardRepository: repository,
      imagePathPicker: () async => paths,
    )));
    await tester.tap(find.byKey(const ValueKey('wb_import_image_tool')));
    await _pumpUntil(
        tester, find.byKey(const ValueKey('wb_pending_card_compensation')));
    expect(find.textContaining('private'), findsNothing);
    expect(await tester.runAsync(repository.listCards), hasLength(1));
    await tester.tap(find.byKey(const ValueKey('wb_retry_card_compensation')));
    await _pumpUntilGone(
        tester, find.byKey(const ValueKey('wb_pending_card_compensation')));
    expect(await tester.runAsync(repository.listCards), isEmpty);
    final objects = RichTextObjectStore(repository.richTextStorage.baseDir)
        .objectsDirectory;
    expect(objects.existsSync() ? objects.listSync() : const [], isEmpty);
  });

  testWidgets('projection key 变化会重新解析预览', (tester) async {
    final root = Directory.systemTemp.createTempSync('wb_media_refresh_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = _CountingCardRepository(db: db, whiteboardRoot: root);
    final harness = _Harness(root, db, repository);
    _disposeHarnessAfterTest(tester, harness);
    final created = DateTime.utc(2026, 8, 23);
    CardContract card(DateTime updated, String ref) => CardContract(
          cardId: 'card_refresh',
          cardKind: CardKind.source,
          createdAt: created,
          updatedAt: updated,
          presentation: {'thumbnail_ref': ref},
        );
    Widget app(CardContract value) => MaterialApp(
            home: CardLocalMediaPreview(
          repository: repository,
          cardId: value.cardId,
          card: value,
          placementKey: 'refresh',
          maxHeight: 80,
          surfaceColor: Colors.white,
          foregroundColor: Colors.black,
        ));
    await tester.pumpWidget(app(card(created, 'objects/a.png')));
    await tester.pump();
    final reads = repository.reads;
    await tester.pumpWidget(
        app(card(created.add(const Duration(seconds: 1)), 'objects/b.png')));
    await tester.pump();
    expect(repository.reads, greaterThan(reads));
  });

  testWidgets('纯本地图片无 Source 时卡片库正常显示且不泄漏 ErrorWidget', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    await tester.runAsync(() async {
      final source = await harness.sourceImage('library.png');
      await harness.imageCard('card_media', source);
    });

    await tester.pumpWidget(MaterialApp(
      home: CardLibraryScreen(repository: harness.repository),
    ));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('card-library-local-image-card_media')),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('图片'), findsOneWidget);
    expect(find.byKey(const ValueKey('card-library-delete-card_media')),
        findsOneWidget);
  });

  testWidgets('图片主卡占据卡面主体且最多保留一行元信息，混排卡仍走正文布局', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    late CardContract imageCard;
    late CardContract mixedCard;
    await tester.runAsync(() async {
      final source = await harness.sourceImage('layout.png');
      imageCard = await harness.imageCard('card_media', source);
      final imageRecord = await harness.repository.getCard(imageCard.cardId);
      final ref = imageRecord!.document!.assetRefs.single;
      final created = await harness.repository.createTextCard(
        cardId: 'card_mixed',
        title: '图文卡',
      );
      mixedCard = await harness.repository.saveRichText(
        created.cardId,
        RichTextDocument(
          blocks: [
            RichTextBlock(
              type: BlockType.image,
              attrs: {'asset_ref_id': ref.refId},
            ),
            const RichTextBlock(type: BlockType.paragraph, text: '可编辑正文'),
          ],
          assetRefs: [ref],
        ),
        title: '图文卡',
      );
    });

    final snapshot = _snapshot(imageCard);
    final imageVm = WhiteboardCanvasViewModel(
      initialSnapshot: snapshot,
      boardId: 'board_media',
    );
    await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasScreen(
      viewModel: imageVm,
      cardRepository: harness.repository,
    )));
    await _pumpUntil(
      tester,
      find.byKey(const Key('wb_image_card_meta_item_media_a')),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('wb_local_media_item_media_a')),
    );
    final media = tester.getSize(
      find.byKey(const ValueKey('wb_local_media_item_media_a')),
    );
    expect(media.height, greaterThan(170));

    final mixedSnapshot = WhiteboardSnapshot(
      boards: snapshot.boards,
      cards: [mixedCard],
      boardItems: const [
        BoardItem(
          itemId: 'item_mixed',
          boardId: 'board_media',
          cardId: 'card_mixed',
          x: -120,
          y: -100,
          width: 240,
          height: 220,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
        home: WhiteboardCanvasScreen(
      viewModel: WhiteboardCanvasViewModel(
        initialSnapshot: mixedSnapshot,
        boardId: 'board_media',
      ),
      cardRepository: harness.repository,
    )));
    await _pumpUntil(tester, find.text('可编辑正文'));
    expect(
        find.byKey(const Key('wb_image_card_meta_item_mixed')), findsNothing);
  });

  testWidgets('图片主卡完整查看只显示整图和标签并可保存，图文卡保持富文本编辑', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    late CardContract imageCard;
    late RichTextAssetRef ref;
    await tester.runAsync(() async {
      final source = await harness.sourceImage('viewer.png');
      imageCard = await harness.imageCard('card_media', source);
      final record = await harness.repository.getCard(imageCard.cardId);
      ref = record!.document!.assetRefs.single;
    });
    CardRichTextEditorScreen.setRepositoryForTesting(harness.repository);
    addTearDown(() => CardRichTextEditorScreen.setRepositoryForTesting(null));

    await tester.pumpWidget(const MaterialApp(
      home: CardRichTextEditorScreen(cardId: 'card_media'),
    ));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('image-primary-full-image')),
    );
    expect(find.byKey(const ValueKey('rich_text_editor_paper')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('card-tag-input')),
      '灵感',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 100));
    final updated = await tester.runAsync(
      () => harness.repository.getCard('card_media', loadDocument: false),
    );
    expect(updated!.card.tags, contains('灵感'));

    await tester.runAsync(() async {
      final mixed = await harness.repository.createTextCard(
        cardId: 'card_mixed',
        title: '图文卡',
      );
      await harness.repository.saveRichText(
        mixed.cardId,
        RichTextDocument(
          blocks: [
            RichTextBlock(
              type: BlockType.image,
              attrs: {'asset_ref_id': ref.refId},
            ),
            const RichTextBlock(type: BlockType.paragraph, text: '正文'),
          ],
          assetRefs: [ref],
        ),
      );
    });
    await tester.pumpWidget(const MaterialApp(
      home: CardRichTextEditorScreen(
        key: ValueKey('mixed-editor'),
        cardId: 'card_mixed',
      ),
    ));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('rich_text_editor_paper')),
    );
    expect(
        find.byKey(const ValueKey('image-primary-card-screen')), findsNothing);
  });

  testWidgets('卡片库全局软删除明确提示所有白板引用且保留 BoardItem', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    late CardContract card;
    final store = WhiteboardDriftStore(harness.db);
    await tester.runAsync(() async {
      final source = await harness.sourceImage('delete.png');
      card = await harness.imageCard('card_media', source);
      await store.save('board_media', _snapshot(card));
    });
    await tester.pumpWidget(MaterialApp(
      home: CardLibraryScreen(
        repository: harness.repository,
        boardStore: store,
      ),
    ));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('card-library-delete-card_media')),
    );
    await tester
        .tap(find.byKey(const ValueKey('card-library-delete-card_media')));
    await tester.pumpAndSettle();
    expect(find.textContaining('所有白板中的这张卡片'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('card-library-confirm-delete-card_media')),
    );
    await tester.pumpAndSettle();
    final deleted = await tester.runAsync(() => harness.repository.getCard(
          'card_media',
          includeDeleted: true,
          loadDocument: false,
        ));
    expect(deleted!.card.deletedAt, isNotNull);
    final reloaded = await tester.runAsync(() => store.load('board_media'));
    expect(reloaded!.snapshot!.boardItems.single.cardId, 'card_media');
  });

  testWidgets('卡片库软删除失败时保留卡片并给出可重试反馈', (tester) async {
    final root = Directory.systemTemp.createTempSync('wb_library_delete_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = _FailingCleanupRepository(
      db: db,
      whiteboardRoot: root,
    );
    final harness = _Harness(root, db, repository);
    _disposeHarnessAfterTest(tester, harness);
    await tester.runAsync(() async {
      final source = await harness.sourceImage('delete-fail.png');
      await harness.imageCard('card_media', source);
    });
    await tester.pumpWidget(MaterialApp(
      home: CardLibraryScreen(repository: repository),
    ));
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('card-library-delete-card_media')),
    );
    await tester
        .tap(find.byKey(const ValueKey('card-library-delete-card_media')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('card-library-confirm-delete-card_media')),
    );
    await tester.pumpAndSettle();
    expect(find.text('卡片没有删除成功，请重试'), findsOneWidget);
    final current = await tester.runAsync(() => repository.getCard(
          'card_media',
          includeDeleted: true,
          loadDocument: false,
        ));
    expect(current!.card.deletedAt, isNull);
  });

  testWidgets('损坏的单张富文本卡降级显示且仍可从卡片库删除', (tester) async {
    final harness = _Harness.create();
    _disposeHarnessAfterTest(tester, harness);
    await tester.runAsync(() async {
      await harness.repository.createTextCard(
        cardId: 'card_broken',
        title: '待处理卡片',
        body: '仍可识别的正文投影',
      );
      final dir = Directory(
        '${harness.repository.richTextStorage.baseDir.path}'
        '${Platform.pathSeparator}card_card_broken',
      );
      await dir.create(recursive: true);
      await File('${dir.path}${Platform.pathSeparator}rich_text.json')
          .writeAsString('{not-json', flush: true);
    });
    await tester.pumpWidget(MaterialApp(
      home: CardLibraryScreen(repository: harness.repository),
    ));
    await _pumpUntil(tester, find.text('仍可识别的正文投影'));
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('card-library-delete-card_broken')),
      findsOneWidget,
    );
  });
}
