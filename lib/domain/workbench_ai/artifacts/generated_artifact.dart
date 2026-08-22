library;

import '../../whiteboard/whiteboard_ids.dart';

enum GeneratedArtifactKind {
  text,
  image,
  html,
  file;

  static GeneratedArtifactKind fromWire(String value) => switch (value) {
        'text' => text,
        'image' => image,
        'html' => html,
        'file' => file,
        _ => throw ArgumentError('Unknown generated artifact kind: $value'),
      };
}

enum ArtifactBindingStatus {
  staged,
  bound,
  promoted,
  retracted;

  static ArtifactBindingStatus fromWire(String value) => switch (value) {
        'staged' => staged,
        'bound' => bound,
        'promoted' => promoted,
        'retracted' => retracted,
        _ => throw ArgumentError('Unknown artifact binding status: $value'),
      };
}

/// Immutable description of bytes produced by a runtime.
///
/// [stagedObjectRef] is deliberately not a local path. Implementations resolve
/// it inside a configured staging root and bind it to content-addressed object
/// storage only after size, MIME and SHA-256 verification.
class ArtifactManifest {
  const ArtifactManifest({
    required this.artifactId,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
    required this.stagedObjectRef,
    required this.objectRef,
    this.provenanceRefs = const [],
  });

  final String artifactId;
  final GeneratedArtifactKind kind;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  final String stagedObjectRef;
  final String objectRef;
  final List<String> provenanceRefs;

  factory ArtifactManifest.fromJson(Map<String, dynamic> json) =>
      ArtifactManifest(
        artifactId: StableId(json['artifact_id']).value,
        kind: GeneratedArtifactKind.fromWire(json['kind'] as String),
        mimeType: json['mime_type'] as String,
        sizeBytes: (json['size_bytes'] as num).toInt(),
        sha256: json['sha256'] as String,
        stagedObjectRef: json['staged_object_ref'] as String,
        objectRef: json['object_ref'] as String,
        provenanceRefs:
            (json['provenance_refs'] as List<dynamic>? ?? const []).cast(),
      );

  Map<String, dynamic> toJson() => {
        'artifact_id': artifactId,
        'kind': kind.name,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'sha256': sha256,
        'staged_object_ref': stagedObjectRef,
        'object_ref': objectRef,
        if (provenanceRefs.isNotEmpty) 'provenance_refs': provenanceRefs,
      };
}

/// Stable product identities attached to one generated artifact.
///
/// IDs are soft references at this layer. Repository code owns persistence and
/// foreign-key policy. A task artifact is not a Card or Source until an
/// explicit [TaskArtifactPromotion] is committed.
class ArtifactBinding {
  const ArtifactBinding({
    required this.artifactId,
    required this.status,
    this.taskArtifactId,
    this.sourceId,
    this.sourceVersionId,
    this.cardId,
    this.boardItemIds = const [],
  });

  final String artifactId;
  final ArtifactBindingStatus status;
  final String? taskArtifactId;
  final String? sourceId;
  final String? sourceVersionId;
  final String? cardId;
  final List<String> boardItemIds;

  factory ArtifactBinding.fromJson(Map<String, dynamic> json) =>
      ArtifactBinding(
        artifactId: StableId(json['artifact_id']).value,
        status: ArtifactBindingStatus.fromWire(json['status'] as String),
        taskArtifactId: tryStableId(json['task_artifact_id']),
        sourceId: tryStableId(json['source_id']),
        sourceVersionId: tryStableId(json['source_version_id']),
        cardId: tryStableId(json['card_id']),
        boardItemIds:
            (json['board_item_ids'] as List<dynamic>? ?? const []).cast(),
      );

  Map<String, dynamic> toJson() => {
        'artifact_id': artifactId,
        'status': status.name,
        if (taskArtifactId != null) 'task_artifact_id': taskArtifactId,
        if (sourceId != null) 'source_id': sourceId,
        if (sourceVersionId != null) 'source_version_id': sourceVersionId,
        if (cardId != null) 'card_id': cardId,
        if (boardItemIds.isNotEmpty) 'board_item_ids': boardItemIds,
      };
}

class GeneratedArtifact {
  const GeneratedArtifact({
    required this.manifest,
    required this.binding,
    required this.createdAt,
  });

  final ArtifactManifest manifest;
  final ArtifactBinding binding;
  final DateTime createdAt;

  factory GeneratedArtifact.fromJson(Map<String, dynamic> json) =>
      GeneratedArtifact(
        manifest: ArtifactManifest.fromJson(
          Map<String, dynamic>.from(json['manifest'] as Map),
        ),
        binding: ArtifactBinding.fromJson(
          Map<String, dynamic>.from(json['binding'] as Map),
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'manifest': manifest.toJson(),
        'binding': binding.toJson(),
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

/// Explicit promotion of a TaskRoom artifact into durable product content.
///
/// [authorizationId] must identify a user-approved action. Merely recording a
/// TaskArtifact never creates User-truth or a Card.
class TaskArtifactPromotion {
  const TaskArtifactPromotion({
    required this.promotionId,
    required this.taskArtifactId,
    required this.artifactId,
    required this.authorizationId,
    required this.sourceId,
    required this.sourceVersionId,
    required this.cardId,
  });

  final String promotionId;
  final String taskArtifactId;
  final String artifactId;
  final String authorizationId;
  final String sourceId;
  final String sourceVersionId;
  final String cardId;

  factory TaskArtifactPromotion.fromJson(Map<String, dynamic> json) =>
      TaskArtifactPromotion(
        promotionId: StableId(json['promotion_id']).value,
        taskArtifactId: StableId(json['task_artifact_id']).value,
        artifactId: StableId(json['artifact_id']).value,
        authorizationId: StableId(json['authorization_id']).value,
        sourceId: StableId(json['source_id']).value,
        sourceVersionId: StableId(json['source_version_id']).value,
        cardId: StableId(json['card_id']).value,
      );

  Map<String, dynamic> toJson() => {
        'promotion_id': promotionId,
        'task_artifact_id': taskArtifactId,
        'artifact_id': artifactId,
        'authorization_id': authorizationId,
        'source_id': sourceId,
        'source_version_id': sourceVersionId,
        'card_id': cardId,
      };
}
