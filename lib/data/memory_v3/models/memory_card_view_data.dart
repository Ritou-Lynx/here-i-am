/// Flat UI-friendly view of a Memory Card for widget consumption.
///
/// Maps from the V3 table family (`memory_cards` + `memory_card_sources`)
/// into a single object suitable for [MemorySummaryCardV3] and
/// [MemoryCardDetailScreenV3].
library;

import 'dart:convert';

/// UI-layer projection of one Memory Card row + its source row.
///
/// Fields intentionally absent:
/// - [confidence] — removed (mood glow only needs valence/arousal)
/// - [sourceKind] — not shown to users (machine-consumed metadata)
/// - [structuredFields] — not shown to users (machine-consumed, used by
///   Schedule panel and future aggregation queries)
class MemoryCardViewData {
  MemoryCardViewData({
    required this.id,
    required this.type,
    required this.title,
    required this.dropletLabel,
    required this.presentationModule,
    required this.retrievalText,
    required this.valence,
    required this.arousal,
    this.status,
    this.needsFollowUp,
    this.rawInput,
    this.recordedAt,
    this.recordedPlace,
    required this.createdAt,
    required this.updatedAt,
    this.structuredFieldsType,
    this.structuredFieldsJson,
  });

  final String id;

  /// fact / event / task / schedule / plan
  final String type;

  /// System field — not displayed on summary card.
  final String title;

  /// 2-4 character essence label.
  final String dropletLabel;

  /// Raw JSON string for [PresentationModule.tryParse].
  final String presentationModule;

  /// Natural-language text for I / embedding retrieval.
  final String retrievalText;

  /// -1.0 ~ 1.0
  final double valence;

  /// 0.0 ~ 1.0
  final double arousal;

  /// Only present for task / schedule / plan cards.
  /// Values: active / completed / cancelled.
  final String? status;

  /// JSON `[{field, question}]` — fields pending user clarification.
  /// Deserialized from the DB text column.
  final List<Map<String, dynamic>>? needsFollowUp;

  // ---- source evidence (from memory_card_sources) ----

  /// Original user input text. May be patched after construction from
  /// the source row.
  String? rawInput;

  /// When the recording action happened (ms since epoch).
  /// May be patched after construction from the source row.
  int? recordedAt;

  /// Auto-tagged location via OpenStreetMap at recording time.
  /// Null when the recording was retrospective. May be patched after
  /// construction from the source row.
  String? recordedPlace;

  // ---- system timestamps ----

  /// Card creation time (ms since epoch).
  final int createdAt;

  /// Card last-update time (ms since epoch).
  final int updatedAt;

  // ---- structured fields (for event-time resolution) ----

  /// Business domain name from Record Organizer (e.g. expense_entry,
  /// income_entry, sleep_record, general). Null if the card has no
  /// structured fields. Populated by query service for cards that need
  /// event-time resolution. Mutable because it's patched in after the
  /// constructor for list queries that don't JOIN structured fields.
  String? structuredFieldsType;

  /// Raw JSON-encoded structured fields (decoded by [structuredFieldsMap]).
  /// Mutable for the same reason as [structuredFieldsType].
  String? structuredFieldsJson;

  /// Lazily decoded structured fields map. Returns null if not populated
  /// or if the JSON is malformed.
  Map<String, dynamic>? get structuredFieldsMap {
    if (structuredFieldsJson == null || structuredFieldsJson!.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(structuredFieldsJson!);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  // ---- convenience ----

  bool get hasFollowUp =>
      needsFollowUp != null && needsFollowUp!.isNotEmpty;

  bool get hasStatus => status != null;

  bool get isTaskLike =>
      type == 'task' || type == 'schedule' || type == 'plan';

  /// Type label for UI display.
  String get typeLabel {
    switch (type) {
      case 'fact':
        return '事实';
      case 'event':
        return '事件';
      case 'task':
        return '任务';
      case 'schedule':
        return '日程';
      case 'plan':
        return '计划';
      default:
        return type;
    }
  }

  /// Status label for UI display.
  String? get statusLabel {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'cancelled':
        return '已取消';
      default:
        return null; // 'active' is the default, don't show
    }
  }

  /// Deserialize [needsFollowUp] from a DB text column value.
  static List<Map<String, dynamic>>? parseNeedsFollowUp(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---- event-time resolution ----

  /// The business event time of this card, in ms since epoch.
  ///
  /// This is the anchor that the Memory Review list uses for sorting and
  /// display, so a card about a 7/15 lunch stays on 7/15 even if the user
  /// edits it on 7/16. Resolution order:
  /// 1. [structuredFieldsMap] time anchor for the card's domain:
  ///    - expense_entry → paidAt
  ///    - income_entry → receivedAt
  ///    - sleep_record → wakeDate or sleepEnd
  ///    - task / schedule / plan → startAt or dueAt
  ///    - general / other → occurredAt
  /// 2. [recordedAt] (when the user pressed the record button).
  /// 3. [createdAt] (card row creation).
  ///
  /// Returns null only if [createdAt] is missing, which should not happen
  /// in practice.
  int? get eventTimeMs {
    final fields = structuredFieldsMap;
    final type = structuredFieldsType;
    if (fields != null && type != null) {
      final anchor = _resolveEventAnchor(type, fields);
      if (anchor != null) return anchor;
    }
    return recordedAt ?? createdAt;
  }

  /// Display-friendly label for the event-time anchor source. UI uses this
  /// to optionally annotate that the timestamp comes from a business field
  /// vs. a recording time vs. a creation time.
  String get eventTimeSource {
    final fields = structuredFieldsMap;
    final type = structuredFieldsType;
    if (fields != null && type != null && _resolveEventAnchor(type, fields) != null) {
      return 'structured';
    }
    if (recordedAt != null) return 'recorded';
    return 'created';
  }

  static int? _resolveEventAnchor(String type, Map<String, dynamic> fields) {
    int? pick(List<String> candidates) {
      for (final key in candidates) {
        final v = fields[key];
        if (v is String && v.isNotEmpty) {
          final parsed = DateTime.tryParse(v);
          if (parsed != null) return parsed.millisecondsSinceEpoch;
        }
      }
      return null;
    }

    switch (type) {
      case 'expense_entry':
      case 'shopping_order':
        return pick(const ['paidAt', 'occurredAt']);
      case 'income_entry':
        return pick(const ['receivedAt', 'occurredAt']);
      case 'sleep_record':
        return pick(const ['wakeDate', 'sleepEnd', 'sleepStart']);
      case 'task':
      case 'schedule':
      case 'plan':
        return pick(const ['startAt', 'dueAt', 'endAt', 'occurredAt']);
      default:
        return pick(const [
          'occurredAt',
          'paidAt',
          'receivedAt',
          'wakeDate',
          'startAt',
          'dueAt',
        ]);
    }
  }

}
