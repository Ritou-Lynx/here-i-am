/// Policy-gated Project Memory projection and explicit project-intent recall.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';

class ProjectMemoryProjectionEnvelope {
  const ProjectMemoryProjectionEnvelope({
    required this.eventId,
    required this.projectId,
    required this.projectKey,
    required this.policyId,
    required this.policyVersion,
    required this.memoryV3Policy,
    required this.sensitivity,
    required this.redactionState,
    required this.authority,
    required this.trustLevel,
    required this.sourceTool,
    required this.sourceSessionId,
    required this.sourceUri,
    required this.summary,
    required this.occurredAt,
    required this.receivedAt,
    this.decisions = const [],
    this.openLoops = const [],
    this.artifactRefs = const [],
    this.eventType = 'session_closeout',
    this.memoryLanesAllowed = const ['project'],
    this.schemaVersion = 1,
  });

  factory ProjectMemoryProjectionEnvelope.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => (json[key] as List? ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    final policy = json['policy'] as Map<String, dynamic>? ?? const {};
    return ProjectMemoryProjectionEnvelope(
      schemaVersion: json['schema_version'] as int? ?? 0,
      eventId: json['event_id']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      projectKey: json['project_key']?.toString() ?? '',
      policyId: policy['id']?.toString() ?? '',
      policyVersion: policy['version'] as int? ?? 0,
      memoryV3Policy: policy['memory_v3']?.toString() ?? '',
      sensitivity: json['sensitivity']?.toString() ?? '',
      redactionState: json['redaction_state']?.toString() ?? '',
      authority: json['authority']?.toString() ?? '',
      trustLevel: json['trust_level']?.toString() ?? '',
      sourceTool: json['source_tool']?.toString() ?? '',
      sourceSessionId: json['source_session_id']?.toString() ?? '',
      sourceUri: json['source']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      decisions: strings('decisions'),
      openLoops: strings('open_loops'),
      artifactRefs: strings('artifact_refs'),
      memoryLanesAllowed: strings('memory_lanes_allowed'),
      occurredAt: DateTime.parse(json['occurred_at'].toString()),
      receivedAt: DateTime.parse(json['received_at'].toString()),
    );
  }

  final int schemaVersion;
  final String eventId;
  final String eventType;
  final String projectId;
  final String projectKey;
  final String policyId;
  final int policyVersion;
  final String memoryV3Policy;
  final String sensitivity;
  final String redactionState;
  final String authority;
  final String trustLevel;
  final String sourceTool;
  final String sourceSessionId;
  final String sourceUri;
  final String summary;
  final List<String> decisions;
  final List<String> openLoops;
  final List<String> artifactRefs;
  final List<String> memoryLanesAllowed;
  final DateTime occurredAt;
  final DateTime receivedAt;
}

class ProjectMemoryQueryScope {
  const ProjectMemoryQueryScope({
    required this.isProjectIntent,
    required this.allowedProjectIds,
  });

  /// Ordinary life chat must pass false and receives no project candidates.
  final bool isProjectIntent;
  final Set<String> allowedProjectIds;
}

class ProjectMemoryHit {
  const ProjectMemoryHit({
    required this.itemId,
    required this.projectId,
    required this.projectKey,
    required this.summary,
    required this.decisions,
    required this.openLoops,
    required this.artifactRefs,
    required this.sourceTool,
    required this.occurredAt,
    required this.rank,
  });

  final String itemId;
  final String projectId;
  final String projectKey;
  final String summary;
  final List<String> decisions;
  final List<String> openLoops;
  final List<String> artifactRefs;
  final String sourceTool;
  final int occurredAt;
  final double rank;
}

class ProjectMemoryService {
  ProjectMemoryService(this._db);

  final AppDatabase _db;

  Future<Set<String>> projectedProjectIds() async {
    final rows = await (_db.selectOnly(_db.projectMemoryItems, distinct: true)
          ..addColumns([_db.projectMemoryItems.projectId])
          ..where(_db.projectMemoryItems.status.equals('active')))
        .get();
    return rows
        .map((row) => row.read(_db.projectMemoryItems.projectId))
        .whereType<String>()
        .toSet();
  }

