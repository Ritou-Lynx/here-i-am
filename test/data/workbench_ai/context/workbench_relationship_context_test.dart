import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/context/workbench_relationship_context.dart';
import 'package:memex/domain/models/character_model.dart';

void main() {
  test('projects real Lin Ai persona and bounded Dreaming layers', () async {
    final backend = _FakeRelationshipBackend(
      character: _legacyCharacter(),
      recentMessages: [
        _message(4, false, '嗯'),
        _message(3, true, '我在'),
        _message(2, false, '嗯'),
        _message(1, true, '早一点的回复'),
      ],
      dreaming: WorkbenchDreamingRecall(
        episodes: List.generate(
          6,
          (index) => WorkbenchDreamingEpisode(
            id: 'episode-$index',
            narrative: '一起经历的片段 $index',
            score: 20 - index,
          ),
        ),
        fragments: List.generate(
          8,
          (index) => WorkbenchDreamingFragment(
            id: 'fragment-$index',
            content: '关系细节 $index',
            score: 10 - index,
          ),
        ),
        sagas: List.generate(
          4,
          (index) => WorkbenchDreamingSaga(
            id: 'saga-$index',
            title: '长期篇章 $index',
            description: '跨越一段时间的共同叙事 $index',
          ),
        ),
      ),
    );
    final assembler = WorkbenchRelationshipContextAssembler(
      backend: backend,
      recentMessageLimit: 3,
      episodeLimit: 2,
      fragmentLimit: 3,
      sagaLimit: 1,
    );

    final context = await assembler.assemble(
      conversationId: 'persona:i',
      characterId: 'i',
      userText: '嗯',
    );
    final prompt = context.toPromptBlock();

    expect(prompt, contains('# 你是林埃'));
    expect(prompt, contains('你是林埃（英文名 i）'));
    expect(prompt, contains('episode/episode-0'));
    expect(prompt, contains('fragment/fragment-0'));
    expect(prompt, contains('saga/saga-0'));
    expect(prompt,
        contains('Dreaming relationship recollections (not User-truth)'));
    expect(prompt, isNot(contains('episode/episode-2')));
    expect(prompt, isNot(contains('fragment/fragment-3')));
    expect(prompt, isNot(contains('saga/saga-1')));
    expect(prompt, contains('- user: 嗯'),
        reason: 'only the latest duplicate current message is skipped');
    expect(prompt, contains('- character: 早一点的回复'));
    expect(prompt, isNot(contains('LEGACY_PERSONA_SHOULD_NOT_APPEAR')));
    expect(prompt, isNot(contains('LEGACY_SYSTEM_OVERRIDE_SHOULD_NOT_APPEAR')));
    expect(prompt, isNot(contains('LEGACY_POST_HISTORY_SHOULD_NOT_APPEAR')));
    expect(prompt, isNot(contains('LEGACY_STYLE_EXAMPLE_SHOULD_NOT_APPEAR')));
    expect(prompt, isNot(contains('GetCurrentLocation')));
    expect(prompt, isNot(contains('AiFinancePenalty')));
    expect(prompt, isNot(contains('record_explicit_memory')));
    expect(backend.lastCharacterId, 'i');
    expect(backend.lastQuery, '嗯');
  });

  test('distinguishes empty Dreaming context from unavailable backend',
      () async {
    final empty = await WorkbenchRelationshipContextAssembler(
      backend: _FakeRelationshipBackend(character: _legacyCharacter()),
    ).assemble(
      conversationId: 'persona:i',
      characterId: 'i',
      userText: '没有相关内容',
    );
    expect(empty.toPromptBlock(), contains('dreaming_status: empty'));

    final failed = await WorkbenchRelationshipContextAssembler(
      backend: _FakeRelationshipBackend(
        character: _legacyCharacter(),
        failRecent: true,
        failDreaming: true,
      ),
    ).assemble(
      conversationId: 'persona:i',
      characterId: 'i',
      userText: '后端失败',
    );
    expect(failed.toPromptBlock(), contains('persona_status: available'));
    expect(failed.toPromptBlock(), contains('recent_chat_status: unavailable'));
    expect(failed.toPromptBlock(), contains('dreaming_status: unavailable'));
  });

  test('character backend failure degrades without inventing an empty result',
      () async {
    final context = await WorkbenchRelationshipContextAssembler(
      backend: _FakeRelationshipBackend(failCharacter: true),
    ).assemble(
      conversationId: 'persona:i',
      characterId: 'i',
      userText: '还记得吗',
    );

    expect(context.toPromptBlock(), contains('persona_status: unavailable'));
    expect(context.toPromptBlock(), contains('dreaming_status: unavailable'));
    expect(context.toPromptBlock(), contains('character_backend_unavailable'));
  });

  test('rejects mismatched conversation scope before any backend read',
      () async {
    final backend = _FakeRelationshipBackend(character: _legacyCharacter());
    final context = await WorkbenchRelationshipContextAssembler(
      backend: backend,
    ).assemble(
      conversationId: 'persona:other',
      characterId: 'i',
      userText: '不要串线',
    );

    expect(context.toPromptBlock(), contains('scope_status: rejected'));
    expect(
      context.toPromptBlock(),
      contains('conversation_character_scope_mismatch'),
    );
    expect(backend.characterLoads, 0);
    expect(backend.dreamingLoads, 0);
  });

  test('rejects non-i character scope without redefining product persona',
      () async {
    final backend = _FakeRelationshipBackend(character: _legacyCharacter());
    final context = await WorkbenchRelationshipContextAssembler(
      backend: backend,
    ).assemble(
      conversationId: 'persona:other',
      characterId: 'other',
      userText: '不要新建角色语义',
    );

    expect(context.toPromptBlock(), contains('scope_status: rejected'));
    expect(context.toPromptBlock(), contains('unsupported_character_scope'));
    expect(context.toPromptBlock(), isNot(contains('# 你是林埃')));
    expect(backend.characterLoads, 0);
  });
}

