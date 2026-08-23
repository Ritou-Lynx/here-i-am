/// Standard positionSpec schema for time_range Anchors.
///
/// W0 left `AnchorContract.positionSpec` as an open `Map<String, dynamic>`.
/// W4 defines the canonical structure for [PositionKind.timeRange] anchors
/// so that all video annotations share a consistent, verifiable shape.
///
/// Canonical time_range positionSpec:
/// ```json
/// {
///   "start_ms": 142000,
///   "end_ms": 146000,
///   "is_point": false,
///   "cue_id": "cue_plave_1"
/// }
/// ```
///
/// - `start_ms` / `end_ms`: required, non-negative, start ≤ end.
/// - `is_point`: optional, defaults to false. When true, start_ms == end_ms
///   and the anchor marks a single moment.
/// - `cue_id`: optional, links to the [TimedTextCue] that inspired the anchor.
library;

import '../anchor_contract.dart';

/// Validates and builds time_range positionSpec maps.
class TimeRangeAnchorSpec {
  final int startMs;
  final int endMs;
  final bool isPoint;
  final String? cueId;

  const TimeRangeAnchorSpec({
    required this.startMs,
    required this.endMs,
    this.isPoint = false,
    this.cueId,
  });

  /// Creates a point anchor at a single timestamp.
  factory TimeRangeAnchorSpec.point(int ms, {String? cueId}) {
    return TimeRangeAnchorSpec(
      startMs: ms,
      endMs: ms,
      isPoint: true,
      cueId: cueId,
    );
  }

  /// Creates a range anchor from start to end.
  factory TimeRangeAnchorSpec.range(int startMs, int endMs, {String? cueId}) {
    return TimeRangeAnchorSpec(
      startMs: startMs,
      endMs: endMs,
      isPoint: false,
      cueId: cueId,
    );
  }

  /// Parses a positionSpec map into a typed spec.
  factory TimeRangeAnchorSpec.fromMap(Map<String, dynamic> map) {
    final error = validate(map);
    if (error != null) throw ArgumentError(error);
    final start = map['start_ms'] as int;
    final end = map['end_ms'] as int;
    return TimeRangeAnchorSpec(
      startMs: start,
      endMs: end,
      isPoint: (map['is_point'] as bool?) ?? (start == end),
      cueId: map['cue_id'] as String?,
    );
  }

  /// Converts to the canonical positionSpec map for [AnchorContract].
  Map<String, dynamic> toMap() => {
        'start_ms': startMs,
        'end_ms': endMs,
        'is_point': isPoint,
        if (cueId != null) 'cue_id': cueId,
      };

  /// Validates a positionSpec map for time_range anchors.
  ///
  /// Returns null if valid, or an error message string.
  static String? validate(Map<String, dynamic> spec) {
    final start = spec['start_ms'];
    final end = spec['end_ms'];
    if (start is! int) {
      return 'time_range positionSpec requires start_ms (int)';
    }
    if (end is! int) {
      return 'time_range positionSpec requires end_ms (int)';
    }
    if (start < 0 || end < 0) {
      return 'time_range start_ms and end_ms must be non-negative';
    }
    if (start > end) {
      return 'time_range start_ms must be <= end_ms';
    }
    return null;
  }

  /// Builds an [AnchorContract] for a time_range position.
  static AnchorContract buildAnchor({
    required String anchorId,
    required String sourceId,
    required String sourceVersionId,
    required TimeRangeAnchorSpec spec,
    String? quote,
    DateTime? createdAt,
  }) {
    final error = validate(spec.toMap());
    if (error != null) {
      throw ArgumentError(error);
    }
    return AnchorContract(
      anchorId: anchorId,
      sourceId: sourceId,
      sourceVersionId: sourceVersionId,
      positionKind: PositionKind.timeRange,
      positionSpec: spec.toMap(),
      quote: quote,
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
  }
}
