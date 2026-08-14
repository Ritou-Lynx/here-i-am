/// Source content and source version contracts.
///
/// `SourceContent` is the identity of an original artifact (book, video, web
/// page, image, etc.). `SourceVersion` is an immutable snapshot of that
/// content at a point in time. Anchors must point to a specific
/// `source_version_id`, not just "latest".
library;

import 'whiteboard_ids.dart';

/// The media type of a source.
enum SourceMediaType {
  text,
  book,
  pdf,
  image,
  web,
  video,
  audio,
  file;

  static SourceMediaType fromString(String? raw) {
    switch (raw) {
      case 'text':
        return SourceMediaType.text;
      case 'book':
        return SourceMediaType.book;
      case 'pdf':
        return SourceMediaType.pdf;
      case 'image':
        return SourceMediaType.image;
      case 'web':
        return SourceMediaType.web;
      case 'video':
        return SourceMediaType.video;
      case 'audio':
        return SourceMediaType.audio;
      case 'file':
        return SourceMediaType.file;
      default:
        throw ArgumentError('Unknown SourceMediaType: $raw');
    }
  }

  String get name => toString().split('.').last;
}

/// The ownership space of an entity.
enum OwnerSpace {
  user,
  i,
  shared;

  static OwnerSpace fromString(String? raw) {
    switch (raw) {
      case 'user':
        return OwnerSpace.user;
      case 'i':
        return OwnerSpace.i;
      case 'shared':
        return OwnerSpace.shared;
      default:
        return OwnerSpace.user;
    }
  }

  String get name => toString().split('.').last;
}

/// The origin of a source — how it entered the system.
enum SourceOrigin {
  import,
  share,
  crawl,
  generate,
  externalLink,
  unknown;

  static SourceOrigin fromString(String? raw) {
    switch (raw) {
      case 'import':
        return SourceOrigin.import;
      case 'share':
        return SourceOrigin.share;
      case 'crawl':
        return SourceOrigin.crawl;
      case 'generate':
        return SourceOrigin.generate;
      case 'external_link':
        return SourceOrigin.externalLink;
      default:
        return SourceOrigin.unknown;
    }
  }

  String get name {
    switch (this) {
      case SourceOrigin.externalLink:
        return 'external_link';
      default:
        return toString().split('.').last;
    }
  }
}

/// An immutable version of a [SourceContent].
///
/// Each version captures a content hash and an object reference. Anchors must
/// point to a specific version so that content changes don't silently move
/// annotations to wrong locations.
class SourceVersion {
  final String versionId;
  final String sourceId;
  final String contentHash;
  final String objectRef;
  final String? parserVersion;
  final DateTime createdAt;

  const SourceVersion({
    required this.versionId,
    required this.sourceId,
    required this.contentHash,
    required this.objectRef,
    this.parserVersion,
    required this.createdAt,
  });

  factory SourceVersion.fromJson(Map<String, dynamic> json) {
    return SourceVersion(
      versionId: StableId(json['version_id']).value,
      sourceId: StableId(json['source_id']).value,
      contentHash: json['content_hash'] as String,
      objectRef: json['object_ref'] as String,
      parserVersion: json['parser_version'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'version_id': versionId,
        'source_id': sourceId,
        'content_hash': contentHash,
        'object_ref': objectRef,
        if (parserVersion != null) 'parser_version': parserVersion,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

/// The identity of an original artifact — the thing being read, watched,
/// or referenced.
///
/// `SourceContent` holds the stable identity and metadata. The actual binary
/// or text content lives in object storage (referenced by [objectRef] on
/// versions), not in the database row.
class SourceContent {
  final String sourceId;
  final SourceMediaType mediaType;
  final String title;
  final OwnerSpace ownerSpace;
  final SourceOrigin origin;
  final String? provider;
  final String? canonicalId;
  final String? mimeType;
  final String? currentVersionId;
  final String? contentHash;
  final String? objectRef;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  const SourceContent({
    required this.sourceId,
    required this.mediaType,
    required this.title,
    this.ownerSpace = OwnerSpace.user,
    this.origin = SourceOrigin.unknown,
    this.provider,
    this.canonicalId,
    this.mimeType,
    this.currentVersionId,
    this.contentHash,
    this.objectRef,
    this.metadata = const {},
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory SourceContent.fromJson(Map<String, dynamic> json) {
    return SourceContent(
      sourceId: tryStableId(json['source_id']) ?? '',
      mediaType: SourceMediaType.fromString(json['media_type'] as String?),
      title: json['title'] as String? ?? '',
      ownerSpace: OwnerSpace.fromString(json['owner_space'] as String?),
      origin: SourceOrigin.fromString(json['origin'] as String?),
      provider: json['provider'] as String?,
      canonicalId: json['canonical_id'] as String?,
      mimeType: json['mime_type'] as String?,
      currentVersionId: json['current_version_id'] as String?,
      contentHash: json['content_hash'] as String?,
      objectRef: json['object_ref'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.utc(2026, 1, 1),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'media_type': mediaType.name,
        'title': title,
        'owner_space': ownerSpace.name,
        'origin': origin.name,
        if (provider != null) 'provider': provider,
        if (canonicalId != null) 'canonical_id': canonicalId,
        if (mimeType != null) 'mime_type': mimeType,
        if (currentVersionId != null) 'current_version_id': currentVersionId,
        if (contentHash != null) 'content_hash': contentHash,
        if (objectRef != null) 'object_ref': objectRef,
        if (metadata.isNotEmpty) 'metadata': metadata,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toUtc().toIso8601String(),
      };
}