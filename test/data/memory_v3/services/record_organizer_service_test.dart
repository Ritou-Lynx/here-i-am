import 'dart:async';
import 'dart:convert';
import 'dart:io' show stderr;

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/record_organizer_agent/agent.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fts5Available = _checkFts5();

  late AppDatabase db;
  late RecordOrganizerServiceV3 service;

  setUp(() {
    if (!fts5Available) return;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = RecordOrganizerServiceV3(db);
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  test('persists every input media as a display block with saved paths',
      () async {
    if (!fts5Available) return;
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

  test('bridges income_entry cards to the AI finance ledger as income',
      () async {
    if (!fts5Available) return;
    // The fake agent returns a single income_entry card without calling an
    // LLM, so we exercise the full organizeAndPersist -> _bridgeToLedger path.
    final agent = _IncomeCardAgent();
    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: agent,
      source: RecordSource(
        sourceKind: 'record_button',
        rawInput: '工资到账 5000',
      ),
    );
    expect(result.isEmpty, isFalse);
    final cardId = result.cardIds.single;

    // _bridgeToLedger is fire-and-forget (unawaited). Pump the microtask
    // queue until the ledger row appears so the assertion is deterministic
    // instead of relying on a fixed Duration delay.
    List<AiFinanceLedgerData> rows = const [];
    for (var i = 0; i < 50; i++) {
      rows = await db.select(db.aiFinanceLedger).get();
      if (rows.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(rows, hasLength(1));
    final entry = rows.single;
    expect(entry.entryType, 'income');
    expect(entry.totalAmount, 5000);
    expect(entry.aiAmount, 0);
    expect(entry.linkedFactId, cardId);
    expect(entry.characterId, 'system:card_bridge');
    expect(entry.purpose, '七月工资到账');
  });

  test('bridges income_entry with explicit AI share to a split ledger entry',
      () async {
    if (!fts5Available) return;
    final agent = _IncomeSplitCardAgent();
    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: agent,
      source: RecordSource(
        sourceKind: 'record_button',
        rawInput: '项目收入 2690，分三成给 i',
      ),
    );
    expect(result.isEmpty, isFalse);
    final cardId = result.cardIds.single;

    List<AiFinanceLedgerData> rows = const [];
    for (var i = 0; i < 50; i++) {
      rows = await db.select(db.aiFinanceLedger).get();
      if (rows.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(rows, hasLength(1));
    final entry = rows.single;
    expect(entry.entryType, 'income');
    expect(entry.totalAmount, 2690);
    // aiAmount = 2690 × 0.3 = 807
    expect(entry.aiAmount, closeTo(807, 0.01));
    expect(entry.contributionRatio, closeTo(0.3, 0.0001));
    expect(entry.myContributionDesc, '修改润色');
    expect(entry.aiContributionDesc, '脚本初稿');
    expect(entry.linkedFactId, cardId);
    expect(entry.characterId, 'system:card_bridge');
  });

  test('updateCard changes only provided fields and writes an update audit',
      () async {
    if (!fts5Available) return;
    final agent = _StaticCardAgent();
    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: agent,
      source: RecordSource(
        sourceKind: 'record_button',
        rawInput: '午饭吃了汉堡',
      ),
    );
    expect(result.isEmpty, isFalse);
    final cardId = result.cardIds.single;

    final original = await (db.select(db.memoryCards)
          ..where((t) => t.id.equals(cardId)))
        .getSingle();
    expect(original.title, '午饭吃了汉堡');

    final updated = await service.updateCard(
      cardId,
      title: '午饭吃了麦辣鸡腿堡',
      retrievalText: '中午吃了麦辣鸡腿堡，和室友 A 一起。',
      dropletLabel: '鸡腿堡',
    );
    expect(updated, isA<MemoryCard>());
    expect(updated!.title, '午饭吃了麦辣鸡腿堡');
    expect(updated.retrievalText, '中午吃了麦辣鸡腿堡，和室友 A 一起。');
    expect(updated.dropletLabel, '鸡腿堡');
    expect(updated.type, original.type); // unchanged
    expect(updated.updatedAt, greaterThan(original.updatedAt));

    final ops = await (db.select(db.memoryCardOperations)
          ..where((t) => t.cardId.equals(cardId)))
        .get();
    final updateOps = ops.where((o) => o.operationType == 'update').toList();
    expect(updateOps, hasLength(1));
    final payload = jsonDecode(updateOps.single.payload) as Map<String, dynamic>;
    expect(payload.keys, containsAll(['title', 'retrievalText', 'dropletLabel']));
  });

  test('updateCard returns null for unknown cardId', () async {
    if (!fts5Available) return;
    final result = await service.updateCard(
      'nonexistent-id',
      title: '不会写入',
    );
    expect(result == null, isTrue);
  });

  test('updateCard patches structured fields, merges with existing, and marks userCorrected',
      () async {
    if (!fts5Available) return;
    final agent = _StaticCardAgent();
    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: agent,
      source: RecordSource(
        sourceKind: 'record_button',
        rawInput: '午饭吃了汉堡',
      ),
    );
    final cardId = result.cardIds.single;

    // Insert initial structured fields with both content and time fields.
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.memoryCardStructuredFields).insert(
          MemoryCardStructuredFieldsCompanion.insert(
            cardId: cardId,
            structuredFieldsType: 'general',
            fieldsJson:
                '{"foo":"bar","amount_cny":100,"merchant":"旧店","receivedAt":"2026-07-15T12:00:00"}',
            createdAt: now,
            updatedAt: now,
          ),
        );

    // Pass a "wrong" time field in structured_fields - it MUST be stripped.
    // Other content fields should merge with existing.
    await service.updateCard(
      cardId,
      structuredFields: {
        'amount_cny': 128,
        'merchant': '麦当劳',
        'receivedAt': 'WRONG_TIME_SHOULD_BE_STRIPPED',
      },
      structuredFieldsType: 'expense_entry',
    );

    final sf = await (db.select(db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(cardId)))
        .getSingle();
    expect(sf.structuredFieldsType, 'expense_entry');
    expect(sf.userCorrected, true);
    final decoded = jsonDecode(sf.fieldsJson) as Map<String, dynamic>;
    expect(decoded['amount_cny'], 128);
    expect(decoded['merchant'], '麦当劳');
    // Unspecified fields preserved.
    expect(decoded['foo'], 'bar');
    // Time field preserved from existing — NOT the wrong value from new.
    expect(decoded['receivedAt'], '2026-07-15T12:00:00');
  });

  test('updateCard timeOverrides can explicitly change time fields', () async {
    if (!fts5Available) return;
    final agent = _StaticCardAgent();
    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: agent,
      source: RecordSource(sourceKind: 'record_button', rawInput: '午饭'),
    );
    final cardId = result.cardIds.single;

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.memoryCardStructuredFields).insert(
          MemoryCardStructuredFieldsCompanion.insert(
            cardId: cardId,
            structuredFieldsType: 'income_entry',
            fieldsJson: '{"amount_cny":2690,"receivedAt":"2026-07-15T08:52:33"}',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await service.updateCard(
      cardId,
      timeOverrides: {'receivedAt': '2026-07-15T09:30:00'},
    );

    final sf = await (db.select(db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(cardId)))
        .getSingle();
    final decoded = jsonDecode(sf.fieldsJson) as Map<String, dynamic>;
    expect(decoded['amount_cny'], 2690); // preserved
    expect(decoded['receivedAt'], '2026-07-15T09:30:00'); // changed via override
  });

  test('updateCard timeOverrides silently ignores non-time keys', () async {
    if (!fts5Available) return;
    final agent = _StaticCardAgent();
    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: agent,
      source: RecordSource(sourceKind: 'record_button', rawInput: '午饭'),
    );
    final cardId = result.cardIds.single;

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.memoryCardStructuredFields).insert(
          MemoryCardStructuredFieldsCompanion.insert(
            cardId: cardId,
            structuredFieldsType: 'general',
            fieldsJson: '{"amount_cny":100,"merchant":"原店"}',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await service.updateCard(
      cardId,
      timeOverrides: {'merchant': '新店', 'paidAt': '2026-07-15T14:00:00'},
    );

    final sf = await (db.select(db.memoryCardStructuredFields)
          ..where((t) => t.cardId.equals(cardId)))
        .getSingle();
    final decoded = jsonDecode(sf.fieldsJson) as Map<String, dynamic>;
    expect(decoded['merchant'], '原店'); // timeOverrides ignored non-time key
    expect(decoded['amount_cny'], 100); // preserved
    expect(decoded['paidAt'], '2026-07-15T14:00:00'); // time field added
  });

  test('updateCard does not refresh memory_cards.updatedAt', () async {
    if (!fts5Available) return;
    final agent = _StaticCardAgent();
    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: agent,
      source: RecordSource(sourceKind: 'record_button', rawInput: '午饭'),
    );
    final cardId = result.cardIds.single;

    final original = await (db.select(db.memoryCards)
          ..where((t) => t.id.equals(cardId)))
        .getSingle();
    // Wait so any new timestamp would be measurably different.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await service.updateCard(
      cardId,
      title: '午饭吃了麦辣鸡腿堡',
      retrievalText: '中午吃了麦辣鸡腿堡，和同事一起。',
    );
    final after = await (db.select(db.memoryCards)
          ..where((t) => t.id.equals(cardId)))
        .getSingle();

    expect(after.title, '午饭吃了麦辣鸡腿堡');
    expect(after.retrievalText, '中午吃了麦辣鸡腿堡，和同事一起。');
    expect(after.updatedAt, original.updatedAt); // unchanged on purpose
  });

  test('updateCard auto-syncs retrievalText into presentationModule text blocks',
      () async {
    if (!fts5Available) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cardId = 'sync-text-card-${DateTime.now().microsecondsSinceEpoch}';
    await db.into(db.memoryCards).insert(
          MemoryCardsCompanion.insert(
            id: cardId,
            memoryScope: const Value('user_truth'),
            type: 'event',
            title: '午饭',
            dropletLabel: '午饭',
            presentationModule: jsonEncode({
              'title': '午饭',
              'blocks': [
                {'type': 'text', 'text': '旧的第一句。'},
                {'type': 'text', 'text': '旧的第二句。'},
                {'type': 'number', 'value': '88', 'unit': '元'},
              ],
            }),
            retrievalText: '旧的第一句。旧的第二句。',
            valence: 0.4,
            arousal: 0.3,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await service.updateCard(
      cardId,
      retrievalText: '新的第一句。新的第二句。',
    );
    final updated = await (db.select(db.memoryCards)
          ..where((t) => t.id.equals(cardId)))
        .getSingle();
    final pm = jsonDecode(updated.presentationModule) as Map<String, dynamic>;
    final blocks = pm['blocks'] as List;
    expect((blocks[0] as Map)['text'], '新的第一句。');
    expect((blocks[1] as Map)['text'], '新的第二句。');
    // Non-text block preserved (number, media, table, quote, ...).
    expect((blocks[2] as Map)['type'], 'number');
    expect((blocks[2] as Map)['value'], '88');
  });

  test('persist reuses an existing card for the same anchored event',
      () async {
    if (!fts5Available) return;
    // Seed an existing active schedule card (simulates the spider-man case:
    // "看蜘蛛侠电影" recorded earlier).
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingId = 'dup-keeper-${now}';
    await db.into(db.memoryCards).insert(
          MemoryCardsCompanion.insert(
            id: existingId,
            memoryScope: const Value('user_truth'),
            type: 'schedule',
            title: '看蜘蛛侠电影 8月1日早上',
            dropletLabel: '蜘蛛侠',
            presentationModule: jsonEncode({
              'blocks': [
                {'kind': 'text', 'text': '计划于8月1日早上去看蜘蛛侠电影。'},
              ],
            }),
            retrievalText: '计划于2026年8月1日早上去看蜘蛛侠电影。',
            valence: 0.5,
            arousal: 0.4,
            status: const Value('active'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.memoryCardStructuredFields).insert(
          MemoryCardStructuredFieldsCompanion.insert(
            cardId: existingId,
            structuredFieldsType: 'general',
            fieldsJson: jsonEncode({'startAt': '2026-08-01T09:00:00'}),
            generatedByVersion: const Value('test'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    // Re-record the same fact at the same time → must NOT create a new card.
    final result = await service.persist(
      organized: OrganizedRecord(cards: [
        OrganizedCard(
          type: 'schedule',
          title: '看蜘蛛侠电影',
          dropletLabel: '蜘蛛侠',
          presentationModule: {
            'blocks': [
              {'kind': 'text', 'text': '8月1日早上去看蜘蛛侠电影。'},
            ],
          },
          retrievalText: '2026年8月1日早上有一场蜘蛛侠电影。',
          valence: 0.6,
          arousal: 0.4,
          structuredFieldsType: 'general',
          structuredFields: {'startAt': '2026-08-01T09:00:00'},
        ),
      ]),
      source: RecordSource(
        sourceKind: 'record_button',
        rawInput: '买了蜘蛛侠电影票周六早上去看',
      ),
    );

    expect(result.cardIds, [existingId]);
    final all = await db.select(db.memoryCards).get();
    expect(all, hasLength(1));
  });

  test('persist keeps distinct events even with same type and similar title '
      'when the time anchor differs', () async {
    if (!fts5Available) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.memoryCards).insert(
          MemoryCardsCompanion.insert(
            id: 'dup-anchor-a-${now}',
            memoryScope: const Value('user_truth'),
            type: 'schedule',
            title: '看蜘蛛侠电影',
            dropletLabel: '蜘蛛侠',
            presentationModule: jsonEncode({'blocks': []}),
            retrievalText: '第一场。',
            valence: 0.5,
            arousal: 0.4,
            status: const Value('active'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.memoryCardStructuredFields).insert(
          MemoryCardStructuredFieldsCompanion.insert(
            cardId: 'dup-anchor-a-${now}',
            structuredFieldsType: 'general',
            fieldsJson: jsonEncode({'startAt': '2026-08-01T09:00:00'}),
            generatedByVersion: const Value('test'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    // Same type, similar title, but DIFFERENT time (next week) → new card.
    final result = await service.persist(
      organized: OrganizedRecord(cards: [
        OrganizedCard(
          type: 'schedule',
          title: '再看一次蜘蛛侠电影',
          dropletLabel: '蜘蛛侠',
          presentationModule: {
            'blocks': [
              {'kind': 'text', 'text': '下周再看一次。'},
            ],
          },
          retrievalText: '下周再看一次蜘蛛侠电影。',
          valence: 0.6,
          arousal: 0.4,
          structuredFieldsType: 'general',
          structuredFields: {'startAt': '2026-08-08T09:00:00'},
        ),
      ]),
      source: RecordSource(
        sourceKind: 'record_button',
        rawInput: '下周再去看一次蜘蛛侠',
      ),
    );

    expect(result.cardIds, hasLength(1));
    expect(result.cardIds.single, isNot('dup-anchor-a-${now}'));
    final all = await db.select(db.memoryCards).get();
    expect(all, hasLength(2));
  });

  test('dedupeExistingScheduleCards removes legacy duplicates', () async {
    if (!fts5Available) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Seed two active schedule cards with the same anchor (the 2026-08-02
    // spider-man bug: same fact recorded twice → two cards).
    for (final (i, title) in [
      '看蜘蛛侠电影 8月1日早上',
      '看蜘蛛侠电影',
    ].indexed) {
      final id = 'legacy-dup-${i}-${now}';
      await db.into(db.memoryCards).insert(
            MemoryCardsCompanion.insert(
              id: id,
              memoryScope: const Value('user_truth'),
              type: 'schedule',
              title: title,
              dropletLabel: '蜘蛛侠',
              presentationModule: jsonEncode({'blocks': []}),
              retrievalText: '看蜘蛛侠电影 $i',
              valence: 0.5,
              arousal: 0.4,
              status: const Value('active'),
              createdAt: now + i,
              updatedAt: now + i,
            ),
          );
      await db.into(db.memoryCardStructuredFields).insert(
            MemoryCardStructuredFieldsCompanion.insert(
              cardId: id,
              structuredFieldsType: 'general',
              fieldsJson: jsonEncode({'startAt': '2026-08-01T09:00:00'}),
              generatedByVersion: const Value('test'),
              createdAt: now + i,
              updatedAt: now + i,
            ),
          );
    }

    final removed = await service.dedupeExistingScheduleCards();
    expect(removed, 1);
    final remaining = await db.select(db.memoryCards).get();
    expect(remaining, hasLength(1));
    expect(remaining.single.title, '看蜘蛛侠电影 8月1日早上');
    // Audit trail preserved.
    final ops = await db.select(db.memoryCardOperations).get();
    expect(ops.map((o) => o.operationType), contains('delete'));
  });
}

/// Agent that skips the LLM and returns a fixed income_entry card.
class _IncomeCardAgent extends RecordOrganizerAgentV3 {
  @override
  Future<OrganizedRecord> organize({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String rawInput,
    required DateTime now,
    List<String> relevantExistingCardSummaries = const [],
    List<String> recentEntityNames = const [],
    List<Map<String, String>>? inputMedia,
  }) async {
    return OrganizedRecord(cards: [
      OrganizedCard(
        type: 'event',
        title: '七月工资到账',
        dropletLabel: '收入',
        presentationModule: {
          'blocks': [
            {'kind': 'text', 'text': '七月工资到账 5000 元'},
          ],
        },
        retrievalText: '七月工资到账 5000 元',
        valence: 0.5,
        arousal: 0.3,
        structuredFieldsType: 'income_entry',
        structuredFields: {
          'amount_cny': 5000,
          'source': '工资',
          'receivedAt': '2026-07-15T09:00:00',
        },
      ),
    ]);
  }
}

/// Agent that returns an income_entry card with an explicit AI share.
class _IncomeSplitCardAgent extends RecordOrganizerAgentV3 {
  @override
  Future<OrganizedRecord> organize({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String rawInput,
    required DateTime now,
    List<String> relevantExistingCardSummaries = const [],
    List<String> recentEntityNames = const [],
    List<Map<String, String>>? inputMedia,
  }) async {
    return OrganizedRecord(cards: [
      OrganizedCard(
        type: 'event',
        title: '项目收入 2690',
        dropletLabel: '收入',
        presentationModule: {
          'blocks': [
            {'kind': 'text', 'text': '项目收入 2690 元，分三成给 i'},
          ],
        },
        retrievalText: '项目收入 2690 元，分三成给 i',
        valence: 0.6,
        arousal: 0.4,
        structuredFieldsType: 'income_entry',
        structuredFields: {
          'amount_cny': 2690,
          'source': '项目收入',
          'receivedAt': '2026-07-15T10:00:00',
          'ai_share_ratio': 0.3,
          'ai_contribution': '脚本初稿',
          'my_contribution': '修改润色',
        },
      ),
    ]);
  }
}

/// Agent that returns a simple event card without structured fields.
class _StaticCardAgent extends RecordOrganizerAgentV3 {
  @override
  Future<OrganizedRecord> organize({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String rawInput,
    required DateTime now,
    List<String> relevantExistingCardSummaries = const [],
    List<String> recentEntityNames = const [],
    List<Map<String, String>>? inputMedia,
  }) async {
    return OrganizedRecord(cards: [
      OrganizedCard(
        type: 'event',
        title: '午饭吃了汉堡',
        dropletLabel: '汉堡',
        presentationModule: {
          'blocks': [
            {'kind': 'text', 'text': '午饭吃了汉堡'},
          ],
        },
        retrievalText: '午饭吃了汉堡',
        valence: 0.4,
        arousal: 0.3,
      ),
    ]);
  }
}

class _FakeLLMClient extends LLMClient {
  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    dynamic cancelToken,
  }) async {
    return ModelMessage(model: modelConfig.model, textOutput: '{}');
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    dynamic cancelToken,
  }) async {
    return const Stream.empty();
  }
}

bool _checkFts5() {
  try {
    final db = sqlite3.sqlite3.openInMemory();
    db.execute('CREATE VIRTUAL TABLE t USING fts5(content)');
    db.dispose();
    return true;
  } catch (_) {
    stderr.writeln('FTS5 unavailable; Record Organizer tests skipped.');
    return false;
  }
}
