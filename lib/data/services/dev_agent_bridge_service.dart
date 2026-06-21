import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

enum DevAgentType {
  claudeCode('claude_code'),
  codex('codex');

  const DevAgentType(this.value);
  final String value;
}

enum DevProjectPermissionTier {
  readOnly('read_only'),
  workspaceWrite('workspace_write'),
  releaseOps('release_ops');

  const DevProjectPermissionTier(this.value);
  final String value;
}

class DevAgentBridgeHealth {
  const DevAgentBridgeHealth({
    required this.ok,
    required this.bridgeId,
    required this.version,
    required this.agents,
  });

  final bool ok;
  final String bridgeId;
  final String version;
  final List<String> agents;
}

class DevAgentBridgeException implements Exception {
  const DevAgentBridgeException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DevAgentDecisionResult {
  const DevAgentDecisionResult({
    required this.accepted,
    this.reason,
    this.message,
  });

  final bool accepted;
  final String? reason;
  final String? message;
}

/// App-side control surface for the remote development bridge.
///
/// The phone never executes Claude Code/Codex itself. This service stores local
/// project/run state and talks to the bridge, which owns credentials, processes,
/// worktrees, and provider-specific streams.
class DevAgentBridgeService {
  DevAgentBridgeService._({
    Dio? dio,
    AppDatabase? db,
  })  : _dio = dio ?? _createDio(),
        _dbOverride = db;

  static DevAgentBridgeService? _instance;
  static DevAgentBridgeService get instance {
    _instance ??= DevAgentBridgeService._();
    return _instance!;
  }

  @visibleForTesting
  static void setTestInstance(DevAgentBridgeService service) {
    _instance = service;
  }

  final Dio _dio;
  final AppDatabase? _dbOverride;
  final Logger _logger = getLogger('DevAgentBridgeService');
  final Uuid _uuid = const Uuid();

