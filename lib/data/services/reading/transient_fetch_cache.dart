/// Ephemeral "fetch article body without persisting an entity" cache.
///
/// The Reading Companion pipeline used to be all-or-nothing: reading a link
/// from chat or share intent meant creating a `reading_item` SharedLifeMemory
/// entity. After the 2026-06-19 memory-contract refactor, chat-sent links are
/// treated as chat material only — but that also killed the ability to *read*
/// the article body. This cache closes that gap:
///
///   1. User sends a link (chat input or system share intent).
///   2. Caller kicks off [fetch] fire-and-forget. No entity is created.
///   3. The companion agent's prompt is augmented with the cached body once
///      it's ready, so the character can discuss the actual content — like
///      the image-analysis path does for image attachments.
///   4. Only when the user explicitly asks to save (double-tap the message,
///      "存一下" voice command, etc.) does the cache entry get promoted to a
///      real `reading_item` entity via [promoteToEntity]; the already-fetched
///      body is reused so we never re-hit the source.
///
/// Entries expire after [_ttl] (default 10 minutes) to bound disk + memory
/// growth. Cache is keyed by the *expanded* URL (after xhslink HEAD-follow)
/// so duplicate shares collapse.
library;

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/reading/fetchers/reading_fetcher.dart';
import 'package:memex/data/services/reading/reading_image_processor.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Status of a transient fetch.
enum TransientFetchStatus { pending, success, failed }

/// The cached payload for a single URL.
class TransientFetchEntry {
  TransientFetchEntry._({
    required this.platform,
    required this.url,
    required this.status,
    this.title,
    this.author,
    this.coverUrl,
    this.imageUrls = const [],
    this.body,
    this.ocrSegments = const [],
    this.errorMessage,
    required this.fetchedAt,
  });

  final String platform;

  /// Expanded URL the fetch was actually run against (post xhslink follow).
  final String url;

  final TransientFetchStatus status;

  /// Article title from the fetcher (may refine the parser's guess).
  final String? title;
  final String? author;
  final String? coverUrl;
  final List<String> imageUrls;

  /// Full plain-text article body (no OCR tail).
  final String? body;

  /// Per-image OCR text, in document order. May be empty.
  final List<String> ocrSegments;

  /// Diagnostic message when status == failed.
  final String? errorMessage;

  final DateTime fetchedAt;

  /// Assembled agent-ready context block. Mirrors the on-disk format used by
  /// the persisted reading pipeline: plain body first, then an OCR section
  /// if any image had recognisable text. Empty when nothing was fetched.
  String? buildAgentContext() {
    final hasBody = body != null && body!.trim().isNotEmpty;
    if (!hasBody && ocrSegments.isEmpty) return null;
    final buf = StringBuffer();
    if (hasBody) buf.write(body!.trim());
    if (ocrSegments.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n\n');
      buf.write('---\n图片文字识别（OCR）：\n\n');
      final indexed = <String>[];
      for (var i = 0; i < ocrSegments.length; i++) {
        final text = ocrSegments[i].trim();
        if (text.isEmpty) continue;
        indexed.add('[图 ${i + 1} - 文字识别]\n$text');
      }
      buf.write(indexed.join('\n\n'));
    }
    return buf.toString();
  }
}

/// In-memory + on-disk transient cache.
///
/// The body itself lives in `workspace/reading_transient/{cacheKey}.md` so
/// large articles don't bloat RAM. The [TransientFetchEntry] held in memory
/// keeps the metadata + a body reference; [buildAgentContext] re-reads the
/// body lazily. In practice callers only need the assembled context block,
/// which is what gets injected into the companion prompt.
class TransientFetchCache {
  TransientFetchCache._({
    required this.fetchersByPlatform,
    required this.imageProcessor,
    required Duration ttl,
  }) : _ttl = ttl;

  static TransientFetchCache? _instance;

  static bool get isInitialized => _instance != null;

  static TransientFetchCache get instance {
    final svc = _instance;
    if (svc == null) {
      throw StateError('TransientFetchCache has not been initialized');
    }
    return svc;
  }

