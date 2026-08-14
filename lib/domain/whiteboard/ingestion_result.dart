/// IngestionResult contract — the output of link/content ingestion.
///
/// The ingestion pipeline (W3) outputs `IngestionResult`. The application layer
/// decides whether to create a `Card` from it — the ingestor does not directly
/// create cards or board items.
library;

import 'source_content.dart';

/// The capability level of an ingestion result for video sources.
enum VideoCapabilityLevel {
  linkOnly,
  playbackStudy,
  localized;

  static VideoCapabilityLevel fromString(String? raw) {
    switch (raw) {
      case 'link_only':
        return VideoCapabilityLevel.linkOnly;
      case 'playback_study':
        return VideoCapabilityLevel.playbackStudy;
      case 'localized':
        return VideoCapabilityLevel.localized;
      default:
        return VideoCapabilityLevel.linkOnly;
    }
  }

  String get name {
    switch (this) {
      case VideoCapabilityLevel.linkOnly:
        return 'link_only';
      case VideoCapabilityLevel.playbackStudy:
        return 'playback_study';
      case VideoCapabilityLevel.localized:
        return 'localized';
    }
  }
}

/// The availability status of an ingestion result.
enum IngestionStatus {
  ok,
  partial,
  failed,
  needsAuth,
  unsupported;

  static IngestionStatus fromString(String? raw) {
    switch (raw) {
      case 'ok':
        return IngestionStatus.ok;
      case 'partial':
        return IngestionStatus.partial;
      case 'failed':
        return IngestionStatus.failed;
      case 'needs_auth':
        return IngestionStatus.needsAuth;
      case 'unsupported':
        return IngestionStatus.unsupported;
      default:
        return IngestionStatus.ok;
    }
  }

  String get name {
    switch (this) {
      case IngestionStatus.needsAuth:
        return 'needs_auth';
      default:
        return toString().split('.').last;
    }
  }
}

/// The result of ingesting a URL or content reference.
///
/// Contains the canonical URL, identified provider, resolved source/version
/// data (if successful), media and body capabilities, and error/permission
/// status. The application layer decides whether to create a `Card` from this.
class IngestionResult {
  final String? resultId;
  final String canonicalUrl;
  final String? provider;
  final String? originalUrl;
  final IngestionStatus status;
  final String? errorMessage;

  /// Resolved source content, if ingestion succeeded.
  final SourceContent? source;

  /// Resolved source version, if ingestion succeeded.
  final Map<String, dynamic>? sourceVersion;

  /// Whether the source has body text capability.
  final bool hasBody;

  /// Whether the source has media (image/video) capability.
  final bool hasMedia;

  /// Whether the source has transcript/subtitle capability (video only).
  final bool hasTranscript;

  /// Video capability level, if applicable.
  final VideoCapabilityLevel? videoCapability;

  /// Raw metadata extracted during ingestion.
  final Map<String, dynamic> metadata;

  final DateTime resolvedAt;

  const IngestionResult({
    this.resultId,
    required this.canonicalUrl,
    this.provider,
    this.originalUrl,
    this.status = IngestionStatus.ok,
    this.errorMessage,
    this.source,
    this.sourceVersion,
    this.hasBody = false,
    this.hasMedia = false,
    this.hasTranscript = false,
    this.videoCapability,
    this.metadata = const {},
    required this.resolvedAt,
  });

  factory IngestionResult.fromJson(Map<String, dynamic> json) {
    return IngestionResult(
      resultId: json['result_id'] as String?,
      canonicalUrl: json['canonical_url'] as String,
      provider: json['provider'] as String?,
      originalUrl: json['original_url'] as String?,
      status: IngestionStatus.fromString(json['status'] as String?),
      errorMessage: json['error_message'] as String?,
      source: json['source'] != null
          ? SourceContent.fromJson(json['source'] as Map<String, dynamic>)
          : null,
      sourceVersion: json['source_version'] as Map<String, dynamic>?,
      hasBody: json['has_body'] as bool? ?? false,
      hasMedia: json['has_media'] as bool? ?? false,
      hasTranscript: json['has_transcript'] as bool? ?? false,
      videoCapability: json['video_capability'] != null
          ? VideoCapabilityLevel.fromString(json['video_capability'] as String?)
          : null,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      resolvedAt: DateTime.parse(json['resolved_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        if (resultId != null) 'result_id': resultId,
        'canonical_url': canonicalUrl,
        if (provider != null) 'provider': provider,
        if (originalUrl != null) 'original_url': originalUrl,
        'status': status.name,
        if (errorMessage != null) 'error_message': errorMessage,
        if (source != null) 'source': source!.toJson(),
        if (sourceVersion != null) 'source_version': sourceVersion,
        'has_body': hasBody,
        'has_media': hasMedia,
        'has_transcript': hasTranscript,
        if (videoCapability != null) 'video_capability': videoCapability!.name,
        if (metadata.isNotEmpty) 'metadata': metadata,
        'resolved_at': resolvedAt.toUtc().toIso8601String(),
      };
}