/// V3 Episode consolidator.
///
/// Pure analysis layer: assembles fragment summaries into prompt context,
/// calls the caller-supplied LLM (MAIN model), and parses JSON into
/// [EpisodeConsolidationResult]. Persistence lives in
/// services/dreaming_orchestrator_service.dart.
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/models/episode_consolidation.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

import 'episode_prompt.dart';

final _logger = getLogger('memory_v3.EpisodeConsolidator');

class EpisodeConsolidatorV3 {
  const EpisodeConsolidatorV3();

  EpisodeConsolidationResult parseForTest(String raw) {
    return _parseAll(raw);
  }

  /// Condense ALL active fragments into episodes, letting the LLM group
  /// related ones by topic. Entity-agnostic — works without entity links.
  Future<EpisodeConsolidationResult> consolidateAll({
    required LLMClient client,
    required ModelConfig modelConfig,
    required List<MemoryFragment> fragments,
  }) async {
    if (fragments.length < 2) {
      return EpisodeConsolidationResult(
        episodes: const [],
        skippedEntityIds: ['need ≥2 fragments, got ${fragments.length}'],
        isDryRun: false,
      );
    }

    final fragmentInputs = fragments
        .map((f) => {
              'id': f.id,
              'content': f.content,
              'emotionalWeight': f.emotionalWeight,
              'createdAt': DateTime.fromMillisecondsSinceEpoch(f.createdAt)
                  .toIso8601String(),
            })
        .toList();

    final payload = <String, dynamic>{
      'fragmentCount': fragments.length,
      'fragments': fragmentInputs,
    };

    final systemPrompt = episodeConsolidatorAllSystemPromptV3();

    final requestMessages = [
      SystemMessage(systemPrompt),
      UserMessage([TextPart(jsonEncode(payload))]),
    ];
    final extraAll = Map<String, dynamic>.from(modelConfig.extra ?? {});
    extraAll['thinking'] = {'type': 'disabled'};
    final mc = ModelConfig(
      model: modelConfig.model,
      maxTokens: 8192,
      extra: extraAll,
    );

    final firstText =
        (await client.generate(requestMessages, modelConfig: mc)).textOutput;
    if (firstText == null || firstText.trim().isEmpty) {
      throw const FormatException('Episode Consolidator returned no output');
    }
    try {
      return _parseAll(firstText);
    } on FormatException catch (e) {
      _logger.warning('Episode parse failed ($e). Retrying.');
    }

    // Retry once
    final retryMessages = [
      SystemMessage(systemPrompt),
      UserMessage([
        TextPart(jsonEncode(payload)),
        TextPart(
          'STRICT: Reply with ONLY a single JSON object. '
          'First char must be "{". Each narrative must start with '
          '"我记得", "我知道", "我注意到", or "我后来记住".',
        ),
      ]),
    ];
    final retryText =
        (await client.generate(retryMessages, modelConfig: mc)).textOutput;
    if (retryText == null || retryText.trim().isEmpty) {
      throw const FormatException('Episode Consolidator retry empty');
    }
    try {
      return _parseAll(retryText);
    } on FormatException {
      final snippet =
          retryText.length > 400 ? retryText.substring(0, 400) : retryText;
      throw FormatException(
        'Episode Consolidator invalid JSON after retry: $snippet',
      );
    }
  }

  /// Try to condense fragments for one entity into an episode.
  ///
  /// Returns [EpisodeConsolidationResult] with up to 2 episodes (split when
  /// fragments clearly describe distinct events). Returns empty result when
  /// the LLM judges the fragments too scattered or trivial to condense.
  Future<EpisodeConsolidationResult> consolidate({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String entityId,
    required String entityName,
    required String entityCategory,
    required List<MemoryFragment> fragments,
  }) async {
    if (fragments.length < 3) {
      return EpisodeConsolidationResult(
        episodes: const [],
        skippedEntityIds: [entityId],
        isDryRun: false,
      );
    }

    final fragmentInputs = fragments
        .map((f) => {
              'id': f.id,
              'content': f.content,
              'emotionalWeight': f.emotionalWeight,
              'createdAt': DateTime.fromMillisecondsSinceEpoch(f.createdAt)
                  .toIso8601String(),
            })
        .toList();

    final payload = <String, dynamic>{
      'entity': {
        'id': entityId,
        'name': entityName,
        'category': entityCategory,
      },
      'fragmentCount': fragments.length,
      'fragments': fragmentInputs,
    };

    final systemPrompt = episodeConsolidatorSystemPromptV3(
      entityName: entityName,
      entityCategory: entityCategory,
    );

    final requestMessages = [
      SystemMessage(systemPrompt),
      UserMessage([TextPart(jsonEncode(payload))]),
    ];
    final extraPerEntity = Map<String, dynamic>.from(modelConfig.extra ?? {});
    extraPerEntity['thinking'] = {'type': 'disabled'};
    final mc = ModelConfig(
      model: modelConfig.model,
      maxTokens: 4096,
      extra: extraPerEntity,
    );

    final firstText =
        (await client.generate(requestMessages, modelConfig: mc)).textOutput;
    if (firstText == null || firstText.trim().isEmpty) {
      throw const FormatException('Episode Consolidator returned no output');
    }
    try {
      return _parse(firstText, entityId);
    } on FormatException catch (e) {
      final snippet =
          firstText.length > 300 ? firstText.substring(0, 300) : firstText;
      _logger.warning(
        'Episode parse failed ($e). Retrying. Raw (first 300): $snippet',
      );
    }

    // Retry once
    final retryMessages = [
      SystemMessage(systemPrompt),
      UserMessage([
        TextPart(jsonEncode(payload)),
        TextPart(
          'STRICT: Reply with ONLY a single JSON object. '
          'No markdown fences, no commentary. First char must be "{". '
          'Each narrative must start with "我记得", "我知道", '
          '"我注意到", or "我后来记住".',
        ),
      ]),
    ];
    final retryText =
        (await client.generate(retryMessages, modelConfig: mc)).textOutput;
    if (retryText == null || retryText.trim().isEmpty) {
      throw const FormatException(
        'Episode Consolidator retry returned no output',
      );
    }
    try {
      return _parse(retryText, entityId);
    } on FormatException {
      final snippet =
          retryText.length > 400 ? retryText.substring(0, 400) : retryText;
      _logger.severe(
        'Episode retry parse also failed. Raw (first 400): $snippet',
      );
      throw FormatException(
        'Episode Consolidator returned invalid JSON after retry. '
        'Raw: $snippet',
      );
    }
  }

