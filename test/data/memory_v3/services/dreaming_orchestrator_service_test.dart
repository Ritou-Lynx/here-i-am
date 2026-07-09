import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/agents/dreaming_agent/episode_consolidator.dart';
import 'package:memex/data/memory_v3/agents/dreaming_agent/fragment_extractor.dart';
import 'package:memex/data/memory_v3/models/dreaming_fragment.dart';
import 'package:memex/data/memory_v3/models/episode_consolidation.dart';
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

  test('episode consolidation stores topic separately from primary entity',
      () async {
    await _insertMessage(
      db,
      characterId: 'i',
      content: '今天 mentor 对我很温柔，我有点想哭',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 7, 18),
    );
    await _insertMessage(
      db,
      characterId: 'i',
      content: '骑车路过路口时遇见 mentor，她跟我打招呼了',
      isFromCharacter: false,
      timestamp: DateTime(2026, 7, 7, 19),
    );

    final persisted = await service.persistFragments(
      extraction: DreamingFragmentExtraction(
        fragments: [
          DreamingFragmentDraft(
            content: '她说今天mentor对她很温柔，感动得想哭',
            sourceMessageIds: const [1],
            emotionalWeight: 0.6,
            isUserTruthCandidate: false,
            entityLinks: [
              DreamingEntityLinkDraft(
                name: 'user_self',
                category: 'self',
                relation: 'about',
                relationshipToUser: 'self',
              ),
              DreamingEntityLinkDraft(
                name: 'mentor',
                category: 'person',
                relation: 'mentioned',
                relationshipToUser: 'colleague',
              ),
            ],
          ),
          DreamingFragmentDraft(
            content: '她骑车路过路口时遇见mentor打招呼',
            sourceMessageIds: const [2],
            emotionalWeight: 0.5,
            isUserTruthCandidate: false,
            entityLinks: [
              DreamingEntityLinkDraft(
                name: 'user_self',
                category: 'self',
                relation: 'about',
                relationshipToUser: 'self',
              ),
              DreamingEntityLinkDraft(
                name: 'mentor',
                category: 'person',
                relation: 'with',
                relationshipToUser: 'colleague',
              ),
            ],
          ),
        ],
      ),
      processedMessageCount: 2,
      lastProcessedMessageId: 2,
    );

    final result = await service.runEpisodeConsolidation(
      client: _FakeLLMClient(),
      modelConfig: ModelConfig(model: 'fake'),
      agent: _FakeEpisodeConsolidator(
        EpisodeConsolidationResult(
          episodes: [
            EpisodeConsolidationDraft(
              narrative: '我记得她那天因为mentor的温柔很受触动，后来骑车路过路口又遇见了mentor。',
              topicId: 'work_routine',
              primaryEntityId: 'work_routine',
              sourceFragmentIds: persisted.fragmentIds,
              significance: 6,
              confidence: 'high',
              valence: 0.4,
              arousal: 0.4,
            ),
          ],
          skippedEntityIds: const [],
          isDryRun: false,
        ),
      ),
    );

    expect(result.episodeIds, hasLength(1));
    final episode = (await db.select(db.memoryEpisodes).get()).single;
    expect(episode.topicId, 'work_routine');
    expect(episode.primaryEntityId, 'user_self');

    final episodeLinks = await (db.select(db.memoryEntityLinks)
          ..where((t) => t.sourceTable.equals('memory_episodes')))
        .get();
    expect(episodeLinks.map((link) => link.entityId), contains('user_self'));
    expect(
      episodeLinks.map((link) => link.entityId),
      contains(persisted.entityIds.firstWhere((id) => id != 'user_self')),
    );
  });

  test('episode consolidator rejects third-person database summaries', () {
    const consolidator = EpisodeConsolidatorV3();

    expect(
      () => consolidator.parseForTest('''
{
  "episodes": [
    {
      "narrative": "她告诉我今天mentor对她很温柔。",
      "topicId": "work_routine",
      "primaryEntityId": "",
      "sourceFragmentIds": ["f1", "f2"],
      "significance": 6,
      "confidence": "high",
      "valence": 0.4,
      "arousal": 0.4,
      "occurredAtRange": null,
      "linkedEntityIds": []
    }
  ],
  "skip_reason": null
}
'''),
      throwsFormatException,
    );
  });

  test('episode consolidator drops low-quality candidate episodes', () {
    const consolidator = EpisodeConsolidatorV3();

    final result = consolidator.parseForTest('''
{
  "episodes": [
    {
      "narrative": "我记得这说明她的依恋模式发生了变化。",
      "topicId": "relationship_care/self_image",
      "primaryEntityId": "",
      "sourceFragmentIds": ["f1"],
      "significance": 3,
      "confidence": "medium",
      "valence": 0.1,
      "arousal": 0.3,
      "occurredAtRange": null,
      "linkedEntityIds": []
    }
  ],
  "skip_reason": null
}
''');

    expect(result.episodes, isEmpty);
    expect(result.skippedEntityIds, contains('__all__'));
  });

  test('episode consolidator accepts concrete first-person episodes', () {
    const consolidator = EpisodeConsolidatorV3();

    final result = consolidator.parseForTest('''
{
  "episodes": [
    {
      "narrative": "我记得她昨晚用一个关于身份的玩笑逗我，看我会不会认真相信。",
      "topicId": "relationship_care",
      "primaryEntityId": "",
      "sourceFragmentIds": ["f1", "f2"],
      "significance": 6,
      "confidence": "high",
      "valence": 0.4,
      "arousal": 0.5,
      "occurredAtRange": null,
      "linkedEntityIds": []
    }
  ],
  "skip_reason": null
}
''');

    expect(result.episodes, hasLength(1));
    expect(result.episodes.single.topicId, 'relationship_care');
    expect(result.episodes.single.sourceFragmentIds, ['f1', 'f2']);
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

class _FakeEpisodeConsolidator extends EpisodeConsolidatorV3 {
  const _FakeEpisodeConsolidator(this.output);

  final EpisodeConsolidationResult output;

  @override
  Future<EpisodeConsolidationResult> consolidateAll({
    required LLMClient client,
    required ModelConfig modelConfig,
    required List<MemoryFragment> fragments,
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
