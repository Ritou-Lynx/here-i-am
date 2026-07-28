import 'package:drift/drift.dart';
import 'package:memex/data/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Generates reading-reaction Memory Cards from co-reading chat discussions.
///
/// Trigger: when the user re-opens a book/comic they've read before.
/// Mechanism: reads messages since the last watermark for that book,
/// formats them as a conversation excerpt, and feeds them to
/// RecordOrganizerService to produce `reading_reaction` cards.
class CoReadingNoteService {
  final AppDatabase _db;
  CoReadingNoteService(this._db);

  static CoReadingNoteService? _instance;
  static bool get isInitialized => _instance != null;
  static CoReadingNoteService get instance {
    if (_instance == null) {
      throw StateError('CoReadingNoteService not initialized');
    }
    return _instance!;
  }

  static void init(AppDatabase db) {
    _instance = CoReadingNoteService(db);
  }

  static final _logger = getLogger('CoReadingNoteService');

  static const _bucket = 'co_reading';
  static const _minUserMessages = 3;
  static const _maxMessages = 200;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Check whether there are unprocessed co-reading messages for [bookId]
  /// and generate reading-reaction cards if so. Fire-and-forget safe.
  Future<void> maybeGenerateForBook({
    required String bookId,
    required String bookTitle,
    required String characterId,
  }) async {
    if (!RecordOrganizerService.isInitialized) return;
    try {
      final watermark = await _getWatermark(bookId);
      final messages = await _messagesSince(characterId, watermark);
      if (messages.length < _minUserMessages) return;

      final userId = await UserStorage.getUserId();
      if (userId == null) return;

      final excerpt = _formatExcerpt(messages, bookTitle);
      _logger.info(
        'Generating notes for "$bookTitle": ${messages.length} messages since watermark $watermark',
      );

      await RecordOrganizerService.instance.recordFromText(
        userId: userId,
        sourceCharacterId: characterId,
        text: excerpt,
        sourceKind: 'co_reading',
      );

      final maxId = messages.map((m) => m.id).reduce((a, b) => a > b ? a : b);
      await _setWatermark(bookId, maxId);
      _logger.info('Notes generated, watermark advanced to $maxId');
    } catch (e, st) {
      _logger.warning('Failed to generate co-reading notes: $e', st);
    }
  }

  // ── Watermark (kv_store) ───────────────────────────────────────────────────

  String _watermarkKey(String bookId) => 'note_watermark.$bookId';

  Future<int> _getWatermark(String bookId) async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) =>
              t.key.equals(_watermarkKey(bookId)) & t.bucket.equals(_bucket)))
        .getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _setWatermark(String bookId, int messageId) async {
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: _watermarkKey(bookId),
            value: Value('$messageId'),
            bucket: const Value(_bucket),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  // ── Message query ──────────────────────────────────────────────────────────

  Future<List<PersonaChatMessage>> _messagesSince(
    String characterId,
    int afterId,
  ) async {
    return (_db.select(_db.personaChatMessages)
          ..where((t) =>
              t.characterId.equals(characterId) &
              t.id.isBiggerThanValue(afterId) &
              t.messageType.equals('chat'))
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(_maxMessages))
        .get();
  }

  // ── Formatting ─────────────────────────────────────────────────────────────

  String _formatExcerpt(List<PersonaChatMessage> messages, String bookTitle) {
    final buf = StringBuffer();
    buf.writeln('[共读讨论] 《$bookTitle》');
    buf.writeln();
    buf.writeln('以下是用户和林埃一起读这本书时的讨论记录。');
    buf.writeln('请从中提取用户的阅读感受、偏好、观点、吐槽和思考，');
    buf.writeln('按话题拆分为独立的记忆卡片。忽略与共读无关的日常闲聊。');
    buf.writeln();
    buf.writeln('---');
    for (final m in messages) {
      final role = m.isFromCharacter ? '林埃' : '用户';
      final text = m.content.trim();
      if (text.isEmpty) continue;
      final short = text.length > 500 ? '${text.substring(0, 500)}…' : text;
      buf.writeln('$role: $short');
    }
    buf.writeln('---');
    return buf.toString();
  }
}
