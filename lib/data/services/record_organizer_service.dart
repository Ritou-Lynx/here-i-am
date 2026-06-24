import 'dart:convert';
import 'dart:io';

import 'package:memex/agent/built_in_tools/asset_analysis_tool.dart';
import 'package:memex/agent/record_organizer_agent/record_organizer_analyzer.dart';
import 'package:memex/data/services/domain_schema_validator.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/media_input_attachment.dart';
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
  /// [media]: pre-processed media attachments (saved + analyzed).
  Future<RecordResult> recordFromMessage({
    required String userId,
    required String sourceCharacterId,
    required int messageId,
    required String content,
    List<MediaInputAttachment>? media,
  }) async {
    final resolvedMedia = await _ensureMessageMedia(
      userId: userId,
      messageId: messageId,
      content: content,
      media: media,
    );
    return _organize(
      userId: userId,
      sourceCharacterId: sourceCharacterId,
      rawInput: content,
      sourceKind: 'record_button',
      sourceRef: messageId.toString(),
      sourceMessageIds: [messageId],
      media: resolvedMedia,
    );
  }

  /// Record arbitrary text input (e.g., from the floating ball quick-save).
  Future<RecordResult> recordFromText({
    required String userId,
    required String sourceCharacterId,
    required String text,
    String sourceKind = 'floating_ball',
    List<MediaInputAttachment>? media,
  }) async {
    return _organize(
      userId: userId,
      sourceCharacterId: sourceCharacterId,
      rawInput: text,
      sourceKind: sourceKind,
      media: media,
    );
  }

  Future<RecordResult> _organize({
    required String userId,
    required String sourceCharacterId,
    required String rawInput,
    required String sourceKind,
    String? sourceRef,
    List<int> sourceMessageIds = const [],
    List<MediaInputAttachment>? media,
  }) async {
    final trimmed = rawInput.trim();
    final usableMedia =
        (media ?? []).where((m) => m.isUsable).toList(growable: false);
    if (trimmed.isEmpty && usableMedia.isEmpty) {
      return const RecordResult(entityIds: [], entityTitles: [], isEmpty: true);
    }
    final mediaSearchText = _mediaSearchText(usableMedia);
    final relevantQuery = [trimmed, mediaSearchText]
        .where((part) => part.trim().isNotEmpty)
        .join('\n');
    final evidenceRawInput = _evidenceRawInput(trimmed, usableMedia);

    // Load known tags and relevant entities for context
    final tagsData = await FileSystemService.instance.readTagsFile(userId);
    final knownTags = tagsData
        .map((t) => t['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);

    final relevantEntities = await _memory.queryRelevantEntities(
      relevantQuery,
      limit: 6,
    );

    // Call LLM
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.recordOrganizerAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );

    // Build media context for the LLM from usable attachments
    final inputMedia = usableMedia
        .map((m) => <String, String>{
              'assetPath': m.savedRelativePath!,
              if (m.analysisText != null) 'analysis': m.analysisText!,
              'kind': m.kind,
            })
        .toList(growable: false);

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
        inputMedia: inputMedia.isNotEmpty ? inputMedia : null,
      );
    } catch (e) {
      _logger.warning('RecordOrganizerAnalyzer failed: $e');
      return const RecordResult(entityIds: [], entityTitles: [], isEmpty: true);
    }

    if (analysis.isEmpty) {
      if (usableMedia.isEmpty) {
        _logger.info('RecordOrganizer: no entities extracted from input');
        return const RecordResult(
            entityIds: [], entityTitles: [], isEmpty: true);
      }
      _logger.info(
          'RecordOrganizer: analyzer returned no entities; preserving media as a record');
    }

    final analyzedOps = analysis.isEmpty
        ? [_fallbackMediaOperation(trimmed, usableMedia)]
        : analysis.operations;

    // Validate and normalize each operation's patch against its domain schema
    const validator = DomainSchemaValidator();
    final schemaValidatedOps = analyzedOps.map((op) {
      final domain = (op.patch['_primaryDomain'] as String?) ?? 'general';
      final normalized = _ensureMediaBlocks(
        validator.validate(domain, op.patch).normalizedPatch,
        usableMedia,
      );
      return SharedLifeOperationDraft(
        operationType: op.operationType,
        entityType: op.entityType,
        title: op.title,
        patch: normalized,
        sourceKind: sourceKind,
        sourceRef: op.sourceRef ?? sourceRef,
        rawInput: evidenceRawInput,
        sourceMessageIds: sourceMessageIds,
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

  Future<List<MediaInputAttachment>?> _ensureMessageMedia({
    required String userId,
    required int messageId,
    required String content,
    List<MediaInputAttachment>? media,
  }) async {
    final current = media ?? const <MediaInputAttachment>[];
    if (current.any((m) => m.isUsable)) return media;

    final message = await (_memory.db.select(_memory.db.personaChatMessages)
          ..where((t) => t.id.equals(messageId)))
        .getSingleOrNull();
    final attachmentsJson = message?.attachmentsJson;
    if (attachmentsJson == null || attachmentsJson.trim().isEmpty) {
      return media;
    }

    final recovered = <MediaInputAttachment>[...current];
    try {
      final raw = jsonDecode(attachmentsJson);
      if (raw is! List) return media;

      final analyses = _extractImageAnalyses(content);
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map) continue;
        final attachment = Map<String, dynamic>.from(item);
        final mimeType = attachment['mimeType']?.toString() ?? '';
        if (!mimeType.startsWith('image/')) continue;
        final base64 = attachment['base64']?.toString();
        if (base64 == null || base64.isEmpty) continue;

        try {
          final saved = await _saveChatImageAttachment(
            userId: userId,
            messageId: messageId,
            index: i,
            mimeType: mimeType,
            base64: base64,
          );
          final analysisText = i < analyses.length
              ? analyses[i]
              : await _analyzeSavedImage(saved.absolutePath);
          recovered.add(MediaInputAttachment(
            savedRelativePath: saved.relativePath,
            analysisText: analysisText,
            kind: 'image',
          ));
        } catch (e) {
          _logger.warning(
              'RecordOrganizer: failed to recover image attachment for message $messageId: $e');
          recovered.add(MediaInputAttachment(error: e.toString()));
        }
      }
    } catch (e) {
      _logger.warning(
          'RecordOrganizer: failed to parse attachments for message $messageId: $e');
    }

    return recovered.isEmpty ? media : recovered;
  }

  Future<({String relativePath, String absolutePath})>
      _saveChatImageAttachment({
    required String userId,
    required int messageId,
    required int index,
    required String mimeType,
    required String base64,
  }) async {
    final bytes = base64Decode(base64);
    final ext = _imageExtensionForMime(mimeType);
    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'record_${messageId}_${DateTime.now().microsecondsSinceEpoch}_$index.$ext',
    );
    await tempFile.writeAsBytes(bytes);
    try {
      final (_, relativePath) =
          await FileSystemService.instance.saveAssetFromFile(
        userId: userId,
        sourcePath: tempFile.path,
        assetType: 'img',
        index: index + 1,
        format: ext,
      );
      return (
        relativePath: relativePath,
        absolutePath: FileSystemService.instance.toAbsolutePath(relativePath),
      );
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<String?> _analyzeSavedImage(String absolutePath) async {
    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.analyzeAssets,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final result = await AssetAnalysisTool(
        client: resources.client,
        modelConfig: resources.modelConfig,
      ).tool(
        assetPath: absolutePath,
        prompt: 'Describe this image briefly in 1-2 sentences. '
            'Focus on what is visible: people, objects, text, scenes. '
            'Be concise and objective.',
      );
      return result
          .replaceFirst(RegExp(r'^#Asset .+ analysis result\n:'), '')
          .trim();
    } catch (e) {
      _logger.warning('RecordOrganizer: image analysis failed: $e');
      return null;
    }
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
      sourceMessageIds: op.sourceMessageIds,
      entityId: op.entityId,
    );
  }).toList(growable: false);
}