  /// Initialize with the same fetchers wired into [ReadingFetchCoordinator].
  /// Call once from `MemexRouter.init` after the coordinator is set up.
  static void init({
    required Map<String, ReadingFetcher> fetchersByPlatform,
    ReadingImageProcessor? imageProcessor,
    Duration ttl = const Duration(minutes: 10),
  }) {
    _instance = TransientFetchCache._(
      fetchersByPlatform: fetchersByPlatform,
      imageProcessor: imageProcessor ?? ReadingImageProcessor(),
      ttl: ttl,
    );
  }

  static void reset() => _instance = null;

  final Map<String, ReadingFetcher> fetchersByPlatform;
  final ReadingImageProcessor imageProcessor;
  final Duration _ttl;
  final Logger _logger = getLogger('TransientFetchCache');

  /// cacheKey -> entry. Entries are removed when [expire] is called or when
  /// [_sweepExpired] drops them.
  final Map<String, TransientFetchEntry> _entries = {};

  /// cacheKey -> in-flight future, so concurrent callers coalesce.
  final Map<String, Future<TransientFetchEntry>> _inFlight = {};

  /// Look up an existing entry by cache key (the expanded URL). Returns null
  /// if there's no entry or it has expired (expired entries are swept here).
  TransientFetchEntry? lookup(String cacheKey) {
    final entry = _entries[cacheKey];
    if (entry == null) return null;
    if (_isExpired(entry)) {
      _entries.remove(cacheKey);
      _deleteBodyFile(cacheKey);
      return null;
    }
    return entry;
  }

  /// Kick off (or join) a fetch for [url] on [platform]. Returns the entry —
  /// potentially still pending. Callers wanting the body should `await` the
  /// returned future, or poll [lookup] later.
  Future<TransientFetchEntry> fetch({
    required String platform,
    required String url,
  }) {
    final cacheKey = _normalizeKey(url);
    final existing = lookup(cacheKey);
    if (existing != null) {
      // Already success/failed — return immediately.
      return Future.value(existing);
    }
    final inFlight = _inFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final future = _doFetch(
      platform: platform,
      url: url,
      cacheKey: cacheKey,
    ).then((entry) {
      _entries[cacheKey] = entry;
      _inFlight.remove(cacheKey);
      _sweepExpired();
      return entry;
    }).catchError((Object e, StackTrace stack) {
      _logger.warning('Transient fetch crashed for $url', e, stack);
      _inFlight.remove(cacheKey);
      final failed = TransientFetchEntry._(
        platform: platform,
        url: url,
        status: TransientFetchStatus.failed,
        errorMessage: 'transient fetch crashed: $e',
        fetchedAt: DateTime.now(),
      );
      _entries[cacheKey] = failed;
      return failed;
    });
    _inFlight[cacheKey] = future;
    return future;
  }

  Future<TransientFetchEntry> _doFetch({
    required String platform,
    required String url,
    required String cacheKey,
  }) async {
    final fetcher = fetchersByPlatform[platform];
    if (fetcher == null) {
      return TransientFetchEntry._(
        platform: platform,
        url: url,
        status: TransientFetchStatus.failed,
        errorMessage: 'no fetcher registered for platform=$platform',
        fetchedAt: DateTime.now(),
      );
    }
    final result = await fetcher.fetch(url);
    if (!result.success) {
      return TransientFetchEntry._(
        platform: platform,
        url: url,
        status: TransientFetchStatus.failed,
        errorMessage: result.errorMessage,
        fetchedAt: DateTime.now(),
      );
    }

    // Run OCR on article images. Reuses the same processor as the persistent
    // pipeline, but lands files under reading_transient/{cacheKey}/images so
    // they stay isolated from real entity bodies and can be GC'd on expiry.
    List<ImageOcrResult> ocrResults = const [];
    final imageUrls = result.imageUrls;
    if (imageUrls.isNotEmpty) {
      try {
        ocrResults = await imageProcessor.processAll(
          entityId: cacheKey,
          imageUrls: imageUrls,
          workspaceSubdir: 'reading_transient',
        );
      } catch (e) {
        _logger.warning('Transient OCR failed for $cacheKey: $e');
      }
    }

    final assembled = _assembleBody(
      baseBody: result.contentFull,
      ocrResults: ocrResults,
    );
    if (assembled != null && assembled.isNotEmpty) {
      await _writeBodyToDisk(cacheKey, assembled);
    }

    return TransientFetchEntry._(
      platform: platform,
      url: url,
      status: TransientFetchStatus.success,
      title: result.title,
      author: result.author,
      coverUrl: result.coverUrl,
      imageUrls: imageUrls,
      body: result.contentFull,
      ocrSegments:
          ocrResults.map((r) => r.recognisedText).toList(growable: false),
      fetchedAt: DateTime.now(),
    );
  }

