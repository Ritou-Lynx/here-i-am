import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/link_import_screen.dart';

String _fixture(String name) =>
    File('test/data/whiteboard/ingestion/fixtures/$name').readAsStringSync();

class _Canned {
  final String body;
  final int statusCode;
  final String contentType;
  _Canned(this.body, this.statusCode, this.contentType);
}

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _Canned> responses;
  _FakeAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final url = options.path;
    final canned = responses[url];
    if (canned == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'No canned response for $url',
      );
    }
    return ResponseBody.fromString(
      canned.body,
      canned.statusCode,
      headers: {
        'content-type': [canned.contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(Map<String, _Canned> responses) {
  return Dio(BaseOptions(
    followRedirects: false,
    validateStatus: (s) => s != null && s >= 200 && s < 400,
  ))
    ..httpClientAdapter = _FakeAdapter(responses);
}

LinkIngestionService _service(
  UnifiedCardRepository repository,
  Map<String, _Canned> responses,
) {
  return LinkIngestionService(
    repository: repository,
    ingestor: LinkIngestor(
      httpClient: SafeHttpClient(
        dio: _dio(responses),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      ),
    ),
  );
}

class _ControlledLinkIngestionService extends LinkIngestionService {
  _ControlledLinkIngestionService({
    required super.repository,
    required LinkIngestionService delegate,
    this.commitGate,
    this.failRecentAfterCommit = false,
  }) : _delegate = delegate;

  final LinkIngestionService _delegate;
  final Completer<void>? commitGate;
  final bool failRecentAfterCommit;

  int ingestCalls = 0;
  int commitCalls = 0;
  bool _commitSucceeded = false;

  @override
  Future<LinkIngestionOutcome> ingestUrl(
    String url, {
    bool createCard = false,
    CardKind cardKind = CardKind.source,
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
  }) {
    ingestCalls += 1;
    return _delegate.ingestUrl(
      url,
      createCard: createCard,
      cardKind: cardKind,
      ownerSpace: ownerSpace,
      createdBy: createdBy,
    );
  }

  @override
  Future<LinkIngestionOutcome> commitResult(
    IngestionResult result, {
    CardKind cardKind = CardKind.source,
    OwnerSpace ownerSpace = OwnerSpace.user,
    CardCreatedBy createdBy = CardCreatedBy.user,
  }) async {
    commitCalls += 1;
    await commitGate?.future;
    final outcome = await _delegate.commitResult(
      result,
      cardKind: cardKind,
      ownerSpace: ownerSpace,
      createdBy: createdBy,
    );
    _commitSucceeded = true;
    return outcome;
  }

  @override
  Future<LinkIngestionRecord?> getSource(String sourceId) =>
      _delegate.getSource(sourceId);

  @override
  Future<List<CardContract>> listCards() {
    if (failRecentAfterCommit && _commitSucceeded) {
      throw StateError('deterministic recent refresh failure');
    }
    return _delegate.listCards();
  }
}

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late UnifiedCardRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('w3_ui_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = UnifiedCardRepository(db: db, whiteboardRoot: tempDir);
  });

  tearDown(() async {
    await db.close();
    // Windows may briefly lock a store file held by an in-flight async
    // operation when the widget tree is torn down — retry the delete.
    for (var i = 0; i < 20; i++) {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  GoRouter routerWith(LinkIngestionService service) {
    return GoRouter(
      initialLocation: AppRoutes.linkImport,
      routes: [
        GoRoute(
          path: AppRoutes.linkImport,
          builder: (_, __) => LinkImportScreen(service: service),
        ),
        GoRoute(
          path: AppRoutes.cardLibrary,
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('卡片库页面'))),
        ),
        GoRoute(
          path: AppRoutes.sourceStudy,
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text('视频研读:${state.pathParameters['sourceId']}'),
            ),
          ),
        ),
      ],
    );
  }

  /// The widget under test performs real file I/O (the IngestionStore is
  /// file-backed), and dio's request pipeline schedules work via
  /// `Timer.run`. In widget tests the fake-async zone must therefore be both
  /// advanced (fake timers) and periodically left (real IO events), then
  /// pumped so the widget's continuations run. Polls until [finder] matches.
  Future<void> settleFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 150; i++) {
      if (tester.any(finder)) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('Timed out waiting for $finder');
  }

  Future<void> pump(WidgetTester tester, LinkIngestionService service) async {
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: routerWith(service)),
    );
    await settleFor(tester, find.widgetWithText(FilledButton, '预览'));
  }

  Future<void> fetch(WidgetTester tester, String url) async {
    await tester.enterText(find.byType(TextField), url);
    await tester.tap(find.widgetWithText(FilledButton, '预览'));
    await settleFor(tester, find.text('预览成功'));
    await tester.pumpAndSettle();
  }

  testWidgets('initial state: input + empty recent list hint', (tester) async {
    await pump(tester, _service(repository, {}));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '预览'), findsOneWidget);
    expect(find.textContaining('example.com/article'), findsNothing);
    expect(find.textContaining('还没有导入记录'), findsOneWidget);
  });

  testWidgets('empty input shows inline error', (tester) async {
    await pump(tester, _service(repository, {}));

    await tester.tap(find.widgetWithText(FilledButton, '预览'));
    await tester.pumpAndSettle();

    expect(find.text('请输入要导入的链接'), findsOneWidget);
  });

  testWidgets('narrow and desktop widths keep the import controls usable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    tester.view.physicalSize = const Size(520, 760);
    await pump(tester, _service(repository, {}));
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('link_import_fetch_button')))
          .width,
      greaterThan(450),
    );

    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('link_import_fetch_button')))
          .width,
      lessThan(180),
    );
  });

  testWidgets('keyboard focus follows URL → preview → cancel → commit',
      (tester) async {
    final service = _service(repository, {
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'),
        200,
        'text/html',
      ),
    });
    await pump(tester, service);

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('link_import_url_input')),
    );
    expect(input.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final previewButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('link_import_fetch_button')),
    );
    expect(previewButton.focusNode!.hasFocus, isTrue);

    await fetch(tester, 'https://example.com/doc');
    previewButton.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final cancelButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('link_import_cancel_preview')),
    );
    expect(cancelButton.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final commitButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('link_import_commit_button')),
    );
    expect(commitButton.focusNode!.hasFocus, isTrue);
  });

  testWidgets('ok flow: fetch → preview → explicit card creation',
      (tester) async {
    final service = _service(repository, {
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'),
        200,
        'text/html; charset=utf-8',
      ),
    });
    await pump(tester, service);

    await fetch(tester, 'https://example.com/doc');

    // Success state with preview content.
    expect(find.text('预览成功'), findsOneWidget);
    expect(find.text('春雨昼眠主题设计文档'), findsOneWidget);
    expect(find.textContaining('主图候选（未加载）'), findsOneWidget);
    expect(find.textContaining('故我在设计站 · 林埃'), findsOneWidget);
    expect(find.text('链接级保存'), findsOneWidget);
    expect(find.text('存入卡片库'), findsOneWidget);

    // Explicitly create the card.
    await tester.tap(find.widgetWithText(FilledButton, '存入卡片库'));
    await settleFor(tester, find.text('已在卡片库'));
    await tester.pumpAndSettle();

    // Card created — no duplicate button, library entry + card id shown.
    expect(find.text('打开卡片库'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '存入卡片库'), findsNothing);

    // One card in the store, recent list shows it.
    final cards = await tester.runAsync(() => service.listCards());
    expect(cards, hasLength(1));
  });

  testWidgets(
      'delayed commit is single-flight and blocks fetch, cancel and resubmit',
      (tester) async {
    final delegate = _service(repository, {
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'),
        200,
        'text/html',
      ),
    });
    final commitGate = Completer<void>();
    final service = _ControlledLinkIngestionService(
      repository: repository,
      delegate: delegate,
      commitGate: commitGate,
    );
    await pump(tester, service);
    await fetch(tester, 'https://example.com/doc');

    await tester.tap(
      find.byKey(const ValueKey('link_import_commit_button')),
    );
    await tester.pump();

    expect(service.ingestCalls, 1);
    expect(service.commitCalls, 1);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('link_import_url_input')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('link_import_fetch_button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('link_import_cancel_preview')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('link_import_commit_button')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('link_import_fetch_button')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('link_import_cancel_preview')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('link_import_commit_button')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(service.ingestCalls, 1);
    expect(service.commitCalls, 1);
    expect(
      find.byKey(const ValueKey('link_import_preview_panel')),
      findsOneWidget,
    );

    commitGate.complete();
    await settleFor(tester, find.text('已在卡片库'));
    await tester.pumpAndSettle();

    expect(service.ingestCalls, 1);
    expect(service.commitCalls, 1);
    expect(await tester.runAsync(delegate.listCards), hasLength(1));
  });

  testWidgets('commit success remains saved when recent-list refresh fails',
      (tester) async {
    final delegate = _service(repository, {
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'),
        200,
        'text/html',
      ),
    });
    final service = _ControlledLinkIngestionService(
      repository: repository,
      delegate: delegate,
      failRecentAfterCommit: true,
    );
    await pump(tester, service);
    await fetch(tester, 'https://example.com/doc');

    await tester.tap(
      find.byKey(const ValueKey('link_import_commit_button')),
    );
    await settleFor(
      tester,
      find.byKey(const ValueKey('link_import_recent_error')),
    );
    await tester.pumpAndSettle();

    final cards = (await tester.runAsync(delegate.listCards))!;
    final record = await tester.runAsync(
      () => delegate.getSource(cards.single.sourceId!),
    );
    expect(cards, hasLength(1));
    expect(record!.versions, hasLength(1));
    expect(service.commitCalls, 1);
    expect(find.text('已在卡片库'), findsOneWidget);
    expect(find.text(cards.single.cardId), findsOneWidget);
    expect(find.textContaining('最近列表刷新失败'), findsOneWidget);
    expect(find.textContaining('存入卡片库失败'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '打开卡片库'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('link_import_commit_button')),
      findsNothing,
    );

    final openLibrary = find.widgetWithText(OutlinedButton, '打开卡片库');
    await tester.ensureVisible(openLibrary);
    await tester.pumpAndSettle();
    await tester.tap(openLibrary);
    await tester.pumpAndSettle();
    expect(find.text('卡片库页面'), findsOneWidget);
    expect(await tester.runAsync(delegate.listCards), hasLength(1));
    expect(service.commitCalls, 1);
  });

  testWidgets('cancel after preview leaves database unchanged', (tester) async {
    final service = _service(repository, {
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'),
        200,
        'text/html',
      ),
    });
    await pump(tester, service);
    await fetch(tester, 'https://example.com/doc');

    expect(await tester.runAsync(service.listCards), isEmpty);
    expect(
      await tester.runAsync(() => db.select(db.whiteboardSources).get()),
      isEmpty,
    );
    expect(
      await tester.runAsync(
        () => db.select(db.whiteboardSourceVersions).get(),
      ),
      isEmpty,
    );

    await tester.tap(
      find.byKey(const ValueKey('link_import_cancel_preview')),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('link_import_preview_panel')), findsNothing);
    expect(await tester.runAsync(service.listCards), isEmpty);
    expect(
      await tester.runAsync(() => db.select(db.whiteboardSources).get()),
      isEmpty,
    );
    expect(
      await tester.runAsync(
        () => db.select(db.whiteboardSourceVersions).get(),
      ),
      isEmpty,
    );
  });

  testWidgets('YouTube preview is zero-write then confirms into source route',
      (tester) async {
    final service = _service(repository, {});
    await pump(tester, service);

    await fetch(
      tester,
      'https://www.youtube.com/watch?v=M7lc1UVf-VE',
    );

    expect(find.textContaining('M7lc1UVf-VE'), findsWidgets);
    expect(find.text('研读级就绪'), findsOneWidget);
    expect(await tester.runAsync(service.listCards), isEmpty);
    expect(
      await tester.runAsync(
        () => service.getSource('src_youtube_M7lc1UVf-VE'),
      ),
      isNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, '保存并进入研读'));
    await settleFor(
      tester,
      find.text('视频研读:src_youtube_M7lc1UVf-VE'),
    );

    final cards = await tester.runAsync(service.listCards);
    expect(cards, hasLength(1));
    expect(cards!.single.sourceId, 'src_youtube_M7lc1UVf-VE');
  });

  testWidgets('failed state shown honestly with error message', (tester) async {
    await pump(tester, _service(repository, {}));

    await tester.enterText(
        find.byType(TextField), 'https://example.com/missing');
    await tester.tap(find.widgetWithText(FilledButton, '预览'));
    await settleFor(tester, find.text('抓取失败'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Network error'), findsOneWidget);
    expect(find.text('明确失败'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '存入卡片库'), findsNothing);
  });

  testWidgets('needsAuth state shown honestly', (tester) async {
    final service = _service(repository, {
      'https://example.com/auth': _Canned('', 403, 'text/html'),
    });
    await pump(tester, service);

    await tester.enterText(find.byType(TextField), 'https://example.com/auth');
    await tester.tap(find.widgetWithText(FilledButton, '预览'));
    await settleFor(tester, find.text('需要登录或已被拒绝'));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 403'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '存入卡片库'), findsNothing);
  });

  testWidgets('unsupported state shown honestly (video platform)',
      (tester) async {
    await pump(tester, _service(repository, {}));

    await tester.enterText(
      find.byType(TextField),
      'https://www.bilibili.com/video/BV1xx411c7mD',
    );
    await tester.tap(find.widgetWithText(FilledButton, '预览'));
    await settleFor(tester, find.text('暂不支持此链接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('研读模块'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '存入卡片库'), findsNothing);
  });

  testWidgets(
      'restart recovery: fresh service on same dir shows recent '
      'imports; re-import is idempotent', (tester) async {
    final responses = {
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'),
        200,
        'text/html',
      ),
    };

    // Session 1: create the card.
    final service1 = _service(repository, responses);
    await pump(tester, service1);
    await fetch(tester, 'https://example.com/doc');
    await tester.tap(find.widgetWithText(FilledButton, '存入卡片库'));
    await settleFor(tester, find.text('已在卡片库'));
    await tester.pumpAndSettle();
    final cards1 = await tester.runAsync(() => service1.listCards());
    expect(cards1, hasLength(1));

    // Session 2: a brand-new service + store instance on the SAME directory
    // — the recent list is recovered from disk.
    final service2 = _service(repository, responses);
    await pump(tester, service2);
    await settleFor(tester, find.text('春雨昼眠主题设计文档'));
    expect(find.text('最近导入'), findsOneWidget);

    // Re-import the same URL: no new card, UI says it is already in library.
    await fetch(tester, 'https://example.com/doc');
    await settleFor(tester, find.text('已在卡片库'));
    expect(find.widgetWithText(FilledButton, '存入卡片库'), findsNothing);

    final cards2 = await tester.runAsync(() => service2.listCards());
    expect(cards2, hasLength(1));
  });

  testWidgets(
      'changed content requires confirmation and appends a version to same card',
      (tester) async {
    final responses = <String, _Canned>{
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'),
        200,
        'text/html',
      ),
    };
    final service = _service(repository, responses);
    await pump(tester, service);

    await fetch(tester, 'https://example.com/doc');
    await tester.tap(find.widgetWithText(FilledButton, '存入卡片库'));
    await settleFor(tester, find.text('已在卡片库'));
    final firstCard =
        (await tester.runAsync(() => service.listCards()))!.single;

    responses['https://example.com/doc'] = _Canned(
      _fixture('updated_content.html'),
      200,
      'text/html',
    );
    await fetch(tester, 'https://example.com/doc');

    expect(find.text('确认内容更新'), findsOneWidget);
    expect(find.textContaining('同一来源新增版本'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认内容更新'));
    await settleFor(tester, find.text('卡片已更新（内容有新版本）'));

    final cards = (await tester.runAsync(() => service.listCards()))!;
    final record = await tester.runAsync(
      () => service.getSource(firstCard.sourceId!),
    );
    expect(cards, hasLength(1));
    expect(cards.single.cardId, firstCard.cardId);
    expect(record!.versions, hasLength(2));
  });
}
