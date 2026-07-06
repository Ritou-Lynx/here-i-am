import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late RecordOrganizerServiceV3 service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = RecordOrganizerServiceV3(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('persists every input media as a display block with saved paths',
      () async {
    const firstAssetId = 'asset-one';
    const secondAssetId = 'asset-two';
    const firstPath = 'workspace/_tester/Facts/assets/img_one.webp';
    const secondPath = 'workspace/_tester/Facts/assets/img_two.webp';
    final now = DateTime(2026, 7, 6, 10).millisecondsSinceEpoch;

    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: firstAssetId,
            assetType: 'image',
            storagePath: const Value(firstPath),
            createdAt: now,
          ),
        );
    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: secondAssetId,
            assetType: 'image',
            storagePath: const Value(secondPath),
            createdAt: now,
          ),
        );

    await service.persist(
      organized: OrganizedRecord(cards: [
        OrganizedCard(
          type: 'event',
          title: '两张图',
          dropletLabel: '图片',
          presentationModule: {
            'blocks': [
              {'kind': 'media', 'assetPath': firstAssetId},
              {'kind': 'text', 'text': '记录两张图片'},
              {'kind': 'media', 'assetPath': 'bad-placeholder-path'},
            ],
          },
          retrievalText: '记录两张图片',
          valence: 0,
          arousal: 0.2,
        ),
      ]),
      source: RecordSource(
        sourceKind: 'record_button',
        rawInput: '记录两张图片',
      ),
      inputMedia: const [
        {
          'assetId': firstAssetId,
          'kind': 'image',
          'path': firstPath,
        },
        {
          'assetId': secondAssetId,
          'kind': 'image',
          'path': secondPath,
        },
      ],
    );

    final card = (await db.select(db.memoryCards).get()).single;
    final presentation =
        jsonDecode(card.presentationModule) as Map<String, dynamic>;
    final blocks = presentation['blocks'] as List<dynamic>;
    final mediaBlocks = blocks
        .whereType<Map>()
        .where((block) => block['type'] == 'media')
        .toList();

    expect(mediaBlocks, hasLength(2));
    expect(mediaBlocks.map((block) => block['assetPath']),
        [firstPath, secondPath]);
    expect(blocks.last, containsPair('text', '记录两张图片'));

    final links = await db.select(db.memoryCardAssets).get();
    expect(links.map((link) => link.assetId).toSet(),
        {firstAssetId, secondAssetId});
  });
}