  /// Body assembled for agent injection. Reads from disk lazily so large
  /// articles don't sit in RAM while the entry is alive.
  Future<String?> loadBody(String cacheKey) async {
    final entry = lookup(cacheKey);
    if (entry == null) return null;
    final assembled = entry.buildAgentContext();
    if (assembled != null) return assembled;
    // Fall back to disk in case the in-memory fields were trimmed.
    return _readBodyFromDisk(cacheKey);
  }

  /// Remove an entry and its body file. Safe to call multiple times.
  void expire(String cacheKey) {
    _entries.remove(cacheKey);
    _inFlight.remove(cacheKey);
    _deleteBodyFile(cacheKey);
  }

  bool _isExpired(TransientFetchEntry entry) {
    return DateTime.now().difference(entry.fetchedAt) > _ttl;
  }

  void _sweepExpired() {
    final expired = <String>[];
    _entries.forEach((key, entry) {
      if (_isExpired(entry)) expired.add(key);
    });
    for (final key in expired) {
      _entries.remove(key);
      _deleteBodyFile(key);
    }
  }

  String _normalizeKey(String url) {
    // Strip trailing slash + query whitespace noise so xhslink expansion and
    // the raw URL collapse to the same key.
    return url.trim().replaceAll(RegExp(r'\s+'), '');
  }

  String? _assembleBody({
    required String? baseBody,
    required List<ImageOcrResult> ocrResults,
  }) {
    final hasBody = baseBody != null && baseBody.trim().isNotEmpty;
    final ocrLines = <String>[];
    for (final r in ocrResults) {
      if (r.recognisedText.trim().isEmpty) continue;
      ocrLines.add('[图 ${r.index} - 文字识别]\n${r.recognisedText.trim()}');
    }
    if (!hasBody && ocrLines.isEmpty) return null;
    final buf = StringBuffer();
    if (hasBody) {
      // hasBody implies baseBody != null, so we can safely use it here.
      buf.write(baseBody!.trim());
    }
    if (ocrLines.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n\n');
      buf.write('---\n图片文字识别（OCR）：\n\n');
      buf.write(ocrLines.join('\n\n'));
    }
    return buf.toString();
  }

  Future<void> _writeBodyToDisk(String cacheKey, String body) async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final workspaceRoot = FileSystemService.instance.getWorkspacePath(userId);
      final file = File(p.join(workspaceRoot, 'reading_transient', '$cacheKey.md'));
      await file.parent.create(recursive: true);
      await file.writeAsString(body);
    } catch (e) {
      _logger.warning('Failed to write transient body for $cacheKey: $e');
    }
  }

  Future<String?> _readBodyFromDisk(String cacheKey) async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return null;
      final workspaceRoot = FileSystemService.instance.getWorkspacePath(userId);
      final file = File(p.join(workspaceRoot, 'reading_transient', '$cacheKey.md'));
      if (!await file.exists()) return null;
      return file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteBodyFile(String cacheKey) async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final workspaceRoot = FileSystemService.instance.getWorkspacePath(userId);
      final file = File(p.join(workspaceRoot, 'reading_transient', '$cacheKey.md'));
      if (await file.exists()) await file.delete();
      // Also sweep the per-key images dir if present.
      final imagesDir = Directory(
        p.join(workspaceRoot, 'reading_transient', cacheKey, 'images'),
      );
      if (await imagesDir.exists()) {
        await imagesDir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}