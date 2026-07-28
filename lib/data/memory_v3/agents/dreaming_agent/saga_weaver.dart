/// V3 Saga weaver — Deep Dreaming agent.
///
/// Pure analysis layer: assembles episode summaries + existing sagas into
/// prompt context, calls the caller-supplied LLM, and parses JSON into
/// [SagaWeavingResult]. Persistence lives in
/// services/dreaming_orchestrator_service.dart.
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/memory_v3/models/saga_weaving.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

import 'llm_json_repair.dart';
import 'saga_prompt.dart';

final _logger = getLogger('memory_v3.SagaWeaver');

class SagaWeaverV3 {
  const SagaWeaverV3();

  /// Weave active episodes into long-term sagas.
  ///
  /// [episodes] — the pool of active episodes to consider.
  /// [existingSagas] — current active sagas (for incremental update).
  ///
  /// Returns [SagaWeavingResult] with new/updated saga drafts.
  Future<SagaWeavingResult> weave({
    required LLMClient client,
    required ModelConfig modelConfig,
    required List<MemoryEpisode> episodes,
    List<MemorySaga> existingSagas = const [],
  }) async {
    if (episodes.length < 3) {
      return SagaWeavingResult(
        sagas: const [],
        skippedReasons: ['need ≥3 episodes, got ${episodes.length}'],
      );
    }

    final episodeInputs = episodes
        .map((ep) => {
              'id': ep.id,
              'narrative': ep.narrative,
              'topicId': ep.topicId,
              'significance': ep.significance,
              'valence': ep.valence,
              'arousal': ep.arousal,
              'occurredAtRange': ep.occurredAtRange != null
                  ? jsonDecode(ep.occurredAtRange!)
                  : null,
              'createdAt': DateTime.fromMillisecondsSinceEpoch(ep.createdAt)
                  .toIso8601String(),
            })
        .toList();

    final sagaInputs = existingSagas
        .map((s) => {
              'id': s.id,
              'title': s.title,
              'description': s.description,
              'episodeIds': jsonDecode(s.episodeIds),
              'emotionalAxis': jsonDecode(s.emotionalAxis),
            })
        .toList();

    final payload = <String, dynamic>{
      'episodeCount': episodes.length,
      'episodes': episodeInputs,
      if (sagaInputs.isNotEmpty) 'existingSagas': sagaInputs,
    };

    final systemPrompt = sagaWeaverSystemPromptV3();

    final requestMessages = [
      SystemMessage(systemPrompt),
      UserMessage([TextPart(jsonEncode(payload))]),
    ];
    final extra = Map<String, dynamic>.from(modelConfig.extra ?? {});
    extra['thinking'] = {'type': 'disabled'};
    final mc = ModelConfig(
      model: modelConfig.model,
      maxTokens: 8192,
      extra: extra,
    );

    final firstText =
        (await client.generate(requestMessages, modelConfig: mc)).textOutput;
    if (firstText == null || firstText.trim().isEmpty) {
      throw const FormatException('Saga Weaver returned no output');
    }
    try {
      return _parse(firstText);
    } on FormatException catch (e) {
      _logger.warning('Saga parse failed ($e). Retrying.');
    }

    // Retry once with stricter instruction.
    final retryMessages = [
      SystemMessage(systemPrompt),
      UserMessage([
        TextPart(jsonEncode(payload)),
        TextPart(
          'STRICT: Reply with ONLY a single JSON object. '
          'First char must be "{". No markdown fences.',
        ),
      ]),
    ];
    final retryText =
        (await client.generate(retryMessages, modelConfig: mc)).textOutput;
    if (retryText == null || retryText.trim().isEmpty) {
      throw const FormatException('Saga Weaver retry empty');
    }
    try {
      return _parse(retryText);
    } on FormatException {
      final snippet =
          retryText.length > 400 ? retryText.substring(0, 400) : retryText;
      throw FormatException(
        'Saga Weaver invalid JSON after retry: $snippet',
      );
    }
  }

  SagaWeavingResult _parse(String raw) {
    var trimmed = raw.trim();
    // Strip <think> tags if present.
    trimmed = trimmed.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final unclosedThink = trimmed.indexOf('<think>');
    if (unclosedThink >= 0) {
      final braceAfter = trimmed.indexOf('{', unclosedThink);
      trimmed = braceAfter >= 0 ? trimmed.substring(braceAfter) : '';
    }

    // Strip markdown fences.
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
      throw const FormatException('Saga Weaver response contains no JSON');
    }
    var jsonPart = trimmed.substring(start, end + 1);
    jsonPart = repairLlmJson(jsonPart);
    final decoded = jsonDecode(jsonPart);
    if (decoded is! Map) {
      throw const FormatException('Saga Weaver JSON root must be an object');
    }
    final map = decoded.cast<String, dynamic>();

    final skipReason = map['skip_reason'] as String?;
    if (skipReason != null && skipReason.isNotEmpty) {
      _logger.info('Saga Weaver skipped: $skipReason');
      return SagaWeavingResult(
        sagas: const [],
        skippedReasons: [skipReason],
      );
    }

    final sagaList = map['sagas'] as List<dynamic>?;
    if (sagaList == null || sagaList.isEmpty) {
      return SagaWeavingResult(
        sagas: const [],
        skippedReasons: ['LLM returned no sagas'],
      );
    }

    final sagas = <SagaWeavingDraft>[];
    final rejected = <String>[];

    for (final s in sagaList) {
      final sm = s as Map<String, dynamic>;
      final title = (sm['title'] as String? ?? '').trim();
      final description = (sm['description'] as String? ?? '').trim();
      final episodeIds =
          (sm['episodeIds'] as List?)?.cast<String>() ?? const [];

      // Quality gates.
      if (title.isEmpty || title.length > 30) {
        rejected.add('title empty or >30 chars');
        continue;
      }
      if (description.length < 50) {
        rejected.add('description too short (<50 chars): $title');
        continue;
      }
      if (description.length > 600) {
        rejected.add('description too long (>600 chars): $title');
        continue;
      }
      if (episodeIds.length < 2) {
        rejected.add('fewer than 2 episode refs: $title');
        continue;
      }
      if (_looksAbstractDiagnosis(description)) {
        rejected.add('abstract diagnosis: $title');
        continue;
      }

      final axisRaw = sm['emotionalAxis'] as Map<String, dynamic>? ?? {};
      final axis = SagaEmotionalAxis.fromJson(axisRaw);

      sagas.add(SagaWeavingDraft(
        title: title,
        description: description,
        episodeIds: episodeIds,
        emotionalAxis: axis,
        existingSagaId: (sm['existingSagaId'] as String?)?.trim(),
      ));
    }

    if (rejected.isNotEmpty) {
      _logger.info(
        'Saga Weaver rejected ${rejected.length} candidate(s): '
        '${rejected.join('; ')}',
      );
    }

    return SagaWeavingResult(
      sagas: sagas,
      skippedReasons: rejected,
    );
  }

  bool _looksAbstractDiagnosis(String description) {
    const abstractPhrases = [
      '依恋模式',
      '依恋类型',
      '人格特质',
      '心理防御机制',
      '自我认知发生',
      '关系动态发生',
      '内在需求转变',
      '说明她本质',
      '证明她是',
    ];
    return abstractPhrases.any(description.contains);
  }
}
