import 'package:memex/agent/record_organizer_agent/record_organizer_analyzer.dart';
import 'package:memex/data/services/domain_schema_validator.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Result from a [RecordOrganizerService] call.
class RecordResult {
  const RecordResult({
    required this.entityIds,
    required this.entityTitles,
    required this.isEmpty,
  });

  final List<String> entityIds;
  final List<String> entityTitles;
  final bool isEmpty;
}

/// Handles explicit user recording requests — the only authorized path for
/// writing User-truth outside of companion tool-calls.
///
/// Sources: message-level record button, floating ball, natural language
/// "记一下", external data imports.
///
/// This service does NOT auto-capture conversation content. It only processes
/// content the user has intentionally flagged for recording.
class RecordOrganizerService {
  RecordOrganizerService(this._memory);

  final SharedLifeMemoryService _memory;
  static final _logger = getLogger('RecordOrganizerService');

  static RecordOrganizerService? _instance;

  static RecordOrganizerService get instance {
    if (_instance == null) {
      throw StateError('RecordOrganizerService has not been initialized');
    }
    return _instance!;
  }

  static bool get isInitialized => _instance != null;

  static void init(SharedLifeMemoryService memory) {
    _instance = RecordOrganizerService(memory);
  }

  static void reset() => _instance = null;

  /// Record a single chat message the user explicitly flagged via the record button.
  ///
  /// [sourceCharacterId]: the character whose chat session the message came from.
  /// [messageId]: the database ID of the PersonaChatMessage.
  /// [content]: the message text.
  Future<RecordResult> recordFromMessage({
    required String userId,
    required String sourceCharacterId,
    required int messageId,
    required String content,
  }) async {
    return _organize(
      userId: userId,
      sourceCharacterId: sourceCharacterId,
      rawInput: content,
      sourceKind: 'record_button',
      sourceRef: messageId.toString(),
    );
  }

  /// Record arbitrary text input (e.g., from the floating ball quick-save).
  Future<RecordResult> recordFromText({
    required String userId,
    required String sourceCharacterId,
    required String text,
    String sourceKind = 'floating_ball',
  }) async {
    return _organize(
      userId: userId,
      sourceCharacterId: sourceCharacterId,
      rawInput: text,
      sourceKind: sourceKind,
    );
  }

  Future<RecordResult> _organize({
    required String userId,
    required String sourceCharacterId,
    required String rawInput,
    required String sourceKind,
    String? sourceRef,
  }) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const RecordResult(entityIds: [], entityTitles: [], isEmpty: true);
    }

    // Load known tags and relevant entities for context
    final tagsData = await FileSystemService.instance.readTagsFile(userId);
    final knownTags = tagsData
        .map((t) => t['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);

    final relevantEntities = await _memory.queryRelevantEntities(
      trimmed,
      limit: 6,
    );

    // Call LLM
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.recordOrganizerAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );

    RecordOrganizerAnalysis analysis;
    try {
      analysis = await const RecordOrganizerAnalyzer().analyze(
        client: resources.client,
        modelConfig: resources.modelConfig,
        rawInput: trimmed,
        sourceKind: sourceKind,
        knownTags: knownTags,
        relevantEntities: relevantEntities,
        now: DateTime.now(),
      );
    } catch (e) {
      _logger.warning('RecordOrganizerAnalyzer failed: $e');
      return const RecordResult(entityIds: [], entityTitles: [], isEmpty: true);
    }

    if (analysis.isEmpty) {
      _logger.info('RecordOrganizer: no entities extracted from input');
      return const RecordResult(entityIds: [], entityTitles: [], isEmpty: true);
    }

    // Validate and normalize each operation's patch against its domain schema
    const validator = DomainSchemaValidator();
    final schemaValidatedOps = analysis.operations.map((op) {
      final domain = (op.patch['_primaryDomain'] as String?) ?? 'general';
      final normalized = validator.validate(domain, op.patch).normalizedPatch;
      return SharedLifeOperationDraft(
        operationType: op.operationType,
        entityType: op.entityType,
        title: op.title,
        patch: normalized,
        sourceKind: op.sourceKind,
        sourceRef: op.sourceRef,
        rawInput: op.rawInput,
        entityId: op.entityId,
      );
    }).toList(growable: false);

    // Restrict tags to known vocabulary
    final validatedOps = _restrictTagsToKnownTags(
      schemaValidatedOps,
      knownTags: knownTags,
    );

    final result = await _memory.applyDirectOperations(
      sourceCharacterId: sourceCharacterId,
      operations: validatedOps,
    );

    final allEntityIds = result.entityIds;
    final allTitles = result.entityTitles;

    if (allEntityIds.isNotEmpty) {
      EventBusService.instance.emitEvent(
        ConversationCaptureRememberedMessage(
          characterId: sourceCharacterId,
          operationIds: [],
          entityTitles: allTitles,
        ),
      );
      _logger.info(
          'RecordOrganizer: recorded ${allEntityIds.length} entity(ies): ${allTitles.join(', ')}');
    }

    return RecordResult(
      entityIds: allEntityIds,
      entityTitles: allTitles,
      isEmpty: allEntityIds.isEmpty,
    );
  }
}

List<SharedLifeOperationDraft> _restrictTagsToKnownTags(
  List<SharedLifeOperationDraft> ops, {
  required List<String> knownTags,
}) {
  if (knownTags.isEmpty) return ops;
  final canonical = {
    for (final tag in knownTags)
      if (tag.isNotEmpty) tag.toLowerCase(): tag,
  };
  return ops.map((op) {
    final patch = Map<String, dynamic>.from(op.patch);
    final rawTags = patch['tags'];
    if (rawTags is List) {
      final filtered = rawTags
          .map((t) => canonical[t.toString().trim().toLowerCase()])
          .whereType<String>()
          .toSet()
          .take(3)
          .toList();
      if (filtered.isEmpty) {
        patch.remove('tags');
      } else {
        patch['tags'] = filtered;
      }
    } else {
      patch.remove('tags');
    }
    return SharedLifeOperationDraft(
      operationType: op.operationType,
      entityType: op.entityType,
      title: op.title,
      patch: patch,
      sourceKind: op.sourceKind,
      sourceRef: op.sourceRef,
      rawInput: op.rawInput,
      entityId: op.entityId,
    );
  }).toList(growable: false);
}
