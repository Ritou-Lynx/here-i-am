import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/whiteboard_contracts.dart';
import 'package:memex/domain/whiteboard/snapshot_integrity.dart';

/// Helper: loads a JSON fixture file from test/domain/whiteboard/fixtures/.
Map<String, dynamic> loadFixture(String filename) {
  final path = 'test/domain/whiteboard/fixtures/$filename';
  final raw = File(path).readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('WhiteboardSnapshot serialization round-trip', () {
    test('normal_snapshot.json parses and serializes back identically', () {
      final raw = loadFixture('normal_snapshot.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);
      final reSerialized = snapshot.toJson();

      // schema_version preserved
      expect(reSerialized['schema_version'], equals(1));

      // counts preserved
      expect(snapshot.sources.length, equals(3));
      expect(snapshot.sourceVersions.length, equals(4));
      expect(snapshot.cards.length, equals(5));
      expect(snapshot.boards.length, equals(2));
      expect(snapshot.boardItems.length, equals(5));
      expect(snapshot.groups.length, equals(1));
      expect(snapshot.groupMembers.length, equals(2));
      expect(snapshot.edges.length, equals(1));

      // re-parsing the serialized output gives the same snapshot
      final snapshot2 = WhiteboardSnapshot.fromJson(reSerialized);
      expect(snapshot2.cards.length, equals(snapshot.cards.length));
      expect(snapshot2.boards.length, equals(snapshot.boards.length));
      expect(snapshot2.boardItems.length, equals(snapshot.boardItems.length));
    });

    test('empty_snapshot.json parses correctly', () {
      final raw = loadFixture('empty_snapshot.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);

      expect(snapshot.cards, isEmpty);
      expect(snapshot.boardItems, isEmpty);
      expect(snapshot.boards.length, equals(1));
      expect(snapshot.sources, isEmpty);
    });

    test('orphaned_anchor_snapshot.json parses with two annotations on same source', () {
      final raw = loadFixture('orphaned_anchor_snapshot.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);

      expect(snapshot.cards.length, equals(2));
      // Both annotations reference the same source
      final annotations = snapshot.cards
          .where((c) => c.cardKind == CardKind.annotation)
          .toList();
      expect(annotations.length, equals(2));
      expect(annotations[0].sourceId, equals(annotations[1].sourceId));
      // Different ownership
      expect(annotations[0].ownerSpace, equals(OwnerSpace.user));
      expect(annotations[1].ownerSpace, equals(OwnerSpace.i));
    });
  });

  group('ID referential integrity', () {
    test('normal_snapshot.json passes integrity validation', () {
      final raw = loadFixture('normal_snapshot.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);
      final result = validateSnapshotIntegrity(snapshot);

      expect(result.isValid, isTrue,
          reason: result.errors.join('\n'));
    });

    test('empty_snapshot.json passes integrity validation', () {
      final raw = loadFixture('empty_snapshot.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);
      final result = validateSnapshotIntegrity(snapshot);

      expect(result.isValid, isTrue,
          reason: result.errors.join('\n'));
    });

    test('invalid_dangling_refs.json fails integrity validation with expected errors', () {
      final raw = loadFixture('invalid_dangling_refs.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);
      final result = validateSnapshotIntegrity(snapshot);

      expect(result.isValid, isFalse);
      // Empty source ID
      expect(result.errors.any((e) => e.contains('empty source_id')), isTrue);
      // BoardItem referencing non-existent board
      expect(
          result.errors.any((e) => e.contains('board_nonexistent')), isTrue);
      // BoardItem referencing non-existent card
      expect(
          result.errors
              .any((e) => e.contains('card_nonexistent') && e.contains('BoardItem')),
          isTrue);
      // Card referencing non-existent source
      expect(
          result.errors.any((e) => e.contains('src_nonexistent')), isTrue);
      // Group referencing non-existent board
      expect(
          result.errors.any((e) => e.contains('group_dangling')), isTrue);
      // GroupMember referencing non-existent item
      expect(
          result.errors.any((e) => e.contains('item_nonexistent')), isTrue);
      // Edge referencing non-existent from_item
      expect(
          result.errors
              .any((e) => e.contains('from_item_id') && e.contains('item_nonexistent')),
          isTrue);
    });
  });

  group('Delete semantics — BoardItem deletion does not affect Card/Source', () {
    test('removing a BoardItem keeps the Card and Source intact', () {
      final raw = loadFixture('normal_snapshot.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);

      // card_book_zhishen appears on two boards
      final bookItems = snapshot.boardItems
          .where((i) => i.cardId == 'card_book_zhishen')
          .toList();
      expect(bookItems.length, equals(2),
          reason: 'card_book_zhishen should be on both boards');

      // Simulate deleting one BoardItem
      final remainingItems = snapshot.boardItems
          .where((i) => i.itemId != 'item_book_stage')
          .toList();
      final remainingCards =
          snapshot.cards.where((c) => c.cardId == 'card_book_zhishen').toList();
      final remainingSources = snapshot.sources
          .where((s) => s.sourceId == 'src_book_zhishen')
          .toList();

      expect(remainingItems.length, equals(snapshot.boardItems.length - 1));
      expect(remainingCards.length, equals(1),
          reason: 'Card must survive BoardItem deletion');
      expect(remainingSources.length, equals(1),
          reason: 'Source must survive BoardItem deletion');

      // The other board's item still references the card
      expect(
          remainingItems.any((i) => i.cardId == 'card_book_zhishen'), isTrue,
          reason: 'The other BoardItem still references the card');
    });

    test('same Card can appear multiple times on same board', () {
      final raw = loadFixture('normal_snapshot.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);

      final mvpItems = snapshot.boardItems
          .where((i) => i.boardId == 'board_whiteboard_mvp')
          .toList();

      // The MVP board has 3 items referencing 3 distinct cards
      final cardIds = mvpItems.map((i) => i.cardId).toSet();
      expect(cardIds.length, equals(3));
    });
  });

  group('Backward compatibility — old schema migration', () {
    test('old_schema_v0.json migrates to current schema', () {
      final raw = loadFixture('old_schema_v0.json');
      expect(raw['schema_version'], equals(0));

      final snapshot = loadSnapshot(raw);

      expect(snapshot.schemaVersion, equals(whiteboardSnapshotSchemaVersion));
      expect(snapshot.cards.length, equals(2));
      expect(snapshot.boards.length, equals(1));
      expect(snapshot.boardItems.length, equals(1));

      // camelCase → snake_case field names
      final card = snapshot.cards.first;
      expect(card.cardId, equals('card_book_zhishen'));
      expect(card.cardKind, equals(CardKind.source));

      final item = snapshot.boardItems.first;
      expect(item.itemId, equals('item_spine'));
      expect(item.boardId, equals('board_whiteboard_mvp'));
      expect(item.cardId, equals('card_note_spine'));
      expect(item.zIndex, equals(1));

      // migrated snapshot passes integrity
      final result = validateSnapshotIntegrity(snapshot);
      expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    });

    test('migrated snapshot serializes to current schema_version', () {
      final raw = loadFixture('old_schema_v0.json');
      final snapshot = loadSnapshot(raw);
      final json = snapshot.toJson();

      expect(json['schema_version'], equals(whiteboardSnapshotSchemaVersion));
    });
  });

  group('StableId validation', () {
    test('StableId rejects empty strings', () {
      expect(() => StableId(''), throwsArgumentError);
      expect(() => StableId(null), throwsArgumentError);
      expect(() => StableId(123), throwsArgumentError);
    });

    test('StableId generates non-empty IDs', () {
      final id = StableId.generate('card');
      expect(id.value, isNotEmpty);
      expect(id.value, startsWith('card_'));
    });

    test('tryStableId returns null for invalid values', () {
      expect(tryStableId(null), isNull);
      expect(tryStableId(''), isNull);
      expect(tryStableId(123), isNull);
      expect(tryStableId('valid_id'), equals('valid_id'));
    });
  });

  group('AnchorContract', () {
    test('anchor binds to source_id + source_version_id', () {
      final anchor = AnchorContract(
        anchorId: 'anchor_test_1',
        sourceId: 'src_book_zhishen',
        sourceVersionId: 'ver_book_zhishen_v2',
        positionKind: PositionKind.textRange,
        positionSpec: {
          'chapter_id': 'ch3',
          'start': 1024,
          'end': 1096,
        },
        quote: '土地出让金',
        createdAt: DateTime.utc(2026, 8, 14),
      );

      final json = anchor.toJson();
      expect(json['source_id'], equals('src_book_zhishen'));
      expect(json['source_version_id'], equals('ver_book_zhishen_v2'));
      expect(json['position_kind'], equals('text_range'));
      expect(json['status'], equals('exact'));

      final restored = AnchorContract.fromJson(json);
      expect(restored.sourceId, equals(anchor.sourceId));
      expect(restored.sourceVersionId, equals(anchor.sourceVersionId));
      expect(restored.positionKind, equals(PositionKind.textRange));
      expect(restored.status, equals(AnchorStatus.exact));
    });

    test('anchor with orphaned status serializes correctly', () {
      final anchor = AnchorContract(
        anchorId: 'anchor_orphan',
        sourceId: 'src_book_zhishen',
        sourceVersionId: 'ver_book_zhishen_v1',
        positionKind: PositionKind.textRange,
        status: AnchorStatus.orphaned,
        createdAt: DateTime.utc(2026, 8, 14),
      );
      final json = anchor.toJson();
      expect(json['status'], equals('orphaned'));
      final restored = AnchorContract.fromJson(json);
      expect(restored.status, equals(AnchorStatus.orphaned));
    });
  });

  group('IngestionResult', () {
    test('serializes and deserializes with all fields', () {
      final result = IngestionResult(
        canonicalUrl: 'https://www.bilibili.com/video/BV1xx411c7mD',
        provider: 'bilibili',
        originalUrl: 'https://b23.tv/abc',
        status: IngestionStatus.ok,
        hasMedia: true,
        hasTranscript: true,
        videoCapability: VideoCapabilityLevel.playbackStudy,
        resolvedAt: DateTime.utc(2026, 8, 14),
      );
      final json = result.toJson();
      final restored = IngestionResult.fromJson(json);

      expect(restored.canonicalUrl, equals(result.canonicalUrl));
      expect(restored.provider, equals('bilibili'));
      expect(restored.hasMedia, isTrue);
      expect(restored.hasTranscript, isTrue);
      expect(restored.videoCapability,
          equals(VideoCapabilityLevel.playbackStudy));
    });

    test('failed ingestion preserves canonical URL and error', () {
      final result = IngestionResult(
        canonicalUrl: 'https://example.com/failed',
        status: IngestionStatus.failed,
        errorMessage: 'SSRF blocked',
        resolvedAt: DateTime.utc(2026, 8, 14),
      );
      final json = result.toJson();
      final restored = IngestionResult.fromJson(json);

      expect(restored.status, equals(IngestionStatus.failed));
      expect(restored.canonicalUrl, isNotEmpty);
      expect(restored.errorMessage, equals('SSRF blocked'));
    });
  });

  group('RichTextDocument', () {
    test('minimal document serializes and round-trips', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(
          type: BlockType.paragraph,
          text: 'Hello 世界',
          marks: [
            RichTextMark(type: MarkType.bold, start: 0, end: 5),
          ],
        ),
      ]);
      final json = doc.toJson();
      final restored = RichTextDocument.fromJson(json);

      expect(restored.schemaVersion, equals(richTextSchemaVersion));
      expect(restored.blocks.length, equals(1));
      expect(restored.blocks.first.text, equals('Hello 世界'));
      expect(restored.blocks.first.marks.first.type, equals(MarkType.bold));
    });

    test('plain text projection', () {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '第一段'),
        RichTextBlock(type: BlockType.paragraph, text: '第二段'),
      ]);
      expect(doc.toPlainText(), equals('第一段\n第二段'));
    });

    test('empty document serializes to minimal JSON', () {
      const doc = RichTextDocument();
      final json = doc.toJson();
      expect(json['schema_version'], equals(richTextSchemaVersion));
      expect(json.containsKey('blocks'), isFalse);
    });
  });

  group('TimedTextTrack', () {
    test('serializes with cues and source kind', () {
      const track = TimedTextTrack(
        trackId: 'track_plave_zh',
        sourceId: 'src_video_plave',
        sourceVersionId: 'ver_video_plave_v1',
        sourceKind: TimedTextSourceKind.platform,
        language: 'zh',
        reliability: TimedTextReliability.reliable,
        cues: [
          TimedTextCue(
            cueId: 'cue_1',
            startMs: 142000,
            endMs: 146000,
            text: '灯光切换',
          ),
        ],
      );
      final json = track.toJson();
      final restored = TimedTextTrack.fromJson(json);

      expect(restored.trackId, equals('track_plave_zh'));
      expect(restored.sourceKind, equals(TimedTextSourceKind.platform));
      expect(restored.cues.length, equals(1));
      expect(restored.cues.first.startMs, equals(142000));
      expect(restored.cues.first.text, equals('灯光切换'));
    });

    test('unavailable reliability serializes correctly', () {
      const track = TimedTextTrack(
        trackId: 'track_unavailable',
        sourceId: 'src_video_no_sub',
        reliability: TimedTextReliability.unavailable,
      );
      final json = track.toJson();
      final restored = TimedTextTrack.fromJson(json);
      expect(restored.reliability, equals(TimedTextReliability.unavailable));
    });
  });

  group('PlayerCapability', () {
    test('isPlaybackStudyCapable is true only when all capabilities present', () {
      const partial = PlayerCapability(
        canSeek: true,
        canReadDuration: true,
        canReadPosition: true,
        hasTranscript: false,
      );
      expect(partial.isPlaybackStudyCapable, isFalse);

      const full = PlayerCapability(
        canSeek: true,
        canReadDuration: true,
        canReadPosition: true,
        hasTranscript: true,
        canEmbedPlayer: true,
        canReverseHighlight: true,
        canCreateTimeAnchor: true,
      );
      expect(full.isPlaybackStudyCapable, isTrue);
    });
  });

  group('WhiteboardOperation', () {
    test('serializes and deserializes with authorization', () {
      final op = WhiteboardOperation(
        operationId: 'op_1',
        boardId: 'board_test',
        actor: OperationActor.i,
        operationKind: OperationKind.place,
        targetIds: ['item_1', 'item_2'],
        payload: {'x': 100, 'y': 200},
        authorizationId: 'auth_session_1',
        createdAt: DateTime.utc(2026, 8, 14),
      );
      final json = op.toJson();
      final restored = WhiteboardOperation.fromJson(json);

      expect(restored.actor, equals(OperationActor.i));
      expect(restored.operationKind, equals(OperationKind.place));
      expect(restored.targetIds, equals(['item_1', 'item_2']));
      expect(restored.authorizationId, equals('auth_session_1'));
    });

    test('undo operation references original operation', () {
      final op = WhiteboardOperation(
        operationId: 'op_2',
        boardId: 'board_test',
        operationKind: OperationKind.undo,
        undoOf: 'op_1',
        createdAt: DateTime.utc(2026, 8, 14),
      );
      final json = op.toJson();
      final restored = WhiteboardOperation.fromJson(json);

      expect(restored.operationKind, equals(OperationKind.undo));
      expect(restored.undoOf, equals('op_1'));
    });
  });

  group('Cross-entity snapshot integrity', () {
    test('snapshot with valid cross-board card reference passes integrity', () {
      final raw = loadFixture('normal_snapshot.json');
      final snapshot = WhiteboardSnapshot.fromJson(raw);
      final result = validateSnapshotIntegrity(snapshot);

      // card_book_zhishen appears on both boards — this is valid
      expect(result.isValid, isTrue);
    });
  });
}