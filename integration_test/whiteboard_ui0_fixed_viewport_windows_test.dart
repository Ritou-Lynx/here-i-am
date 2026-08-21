/// UI-0 fixed-viewport visual acceptance in a real Windows runner window.
///
/// The test resizes the native Win32 window instead of overriding
/// `tester.view`, mounts the production route table against a real temporary
/// Drift database, and writes Flutter-surface screenshots to
/// `build/m5b2_screenshots/` for human review.
///
/// Run:
///   flutter test integration_test/whiteboard_ui0_fixed_viewport_windows_test.dart -d windows
library;

import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/whiteboard/thumbnail/safe_thumbnail_resolver.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/desktop/desktop_workbench_shell.dart';
import 'package:memex/ui/desktop/view_models/desktop_home_view_model.dart';
import 'package:memex/ui/desktop/widgets/global_desktop_chat_overlay.dart';
import 'package:memex/ui/whiteboard/card_rich_text_editor_screen.dart';
import 'package:memex/ui/whiteboard/link_import_screen.dart';
import 'package:memex/ui/whiteboard/whiteboard_index_screen.dart';
import 'package:memex/utils/user_storage.dart';

typedef _GetWindowNative = IntPtr Function();
typedef _GetWindowDart = int Function();
typedef _SetWindowPosNative = Int32 Function(
  IntPtr window,
  IntPtr insertAfter,
  Int32 x,
  Int32 y,
  Int32 width,
  Int32 height,
  Uint32 flags,
);
typedef _SetWindowPosDart = int Function(
  int window,
  int insertAfter,
  int x,
  int y,
  int width,
  int height,
  int flags,
);

