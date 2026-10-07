/// Validated item from the private, authenticated remember feed.
class ClaudeWebNoteChange {
  const ClaudeWebNoteChange({
    required this.noteId,
    required this.revision,
    required this.feedSeq,
    required this.deleted,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });
  final String noteId;
  final int revision;
  final int feedSeq;
  final bool deleted;
  final String? text;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ClaudeWebNoteChange.fromJson(Map<String, dynamic> json) {
    final id = json['note_id'];
    final revision = json['revision'];
    final seq = json['feed_seq'];
    final op = json['op'];
    final text = json['text'];
    final created = json['created_at_ms'];
    final updated = json['updated_at_ms'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 256 ||
        revision is! int ||
        revision < 1 ||
        seq is! int ||
        seq < 1 ||
        (op != 'upsert' && op != 'delete') ||
        json['source'] != 'claude_web' ||
        created is! int ||
        updated is! int ||
        created < 0 ||
        updated < 0 ||
        (op == 'upsert' &&
            (text is! String ||
                text.trim().isEmpty ||
                text.runes.length > 2000)) ||
        (op == 'delete' && text != null)) {
      throw const FormatException('网页记录格式不正确');
    }
    return ClaudeWebNoteChange(
      noteId: id,
      revision: revision,
      feedSeq: seq,
      deleted: op == 'delete',
      text: text as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updated),
    );
  }
}

enum ClaudeWebNoteSyncStatus { notConfigured, unauthorized, synced }

class ClaudeWebNoteSyncReport {
  const ClaudeWebNoteSyncReport(
    this.status, {
    this.processed = 0,
    this.cursor = 0,
    this.pending = 0,
  });
  final ClaudeWebNoteSyncStatus status;
  final int processed;
  final int cursor;
  final int pending;
}
