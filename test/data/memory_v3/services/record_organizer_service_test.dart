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
