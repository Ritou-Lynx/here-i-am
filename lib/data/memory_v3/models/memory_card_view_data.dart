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

}