const _viewports = <Size>[
  Size(1440, 900),
  Size(1280, 720),
  Size(1024, 768),
];
int _flutterViewHandle = 0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Windows window renders all UI-0 surfaces at three fixed viewports',
    (tester) async {
      expect(Platform.isWindows, isTrue,
          reason: 'This visual acceptance is Windows-only.');
      SharedPreferences.setMockInitialValues({'language': 'zh'});
      AppFlavor.init('hereIAmV3');
      await UserStorage.initL10n();

      final root = await Directory.systemTemp.createTemp('ui0_m5b2_');
      const userId = 'm5b2_visual_user';
      await UserStorage.saveUser(userId);
      await FileSystemService.init(root.path);
      final primaryCharacter =
          await CharacterService.instance.getPrimaryCompanion(userId);
      expect(primaryCharacter, isNotNull);
      expect(primaryCharacter!.id, 'i');
      final dbFile =
          File('${root.path}${Platform.pathSeparator}whiteboard.sqlite');
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      final repository = UnifiedCardRepository(
        db: db,
        whiteboardRoot: root,
        thumbnailResolver: SafeThumbnailResolver(whiteboardRoot: root),
      );
      final store = WhiteboardDriftStore(db);
      AppDatabase.setTestInstance(db);
      WhiteboardDataBootstrap.setRepositoryForTesting(repository);
      CardRichTextEditorScreen.setRepositoryForTesting(repository);
      GlobalDesktopChatOverlayController.instance.reset();

      late final GoRouter router;
      final screenshot = ScreenshotController();
      final output = Directory(
        '${Directory.current.path}${Platform.pathSeparator}build'
        '${Platform.pathSeparator}m5b2_screenshots',
      );
      if (output.existsSync()) output.deleteSync(recursive: true);
      output.createSync(recursive: true);

      addTearDown(() async {
        GlobalDesktopChatOverlayController.instance.reset();
        CardRichTextEditorScreen.setRepositoryForTesting(null);
        WhiteboardDataBootstrap.setRepositoryForTesting(null);
        router.dispose();
        await db.close();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      final fixture = await _seedFixture(store, repository);
      router = createAppRouter(
        GlobalKey<NavigatorState>(),
        () => DesktopWorkbenchShell(
          characterId: 'i',
          viewModel: DesktopHomeViewModel(
            db: db,
            cardRepository: repository,
          ),
        ),
      );

      await tester.pumpWidget(
        Screenshot(
          controller: screenshot,
          child: MaterialApp.router(
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => Stack(
              children: [
                Positioned.fill(child: child ?? const SizedBox.shrink()),
                Positioned.fill(
                  child: Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => GlobalDesktopChatOverlay(
                          characterIdResolver: () async => primaryCharacter.id,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      for (final viewport in _viewports) {
        await _resizeNativeWindow(tester, viewport);
        final label = '${viewport.width.toInt()}x${viewport.height.toInt()}';

        await _routeAndCapture(
          tester: tester,
          router: router,
          screenshot: screenshot,
          output: output,
          location: AppRoutes.home,
          ready: find.byKey(const ValueKey('workbench_module_grid')),
          name: '${label}_01_home',
        );
        expect(find.byKey(const ValueKey('desktop_floating_ball')),
            findsOneWidget);

        await _routeAndCapture(
          tester: tester,
          router: router,
          screenshot: screenshot,
          output: output,
          location: AppRoutes.whiteboard,
          ready: find.byType(WhiteboardIndexScreen),
          name: '${label}_02_whiteboard_index',
        );

        await _routeAndCapture(
          tester: tester,
          router: router,
          screenshot: screenshot,
          output: output,
          location: AppRoutes.cardLibrary,
          ready: find.byKey(
            const ValueKey('card-library-thumbnail-m5b2_source_card'),
          ),
          name: '${label}_03_card_library',
        );

        await _routeAndCapture(
          tester: tester,
          router: router,
          screenshot: screenshot,
          output: output,
          location: AppRoutes.cardEditPath(fixture.editorCardId),
          ready: find.byType(CardRichTextEditorScreen),
          name: '${label}_04_rich_text_editor',
        );

        await _routeAndCapture(
          tester: tester,
          router: router,
          screenshot: screenshot,
          output: output,
          location: AppRoutes.linkImport,
          ready: find.byType(LinkImportScreen),
          name: '${label}_05_link_import',
        );

        await _routeAndCapture(
          tester: tester,
          router: router,
          screenshot: screenshot,
          output: output,
          location: AppRoutes.whiteboardCanvasPath(fixture.boardId),
          ready: find.byKey(const ValueKey('wb_canvas_chrome_launcher')),
          name: '${label}_06_canvas_retreat',
        );
        expect(find.byKey(const ValueKey('wb_navigation_group')), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('wb_canvas_chrome_launcher')),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(
            find.byKey(const ValueKey('wb_navigation_group')), findsOneWidget);
        await _capture(
          screenshot,
          output,
          '${label}_07_canvas_navigation',
        );

        await _routeAndCapture(
          tester: tester,
          router: router,
          screenshot: screenshot,
          output: output,
          location: AppRoutes.sourceStudyPath(fixture.sourceId),
          ready: find.byKey(const ValueKey('source_reading_column')),
          name: '${label}_08_source_study',
        );

        expect(tester.takeException(), isNull, reason: 'viewport $viewport');
      }

      router.go(AppRoutes.home);
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('workbench_module_grid')),
        'home before Lin Ai overlay acceptance',
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop_floating_ball')),
      );
      await _pumpUntilPresent(
        tester,
        find.byKey(const ValueKey('desktop_chat_panel')),
        'Lin Ai desktop chat panel',
      );
      await _pumpUntilPresent(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('desktop_chat_panel')),
          matching: find.byType(TextField),
        ),
        'Lin Ai production composer',
      );
      for (final viewport in _viewports) {
        await _resizeNativeWindow(tester, viewport);
        final label = '${viewport.width.toInt()}x${viewport.height.toInt()}';
        await _capture(
          screenshot,
          output,
          '${label}_01b_home_chat',
        );
      }

      final screenshots = output
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'))
          .toList();
      expect(screenshots, hasLength(_viewports.length * 9));
      for (final file in screenshots) {
        expect(file.lengthSync(), greaterThan(10000), reason: file.path);
      }
      debugPrint('M5B2_SCREENSHOTS=${output.path}');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<_Fixture> _seedFixture(
  WhiteboardDriftStore store,
  UnifiedCardRepository repository,
) async {
  final boardId = await store.createBoard(name: '跨设备研究白板');
  await store.createBoard(name: '八月阅读线索');
  await store.createBoard(name: '产品决策地图');

  final cards = [
    await repository.createTextCard(
      cardId: 'm5b2_note_primary',
      title: '白板迁移验收笔记',
      body: '核对白板、卡片、来源与林埃入口是否共享同一份真实数据。',
      tags: const ['UI-0', '验收'],
    ),
    await repository.createTextCard(
      cardId: 'm5b2_note_second',
      title: '桌面布局观察',
      body: '紧凑窗口仍应保留层级、动作入口与诚实的缺失状态。',
      tags: const ['桌面', '布局'],
    ),
    await repository.createTextCard(
      cardId: 'm5b2_note_third',
      title: '后续复验清单',
      body: '真人中文输入法、来源返回位置、画布工具完整退场。',
      tags: const ['复验'],
    ),
  ];

  final now = DateTime.utc(2026, 8, 21, 10);
  await store.save(
    boardId,
    WhiteboardSnapshot(
      boards: [Board(boardId: boardId, name: '跨设备研究白板', createdAt: now)],
      boardItems: [
        BoardItem(
          itemId: 'm5b2_item_primary',
          boardId: boardId,
          cardId: cards[0].cardId,
          x: -250,
          y: -90,
          width: 220,
          height: 150,
        ),
        BoardItem(
          itemId: 'm5b2_item_second',
          boardId: boardId,
          cardId: cards[1].cardId,
          x: 30,
          y: -20,
          width: 220,
          height: 150,
        ),
      ],
    ),
  );

  const sourceId = 'm5b2_source_article';
  const versionId = 'm5b2_source_article_v1';
  const thumbnailCandidate = 'https://example.com/ui0-cover.png';
  final thumbnail = img.Image(width: 480, height: 320);
  img.fill(thumbnail, color: img.ColorRgb8(206, 211, 180));
  img.fillRect(
    thumbnail,
    x1: 34,
    y1: 38,
    x2: 446,
    y2: 124,
    color: img.ColorRgb8(67, 89, 59),
  );
  img.fillRect(
    thumbnail,
    x1: 34,
    y1: 156,
    x2: 300,
    y2: 282,
    color: img.ColorRgb8(176, 150, 112),
  );
  final thumbnailBytes = img.encodePng(thumbnail);
  final thumbnailHash = sha256.convert(thumbnailBytes).toString();
  final thumbnailCandidateHash =
      sha256.convert(thumbnailCandidate.codeUnits).toString();
  final thumbnailRef = 'objects/thumbnails/$thumbnailHash.png';
  final thumbnailDirectory = Directory(
    '${repository.whiteboardRoot.path}${Platform.pathSeparator}objects'
    '${Platform.pathSeparator}thumbnails',
  );
  await thumbnailDirectory.create(recursive: true);
  await File(
    '${thumbnailDirectory.path}${Platform.pathSeparator}$thumbnailHash.png',
  ).writeAsBytes(thumbnailBytes, flush: true);
  final source = SourceContent(
    sourceId: sourceId,
    mediaType: SourceMediaType.web,
    title: '从真实来源进入沉浸研读',
    origin: SourceOrigin.externalLink,
    provider: 'example.com',
    canonicalId: 'https://example.com/ui0',
    currentVersionId: versionId,
    contentHash: 'm5b2-source-hash',
    objectRef: 'objects/sources/$sourceId/$versionId.json',
    metadata: const {
      'canonical_url': 'https://example.com/ui0',
      'site_name': 'Example Research',
      'author': 'Here I am',
      'description': '用于 UI-0 实窗验收的真实 Repository 记录。',
      'og_image': thumbnailCandidate,
    },
    createdAt: now,
    updatedAt: now,
  );
  final version = SourceVersion(
    versionId: versionId,
    sourceId: sourceId,
    contentHash: 'm5b2-source-hash',
    objectRef: source.objectRef!,
    parserVersion: 'm5b2-fixture-v1',
    createdAt: now,
  );
  await repository.importLegacyIngestion(
    source: source,
    versions: [version],
    card: CardContract(
      cardId: 'm5b2_source_card',
      cardKind: CardKind.source,
      sourceId: sourceId,
      title: source.title,
      body: '来源正文投影来自统一卡片仓库；对象缺失时必须诚实降级，并保留完整来源身份。',
      presentation: {
        'thumbnail': thumbnailCandidate,
        'thumbnail_ref': thumbnailRef,
        'thumbnail_version_id': versionId,
        'thumbnail_candidate_hash': thumbnailCandidateHash,
      },
      createdAt: now,
      updatedAt: now,
    ),
  );

  return _Fixture(
    boardId: boardId,
    editorCardId: cards.first.cardId,
    sourceId: sourceId,
  );
}

Future<void> _routeAndCapture({
  required WidgetTester tester,
  required GoRouter router,
  required ScreenshotController screenshot,
  required Directory output,
  required String location,
  required Finder ready,
  required String name,
}) async {
  router.go(location);
  await _pumpUntil(tester, ready, name);
  await _capture(screenshot, output, name);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder,
  String description,
) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
      return;
    }
  }
  fail('Timed out waiting for $description');
}

Future<void> _pumpUntilPresent(
  WidgetTester tester,
  Finder finder,
  String description,
) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 250));
      return;
    }
  }
  fail('Timed out waiting for $description');
}

