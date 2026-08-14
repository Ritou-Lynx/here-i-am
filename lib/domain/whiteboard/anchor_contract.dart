/// Anchor contract — a position in a source, without ownership.
///
/// An `Anchor` describes a stable position in a specific `SourceVersion`. It
/// has no `owner_space`, author, or annotation body — those belong to
/// annotation cards. Multiple annotations from different owners can share the
/// same anchor.
library;

import 'whiteboard_ids.dart';

/// The kind of position an anchor points to.
enum PositionKind {
  textRange,
  pageRegion,
  imageRegion,
  timeRange,
  webSnapshotRange;

  static PositionKind fromString(String? raw) {
    switch (raw) {
      case 'text_range':
        return PositionKind.textRange;
      case 'page_region':
        return PositionKind.pageRegion;
      case 'image_region':
        return PositionKind.imageRegion;
      case 'time_range':
        return PositionKind.timeRange;
      case 'web_snapshot_range':
        return PositionKind.webSnapshotRange;
      default:
        throw ArgumentError('Unknown PositionKind: $raw');
    }
  }

  String get name {
    switch (this) {
      case PositionKind.textRange:
        return 'text_range';
      case PositionKind.pageRegion:
        return 'page_region';
      case PositionKind.imageRegion:
        return 'image_region';
      case PositionKind.timeRange:
        return 'time_range';
      case PositionKind.webSnapshotRange:
        return 'web_snapshot_range';
    }
  }
}

/// The resolution status of an anchor after a source version change.
enum AnchorStatus {
  exact,
  reanchored,
  orphaned;

  static AnchorStatus fromString(String? raw) {
    switch (raw) {
      case 'exact':
        return AnchorStatus.exact;
      case 'reanchored':
        return AnchorStatus.reanchored;
      case 'orphaned':
        return AnchorStatus.orphaned;
      default:
        return AnchorStatus.exact;
    }
  }
}

/// A stable position in a source version.
///
/// Anchors MUST bind to `sourceId` + `sourceVersionId`. When a source gets a
/// new version, the anchor's [status] indicates whether the position is still
/// [AnchorStatus.exact], was [AnchorStatus.reanchored], or is [AnchorStatus.orphaned].
class AnchorContract {
  final String anchorId;
  final String sourceId;
  final String sourceVersionId;
  final PositionKind positionKind;
  final Map<String, dynamic> positionSpec;
  final String? quote;
  final String? prefix;
  final String? suffix;
  final String? fingerprint;
  final AnchorStatus status;
  final DateTime createdAt;

  const AnchorContract({
    required this.anchorId,
    required this.sourceId,
    required this.sourceVersionId,
    required this.positionKind,
    this.positionSpec = const {},
    this.quote,
    this.prefix,
    this.suffix,
    this.fingerprint,
    this.status = AnchorStatus.exact,
    required this.createdAt,
  });

  factory AnchorContract.fromJson(Map<String, dynamic> json) {
    return AnchorContract(
      anchorId: StableId(json['anchor_id']).value,
      sourceId: StableId(json['source_id']).value,
      sourceVersionId: StableId(json['source_version_id']).value,
      positionKind: PositionKind.fromString(json['position_kind'] as String?),
      positionSpec:
          (json['position_spec'] as Map<String, dynamic>?) ?? const {},
      quote: json['quote'] as String?,
      prefix: json['prefix'] as String?,
      suffix: json['suffix'] as String?,
      fingerprint: json['fingerprint'] as String?,
      status: AnchorStatus.fromString(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'anchor_id': anchorId,
        'source_id': sourceId,
        'source_version_id': sourceVersionId,
        'position_kind': positionKind.name,
        if (positionSpec.isNotEmpty) 'position_spec': positionSpec,
        if (quote != null) 'quote': quote,
        if (prefix != null) 'prefix': prefix,
        if (suffix != null) 'suffix': suffix,
        if (fingerprint != null) 'fingerprint': fingerprint,
        'status': status.name,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}