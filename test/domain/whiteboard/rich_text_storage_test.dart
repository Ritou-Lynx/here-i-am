import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';

void main() {
  late Directory tempDir;
  late RichTextStorage storage;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rich_text_test_');
    storage = RichTextStorage(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('RichTextStorage save and load', () {
    test('save then load round-trips', () async {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.heading, text: '标题', attrs: {'level': 1}),
        RichTextBlock(type: BlockType.paragraph, text: '正文内容'),
      ]);
      await storage.save('card_1', doc);
      final loaded = await storage.load('card_1');
      expect(loaded, isNotNull);
      expect(loaded!.blocks.length, equals(2));
      expect(loaded.blocks[0].text, equals('标题'));
      expect(loaded.blocks[1].text, equals('正文内容'));
    });

    test('load returns null when no file exists', () async {
      final loaded = await storage.load('nonexistent');
      expect(loaded, isNull);
    });

    test('exists returns true after save', () async {
      final doc = RichTextDocument.empty();
      await storage.save('card_2', doc);
      expect(storage.exists('card_2'), isTrue);
      expect(storage.exists('card_3'), isFalse);
    });

    test('restart recovery: save, dispose, new storage, load', () async {
      const doc = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: '持久化文字'),
        RichTextBlock(
          type: BlockType.paragraph,
          text: '带标记',
          marks: [RichTextMark(type: MarkType.bold, start: 0, end: 3)],
        ),
      ]);
      await storage.save('card_restart', doc);

      // Simulate restart: new storage instance pointing at same dir.
      final restarted = RichTextStorage(tempDir);
      final loaded = await restarted.load('card_restart');
      expect(loaded, isNotNull);
      expect(loaded!.blocks.length, equals(2));
      expect(loaded.blocks[1].marks.first.type, equals(MarkType.bold));
    });

    test('read completes an interrupted replacement from a valid temp',
        () async {
      const oldDocument = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: 'old body'),
      ]);
      const newDocument = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: 'new body'),
      ]);
      await storage.save('card_temp_recovery', oldDocument);
      final target = File(
        '${tempDir.path}${Platform.pathSeparator}card_card_temp_recovery'
        '${Platform.pathSeparator}rich_text.json',
      );
      await target.rename('${target.path}.bak');
      await File('${target.path}.tmp')
          .writeAsString(jsonEncode(newDocument.toJson()), flush: true);

      final loaded = await RichTextStorage(tempDir).load('card_temp_recovery');
      expect(loaded!.blocks.single.text, 'new body');
      expect(await File('${target.path}.tmp').exists(), isFalse);
      expect(await File('${target.path}.bak').exists(), isFalse);
    });

    test('read restores backup when an interrupted temp is corrupt', () async {
      const oldDocument = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: 'recover old body'),
      ]);
      await storage.save('card_backup_recovery', oldDocument);
      final target = File(
        '${tempDir.path}${Platform.pathSeparator}card_card_backup_recovery'
        '${Platform.pathSeparator}rich_text.json',
      );
      await target.rename('${target.path}.bak');
      await File('${target.path}.tmp').writeAsString('{broken', flush: true);

      final loaded =
          await RichTextStorage(tempDir).load('card_backup_recovery');
      expect(loaded!.blocks.single.text, 'recover old body');
      expect(await File('${target.path}.tmp').exists(), isFalse);
      expect(await File('${target.path}.bak').exists(), isFalse);
    });

    test('corrupt file degrades to empty document', () async {
      // Use the storage's own path layout: card_<id>/rich_text.json
      await storage.save('card_corrupt', RichTextDocument.empty());
      // Overwrite with corrupt content.
      final dir = Directory(
          '${tempDir.path}${Platform.pathSeparator}card_card_corrupt');
      File('${dir.path}${Platform.pathSeparator}rich_text.json')
          .writeAsStringSync('not valid json {{{');
      final loaded = await storage.load('card_corrupt');
      expect(loaded, isNotNull);
      expect(loaded!.blocks.length, equals(1));
      expect(loaded.blocks.first.text, isEmpty);
    });

    test('old schema v0 file migrates on load', () async {
      await storage.save('card_v0', RichTextDocument.empty());
      final dir =
          Directory('${tempDir.path}${Platform.pathSeparator}card_card_v0');
      File('${dir.path}${Platform.pathSeparator}rich_text.json')
          .writeAsStringSync(jsonEncode({
        'schema_version': 0,
        'body': '旧版本\n两行',
      }));
      final loaded = await storage.load('card_v0');
      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, equals(richTextSchemaVersion));
      expect(loaded.blocks.length, equals(2));
    });

    test('delete removes the file', () async {
      await storage.save('card_del', RichTextDocument.empty());
      expect(storage.exists('card_del'), isTrue);
      await storage.delete('card_del');
      expect(storage.exists('card_del'), isFalse);
    });

    test('legacy save/reopen/recoverAll/delete is isolated from lookalike id',
        () async {
      const legacyId = 'card:0123456789abcdef01234567:3';
      const normalId = 'legacy_runtime_0123456789abcdef01234567_3';
      const legacyOld = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: 'legacy old'),
      ]);
      const legacyRecovered = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: 'legacy recovered'),
      ]);
      const normalDocument = RichTextDocument(blocks: [
        RichTextBlock(type: BlockType.paragraph, text: 'normal document'),
      ]);
      await storage.save(legacyId, legacyOld);
      await storage.save(normalId, normalDocument);
      final mappedDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}'
        'legacy_runtime_cards${Platform.pathSeparator}'
        'card_0123456789abcdef01234567_3',
      );
      final normalDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}'
        'card_legacy_runtime_0123456789abcdef01234567_3',
      );
      expect(mappedDir.existsSync(), isTrue);
      expect(normalDir.existsSync(), isTrue);

      final reopened = RichTextStorage(tempDir);
      expect((await reopened.load(legacyId))!.toPlainText(), 'legacy old');
      expect((await reopened.load(normalId))!.toPlainText(), 'normal document');
      final target = File(
        '${mappedDir.path}${Platform.pathSeparator}rich_text.json',
      );
      await target.rename('${target.path}.bak');
      await File('${target.path}.tmp')
          .writeAsString(jsonEncode(legacyRecovered.toJson()), flush: true);

      await reopened.recoverAll();
      expect((await reopened.load(legacyId))!.toPlainText(), 'legacy recovered');
      expect(File('${target.path}.tmp').existsSync(), isFalse);
      expect(File('${target.path}.bak').existsSync(), isFalse);
      await reopened.delete(legacyId);
      expect(reopened.exists(legacyId), isFalse);
      expect(reopened.exists(normalId), isTrue);
      expect((await reopened.load(normalId))!.toPlainText(), 'normal document');
    });

    test('arbitrary unsafe ids remain rejected by the dedicated error', () {
      for (final cardId in const [
        'card:not-legacy:0',
        'card/escape',
        r'card\escape',
        'card..escape',
      ]) {
        expect(
          () => storage.exists(cardId),
          throwsA(isA<RichTextUnsafeCardIdError>()),
          reason: cardId,
        );
      }
    });

    test('sync load works', () {
      storage.saveSync(
          'card_sync',
          const RichTextDocument(blocks: [
            RichTextBlock(type: BlockType.paragraph, text: '同步'),
          ]));
      final loaded = storage.loadSync('card_sync');
      expect(loaded!.blocks.first.text, equals('同步'));
    });
  });
}
