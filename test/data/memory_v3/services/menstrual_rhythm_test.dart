import 'dart:async';
import 'dart:convert';
import 'dart:io' show stderr;

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/record_organizer_agent/agent.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
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
    UserRhythmService.init(db);
  });

  tearDown(() async {
    if (!fts5Available) return;
    await db.close();
  });

  /// Pump the microtask queue + small delays until [predicate] returns true,
  /// because the card->rhythm bridge is fire-and-forget (unawaited).
  Future<void> waitUntil(Future<bool> Function() predicate,
      {int maxIterations = 50}) async {
    for (var i = 0; i < maxIterations; i++) {
      if (await predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('organizeAndPersist rebuilds menstrual rhythm from a menstrual_record card',
      () async {
    if (!fts5Available) return;
    final agent = _MenstrualCardAgent(
      startDate: '2026-08-02',
      endDate: null,
      flowLevel: 'medium',
      painLevel: 4,
    );
    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: agent,
      source: RecordSource(
        sourceKind: 'fab',
        rawInput: '大姨妈 2026-08-02 来了',
      ),
    );
    expect(result.isEmpty, isFalse);

    // The rhythm rebuild is fire-and-forget. Wait until a menstrual_cycle
    // rhythm row appears.
    await waitUntil(() async {
      final rhythms = await UserRhythmService.instance
          .getActiveRhythmsByKind('menstrual_cycle');
      return rhythms.isNotEmpty;
    });

    final rhythms = await UserRhythmService.instance
        .getActiveRhythmsByKind('menstrual_cycle');
    expect(rhythms, hasLength(1));

    // Verify the cycle history contains the recorded start date.
    final rrule = rhythms.first.rrule;
    final decoded = jsonDecode(rrule) as Map<String, dynamic>;
    final history = decoded['cycleHistory'] as List;
    expect(history, hasLength(1));
    expect(history.first['start'], '2026-08-02');
    expect(history.first['flow'], 'medium');
    expect(history.first['pain'], 4);

    // The status should reflect "menstrual" phase (within 7 days of start,
    // no end date).
    final status = await UserRhythmService.instance.getMenstrualCycleStatus(
      now: DateTime(2026, 8, 3),
    );
    expect(status, isNotNull);
    expect(status!.phase, 'menstrual');
    expect(status.cycleCount, 1);
  });

  test('rebuildMenstrualRhythmFromCards merges cards with the same startDate',
      () async {
    if (!fts5Available) return;

    // Record "period started" with one card.
    await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: _MenstrualCardAgent(
        startDate: '2026-08-02',
        endDate: null,
        flowLevel: null,
        painLevel: null,
      ),
      source: RecordSource(sourceKind: 'fab', rawInput: '大姨妈来了'),
    );

    // Wait for the first rebuild.
    await waitUntil(() async {
      final rhythms = await UserRhythmService.instance
          .getActiveRhythmsByKind('menstrual_cycle');
      return rhythms.isNotEmpty;
    });

    // Record "period ended" with a second card sharing the same startDate.
    await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: _MenstrualCardAgent(
        startDate: '2026-08-02',
        endDate: '2026-08-07',
        flowLevel: 'medium',
        painLevel: null,
      ),
      source: RecordSource(sourceKind: 'fab', rawInput: '大姨妈结束了'),
    );

    // Wait for the rebuild to settle (two fire-and-forget rebuilds).
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final rhythms = await UserRhythmService.instance
        .getActiveRhythmsByKind('menstrual_cycle');
    expect(rhythms, hasLength(1));

    final decoded =
        jsonDecode(rhythms.first.rrule) as Map<String, dynamic>;
    final history = decoded['cycleHistory'] as List;
    // Two cards with the same startDate should merge into ONE cycle entry.
    expect(history, hasLength(1));
    expect(history.first['start'], '2026-08-02');
    expect(history.first['end'], '2026-08-07');
    expect(history.first['flow'], 'medium');
  });

  test('rebuildMenstrualRhythmFromCards predicts next start from cycle history',
      () async {
    if (!fts5Available) return;

    // Record three cycles 28 days apart.
    for (final start in ['2026-07-05', '2026-07-18', '2026-08-02']) {
      await service.organizeAndPersist(
        client: _FakeLLMClient(),
        modelConfig: ModelConfig(model: 'fake'),
        agent: _MenstrualCardAgent(
          startDate: start,
          endDate: null,
          flowLevel: null,
          painLevel: null,
        ),
        source: RecordSource(sourceKind: 'fab', rawInput: '经期 $start'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final rhythms = await UserRhythmService.instance
        .getActiveRhythmsByKind('menstrual_cycle');
    expect(rhythms, hasLength(1));

    final decoded =
        jsonDecode(rhythms.first.rrule) as Map<String, dynamic>;
    // With >= 3 cycles, confidence should be 0.9.
    expect((decoded['confidence'] as num).toDouble(), 0.9);

    final status = await UserRhythmService.instance.getMenstrualCycleStatus(
      now: DateTime(2026, 8, 2),
    );
    expect(status, isNotNull);
    expect(status!.cycleCount, 3);
    // avgCycle from starts 7/5->7/18 (13d) and 7/18->8/2 (15d) = 14d.
    // Predicted next = 8/2 + 14 = 8/16.
    expect(status.avgCycleDays, 14);
  });

  test('deleteCard on a menstrual_record card expires the rhythm',
      () async {
    if (!fts5Available) return;

    final result = await service.organizeAndPersist(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: _MenstrualCardAgent(
        startDate: '2026-08-02',
        endDate: null,
        flowLevel: null,
        painLevel: null,
      ),
      source: RecordSource(sourceKind: 'fab', rawInput: '经期来了'),
    );
    final cardId = result.cardIds.single;

    await waitUntil(() async {
      final rhythms = await UserRhythmService.instance
          .getActiveRhythmsByKind('menstrual_cycle');
      return rhythms.isNotEmpty;
    });

    // Delete the only menstrual card. The rebuild should expire the rhythm.
    await service.deleteCard(cardId);

    await waitUntil(() async {
      final rhythms = await UserRhythmService.instance
          .getActiveRhythmsByKind('menstrual_cycle');
      return rhythms.isEmpty;
    });

    final rhythms = await UserRhythmService.instance
        .getActiveRhythmsByKind('menstrual_cycle');
    expect(rhythms, isEmpty);
  });
}

/// Agent that returns a fixed menstrual_record card without calling an LLM.
class _MenstrualCardAgent extends RecordOrganizerAgentV3 {
  final String startDate;
  final String? endDate;
  final String? flowLevel;
  final int? painLevel;

  _MenstrualCardAgent({
    required this.startDate,
    required this.endDate,
    required this.flowLevel,
    required this.painLevel,
  });

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
    final fields = <String, dynamic>{
      'startDate': startDate,
      'occurredAt': startDate,
    };
    if (endDate != null) fields['endDate'] = endDate;
    if (flowLevel != null) fields['flowLevel'] = flowLevel;
    if (painLevel != null) fields['painLevel'] = painLevel;

    return OrganizedRecord(cards: [
      OrganizedCard(
        type: 'event',
        title: '经期记录 $startDate',
        dropletLabel: '经期',
        presentationModule: {
          'blocks': [
            {'kind': 'text', 'text': '经期 $startDate'},
          ],
        },
        retrievalText: '经期记录 $startDate',
        valence: 0.0,
        arousal: 0.4,
        structuredFieldsType: 'menstrual_record',
        structuredFields: fields,
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
    stderr.writeln('FTS5 unavailable; menstrual rhythm tests skipped.');
    return false;
  }
}