Future<void> _capture(
  ScreenshotController controller,
  Directory output,
  String name,
) async {
  final bytes = await controller.capture(
    delay: Duration.zero,
    pixelRatio: 1,
  );
  expect(bytes, isNotNull, reason: 'capture $name');
  await File(
    '${output.path}${Platform.pathSeparator}$name.png',
  ).writeAsBytes(bytes!, flush: true);
}

Future<void> _resizeNativeWindow(WidgetTester tester, Size target) async {
  final user32 = DynamicLibrary.open('user32.dll');
  final getFocus =
      user32.lookupFunction<_GetWindowNative, _GetWindowDart>('GetFocus');
  final setWindowPos = user32
      .lookupFunction<_SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');
  final focusedView = getFocus();
  if (focusedView != 0) _flutterViewHandle = focusedView;
  final flutterView = _flutterViewHandle;
  expect(flutterView, isNot(0), reason: 'native Flutter child-window handle');

  final pixelRatio = tester.view.devicePixelRatio;
  final physicalWidth = (target.width * pixelRatio).round();
  final physicalHeight = (target.height * pixelRatio).round();
  const flags = 0x0004 | 0x0040; // SWP_NOZORDER | SWP_SHOWWINDOW
  final resized = setWindowPos(
    flutterView,
    0,
    0,
    0,
    physicalWidth,
    physicalHeight,
    flags,
  );
  expect(resized, isNot(0), reason: 'SetWindowPos($target)');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final actual = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(actual.width, closeTo(target.width, 0.5), reason: 'logical width');
  expect(actual.height, closeTo(target.height, 0.5), reason: 'logical height');
  debugPrint(
    'M5B2_VIEWPORT target=${target.width}x${target.height} '
    'actual=${actual.width}x${actual.height} dpr=$pixelRatio',
  );
}

class _Fixture {
  const _Fixture({
    required this.boardId,
    required this.editorCardId,
    required this.sourceId,
  });

  final String boardId;
  final String editorCardId;
  final String sourceId;
}
