/// V3 Dreaming orchestration service.
///
/// First MVP slice: read persona chat messages after a per-character
/// watermark, run Fragment extraction, and persist automatic fragments plus
/// seed entity links. Episode/Saga consolidation is intentionally left for
/// later slices.
library;

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/agents/dreaming_agent/fragment_extractor.dart';
import 'package:memex/data/memory_v3/models/dreaming_fragment.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

final _logger = getLogger('memory_v3.DreamingOrchestratorService');

class DreamingFragmentPersistResult {
  DreamingFragmentPersistResult({
    required this.fragmentIds,
    required this.entityIds,
    required this.processedMessageCount,
    required this.lastProcessedMessageId,
    required this.isEmpty,
  });

  final List<String> fragmentIds;
  final List<String> entityIds;
  final int processedMessageCount;
  final int lastProcessedMessageId;
  final bool isEmpty;
}

class DreamingOrchestratorServiceV3 {
  DreamingOrchestratorServiceV3(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _bucket = 'memory_v3.dreaming';
  static const _extractorVersion = 'dreaming.fragment_extractor.v3.0';

  static DreamingOrchestratorServiceV3? _instance;

  static DreamingOrchestratorServiceV3 get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError(
        'DreamingOrchestratorServiceV3 has not been initialized. Call init() first.',
      );
    }
    return inst;
  }

  static bool get isInitialized => _instance != null;

  static void init(AppDatabase db) {
    _instance = DreamingOrchestratorServiceV3(db);
  }

  static void reset() => _instance = null;

  /// Run one bounded Daily Dreaming fragment extraction batch for a character.
  ///
  /// The batch is capped to V3 § 10.4's 60-message limit. This method does not
  /// decide charging/Wi-Fi/idle policy; callers should invoke it only when the
  /// environment is appropriate.
  Future<DreamingFragmentPersistResult> runDailyFragmentBatch({
    required String characterId,
    required LLMClient client,
    required ModelConfig modelConfig,
    int batchSize = 60,
    String sourceScope = 'main_chat',
    DreamingFragmentExtractorV3 agent = const DreamingFragmentExtractorV3(),
  }) async {
    final cappedBatchSize = batchSize.clamp(1, 60).toInt();
    final lastMessageId = await _readWatermark(characterId);
    final rows = await (_db.select(_db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.id.isBiggerThanValue(lastMessageId) &
              t.content.isNotValue('') &
              t.messageType.equals('chat'))
          ..orderBy([
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(cappedBatchSize))
        .get();

    if (rows.isEmpty) {
      return DreamingFragmentPersistResult(
        fragmentIds: const [],
        entityIds: const [],
        processedMessageCount: 0,
        lastProcessedMessageId: lastMessageId,
        isEmpty: true,
      );
    }

    final inputs = rows
        .map((row) => DreamingChatMessageInput(
              id: row.id,
              isFromCharacter: row.isFromCharacter,
              content: row.content,
              timestamp: row.timestamp,
              messageType: row.messageType,
            ))
        .toList(growable: false);
    final existing = await _recentFragmentSummaries();
    final extracted = await agent.extract(
      client: client,
      modelConfig: modelConfig,
      messages: inputs,
      now: DateTime.now(),
      existingFragmentSummaries: existing,
    );
    final result = await persistFragments(
      extraction: extracted,
      processedMessageCount: rows.length,
      lastProcessedMessageId: rows.last.id,
      sourceScope: sourceScope,
    );
    await _writeWatermark(characterId, rows.last.id);
    return result;
  }

  /// Persist already-extracted Dreaming fragments.
  ///
  /// This is useful for tests and for future schedulers that may split LLM
  /// extraction from storage.
  Future<DreamingFragmentPersistResult> persistFragments({
    required DreamingFragmentExtraction extraction,
    required int processedMessageCount,
    required int lastProcessedMessageId,
    String sourceScope = 'main_chat',
  }) async {
    if (extraction.isEmpty) {
      return DreamingFragmentPersistResult(
        fragmentIds: const [],
        entityIds: const [],
        processedMessageCount: processedMessageCount,
        lastProcessedMessageId: lastProcessedMessageId,
        isEmpty: true,
      );
    }

    return _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existingKeys = await _existingFragmentKeys();
      final seenThisBatch = <String>{};
      final fragmentIds = <String>[];
      final entityIds = <String>[];

      for (final draft in extraction.fragments) {
        final key = _dedupeKey(draft.content);
        if (key.isEmpty ||
            existingKeys.contains(key) ||
            seenThisBatch.contains(key) ||
            draft.sourceMessageIds.isEmpty) {
          continue;
        }
        final sourceMessages = await _sourceMessagesFor(draft.sourceMessageIds);
        if (!_passesRelationshipEvidenceGuard(draft, sourceMessages)) {
          continue;
        }
        seenThisBatch.add(key);

        final fragmentId = _uuid.v4();
        fragmentIds.add(fragmentId);
        await _db.into(_db.memoryFragments).insert(
              MemoryFragmentsCompanion.insert(
                id: fragmentId,
                content: draft.content,
                sourceMessageIds: Value(jsonEncode(draft.sourceMessageIds)),
                sourceScope: Value(draft.sourceScope.isNotEmpty
                    ? draft.sourceScope
                    : sourceScope),
                emotionalWeight: Value(draft.emotionalWeight),
                isUserTruthCandidate: Value(draft.isUserTruthCandidate),
                generatedByVersion: const Value(_extractorVersion),
                createdAt: now,
              ),
            );

        for (final link in draft.entityLinks) {
          final entityId = await _resolveDreamingEntity(link, now: now);
          entityIds.add(entityId);
          await _db.into(_db.memoryEntityLinks).insert(
                MemoryEntityLinksCompanion.insert(
                  id: _uuid.v4(),
                  sourceTable: 'memory_fragments',
                  sourceId: fragmentId,
                  entityId: entityId,
                  relation: link.relation,
                  confidence: Value(link.confidence),
                  createdAt: now,
                ),
              );
        }
      }

      _logger.info(
        'Persisted ${fragmentIds.length} Dreaming fragment(s); '
        '${entityIds.toSet().length} linked entity/entities',
      );

      return DreamingFragmentPersistResult(
        fragmentIds: fragmentIds,
        entityIds: entityIds.toSet().toList(),
        processedMessageCount: processedMessageCount,
        lastProcessedMessageId: lastProcessedMessageId,
        isEmpty: fragmentIds.isEmpty,
      );
    });
  }

  Future<int> _readWatermark(String characterId) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) =>
              t.key.equals(_watermarkKey(characterId)) &
              t.bucket.equals(_bucket)))
        .getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _writeWatermark(String characterId, int messageId) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _watermarkKey(characterId),
            value: Value('$messageId'),
            bucket: const Value(_bucket),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  String _watermarkKey(String characterId) =>
      'dreaming.fragment.last_message_id.$characterId';

  Future<List<String>> _recentFragmentSummaries({int limit = 120}) async {
    final rows = await (_db.select(_db.memoryFragments)
          ..where((t) => t.status.isNotIn(const ['deleted']))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
          ])
          ..limit(limit))
        .get();
    return rows.map((row) => row.content).toList(growable: false);
  }

  Future<Set<String>> _existingFragmentKeys() async {
    final rows = await (_db.select(_db.memoryFragments)
          ..where((t) => t.status.isNotIn(const ['deleted'])))
        .get();
    return rows.map((row) => _dedupeKey(row.content)).toSet();
  }

  String _dedupeKey(String content) =>
      content.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  Future<List<PersonaChatMessage>> _sourceMessagesFor(List<int> ids) async {
    final result = <PersonaChatMessage>[];
    for (final id in ids.toSet()) {
      final row = await (_db.select(_db.personaChatMessages)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row != null) {
        result.add(row);
      }
    }
    return result;
  }

  bool _passesRelationshipEvidenceGuard(
    DreamingFragmentDraft draft,
    List<PersonaChatMessage> sourceMessages,
  ) {
    final content = draft.content.trim();
    if (content.isEmpty || sourceMessages.isEmpty) {
      _logger.info('Rejected Dreaming fragment with missing source evidence');
      return false;
    }
    if (content.contains('用户') || content.contains('对方')) {
      _logger.info('Rejected Dreaming fragment with system/vague subject: '
          '$content');
      return false;
    }
    if (_containsRuntimeError(content) ||
        sourceMessages.any((m) => _containsRuntimeError(m.content))) {
      _logger.info('Rejected Dreaming fragment sourced from runtime error: '
          '$content');
      return false;
    }
    if (_looksLikeBarePsychDoctorJoke(draft, sourceMessages)) {
      _logger.info('Rejected Dreaming fragment: bare psych-doctor joke: '
          '$content');
      return false;
    }
    if (_addsUnsupportedCounselingConclusion(draft, sourceMessages)) {
      _logger.info('Rejected Dreaming fragment: unsupported counseling '
          'conclusion: $content');
      return false;
    }
    return true;
  }

  bool _containsRuntimeError(String text) {
    return text.contains('Connection interrupted') ||
        text.contains('AgentException') ||
        text.contains('model_not_found') ||
        text.contains('503 Service Unavailable');
  }

  bool _looksLikeBarePsychDoctorJoke(
    DreamingFragmentDraft draft,
    List<PersonaChatMessage> sourceMessages,
  ) {
    final content = draft.content;
    if (!content.contains('心理医生')) return false;

    final userTexts = sourceMessages
        .where((m) => !m.isFromCharacter)
        .map((m) => _compactChinese(m.content))
        .toList(growable: false);
    final hasBareReply = userTexts.any((text) =>
        RegExp(r'^(嗯+|嗯嗯|哈哈|哈|行|好)?，?心理医生来了[。！!～~]*$').hasMatch(text));
    if (!hasBareReply) return false;

    const explicitLifeCues = [
      '预约',
      '咨询',
      '复诊',
      '治疗',
      '见心理医生',
      '我的心理医生',
      '心理咨询',
      '医生到了',
      '到了医院',
    ];
    return !userTexts.any(
      (text) => explicitLifeCues.any(text.contains),
    );
  }

  bool _addsUnsupportedCounselingConclusion(
    DreamingFragmentDraft draft,
    List<PersonaChatMessage> sourceMessages,
  ) {
    final content = draft.content;
    if (!content.contains('心理医生') &&
        !content.contains('心理咨询') &&
        !content.contains('咨询')) {
      return false;
    }
    const conclusionCues = [
      '刚结束',
      '结束咨询',
      '刚做完',
      '刚咨询',
      '心理咨询',
    ];
    if (!conclusionCues.any(content.contains)) return false;

    final sourceText = sourceMessages.map((m) => m.content).join('\n');
    return !conclusionCues.any(sourceText.contains);
  }

  String _compactChinese(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('，', ',')
        .replaceAll(',', '，')
        .trim();
  }

  Future<String> _resolveDreamingEntity(
    DreamingEntityLinkDraft link, {
    required int now,
  }) async {
    final existing = await (_db.select(_db.memoryEntities)
          ..where((t) =>
              t.name.lower().equals(link.name.toLowerCase()) &
              t.status.isNotIn(const ['deleted', 'merged'])))
        .getSingleOrNull();

    if (existing != null) {
      final nextCount = existing.fragmentCount + 1;
      final firstMentionedAt = existing.firstMentionedAt ?? now;
      final shouldPromote = existing.status == 'seed' &&
          nextCount >= 3 &&
          now - firstMentionedAt >= const Duration(days: 2).inMilliseconds;
      await (_db.update(_db.memoryEntities)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        MemoryEntitiesCompanion(
          lastMentionedAt: Value(now),
          firstMentionedAt: Value(firstMentionedAt),
          fragmentCount: Value(nextCount),
          status: shouldPromote ? const Value('active') : const Value.absent(),
        ),
      );
      return existing.id;
    }

    final id = _uuid.v4();
    await _db.into(_db.memoryEntities).insert(
          MemoryEntitiesCompanion.insert(
            id: id,
            name: link.name,
            category: link.category,
            status: const Value('seed'),
            relationshipToUser: Value(link.relationshipToUser),
            firstMentionedAt: Value(now),
            lastMentionedAt: Value(now),
            fragmentCount: const Value(1),
            generatedByVersion: const Value(_extractorVersion),
          ),
        );
    return id;
  }
}
