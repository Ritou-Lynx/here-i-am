import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/ingestion/ingestion_store.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestion_service.dart';
import 'package:memex/data/whiteboard/ingestion/link_ingestor.dart';
import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
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
  ))..httpClientAdapter = _FakeAdapter(responses);
}

LinkIngestionService _service(Directory dir, Map<String, _Canned> responses) {
  return LinkIngestionService(
    store: IngestionStore(dir),
    ingestor: LinkIngestor(
      httpClient: SafeHttpClient(
        dio: _dio(responses),
        config: const SafeHttpConfig(enforceDnsCheck: false),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('w3_ui_');
  });

  tearDown(() async {
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
    await settleFor(tester, find.widgetWithText(FilledButton, '抓取'));
  }

  Future<void> fetch(WidgetTester tester, String url) async {
    await tester.enterText(find.byType(TextField), url);
    await tester.tap(find.widgetWithText(FilledButton, '抓取'));
    await settleFor(tester, find.text('抓取成功'));
    await tester.pumpAndSettle();
  }

  testWidgets('initial state: input + empty recent list hint', (tester) async {
    await pump(tester, _service(tempDir, {}));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '抓取'), findsOneWidget);
    expect(find.textContaining('还没有导入记录'), findsOneWidget);
  });

  testWidgets('empty input shows inline error', (tester) async {
    await pump(tester, _service(tempDir, {}));

    await tester.tap(find.widgetWithText(FilledButton, '抓取'));
    await tester.pumpAndSettle();

    expect(find.text('请输入要导入的链接'), findsOneWidget);
  });

  testWidgets('ok flow: fetch → preview → explicit card creation',
      (tester) async {
    final service = _service(tempDir, {
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'), 200, 'text/html; charset=utf-8',
      ),
    });
    await pump(tester, service);

    await fetch(tester, 'https://example.com/doc');

    // Success state with preview content.
    expect(find.text('抓取成功'), findsOneWidget);
    expect(find.text('春雨昼眠主题设计文档'), findsOneWidget);
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

  testWidgets('failed state shown honestly with error message',
      (tester) async {
    await pump(tester, _service(tempDir, {}));

    await tester.enterText(find.byType(TextField), 'https://example.com/missing');
    await tester.tap(find.widgetWithText(FilledButton, '抓取'));
    await settleFor(tester, find.text('抓取失败'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Network error'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '存入卡片库'), findsNothing);
  });

  testWidgets('needsAuth state shown honestly', (tester) async {
    final service = _service(tempDir, {
      'https://example.com/auth': _Canned('', 403, 'text/html'),
    });
    await pump(tester, service);

    await tester.enterText(find.byType(TextField), 'https://example.com/auth');
    await tester.tap(find.widgetWithText(FilledButton, '抓取'));
    await settleFor(tester, find.text('需要登录或已被拒绝'));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 403'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '存入卡片库'), findsNothing);
  });

  testWidgets('unsupported state shown honestly (video platform)',
      (tester) async {
    await pump(tester, _service(tempDir, {}));

    await tester.enterText(
      find.byType(TextField),
      'https://www.bilibili.com/video/BV1xx411c7mD',
    );
    await tester.tap(find.widgetWithText(FilledButton, '抓取'));
    await settleFor(tester, find.text('暂不支持此链接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('研读模块'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '存入卡片库'), findsNothing);
  });

  testWidgets('restart recovery: fresh service on same dir shows recent '
      'imports; re-import is idempotent', (tester) async {
    final responses = {
      'https://example.com/doc': _Canned(
        _fixture('open_graph.html'), 200, 'text/html',
      ),
    };

    // Session 1: create the card.
    final service1 = _service(tempDir, responses);
    await pump(tester, service1);
    await fetch(tester, 'https://example.com/doc');
    await tester.tap(find.widgetWithText(FilledButton, '存入卡片库'));
    await settleFor(tester, find.text('已在卡片库'));
    await tester.pumpAndSettle();
    final cards1 = await tester.runAsync(() => service1.listCards());
    expect(cards1, hasLength(1));

    // Session 2: a brand-new service + store instance on the SAME directory
    // — the recent list is recovered from disk.
    final service2 = _service(tempDir, responses);
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
}