  Future<bool> project(ProjectMemoryProjectionEnvelope envelope) async {
    _validate(envelope);
    final contentHash = _contentHash(envelope);
    final existingSource = await (_db.select(_db.projectMemorySources)
          ..where((table) => table.sourceEventId.equals(envelope.eventId)))
        .getSingleOrNull();
    if (existingSource != null) {
      if (existingSource.contentHash != contentHash) {
        throw StateError(
          'Project Memory event ${envelope.eventId} changed after projection.',
        );
      }
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final decisionsJson = jsonEncode(envelope.decisions);
    final openLoopsJson = jsonEncode(envelope.openLoops);
    final artifactRefsJson = jsonEncode(envelope.artifactRefs);
    final retrievalText = [
      envelope.projectKey,
      envelope.summary,
      ...envelope.decisions,
      ...envelope.openLoops,
      ...envelope.artifactRefs,
    ].join('\n');

    await _db.transaction(() async {
      await _db.into(_db.projectMemoryItems).insert(
            ProjectMemoryItemsCompanion.insert(
              id: envelope.eventId,
              projectId: envelope.projectId,
              projectKey: envelope.projectKey,
              summary: envelope.summary,
              decisionsJson: Value(decisionsJson),
              openLoopsJson: Value(openLoopsJson),
              artifactRefsJson: Value(artifactRefsJson),
              retrievalText: retrievalText,
              policyId: envelope.policyId,
              policyVersion: Value(envelope.policyVersion),
              memoryV3Policy: envelope.memoryV3Policy,
              sensitivity: envelope.sensitivity,
              redactionState: envelope.redactionState,
              authority: envelope.authority,
              trustLevel: envelope.trustLevel,
              occurredAt: envelope.occurredAt.millisecondsSinceEpoch,
              receivedAt: envelope.receivedAt.millisecondsSinceEpoch,
              updatedAt: now,
            ),
          );
      await _db.into(_db.projectMemorySources).insert(
            ProjectMemorySourcesCompanion.insert(
              id: envelope.eventId,
              itemId: envelope.eventId,
              sourceEventId: envelope.eventId,
              sourceUri: envelope.sourceUri,
              sourceTool: envelope.sourceTool,
              sourceSessionId: envelope.sourceSessionId,
              contentHash: contentHash,
              receivedAt: envelope.receivedAt.millisecondsSinceEpoch,
            ),
          );
      await _db.searchDao.upsertProjectMemoryFts(
        itemId: envelope.eventId,
        projectId: envelope.projectId,
        projectKey: envelope.projectKey,
        summary: envelope.summary,
        decisions: envelope.decisions.join('\n'),
        openLoops: envelope.openLoops.join('\n'),
        artifactRefs: envelope.artifactRefs.join('\n'),
      );
    });
    return true;
  }

  Future<List<ProjectMemoryHit>> search(
    String query, {
    required ProjectMemoryQueryScope scope,
    int limit = 10,
  }) async {
    if (!scope.isProjectIntent || scope.allowedProjectIds.isEmpty) return [];
    final raw = await _db.searchDao.searchProjectMemory(
      query,
      allowedProjectIds: scope.allowedProjectIds,
      limit: limit,
    );
    final hits = <ProjectMemoryHit>[];
    for (final result in raw) {
      final item = await (_db.select(_db.projectMemoryItems)
            ..where((table) =>
                table.id.equals(result['item_id'] as String) &
                table.status.equals('active') &
                table.projectId.isIn(scope.allowedProjectIds.toList())))
          .getSingleOrNull();
      if (item == null) continue;
      hits.add(ProjectMemoryHit(
        itemId: item.id,
        projectId: item.projectId,
        projectKey: item.projectKey,
        summary: item.summary,
        decisions: _decodeList(item.decisionsJson),
        openLoops: _decodeList(item.openLoopsJson),
        artifactRefs: _decodeList(item.artifactRefsJson),
        sourceTool: (await (_db.select(_db.projectMemorySources)
                  ..where((table) => table.itemId.equals(item.id)))
                .getSingle())
            .sourceTool,
        occurredAt: item.occurredAt,
        rank: (result['rank'] as num).toDouble(),
      ));
    }
    return hits;
  }

  static List<String> _decodeList(String value) {
    final decoded = jsonDecode(value);
    return decoded is List
        ? decoded.map((entry) => entry.toString()).toList(growable: false)
        : const [];
  }

  static String _contentHash(ProjectMemoryProjectionEnvelope envelope) {
    final canonical = jsonEncode({
      'event_id': envelope.eventId,
      'project_id': envelope.projectId,
      'project_key': envelope.projectKey,
      'policy_id': envelope.policyId,
      'policy_version': envelope.policyVersion,
      'memory_v3': envelope.memoryV3Policy,
      'sensitivity': envelope.sensitivity,
      'redaction_state': envelope.redactionState,
      'summary': envelope.summary,
      'decisions': envelope.decisions,
      'open_loops': envelope.openLoops,
      'artifact_refs': envelope.artifactRefs,
      'source': envelope.sourceUri,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static void _validate(ProjectMemoryProjectionEnvelope envelope) {
    if (envelope.schemaVersion != 1 ||
        envelope.eventType != 'session_closeout' ||
        envelope.eventId.isEmpty ||
        envelope.projectId.isEmpty ||
        envelope.projectKey.isEmpty ||
        envelope.summary.trim().isEmpty) {
      throw const FormatException('Invalid Project Memory envelope.');
    }
    if (!envelope.memoryLanesAllowed.contains('project')) {
      throw const FormatException('Project memory lane is not allowed.');
    }
    final personal = envelope.policyId == 'personal_full' &&
        envelope.memoryV3Policy == 'project_summary' &&
        envelope.redactionState == 'policy_summary';
    final redacted = envelope.policyId == 'work_redacted' &&
        envelope.memoryV3Policy == 'redacted_summary' &&
        envelope.redactionState == 'activity_index_redacted' &&
        envelope.decisions.isEmpty &&
        envelope.openLoops.isEmpty &&
        envelope.artifactRefs.isEmpty;
    if (!personal && !redacted) {
      throw const FormatException(
        'Project policy does not permit this Memory V3 projection.',
      );
    }
    if (envelope.sensitivity == 'local_only' ||
        envelope.sensitivity == 'private' ||
        envelope.policyId == 'confidential_local') {
      throw const FormatException('Local/private project data cannot project.');
    }
    if (!envelope.sourceUri.startsWith('i://project-activity/')) {
      throw const FormatException('Untrusted Project Memory source URI.');
    }
  }
}