  AppDatabase get _db => _dbOverride ?? AppDatabase.instance;

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (kDebugMode) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (_, host, __) {
          return _isDebugLoopbackHost(host);
        };
        return client;
      };
    }
    return dio;
  }

  static bool _isDebugLoopbackHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }

  Stream<List<DevProject>> watchProjects() {
    final query = _db.select(_db.devProjects)
      ..orderBy([
        (t) => OrderingTerm.asc(t.name),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    return query.watch();
  }

  Future<List<DevProject>> listProjects() {
    final query = _db.select(_db.devProjects)
      ..orderBy([
        (t) => OrderingTerm.asc(t.name),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    return query.get();
  }

  Future<DevProject?> getProject(String projectId) {
    return (_db.select(_db.devProjects)..where((t) => t.id.equals(projectId)))
        .getSingleOrNull();
  }

  Future<String> saveProject({
    String? id,
    required String name,
    required String rootPath,
    required String defaultBranch,
    required String bridgeUrl,
    String permissionTier = 'read_only',
  }) async {
    final projectId = id ?? _uuid.v4();
    _validateBridgeUrl(bridgeUrl);
    _validatePermissionTier(permissionTier);

    await _db.into(_db.devProjects).insertOnConflictUpdate(
          DevProjectsCompanion.insert(
            id: projectId,
            name: name.trim(),
            rootPath: rootPath.trim(),
            defaultBranch: Value(
              defaultBranch.trim().isEmpty ? 'main' : defaultBranch.trim(),
            ),
            bridgeUrl: bridgeUrl.trim(),
            permissionTier: Value(permissionTier),
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
        );
    return projectId;
  }

  Future<void> deleteProject(String projectId) async {
    await (_db.delete(_db.devProjects)..where((t) => t.id.equals(projectId)))
        .go();
  }

  Stream<List<DevAgentRun>> watchRuns({String? projectId}) {
    final query = _db.select(_db.devAgentRuns)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    if (projectId != null) {
      query.where((t) => t.projectId.equals(projectId));
    }
    return query.watch();
  }

  Future<DevAgentRun?> getRun(String runId) {
    return (_db.select(_db.devAgentRuns)..where((t) => t.id.equals(runId)))
        .getSingleOrNull();
  }

  Stream<DevAgentRun?> watchRun(String runId) {
    final query = _db.select(_db.devAgentRuns)
      ..where((t) => t.id.equals(runId));
    return query.watchSingleOrNull();
  }

  Stream<List<DevAgentEvent>> watchEvents(String runId) {
    final query = _db.select(_db.devAgentEvents)
      ..where((t) => t.runId.equals(runId))
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return query.watch();
  }

  Stream<List<DevAgentApproval>> watchPendingApprovals(String runId) {
    final query = _db.select(_db.devAgentApprovals)
      ..where((t) => t.runId.equals(runId) & t.status.equals('pending'))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch();
  }

  Stream<List<DevAgentArtifact>> watchArtifacts(String runId) {
    final query = _db.select(_db.devAgentArtifacts)
      ..where((t) => t.runId.equals(runId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Future<List<DevAgentEvent>> listEvents(String runId) {
    final query = _db.select(_db.devAgentEvents)
      ..where((t) => t.runId.equals(runId))
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return query.get();
  }

  Future<List<DevAgentArtifact>> listArtifacts(String runId) {
    final query = _db.select(_db.devAgentArtifacts)
      ..where((t) => t.runId.equals(runId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  Future<DevAgentBridgeHealth> checkBridgeHealth(String bridgeUrl) async {
    _validateBridgeUrl(bridgeUrl);
    final response = await _dio.getUri<Map<String, dynamic>>(
      _bridgeUri(bridgeUrl, '/v1/health'),
    );
    final data = response.data ?? {};
    final agents = data['agents'];
    return DevAgentBridgeHealth(
      ok: data['ok'] == true,
      bridgeId: data['bridge_id']?.toString() ?? 'unknown',
      version: data['version']?.toString() ?? 'unknown',
      agents: agents is List ? agents.map((e) => e.toString()).toList() : [],
    );
  }

  Future<int> refreshActiveRuns({String? projectId}) async {
    final query = _db.select(_db.devAgentRuns)
      ..where(
        (t) =>
            t.sessionId.isNotNull() &
            t.status.isNotIn(const ['done', 'failed', 'aborted']),
      );
    if (projectId != null) {
      query.where((t) => t.projectId.equals(projectId));
    }
    final runs = await query.get();
    for (final run in runs) {
      await refreshRun(run.id);
    }
    return runs.length;
  }

  Future<String> startRun({
    required String projectId,
    required String prompt,
    required DevAgentType agentType,
  }) async {
    final project = await getProject(projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }
    _validateBridgeUrl(project.bridgeUrl);

    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw const DevAgentBridgeException('Task prompt cannot be empty.');
    }

    final runId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.devAgentRuns).insert(
          DevAgentRunsCompanion.insert(
            id: runId,
            projectId: project.id,
            agentType: agentType.value,
            initialPrompt: trimmedPrompt,
            status: 'pending',
            startedAt: now,
          ),
        );

    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        _bridgeUri(project.bridgeUrl, '/v1/runs'),
        data: {
          'client_run_id': runId,
          'project': {
            'id': project.id,
            'name': project.name,
            'root_path': project.rootPath,
            'default_branch': project.defaultBranch,
            'permission_tier': project.permissionTier,
          },
          'agent_type': agentType.value,
          'prompt': trimmedPrompt,
          // For MVP, mode follows project's permission tier. release_ops runs
          // as workspace_write here — actual push/PR is gated separately later.
          'mode': project.permissionTier == 'read_only'
              ? 'read_only'
              : 'workspace_write',
        },
      );
      final data = response.data ?? {};
      final bridgeRunId = data['run_id']?.toString();
      final sessionId = data['session_id']?.toString() ?? bridgeRunId;
      final status = data['status']?.toString() ?? 'running';
      await (_db.update(_db.devAgentRuns)..where((t) => t.id.equals(runId)))
          .write(
        DevAgentRunsCompanion(
          sessionId: Value(sessionId),
          status: Value(status),
        ),
      );
      await _insertLocalEvent(
        runId: runId,
        kind: 'status',
        payload: {
          'status': status,
          if (bridgeRunId != null) 'bridge_run_id': bridgeRunId,
          'message': 'Run started on bridge.',
        },
      );
    } catch (e, stack) {
      _logger.warning('Failed to start dev agent run', e, stack);
      await _markRunFailed(runId, _describeError(e));
      rethrow;
    }

    return runId;
  }

  /// Builds a debug-friendly error message. For Dio errors with a JSON body,
  /// includes the bridge's actual response so the user does not have to
  /// resort to reading bridge logs to figure out what went wrong.
  String _describeError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      String? body;
      if (data is Map) {
        body = data['message']?.toString() ?? data['error']?.toString();
      } else if (data is String && data.isNotEmpty) {
        body = data;
      }
      if (code != null && body != null && body.isNotEmpty) {
        return 'Bridge $code: $body';
      }
      if (code != null) return 'Bridge HTTP $code: ${e.message ?? ''}';
    }
    return e.toString();
  }

  Future<void> refreshRun(String runId) async {
    final run = await getRun(runId);
    if (run == null || run.sessionId == null) return;
    final project = await getProject(run.projectId);
    if (project == null) return;

    final bridgeRunId = run.sessionId!;
    try {
      final statusResponse = await _dio.getUri<Map<String, dynamic>>(
        _bridgeUri(project.bridgeUrl, '/v1/runs/$bridgeRunId'),
      );
      await _applyRunStatus(runId, statusResponse.data ?? {});

      final after = await _lastBridgeSeq(runId);
      final eventsResponse = await _dio.getUri<Map<String, dynamic>>(
        _bridgeUri(
          project.bridgeUrl,
          '/v1/runs/$bridgeRunId/events?after=$after',
        ),
      );
      final events = eventsResponse.data?['events'];
      if (events is List) {
        for (final raw in events) {
          if (raw is Map) {
            await _persistBridgeEvent(
              runId,
              Map<String, dynamic>.from(raw),
            );
          }
        }
      }
      await refreshArtifacts(runId);
    } catch (e, stack) {
      _logger.warning('Failed to refresh dev agent run $runId', e, stack);
      await _insertLocalEvent(
        runId: runId,
        kind: 'error',
        payload: {'message': e.toString()},
      );
    }
  }

  Future<void> refreshArtifacts(String runId) async {
    final run = await getRun(runId);
    if (run == null || run.sessionId == null) return;
    final project = await getProject(run.projectId);
    if (project == null) return;

    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        _bridgeUri(project.bridgeUrl, '/v1/runs/${run.sessionId}/artifacts'),
      );
      final artifacts = response.data?['artifacts'];
      if (artifacts is! List) return;
      for (final raw in artifacts) {
        if (raw is Map) {
          await _upsertArtifact(runId, Map<String, dynamic>.from(raw));
        }
      }
    } catch (e) {
      _logger.fine('Artifact refresh skipped for $runId: $e');
    }
  }

  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
  }) async {
    final approval = await (_db.select(_db.devAgentApprovals)
          ..where((t) => t.id.equals(approvalId)))
        .getSingleOrNull();
    if (approval == null) {
      throw const DevAgentBridgeException('Approval request not found.');
    }
    final run = await getRun(approval.runId);
    if (run == null || run.sessionId == null) {
      throw const DevAgentBridgeException('Run is not connected to a bridge.');
    }
    final project = await getProject(run.projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }

    final status = approved ? 'approved' : 'denied';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await (_db.update(_db.devAgentApprovals)
          ..where((t) => t.id.equals(approvalId)))
        .write(
      DevAgentApprovalsCompanion(
        status: Value(status),
        respondedAt: Value(now),
      ),
    );

    try {
      await _dio.postUri<Map<String, dynamic>>(
        _bridgeUri(
          project.bridgeUrl,
          '/v1/runs/${run.sessionId}/approvals/$approvalId',
        ),
        data: {
          'decision': status,
          'responded_at': now,
        },
      );
      await _insertLocalEvent(
        runId: run.id,
        kind: 'status',
        payload: {
          'status': 'approval_$status',
          'approval_id': approvalId,
        },
      );
    } catch (e, stack) {
      _logger.warning('Failed to send approval response', e, stack);
      await (_db.update(_db.devAgentApprovals)
            ..where((t) => t.id.equals(approvalId)))
          .write(
        const DevAgentApprovalsCompanion(
          status: Value('pending'),
          respondedAt: Value(null),
        ),
      );
      rethrow;
    }
  }

  /// Legacy `/actions` shell kept alive while the App still references it. The
  /// authoritative path is `decideRun()` below — this one POSTs to the bridge's
  /// stub endpoint which only accepts `leave` (and returns 501 for the rest).
  /// Slated for removal once all callers move to `decideRun`.
  Future<void> runAction({
    required String runId,
    required String action,
  }) async {
    final run = await getRun(runId);
    if (run == null || run.sessionId == null) {
      throw const DevAgentBridgeException('Run is not connected to a bridge.');
    }
    final project = await getProject(run.projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }
    await _dio.postUri<Map<String, dynamic>>(
      _bridgeUri(project.bridgeUrl, '/v1/runs/${run.sessionId}/actions'),
      data: {'action': action},
    );
    await refreshRun(runId);
  }

  /// Send a post-run decision (`leave` / `discard` / `apply`) to the bridge.
  ///
  /// The app never executes git/shell itself — this only forwards the user's
  /// decision. The bridge owns worktrees and is responsible for actually
  /// applying or discarding changes. Read-only runs (which never produce a
  /// worktree) get `discard` / `apply` rejected with `no_worktree`.
  Future<DevAgentDecisionResult> decideRun(
    String runId,
    String decision,
  ) async {
    const allowed = {'leave', 'discard', 'apply'};
    if (!allowed.contains(decision)) {
      throw DevAgentBridgeException('Unknown decision: $decision');
    }
    final run = await getRun(runId);
    if (run == null) {
      throw const DevAgentBridgeException('Run not found.');
    }
    if (run.sessionId == null) {
      throw const DevAgentBridgeException('Run is not connected to a bridge.');
    }
    final project = await getProject(run.projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        _bridgeUri(
          project.bridgeUrl,
          '/v1/runs/${run.sessionId}/decision',
        ),
        data: {
          'decision': decision,
          'responded_at': now,
        },
        options: Options(
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      final payload = response.data ?? const <String, dynamic>{};
      final accepted = response.statusCode == 200 && payload['ok'] == true;
      await _insertLocalEvent(
        runId: runId,
        kind: 'decision',
        payload: {
          'decision': decision,
          'status': accepted ? 'accepted' : 'rejected',
          if (!accepted && payload['reason'] != null) 'reason': payload['reason'],
          if (!accepted && payload['message'] != null)
            'message': payload['message'],
        },
      );
      return DevAgentDecisionResult(
        accepted: accepted,
        reason: payload['reason']?.toString(),
        message: payload['message']?.toString(),
      );
    } catch (e, stack) {
      _logger.warning('Failed to send run decision', e, stack);
      rethrow;
    }
  }

  Future<void> abort(String runId) async {
    final run = await getRun(runId);
    if (run == null) return;
    final project = await getProject(run.projectId);
    if (project == null) return;

    if (run.sessionId != null) {
      await _dio.postUri<Map<String, dynamic>>(
        _bridgeUri(project.bridgeUrl, '/v1/runs/${run.sessionId}/abort'),
      );
    }
    await (_db.update(_db.devAgentRuns)..where((t) => t.id.equals(runId)))
        .write(
      DevAgentRunsCompanion(
        status: const Value('aborted'),
        endedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
    await _insertLocalEvent(
      runId: runId,
      kind: 'status',
      payload: {'status': 'aborted', 'message': 'Run aborted by user.'},
    );
  }

  Future<void> _applyRunStatus(
    String runId,
    Map<String, dynamic> payload,
  ) async {
    final status = payload['status']?.toString();
    if (status == null || status.isEmpty) return;
    final isTerminal = {'done', 'failed', 'aborted'}.contains(status);
    await (_db.update(_db.devAgentRuns)..where((t) => t.id.equals(runId)))
        .write(
      DevAgentRunsCompanion(
        status: Value(status),
        summary: Value(payload['summary']?.toString()),
        branch: Value(payload['branch']?.toString()),
        worktreePath: Value(payload['worktree_path']?.toString()),
        endedAt: isTerminal
            ? Value(DateTime.now().millisecondsSinceEpoch ~/ 1000)
            : const Value.absent(),
      ),
    );
  }

  Future<void> _persistBridgeEvent(
    String runId,
    Map<String, dynamic> raw,
  ) async {
    final kind = raw['kind']?.toString() ?? 'text';
    final payload = raw['payload'];
    final payloadMap = payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{'value': payload};
    if (raw['seq'] != null) payloadMap['bridge_seq'] = raw['seq'];
    await _insertLocalEvent(
      runId: runId,
      kind: kind,
      ts: _intOrNow(raw['ts']),
      payload: payloadMap,
    );
    if (kind == 'status') {
      await _applyRunStatus(runId, payloadMap);
    }
    if (kind == 'approval_request') {
      await _upsertApproval(runId, payloadMap);
    }
  }

  Future<void> _upsertApproval(
    String runId,
    Map<String, dynamic> payload,
  ) async {
    final id = payload['approval_id']?.toString() ?? _uuid.v4();
    final kind = payload['kind']?.toString() ?? 'command';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.devAgentApprovals).insertOnConflictUpdate(
          DevAgentApprovalsCompanion.insert(
            id: id,
            runId: runId,
            kind: kind,
            descriptionJson: jsonEncode(payload),
            status: 'pending',
            createdAt: now,
          ),
        );
  }

  Future<void> _upsertArtifact(
    String runId,
    Map<String, dynamic> payload,
  ) async {
    final id = payload['id']?.toString() ?? _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.devAgentArtifacts).insertOnConflictUpdate(
          DevAgentArtifactsCompanion.insert(
            id: id,
            runId: runId,
            kind: payload['kind']?.toString() ?? 'link',
            title: payload['title']?.toString() ?? 'Artifact',
            content: Value(payload['content']?.toString()),
            uri: Value(payload['uri']?.toString()),
            createdAt: _intOrNow(payload['created_at'] ?? now),
          ),
        );
  }

  Future<void> _insertLocalEvent({
    required String runId,
    required String kind,
    required Map<String, dynamic> payload,
    int? ts,
  }) {
    return _db.into(_db.devAgentEvents).insert(
          DevAgentEventsCompanion.insert(
            runId: runId,
            ts: ts ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
            kind: kind,
            payloadJson: jsonEncode(payload),
          ),
        );
  }

  Future<void> _markRunFailed(String runId, String message) async {
    await (_db.update(_db.devAgentRuns)..where((t) => t.id.equals(runId)))
        .write(
      DevAgentRunsCompanion(
        status: const Value('failed'),
        summary: Value(message),
        endedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
    await _insertLocalEvent(
      runId: runId,
      kind: 'error',
      payload: {'message': message},
    );
  }

  Future<int> _lastBridgeSeq(String runId) async {
    final rows = await listEvents(runId);
    var maxSeq = 0;
    for (final row in rows) {
      try {
        final payload = jsonDecode(row.payloadJson);
        if (payload is Map && payload['bridge_seq'] is int) {
          final seq = payload['bridge_seq'] as int;
          if (seq > maxSeq) maxSeq = seq;
        }
      } catch (_) {
        // Ignore malformed historical rows.
      }
    }
    return maxSeq;
  }

  int _intOrNow(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  Uri _bridgeUri(String baseUrl, String pathAndQuery) {
    final base = Uri.parse(baseUrl.trim());
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final pathOnly = pathAndQuery.split('?').first;
    final query = pathAndQuery.contains('?')
        ? pathAndQuery.substring(pathAndQuery.indexOf('?') + 1)
        : null;
    return base.replace(
      path: '$basePath$pathOnly',
      query: query,
    );
  }

  void _validateBridgeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority || uri.scheme != 'https') {
      throw const DevAgentBridgeException(
        'Bridge URL must be an HTTPS address. Tokens stay on the bridge side.',
      );
    }
  }

  void _validatePermissionTier(String value) {
    final allowed = DevProjectPermissionTier.values.map((e) => e.value).toSet();
    if (!allowed.contains(value)) {
      throw DevAgentBridgeException('Unsupported permission tier: $value');
    }
  }
}
