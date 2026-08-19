import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/video/video_domain.dart';
import 'package:memex/ui/whiteboard/video/session_store_io.dart';

VideoAnnotationSession _sampleSession() {
  final anchor = TimeRangeAnchorSpec.buildAnchor(
    anchorId: 'anchor_test_1',
    sourceId: 'src_video_test',
    sourceVersionId: 'ver_video_test_v1',
    spec: TimeRangeAnchorSpec.range(10000, 14000),
    quote: '第一段副歌',
  );
  final card = CardContract(
    cardId: 'card_test_1',
    cardKind: CardKind.annotation,
    sourceId: 'src_video_test',
    title: '副歌',
    body: '值得再看',
    tags: const ['video_annotation'],
    presentation: {'anchor_id': anchor.anchorId, 'start_ms': 10000},
    createdAt: DateTime.utc(2026, 8, 16),
  );
  return VideoAnnotationSession(
    sourceId: 'src_video_test',
    sourceVersionId: 'ver_video_test_v1',
    lastPositionMs: 12000,
    anchors: [anchor],
    annotationCards: [card],
    anchorToCard: {anchor.anchorId: card.cardId},
    dockOrientation: 'bottom',
    dockRatio: 0.28,
    savedAt: DateTime.utc(2026, 8, 16, 12),
  );
}

void main() {
  group('FileVideoSessionStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('w4_store_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('save → load round-trips the full session', () async {
      final store = FileVideoSessionStore(
        file: File('${tempDir.path}${Platform.pathSeparator}session.json'),
      );
      await store.save(_sampleSession());

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.sourceId, equals('src_video_test'));
      expect(loaded.sourceVersionId, equals('ver_video_test_v1'));
      expect(loaded.lastPositionMs, equals(12000));
      expect(loaded.anchors.length, equals(1));
      expect(loaded.anchors.first.positionSpec['start_ms'], equals(10000));
      expect(loaded.annotationCards.length, equals(1));
      expect(loaded.annotationCards.first.title, equals('副歌'));
      expect(loaded.anchorToCard['anchor_test_1'], equals('card_test_1'));
      expect(loaded.dockOrientation, 'bottom');
      expect(loaded.dockRatio, 0.28);
    });

    test('load with no file returns null', () async {
      final store = FileVideoSessionStore(
        file: File('${tempDir.path}${Platform.pathSeparator}missing.json'),
      );
      expect(await store.load(), isNull);
    });

    test('load with corrupted content returns null (never throws)', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}bad.json');
      await file.writeAsString('{not json');
      final store = FileVideoSessionStore(file: file);
      expect(await store.load(), isNull);
    });

    test('clear removes the persisted session', () async {
      final store = FileVideoSessionStore(
        file: File('${tempDir.path}${Platform.pathSeparator}session.json'),
      );
      await store.save(_sampleSession());
      expect(await store.load(), isNotNull);

      await store.clear();
      expect(await store.load(), isNull);
    });

    test('save replaces a previous session', () async {
      final store = FileVideoSessionStore(
        file: File('${tempDir.path}${Platform.pathSeparator}session.json'),
      );
      await store.save(_sampleSession());
      final replaced = VideoAnnotationSession(
        sourceId: 'src_video_test',
        sourceVersionId: 'ver_video_test_v2',
        lastPositionMs: 5000,
        anchors: const [],
        annotationCards: const [],
        anchorToCard: const {},
        savedAt: DateTime.utc(2026, 8, 16, 13),
      );
      await store.save(replaced);

      final loaded = await store.load();
      expect(loaded!.sourceVersionId, equals('ver_video_test_v2'));
      expect(loaded.lastPositionMs, equals(5000));
      expect(loaded.anchors, isEmpty);
    });

    test('serialized JSON is the VideoAnnotationSession schema', () async {
      final store = FileVideoSessionStore(
        file: File('${tempDir.path}${Platform.pathSeparator}session.json'),
      );
      await store.save(_sampleSession());
      final raw = await File(store.file.path).readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['source_id'], equals('src_video_test'));
      expect(json['last_position_ms'], equals(12000));
      expect(json['anchors'], isA<List<dynamic>>());
      expect(json['annotation_cards'], isA<List<dynamic>>());
      expect(json['anchor_to_card'], isA<Map<String, dynamic>>());
      expect(json['dock_orientation'], 'bottom');
      expect(json['dock_ratio'], 0.28);
    });
  });
}
