import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'package:memex/data/services/active_persona_chat_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/reading/reading_fetch_coordinator.dart';
import 'package:memex/data/services/reading/reading_share_parser.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Outcome of a share-capture attempt.
enum ReadingCaptureStatus {
  /// Saved successfully and a chat message was emitted.
  captured,

  /// The shared text didn't look like a recognised reading link.
  notRecognised,

  /// Parsed correctly but couldn't persist (no companion / no user / etc.).
  /// The caller should fall back to the legacy ShareIntentHandler path so
  /// the share isn't silently swallowed.
  failed,
}

class ReadingCaptureResult {
  const ReadingCaptureResult({
    required this.status,
    this.entityId,
    this.title,
    this.platform,
  });

  final ReadingCaptureStatus status;
  final String? entityId;
  final String? title;
  final String? platform;

  bool get success => status == ReadingCaptureStatus.captured;
}

/// Coordinates the "user shares a 小红书 / 微信公众号 / web link -> companion
/// catches it" flow.
///
/// Pipeline:
///   1. parse share text -> {platform, url, title?}
///   2. follow short link to real URL (HEAD), best-effort
///   3. pick the companion to route the capture to
///        a) active persona chat (within 2-min freshness window), or
///        b) primary companion
///   4. emit a character chat message ("收到了《XX》") carrying a
///      `reading_card` addendum that points at the new entity
///   5. persist a `reading_item` entity via SharedLifeMemoryService using
///      that chat message as the source-of-evidence message
///
/// Constructor-injected dependencies: no AppDatabase.instance, no
/// MemexRouter, per the architecture guard rules in CLAUDE.md.
class ReadingCaptureService {
  // ---- static singleton wiring -----------------------------------------
  // Static `init`/`instance` so the service can be reached from Share intent
  // / debug menus without going through the MemexRouter facade.
  static ReadingCaptureService? _instance;

  static bool get isInitialized => _instance != null;

  static ReadingCaptureService get instance {
    final svc = _instance;
    if (svc == null) {
      throw StateError('ReadingCaptureService has not been initialized');
    }
    return svc;
  }

  static void init({
    required AppDatabase db,
    required SharedLifeMemoryService sharedLifeMemory,
  }) {
    _instance = ReadingCaptureService(
      db: db,
      sharedLifeMemory: sharedLifeMemory,
    );
  }

