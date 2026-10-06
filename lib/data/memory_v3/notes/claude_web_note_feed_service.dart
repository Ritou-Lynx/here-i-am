import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:memex/utils/result.dart';
import 'claude_web_note_feed_storage.dart';
import 'claude_web_note_importer.dart';
import 'claude_web_note_models.dart';
import 'package:memex/data/personal_data_hub/capture_consumer_ownership.dart';

export 'claude_web_note_feed_storage.dart';
export 'claude_web_note_importer.dart';
export 'claude_web_note_models.dart';

/// One bounded pull, serialized with connection changes. Call on foreground
/// resume or explicitly; this class owns no background scheduler.
class ClaudeWebNoteFeedService {
  ClaudeWebNoteFeedService({
    required ClaudeWebNoteFeedStorage storage,
    ClaudeWebNoteImporter? importer,
    ClaudeWebNoteImporter Function()? importerFactory,
    http.Client? client,
    CaptureConsumerOwnership? ownership,
    this.requestTimeout = const Duration(seconds: 20),
    this.maxPages = 10,
  })  : assert(importer != null || importerFactory != null),
        _storage = storage,
        _fixedImporter = importer,
        _importerFactory = importerFactory,
        _client = client ?? http.Client(),
        _ownership = ownership;
  final CaptureConsumerOwnership? _ownership;
  CaptureConsumerOwnership _ownerFor(ClaudeWebNoteImporter importer) =>
      _ownership ?? CaptureConsumerOwnership.forDatabase(importer.database);
  CaptureConsumerOwnership get ownership => _ownerFor(_importer);
  final ClaudeWebNoteImporter? _fixedImporter;
  final ClaudeWebNoteImporter Function()? _importerFactory;
  ClaudeWebNoteImporter get _importer =>
      _importerFactory?.call() ?? _fixedImporter!;
  final ClaudeWebNoteFeedStorage _storage;
  bool _disposed = false, _disposing = false;
  final http.Client _client;
  final Duration requestTimeout;
  final int maxPages;
  Future<void> _queue = Future.value();
  Future<Result<ClaudeWebNoteSyncReport>>? _inFlight;

  Future<Result<T>> _serialized<T>(Future<T> Function() action) {
    if (_disposing) {
      return Future.value(Error(StateError('Web note feed disposing')));
    }
    final task = _queue.then((_) => runResult(() {
          if (_disposed) throw StateError('Web note feed disposed');
          return action();
        }));
    _queue = task.then((_) {});
    return task;
  }

  Future<Result<ClaudeWebNoteFeedConfig?>> readConfig() =>
      _serialized(_storage.readConfig);
  Future<Result<void>> configure({
    required String baseUrl,
    required String token,
  }) =>
      _serialized(() => ownership.configure(
          () => _storage.saveConfig(baseUrl: baseUrl, token: token)));
  Future<Result<void>> clearConnection() =>
      _serialized(() => ownership.configure(_storage.clearConfig));

  Future<Result<ClaudeWebNoteSyncReport>> syncOnce() {
    if (_inFlight != null) return _inFlight!;
    final future = _serialized(() {
      final importer = _importer;
      return _ownerFor(importer).runLegacy((lease) => _sync(lease, importer));
    });
    _inFlight = future;
    unawaited(
      future.then((_) {
        _inFlight = null;
      }),
    );
    return future;
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    String token, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return (() async {
      final streamed = await _client.send(request);
      final bytes = <int>[];
      await for (final chunk in streamed.stream) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          throw const FormatException('记录响应过大');
        }
        bytes.addAll(chunk);
      }
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
      );
    })()
        .timeout(requestTimeout);
  }

  Future<ClaudeWebNoteSyncReport> _sync(
      CaptureConsumerLease lease, ClaudeWebNoteImporter importer) async {
    final config = await _storage.readConfig();
    if (config == null) {
      return const ClaudeWebNoteSyncReport(
        ClaudeWebNoteSyncStatus.notConfigured,
      );
    }
    var cursor = config.cursor;
    var processed = 0;
    var pending = 0;
    for (var page = 0; page < maxPages; page++) {
      await lease.verify();
      final response = await _request(
        'GET',
        Uri.parse(
          '${config.baseUrl}/v1/remember/changes',
        ).replace(queryParameters: {'after': '$cursor', 'limit': '200'}),
        config.token,
      );
      if (response.statusCode == 401) {
        return ClaudeWebNoteSyncReport(
          ClaudeWebNoteSyncStatus.unauthorized,
          processed: processed,
          cursor: cursor,
        );
      }
      if (response.statusCode != 200) {
        throw StateError('记录拉取失败（${response.statusCode}）');
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final raw = data['notes'];
      final next = data['next_after'];
      final more = data['has_more'];
      if (raw is! List ||
          raw.length > 200 ||
          next is! int ||
          next < cursor ||
          more is! bool) {
        throw const FormatException('记录分页格式不正确');
      }
      final notes = raw
          .map(
            (item) => ClaudeWebNoteChange.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList();
      var last = cursor;
      for (final note in notes) {
        if (note.feedSeq <= last) throw const FormatException('记录序列未递增');
        last = note.feedSeq;
      }
      // Do not let an invalid next_after skip an unprocessed feed item.
      if (next != last || (more && notes.isEmpty)) {
        throw const FormatException('记录分页游标不一致');
      }
      for (final note in notes) {
        final cardId = await importer.apply(note, lease: lease);
        pending += (await importer.pendingIssues(note.noteId)).length;
        await lease.verify();
        final ack = await _request(
          'POST',
          Uri.parse('${config.baseUrl}/v1/remember/ack'),
          config.token,
          body: {
            'note_id': note.noteId,
            'revision': note.revision,
            if (cardId != null) 'card_id': cardId,
          },
        );
        if (ack.statusCode == 401) {
          return ClaudeWebNoteSyncReport(
            ClaudeWebNoteSyncStatus.unauthorized,
            processed: processed,
            cursor: cursor,
          );
        }
        if (ack.statusCode != 200 ||
            (jsonDecode(utf8.decode(ack.bodyBytes)) as Map)['ok'] != true) {
          throw StateError('记录回执失败，保留等待重试');
        }
        await lease.fenced(() =>
            _storage.saveCursor(baseUrl: config.baseUrl, cursor: note.feedSeq));
        cursor = note.feedSeq;
        processed++;
      }
      if (!more) break;
    }
    return ClaudeWebNoteSyncReport(
      ClaudeWebNoteSyncStatus.synced,
      processed: processed,
      cursor: cursor,
      pending: pending,
    );
  }

  Future<void> dispose() async {
    // Let an admitted pull finish its durable receipt/ACK/cursor. Closing a
    // settings page does not own this lifetime and must never cancel it.
    _disposing = true;
    await _queue;
    _disposed = true;
    _client.close();
  }
}