CharacterModel _legacyCharacter() => CharacterModel(
      id: 'i',
      name: 'I',
      tags: const ['primary'],
      persona: 'LEGACY_PERSONA_SHOULD_NOT_APPEAR',
      enabled: true,
      systemPromptOverride: 'LEGACY_SYSTEM_OVERRIDE_SHOULD_NOT_APPEAR',
      postHistoryInstructions: 'LEGACY_POST_HISTORY_SHOULD_NOT_APPEAR',
      mesExample: 'LEGACY_STYLE_EXAMPLE_SHOULD_NOT_APPEAR',
    );

WorkbenchRecentRelationshipMessage _message(
  int id,
  bool isFromCharacter,
  String content,
) =>
    WorkbenchRecentRelationshipMessage(
      id: id,
      isFromCharacter: isFromCharacter,
      content: content,
      timestamp: DateTime.utc(2026, 8, 26, 10, id),
    );

class _FakeRelationshipBackend implements WorkbenchRelationshipContextBackend {
  _FakeRelationshipBackend({
    this.character,
    this.recentMessages = const [],
    this.dreaming = const WorkbenchDreamingRecall(),
    this.failCharacter = false,
    this.failRecent = false,
    this.failDreaming = false,
  });

  final CharacterModel? character;
  final List<WorkbenchRecentRelationshipMessage> recentMessages;
  final WorkbenchDreamingRecall dreaming;
  final bool failCharacter;
  final bool failRecent;
  final bool failDreaming;
  int characterLoads = 0;
  int dreamingLoads = 0;
  String? lastCharacterId;
  String? lastQuery;

  @override
  Future<CharacterModel?> loadCharacter(String characterId) async {
    characterLoads++;
    lastCharacterId = characterId;
    if (failCharacter) throw StateError('character backend unavailable');
    return character;
  }

  @override
  Future<WorkbenchDreamingRecall> loadDreaming({
    required String characterId,
    required String query,
    required int episodeLimit,
    required int fragmentLimit,
    required int sagaLimit,
  }) async {
    dreamingLoads++;
    lastCharacterId = characterId;
    lastQuery = query;
    if (failDreaming) throw StateError('dreaming backend unavailable');
    return dreaming;
  }

  @override
  Future<List<WorkbenchRecentRelationshipMessage>> loadRecentMessages({
    required String characterId,
    required int limit,
  }) async {
    lastCharacterId = characterId;
    if (failRecent) throw StateError('recent backend unavailable');
    return recentMessages.take(limit).toList(growable: false);
  }
}