  // ---- instance -------------------------------------------------------
  ReadingCaptureService({
    required this.db,
    required this.sharedLifeMemory,
    PersonaChatService? chatService,
    CharacterService? characterService,
    ActivePersonaChatService? activeChatService,
    Dio? dio,
  })  : _chatService = chatService ?? PersonaChatService.instance,
        _characterService = characterService ?? CharacterService.instance,
        _activeChatService =
            activeChatService ?? ActivePersonaChatService.instance,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              followRedirects: false,
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
            ));

  final AppDatabase db;
  final SharedLifeMemoryService sharedLifeMemory;
  final PersonaChatService _chatService;
  final CharacterService _characterService;
  final ActivePersonaChatService _activeChatService;
  final Dio _dio;

  final Logger _logger = getLogger('ReadingCaptureService');

  /// Main entry point for system Share Intent. Pass the raw text that landed
  /// in `SharedMedia.content`. The originating action has no chat message of
  /// its own; the only sourceMessage will be the "收到了" character message
  /// emitted by this service.
  Future<ReadingCaptureResult> captureFromShare(String? rawShareText) async {
    final parsed = parseReadingShare(rawShareText);
    if (parsed == null) {
      return const ReadingCaptureResult(
          status: ReadingCaptureStatus.notRecognised);
    }
    return _capture(parsed, originatingUserMessageId: null);
  }

  /// Debug entry point: accepts an already-parsed sample, skipping share
  /// intent altogether. Used by the in-app debug menu (kDebugMode).
  Future<ReadingCaptureResult> captureForDebug(ReadingShareParseResult sample) {
    return _capture(sample, originatingUserMessageId: null);
  }

  Future<ReadingCaptureResult> _capture(
    ReadingShareParseResult parsed, {
    required int? originatingUserMessageId,
    String? preferredCharacterId,
  }) async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null || userId.isEmpty) {
        _logger.warning('No userId; cannot capture reading share');
        return const ReadingCaptureResult(status: ReadingCaptureStatus.failed);
      }

      final characterId =
          preferredCharacterId ?? await _pickRoutingCharacter(userId);
      if (characterId == null) {
        _logger.warning('No companion to route reading capture to');
        return const ReadingCaptureResult(status: ReadingCaptureStatus.failed);
      }

      final resolvedUrl = await _expandShortLink(parsed.url);
      final title = parsed.title ?? _fallbackTitleFromUrl(resolvedUrl);

      // Step 1: emit the character chat message FIRST so we get a real
      // messageId to use as evidence. The addendum carries a placeholder
      // entityId; we patch the chat row at the end (cheap update, no
      // re-render).
      final placeholderEntityId =
          'pending-${DateTime.now().microsecondsSinceEpoch}';
      final messageId = await _chatService.addCharacterMessage(
        characterId,
        '收到了，先帮你存着，回头慢慢看。',
        addenda: [
          _buildReadingCardAddendum(
            entityId: placeholderEntityId,
            title: title,
            platform: parsed.platform,
            url: resolvedUrl,
          ),
        ],
      );

      // Step 2: persist the reading_item entity. Source evidence includes
      // the "收到了" character message we just emitted AND, if the capture
      // was kicked off by a user typing a link into the chat input, the
      // user's original message, so the reading_item naturally remembers
      // what the user said alongside the link.
      //
      // patch fields end up flattened into the entity's stateJson via
      // _mergePatch in SharedLifeMemoryService; keep them flat (no nested
      // `state` key) so haystack search and downstream readers see them
      // directly.
      final sourceMessageIds = <int>[
        messageId,
        if (originatingUserMessageId != null) originatingUserMessageId,
      ];
      final applyResult = await sharedLifeMemory.applyOperations(
        sourceCharacterId: characterId,
        captureTaskId: null,
        operations: [
          SharedLifeOperationDraft(
            operationType: 'create',
            entityType: 'reading_item',
            title: title,
            patch: {
              'summary': title,
              'platform': parsed.platform,
              'url': resolvedUrl,
              'original_share_url': parsed.url,
              'read_status': 'unread',
              'captured_at': DateTime.now().toIso8601String(),
              if (parsed.capturedNote != null)
                'captured_note': parsed.capturedNote,
            },
            sourceMessageIds: sourceMessageIds,
          ),
        ],
        allowedSourceMessageIds: sourceMessageIds.toSet(),
      );

      if (applyResult.isEmpty || applyResult.entityIds.isEmpty) {
        _logger.warning('Reading entity persistence returned empty result');
        return const ReadingCaptureResult(status: ReadingCaptureStatus.failed);
      }

      final entityId = applyResult.entityIds.first;

      // Step 3: patch the chat message's addendum so the reading_card
      // points at the real entityId (so tap-to-open works downstream).
      await _chatService.updateMessageAddenda(
        messageId,
        addenda: [
          _buildReadingCardAddendum(
            entityId: entityId,
            title: title,
            platform: parsed.platform,
            url: resolvedUrl,
          ),
        ],
      );

      _logger.info('Captured reading_item entity=$entityId title="$title" '
          'platform=${parsed.platform}');

      // Fire-and-forget: pull the article body in the background so the
      // user sees the "收到了" placeholder card immediately. The card
      // re-renders when the fetch coordinator patches the entity (chat
      // screens listen to PersonaChatService change notifications, which
      // re-fire when we updateMessageAddenda below, but a separate flow
      // listens to SharedLifeEntities changes for the card itself).
      if (ReadingFetchCoordinator.isInitialized) {
        // ignore: unawaited_futures
        ReadingFetchCoordinator.instance
            .fetchAndPersist(entityId)
            .catchError((e) {
          _logger.warning('Background fetchAndPersist failed: $e');
        });
      }

      return ReadingCaptureResult(
        status: ReadingCaptureStatus.captured,
        entityId: entityId,
        title: title,
        platform: parsed.platform,
      );
    } catch (e, stackTrace) {
      _logger.severe('Reading capture failed: $e', e, stackTrace);
      return const ReadingCaptureResult(status: ReadingCaptureStatus.failed);
    }
  }

  /// Prefer the currently-active chat (so user feels the response "from
  /// the companion they were just talking to"), fall back to primary
  /// companion otherwise.
  Future<String?> _pickRoutingCharacter(String userId) async {
    final active = await _activeChatService.getActiveCharacterId();
    if (active != null && active.isNotEmpty) return active;
    final primary = await _characterService.getPrimaryCompanion(userId);
    return primary?.id;
  }

  /// HEAD-follows a short link (xhslink, etc.) to the final URL. Returns
  /// the original URL on any failure; the user gets a working
  /// reading_item either way; the resolved URL is only nice-to-have for
  /// later WebView fetching.
  Future<String> _expandShortLink(String url) async {
    // No need to expand if it's already a full xiaohongshu / wechat / etc URL.
    if (!url.contains('xhslink.com')) return url;
    try {
      // followRedirects:false in BaseOptions, so we read Location ourselves
      // and stop at the first hop. xhslink is single-hop in practice.
      final response = await _dio.head(url);
      final location = response.headers.value('location');
      if (location != null && location.isNotEmpty) {
        return location;
      }
    } catch (e) {
      _logger.fine('Short-link expand failed (will use raw): $e');
    }
    return url;
  }

  String _fallbackTitleFromUrl(String url) {
    // Very rough title-from-URL fallback. Used only when the share carried
    // no quoted title and we haven't fetched the actual page yet.
    final uri = Uri.tryParse(url);
    if (uri == null) return '未命名链接';
    final host = uri.host.isNotEmpty ? uri.host : '链接';
    return '来自 $host 的内容';
  }

  Map<String, dynamic> _buildReadingCardAddendum({
    required String entityId,
    required String title,
    required String platform,
    String? url,
  }) {
    return <String, dynamic>{
      'type': 'reading_card',
      'entityId': entityId,
      'title': title,
      'source': platform,
      if (url != null && url.isNotEmpty) 'url': url,
    };
  }
}