String _mediaSearchText(List<MediaInputAttachment> media) {
  return media
      .map((m) => m.analysisText?.trim() ?? '')
      .where((text) => text.isNotEmpty)
      .join('\n');
}

List<String> _extractImageAnalyses(String content) {
  final match = RegExp(r'^\[Image analysis:\s*(.*?)\]').firstMatch(content);
  if (match == null) return const [];
  final body = match.group(1)?.trim() ?? '';
  if (body.isEmpty) return const [];
  return body
      .split(' | ')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

String _imageExtensionForMime(String mimeType) {
  final lower = mimeType.toLowerCase();
  if (lower.contains('webp')) return 'webp';
  if (lower.contains('png')) return 'png';
  if (lower.contains('gif')) return 'gif';
  if (lower.contains('heic')) return 'heic';
  if (lower.contains('heif')) return 'heif';
  return 'jpg';
}

String _evidenceRawInput(String text, List<MediaInputAttachment> media) {
  final parts = <String>[];
  if (text.trim().isNotEmpty) parts.add(text.trim());
  for (final item in media) {
    final path = item.savedRelativePath;
    if (path == null) continue;
    final analysis = item.analysisText?.trim();
    parts.add(
      analysis == null || analysis.isEmpty
          ? '[media:${item.kind}] $path'
          : '[media:${item.kind}] $path\n$analysis',
    );
  }
  return parts.join('\n\n');
}

SharedLifeOperationDraft _fallbackMediaOperation(
  String text,
  List<MediaInputAttachment> media,
) {
  final caption = _captionFor(media.first);
  return SharedLifeOperationDraft(
    operationType: 'create',
    entityType: 'event',
    title: text.isNotEmpty ? text : caption,
    patch: {
      '_primaryDomain': 'general',
      '_facets': const [],
      '_dropletLabel': '图片',
      '_sourceExcerpts': [
        if (text.isNotEmpty) text else caption,
      ],
      '_presentation': {
        'title': text.isNotEmpty ? text : '图片记录',
        'blocks': [
          if (text.isNotEmpty) {'type': 'text', 'text': text},
          ..._mediaBlocks(media),
        ],
      },
      'summary': text.isNotEmpty ? text : caption,
    },
  );
}

Map<String, dynamic> _ensureMediaBlocks(
  Map<String, dynamic> patch,
  List<MediaInputAttachment> media,
) {
  if (media.isEmpty) return patch;

  final normalized = Map<String, dynamic>.from(patch);
  final presentation = _presentationMap(normalized['_presentation']) ??
      <String, dynamic>{
        if (normalized['_dropletLabel'] is String)
          'title': normalized['_dropletLabel'],
        'blocks': <Map<String, dynamic>>[],
      };

  final rawBlocks = presentation['blocks'];
  final blocks = rawBlocks is List
      ? rawBlocks
          .whereType<Object>()
          .map((item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{})
          .where((item) => item.isNotEmpty)
          .toList()
      : <Map<String, dynamic>>[];

  for (final block in _mediaBlocks(media)) {
    final assetPath = block['assetPath'];
    final alreadyPresent = blocks.any((existing) =>
        existing['type'] == 'media' && existing['assetPath'] == assetPath);
    if (!alreadyPresent) blocks.add(block);
  }

  presentation['blocks'] = blocks;
  normalized['_presentation'] = presentation;
  return normalized;
}

Map<String, dynamic>? _presentationMap(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

List<Map<String, dynamic>> _mediaBlocks(List<MediaInputAttachment> media) {
  return media
      .where((m) => m.savedRelativePath != null)
      .map((m) => <String, dynamic>{
            'type': 'media',
            'assetPath': m.savedRelativePath!,
            'caption': _captionFor(m),
            'kind': m.kind,
          })
      .toList(growable: false);
}

String _captionFor(MediaInputAttachment media) {
  final analysis = media.analysisText?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (analysis != null && analysis.isNotEmpty) {
    return analysis.length <= 80 ? analysis : '${analysis.substring(0, 80)}...';
  }
  return media.kind == 'image' ? '图片记录' : '媒体记录';
}