  EpisodeConsolidationResult _parseAll(String raw) {
    return _parse(raw, '__all__');
  }

  EpisodeConsolidationResult _parse(String raw, String entityId) {
    var trimmed = raw.trim();
    trimmed = trimmed.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final unclosedThink = trimmed.indexOf('<think>');
    if (unclosedThink >= 0) {
      final braceAfter = trimmed.indexOf('{', unclosedThink);
      trimmed = braceAfter >= 0 ? trimmed.substring(braceAfter) : '';
    }

    var fenceMatch = RegExp(
      r'^```(?:json|JSON)?\s*\n([\s\S]*?)\n```\s*$',
    ).firstMatch(trimmed);
    fenceMatch ??= RegExp(
      r'```(?:json|JSON)?\s*\n([\s\S]*?)\n```',
    ).firstMatch(trimmed);
    if (fenceMatch != null) {
      trimmed = fenceMatch.group(1)!.trim();
    }

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException(
        'Episode Consolidator response contains no JSON',
      );
    }
    var jsonPart = trimmed.substring(start, end + 1);
    jsonPart = jsonPart.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
    jsonPart = jsonPart.replaceAll(',,', ',');
    final decoded = jsonDecode(jsonPart);
    if (decoded is! Map) {
      throw const FormatException(
        'Episode Consolidator JSON root must be an object',
      );
    }
    final map = decoded.cast<String, dynamic>();

    final skipReason = map['skip_reason'] as String?;
    if (skipReason != null && skipReason.isNotEmpty) {
      _logger
          .info('Episode Consolidator skipped entity $entityId: $skipReason');
      return EpisodeConsolidationResult(
        episodes: const [],
        skippedEntityIds: [entityId],
        isDryRun: false,
      );
    }

    final episodeList = map['episodes'] as List<dynamic>?;
    if (episodeList == null || episodeList.isEmpty) {
      return EpisodeConsolidationResult(
        episodes: const [],
        skippedEntityIds: [entityId],
        isDryRun: false,
      );
    }

    final episodes = <EpisodeConsolidationDraft>[];
    final invalidNarratives = <String>[];
    for (final e in episodeList) {
      final em = e as Map<String, dynamic>;
      final narrative = (em['narrative'] as String).trim();
      if (!_isFirstPersonRelationshipNarrative(narrative)) {
        invalidNarratives.add(narrative);
        continue;
      }
      final topicId = ((em['topicId'] as String?) ??
              (em['primaryEntityId'] as String?) ??
              '')
          .trim();
      final primaryEntityId = entityId == '__all__'
          ? ((em['primaryEntityId'] as String?)?.trim() ?? '')
          : entityId;
      episodes.add(EpisodeConsolidationDraft(
        narrative: narrative,
        topicId: topicId.isNotEmpty ? topicId : '__ungrouped__',
        primaryEntityId: primaryEntityId,
        sourceFragmentIds: (em['sourceFragmentIds'] as List).cast<String>(),
        significance: em['significance'] as int,
        confidence: em['confidence'] as String,
        valence: (em['valence'] as num).toDouble(),
        arousal: (em['arousal'] as num).toDouble(),
        occurredAtStart: (em['occurredAtRange']
            as Map<String, dynamic>?)?['start'] as String?,
        occurredAtEnd:
            (em['occurredAtRange'] as Map<String, dynamic>?)?['end'] as String?,
        linkedEntityIds:
            (em['linkedEntityIds'] as List?)?.cast<String>() ?? const [],
      ));
    }

    if (episodes.isEmpty && invalidNarratives.isNotEmpty) {
      throw FormatException(
        'Episode narratives were not first-person memories: '
        '${invalidNarratives.first}',
      );
    }
    if (invalidNarratives.isNotEmpty) {
      _logger.info(
        'Dropped ${invalidNarratives.length} episode(s) with non-first-person '
        'narrative style',
      );
    }

    return EpisodeConsolidationResult(
      episodes: episodes,
      skippedEntityIds: const [],
      isDryRun: false,
    );
  }

  bool _isFirstPersonRelationshipNarrative(String narrative) {
    if (narrative.isEmpty || narrative.startsWith('她')) {
      return false;
    }
    const allowedStarts = ['我记得', '我知道', '我注意到', '我后来记住'];
    return allowedStarts.any(narrative.startsWith) && narrative.contains('她');
  }
}
