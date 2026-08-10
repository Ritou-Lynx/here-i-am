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

const _chatImageAttachmentPathKeys = <String>[
  'sourcePath',
  'originalPath',
  'filePath',
  'path',
  'localPath',
];

String? _recoverableImageAttachmentPath(Map<dynamic, dynamic> attachment) {
  for (final key in _chatImageAttachmentPathKeys) {
    final raw = attachment[key]?.toString().trim();
    if (raw == null || raw.isEmpty) continue;
    if (raw.startsWith('file://')) {
      try {
        return Uri.parse(raw).toFilePath();
      } catch (_) {
        return raw.replaceFirst('file://', '');
      }
    }
    return raw;
  }
  return null;
}

bool _chatAttachmentLooksLikeImage(Map<dynamic, dynamic> attachment) {
  final mimeType = attachment['mimeType']?.toString().toLowerCase().trim();
  if (mimeType != null && mimeType.startsWith('image/')) return true;
  final sourcePath = _recoverableImageAttachmentPath(attachment);
  return sourcePath != null && _imageMimeTypeFromPath(sourcePath) != null;
}

String _imageMimeTypeForAttachment(Map<dynamic, dynamic> attachment) {
  final mimeType = attachment['mimeType']?.toString().toLowerCase().trim();
  if (mimeType != null && mimeType.startsWith('image/')) return mimeType;
  final sourcePath = _recoverableImageAttachmentPath(attachment);
  return _imageMimeTypeFromPath(sourcePath ?? '') ?? 'image/jpeg';
}

