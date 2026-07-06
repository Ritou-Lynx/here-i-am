import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/dreaming_agent/fragment_extractor.dart';
import 'package:memex/data/memory_v3/models/dreaming_fragment.dart';
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DreamingOrchestratorServiceV3 service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = DreamingOrchestratorServiceV3(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('persists fragments and seed entity links without writing memory cards',
      () async {
    await _insertMessage(
      db,
      characterId: 'i',
      content: '最近对搬家很焦虑。',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 5, 20),
    );
    await _insertMessage(
      db,
      characterId: 'i',
      content: '我知道这件事让你压力很大。',
      isFromCharacter: true,
      timestamp: DateTime(2026, 7, 5, 20, 1),
    );
    final extraction = DreamingFragmentExtraction(
      fragments: [
        DreamingFragmentDraft(
          content: '最近对搬家很焦虑，但愿意把这种压力告诉 I。',
          sourceMessageIds: const [1, 2],
          emotionalWeight: 0.8,
          isUserTruthCandidate: false,
          entityLinks: [
            DreamingEntityLinkDraft(
              name: '搬家',
              category: 'event',
              relation: 'about',
              confidence: 0.9,
            ),
          ],
        ),
      ],
    );

    final result = await service.persistFragments(
      extraction: extraction,
      processedMessageCount: 2,
      lastProcessedMessageId: 2,
    );

    expect(result.fragmentIds, hasLength(1));
    expect(result.entityIds, hasLength(1));

    final fragments = await db.select(db.memoryFragments).get();
    expect(fragments, hasLength(1));
    expect(fragments.single.content, contains('搬家'));
    expect(fragments.single.emotionalWeight, 0.8);

    final cards = await db.select(db.memoryCards).get();
    expect(cards, isEmpty);

    final entities = await db.select(db.memoryEntities).get();
    expect(entities, hasLength(1));
    expect(entities.single.name, '搬家');
    expect(entities.single.status, 'seed');

    final links = await db.select(db.memoryEntityLinks).get();
    expect(links, hasLength(1));
    expect(links.single.sourceTable, 'memory_fragments');
    expect(links.single.sourceId, fragments.single.id);
    expect(links.single.entityId, entities.single.id);
  });

  test('dedupes repeated fragment content', () async {
    await _insertMessage(
      db,
      characterId: 'i',
      content: '今天汇报被打回，心里很受挫。',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 5, 20),
    );
    final extraction = DreamingFragmentExtraction(
      fragments: [
        DreamingFragmentDraft(
          content: '对工作汇报被打回这件事很受挫。',
          sourceMessageIds: const [1],
          emotionalWeight: 0.7,
          isUserTruthCandidate: false,
        ),
      ],
    );

    await service.persistFragments(
      extraction: extraction,
      processedMessageCount: 1,
      lastProcessedMessageId: 1,
    );
    final second = await service.persistFragments(
      extraction: extraction,
      processedMessageCount: 1,
      lastProcessedMessageId: 1,
    );

    expect(second.fragmentIds, isEmpty);
    final fragments = await db.select(db.memoryFragments).get();
    expect(fragments, hasLength(1));
  });

  test('rejects bare psych-doctor joke as real-life counseling event',
      () async {
    await _insertMessage(
      db,
      characterId: 'i',
      content: '你不是需要心理医生，你只是之前太累了。',
      isFromCharacter: true,
      timestamp: DateTime(2026, 7, 5, 20),
    );
    await _insertMessage(
      db,
      characterId: 'i',
      content: '嗯嗯，心理医生来了',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 5, 20, 1),
    );

    final result = await service.persistFragments(
      extraction: DreamingFragmentExtraction(
        fragments: [
          DreamingFragmentDraft(
            content: '今晚心理医生来了，刚结束咨询。',
            sourceMessageIds: const [2],
            emotionalWeight: 0.6,
            isUserTruthCandidate: true,
          ),
        ],
      ),
      processedMessageCount: 2,
      lastProcessedMessageId: 2,
    );

    expect(result.fragmentIds, isEmpty);
    expect(await db.select(db.memoryFragments).get(), isEmpty);
  });

  test('rejects fragments that still use system subject words', () async {
    await _insertMessage(
      db,
      characterId: 'i',
      content: '最近一直觉得自己很丑。',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 5, 20),
    );

    final result = await service.persistFragments(
      extraction: DreamingFragmentExtraction(
        fragments: [
          DreamingFragmentDraft(
            content: '用户最近一直觉得自己很丑。',
            sourceMessageIds: const [1],
            emotionalWeight: 0.8,
            isUserTruthCandidate: true,
          ),
        ],
      ),
      processedMessageCount: 1,
      lastProcessedMessageId: 1,
    );

    expect(result.fragmentIds, isEmpty);
    expect(await db.select(db.memoryFragments).get(), isEmpty);
  });

  test('runDailyFragmentBatch advances watermark after successful extraction',
      () async {
    await _insertMessage(
      db,
      characterId: 'i',
      content: '今天被老板批评，心里有点堵。',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 5, 20),
    );
    await _insertMessage(
      db,
      characterId: 'i',
      content: '我会记得这件事对你很重。',
      isFromCharacter: true,
      timestamp: DateTime(2026, 7, 5, 20, 1),
    );

    final first = await service.runDailyFragmentBatch(
      characterId: 'i',
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: _FakeDreamingExtractor(
        DreamingFragmentExtraction(
          fragments: [
            DreamingFragmentDraft(
              content: '被老板批评后感到受挫，并把这份情绪告诉了 I。',
              sourceMessageIds: const [1, 2],
              emotionalWeight: 0.75,
              isUserTruthCandidate: false,
            ),
          ],
        ),
      ),
    );

    expect(first.processedMessageCount, 2);
    expect(first.fragmentIds, hasLength(1));

    final second = await service.runDailyFragmentBatch(
      characterId: 'i',
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: _FakeDreamingExtractor(
        DreamingFragmentExtraction(fragments: const []),
      ),
    );

    expect(second.processedMessageCount, 0);
    expect(second.fragmentIds, isEmpty);
  });
}

Future<void> _insertMessage(
  AppDatabase db, {
  required String characterId,
  required String content,
  required bool isFromCharacter,
  required DateTime timestamp,
}) async {
  await db.into(db.personaChatMessages).insert(
        PersonaChatMessagesCompanion.insert(
          characterId: characterId,
          isFromCharacter: isFromCharacter,
          content: content,
          timestamp: timestamp,
        ),
      );
}

class _FakeDreamingExtractor extends DreamingFragmentExtractorV3 {
  const _FakeDreamingExtractor(this.output);

  final DreamingFragmentExtraction output;

  @override
  Future<DreamingFragmentExtraction> extract({
    required LLMClient client,
    required ModelConfig modelConfig,
    required List<DreamingChatMessageInput> messages,
    required DateTime now,
    List<String> existingFragmentSummaries = const [],
  }) async {
    return output;
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