String? _imageMimeTypeFromPath(String sourcePath) {
  final path = sourcePath.split('?').first.split('#').first.toLowerCase();
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.webp')) return 'image/webp';
  if (path.endsWith('.gif')) return 'image/gif';
  if (path.endsWith('.heic')) return 'image/heic';
  if (path.endsWith('.heif')) return 'image/heif';
  if (path.endsWith('.bmp')) return 'image/bmp';
  if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
  return null;
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
    String? sourceRef,
    List<int> sourceMessageIds = const [],
    List<MediaInputAttachment>? media,
  }) async {
    return _organize(
      userId: userId,
      sourceCharacterId: sourceCharacterId,
      rawInput: text,
      sourceKind: sourceKind,
      sourceRef: sourceRef,
      sourceMessageIds: sourceMessageIds,
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
    _logger.info(
        'Organize: rawInput="${trimmed.length > 60 ? '${trimmed.substring(0, 60)}...' : trimmed}", '
        'mediaIn=${media?.length ?? 0}, usableMedia=${usableMedia.length}');
    if (trimmed.isEmpty && usableMedia.isEmpty) {
      _logger.info('Organize: bail — no content and no usable media');
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
    _logger.info(
        'Organize: ${analysis.isEmpty ? "fallback" : "LLM"} produced ${analyzedOps.length} op(s), '
        'pre-ensureMediaBlocks');

    // Validate and normalize each operation's patch against its domain schema
    const validator = DomainSchemaValidator();
    final schemaValidatedOps = analyzedOps.map((op) {
      final domain = (op.patch['_primaryDomain'] as String?) ?? 'general';
      final before = (op.patch['_presentation'] as Map?)?['blocks'];
      final beforeCount = before is List ? before.length : 0;
      final normalized = _ensureMediaBlocks(
        validator.validate(domain, op.patch).normalizedPatch,
        usableMedia,
      );
      final after = (normalized['_presentation'] as Map?)?['blocks'];
      final afterCount = after is List ? after.length : 0;
      if (usableMedia.isNotEmpty && afterCount <= beforeCount) {
        _logger.warning(
            'Organize: _ensureMediaBlocks may NOT have added blocks! '
            'before=$beforeCount after=$afterCount usableMedia=${usableMedia.length}');
      }
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
      _logger
          .info('_ensureMessageMedia: no attachmentsJson for msg#$messageId, '
              'returning ${media != null ? 'original media' : 'null'}');
      return media;
    }

    final recovered = <MediaInputAttachment>[...current];
    try {
      final raw = jsonDecode(attachmentsJson);
      if (raw is! List) {
        _logger.warning(
            '_ensureMessageMedia: attachmentsJson for msg#$messageId is not a List');
        return recovered.isEmpty ? media : recovered;
      }

      final analyses = _extractImageAnalyses(content);
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map) continue;
        final attachment = Map<dynamic, dynamic>.from(item);
        if (!_chatAttachmentLooksLikeImage(attachment)) continue;
        final mimeType = _imageMimeTypeForAttachment(attachment);
        final base64 = attachment['base64']?.toString();
        final recoveryPath = _recoverableImageAttachmentPath(attachment);
        if ((base64 == null || base64.isEmpty) && recoveryPath == null) {
          _logger.info(
              '_ensureMessageMedia: msg#$messageId image#$i has neither base64 nor sourcePath');
          recovered.add(const MediaInputAttachment(
            error: 'image attachment has neither bytes nor sourcePath',
          ));
          continue;
        }

        try {
          final saved = await _saveChatImageAttachment(
            userId: userId,
            messageId: messageId,
            index: i,
            mimeType: mimeType,
            base64: base64,
            sourcePath: recoveryPath,
          );
          // 3-tier analysis priority (same as chat screen _recordMessage):
          // Tier 1: from [Image analysis: ...] prefix in message content
          // Tier 2: from attachment.analysis stored during send
          // Tier 3: run inline AssetAnalysisTool
          String? analysisText;
          if (i < analyses.length) {
            analysisText = analyses[i];
          }
          if (analysisText == null || analysisText.trim().isEmpty) {
            final storedAnalysis = attachment['analysis']?.toString();
            if (storedAnalysis != null && storedAnalysis.trim().isNotEmpty) {
              analysisText = storedAnalysis.trim();
            }
          }
          if (analysisText == null || analysisText.trim().isEmpty) {
            analysisText = await _analyzeSavedImage(saved.absolutePath);
          }
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
    String? base64,
    String? sourcePath,
  }) async {
    final ext = _imageExtensionForMime(mimeType);
    File? tempFile;
    late final String sourcePathForSave;
    if (base64 != null && base64.isNotEmpty) {
      try {
        final bytes = base64Decode(base64);
        tempFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'record_${messageId}_${DateTime.now().microsecondsSinceEpoch}_$index.$ext',
        );
        await tempFile.writeAsBytes(bytes);
        sourcePathForSave = tempFile.path;
      } catch (e) {
        if (sourcePath == null || sourcePath.isEmpty) rethrow;
        _logger.info(
            '_saveChatImageAttachment: msg#$messageId image#$index base64 failed; '
            'recovering from sourcePath: $e');
        sourcePathForSave = sourcePath;
      }
    } else if (sourcePath != null && sourcePath.isNotEmpty) {
      sourcePathForSave = sourcePath;
    } else {
      throw const FileSystemException(
        'Image attachment has neither bytes nor sourcePath',
      );
    }
    if (!await File(sourcePathForSave).exists()) {
      throw FileSystemException(
        'Image source not found for record attachment',
        sourcePathForSave,
      );
    }
    try {
      final (_, relativePath) =
          await FileSystemService.instance.saveAssetFromFile(
        userId: userId,
        sourcePath: sourcePathForSave,
        assetType: 'img',
        index: index + 1,
        format: ext,
        factId: '${DateTime.now().year}/'
            '${DateTime.now().month.toString().padLeft(2, '0')}/'
            '${DateTime.now().day.toString().padLeft(2, '0')}.md'
            '#ts_${DateTime.now().microsecondsSinceEpoch}',
      );
      return (
        relativePath: relativePath,
        absolutePath: FileSystemService.instance.toAbsolutePath(relativePath),
      );
    } finally {
      if (tempFile != null) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
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
        prompt: '用1-2句中文简要描述这张图片的内容。'
            '关注画面中可见的人、物体、文字、场景。'
            '简洁客观。',
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
  return SharedLifeOperationDraft(
    operationType: 'create',
    entityType: 'event',
    title: text.isNotEmpty ? text : '图片记录',
    patch: {
      '_primaryDomain': 'general',
      '_facets': const [],
      '_dropletLabel': '图片',
      '_sourceExcerpts': [
        if (text.isNotEmpty) text else '图片记录',
      ],
      '_presentation': {
        'title': text.isNotEmpty ? text : '图片记录',
        'blocks': [
          if (text.isNotEmpty) {'type': 'text', 'text': text},
          ..._mediaBlocks(media),
        ],
      },
      'summary': text.isNotEmpty ? text : '图片记录',
    },
  );
}

Map<String, dynamic> _ensureMediaBlocks(
  Map<String, dynamic> patch,
  List<MediaInputAttachment> media,
) {
  if (media.isEmpty) {
    RecordOrganizerService._logger.info(
        '_ensureMediaBlocks: no usable media — returning patch unchanged');
    return patch;
  }

  final normalized = Map<String, dynamic>.from(patch);
  final presentation = _presentationMap(normalized['_presentation']) ??
      <String, dynamic>{
        if (normalized['_dropletLabel'] is String)
          'title': normalized['_dropletLabel'],
        'blocks': <Map<String, dynamic>>[],
      };

  final rawBlocks = presentation['blocks'];
  var blocks = rawBlocks is List
      ? rawBlocks
          .whereType<Object>()
          .map((item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{})
          .where((item) => item.isNotEmpty)
          .toList()
      : <Map<String, dynamic>>[];

  // Remove ALL existing media blocks — the LLM may have generated blocks
  // with wrong assetPaths that would render as broken-image placeholders.
  // Replace them with the ground-truth blocks built from saved media.
  final beforeMediaCount = blocks.where((b) => b['type'] == 'media').length;
  blocks.removeWhere((b) => b['type'] == 'media');

  final mediaBlockDefs = _mediaBlocks(media);
  blocks.addAll(mediaBlockDefs);
  if (mediaBlockDefs.isNotEmpty) {
    RecordOrganizerService._logger.info(
        '_ensureMediaBlocks: replaced $beforeMediaCount LLM media block(s) '
        'with ${mediaBlockDefs.length} ground-truth block(s), '
        'total blocks now ${blocks.length}');
  }

  // Merge adjacent text blocks so the card shows ONE unified description
  // instead of fragmented LLM output.
  blocks = _mergeAdjacentTextBlocks(blocks);

  presentation['blocks'] = blocks;
  normalized['_presentation'] = presentation;
  return normalized;
}

/// Merges consecutive blocks of type 'text' into a single text block,
/// joining their text with newlines.  Non-text blocks break the merge.
List<Map<String, dynamic>> _mergeAdjacentTextBlocks(
    List<Map<String, dynamic>> blocks) {
  if (blocks.length < 2) return blocks;
  final result = <Map<String, dynamic>>[];
  String? pendingText;
  List<String>? pendingEmphases;

  void flush() {
    if (pendingText != null) {
      final merged = <String, dynamic>{
        'type': 'text',
        'text': pendingText!,
      };
      if (pendingEmphases != null && pendingEmphases!.isNotEmpty) {
        merged['emphases'] = pendingEmphases;
      }
      result.add(merged);
      pendingText = null;
      pendingEmphases = null;
    }
  }

  for (final block in blocks) {
    if (block['type'] == 'text') {
      final text = (block['text'] as String?) ?? '';
      final emphases =
          (block['emphases'] as List?)?.map((e) => e.toString()).toList();
      if (pendingText == null) {
        pendingText = text;
        pendingEmphases = emphases;
      } else {
        pendingText = '$pendingText\n$text';
        if (emphases != null && emphases.isNotEmpty) {
          pendingEmphases = [
            if (pendingEmphases != null) ...pendingEmphases!,
            ...emphases,
          ];
        }
      }
    } else {
      flush();
      result.add(block);
    }
  }
  flush();
  return result;
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
            'kind': m.kind,
          })
      .toList(growable: false);
}
