import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/persona_chat_service.dart';
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
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Future<List<DevProject>> listProjects() {
    final query = _db.select(_db.devProjects)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
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

  /// Walks all terminal runs of [projectId] that still have a worktree, and
  /// asks the bridge to clean them up. Returns (removed, failed) counts.
  Future<({int removed, int failed})> cleanupProjectWorktrees(
    String projectId,
  ) async {
    final project = await getProject(projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        _bridgeUri(project.bridgeUrl, '/v1/cleanup/worktrees'),
        data: {'project_id': projectId},
      );
      final data = response.data ?? const <String, dynamic>{};
      final failures = data['failures'];
      return (
        removed: (data['removed'] as num?)?.toInt() ?? 0,
        failed: failures is List ? failures.length : 0,
      );
    } catch (e, stack) {
      _logger.warning('Failed to cleanup worktrees', e, stack);
      rethrow;
    }
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

  Stream<List<DevAgentSession>> watchSessions({String? projectId}) {
    final query = _db.select(_db.devAgentSessions)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    if (projectId != null) {
      query.where((t) => t.projectId.equals(projectId));
    }
    return query.watch();
  }

  Future<DevAgentSession?> getSession(String sessionId) {
    return (_db.select(_db.devAgentSessions)
          ..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
  }

  Future<List<DevAgentSession>> listSessions({
    String? projectId,
    String? ownerCharacterId,
    String? agentType,
    String? status,
    int limit = 20,
  }) {
    final query = _db.select(_db.devAgentSessions)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit);
    if (projectId != null) {
      query.where((t) => t.projectId.equals(projectId));
    }
    if (ownerCharacterId != null) {
      query.where((t) => t.ownerCharacterId.equals(ownerCharacterId));
    }
    if (agentType != null) {
      query.where((t) => t.agentType.equals(agentType));
    }
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    return query.get();
  }

  Stream<DevAgentSession?> watchSession(String sessionId) {
    final query = _db.select(_db.devAgentSessions)
      ..where((t) => t.id.equals(sessionId));
    return query.watchSingleOrNull();
  }

  Stream<List<DevAgentSessionMessage>> watchSessionMessages(
    String sessionId,
  ) {
    final query = _db.select(_db.devAgentSessionMessages)
      ..where((t) => t.sessionId.equals(sessionId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch();
  }

  Future<String> createSession({
    required String projectId,
    required DevAgentType agentType,
    required String title,
    String? goal,
    String? ownerCharacterId,
    String mode = 'read_only',
  }) async {
    final project = await getProject(projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }
    final trimmedTitle = title.trim().isEmpty ? 'Dev Session' : title.trim();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sessionId = _uuid.v4();
    await _db.into(_db.devAgentSessions).insert(
          DevAgentSessionsCompanion.insert(
            id: sessionId,
            projectId: projectId,
            agentType: agentType.value,
            title: trimmedTitle,
            goal: Value(goal?.trim().isEmpty == true ? null : goal?.trim()),
            mode: Value(mode),
            ownerCharacterId: Value(ownerCharacterId),
            status: const Value('active'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return sessionId;
  }

  Future<String> continueSession({
    required String sessionId,
    required String message,
  }) async {
    final session = await getSession(sessionId);
    if (session == null) {
      throw const DevAgentBridgeException('Dev session not found.');
    }
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      throw const DevAgentBridgeException('Message cannot be empty.');
    }
    final bridgePrompt = await _buildSessionPrompt(session, trimmed);
    await _insertSessionMessage(
      sessionId: sessionId,
      role: 'user',
      content: trimmed,
    );
    final runId = await startRun(
      projectId: session.projectId,
      prompt: trimmed,
      bridgePrompt: bridgePrompt,
      agentType: DevAgentType.values.firstWhere(
        (type) => type.value == session.agentType,
        orElse: () => DevAgentType.codex,
      ),
      devSessionId: sessionId,
    );
    await _insertSessionMessage(
      sessionId: sessionId,
      role: 'system',
      content: 'Started a linked run.',
      linkedRunId: runId,
    );
    return runId;
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
    String? bridgePrompt,
    String? devSessionId,
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
    final promptForBridge = (bridgePrompt?.trim().isNotEmpty == true)
        ? bridgePrompt!.trim()
        : trimmedPrompt;

    final runId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.devAgentRuns).insert(
          DevAgentRunsCompanion.insert(
            id: runId,
            projectId: project.id,
            agentType: agentType.value,
            devSessionId: Value(devSessionId),
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
          'prompt': promptForBridge,
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
      if (devSessionId != null) {
        await (_db.update(_db.devAgentSessions)
              ..where((t) => t.id.equals(devSessionId)))
            .write(
          DevAgentSessionsCompanion(
            providerSessionId: Value(sessionId),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ),
        );
      }
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
          if (!accepted && payload['reason'] != null)
            'reason': payload['reason'],
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
    final runBeforeUpdate = await getRun(runId);
    final isTerminal = {'done', 'failed', 'aborted'}.contains(status);
    final summary = payload['summary']?.toString();
    await (_db.update(_db.devAgentRuns)..where((t) => t.id.equals(runId)))
        .write(
      DevAgentRunsCompanion(
        status: Value(status),
        summary: Value(summary),
        branch: Value(payload['branch']?.toString()),
        worktreePath: Value(payload['worktree_path']?.toString()),
        endedAt: isTerminal
            ? Value(DateTime.now().millisecondsSinceEpoch ~/ 1000)
            : const Value.absent(),
      ),
    );
    if (isTerminal && runBeforeUpdate?.devSessionId != null) {
      await _upsertRunSummaryMessage(
        sessionId: runBeforeUpdate!.devSessionId!,
        runId: runId,
        status: status,
        summary: summary,
      );
    }
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

  Future<String> _insertSessionMessage({
    required String sessionId,
    required String role,
    required String content,
    String? linkedRunId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.devAgentSessionMessages).insert(
          DevAgentSessionMessagesCompanion.insert(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            linkedRunId: Value(linkedRunId),
            createdAt: now,
          ),
        );
    await (_db.update(_db.devAgentSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(DevAgentSessionsCompanion(updatedAt: Value(now)));
    return id;
  }

  Future<String> _buildSessionPrompt(
    DevAgentSession session,
    String newMessage,
  ) async {
    final query = _db.select(_db.devAgentSessionMessages)
      ..where((t) => t.sessionId.equals(session.id))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(12);
    final recent = (await query.get()).reversed.toList();
    if (recent.isEmpty && (session.goal == null || session.goal!.isEmpty)) {
      return newMessage;
    }
    final buffer = StringBuffer()
      ..writeln('You are continuing an app-side Dev Session.')
      ..writeln('Session title: ${session.title}');
    if (session.goal != null && session.goal!.trim().isNotEmpty) {
      buffer.writeln('Session goal: ${session.goal}');
    }
    if (recent.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Recent session messages:');
      for (final message in recent) {
        buffer.writeln('[${message.role}] ${message.content}');
      }
    }
    buffer
      ..writeln()
      ..writeln('New user request:')
      ..writeln(newMessage)
      ..writeln()
      ..writeln(
        'Continue from the prior session context, inspect the project as needed, '
        'and keep the final answer concise for the phone UI.',
      );
    return buffer.toString();
  }

  Future<void> _upsertRunSummaryMessage({
    required String sessionId,
    required String runId,
    required String status,
    String? summary,
  }) async {
    final content = summary?.trim().isNotEmpty == true
        ? summary!.trim()
        : 'Run finished with status: $status';
    final existing = await (_db.select(_db.devAgentSessionMessages)
          ..where(
            (t) =>
                t.sessionId.equals(sessionId) &
                t.linkedRunId.equals(runId) &
                t.role.equals('agent'),
          ))
        .getSingleOrNull();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (existing == null) {
      await _insertSessionMessage(
        sessionId: sessionId,
        role: 'agent',
        content: content,
        linkedRunId: runId,
      );
      await _postRunSummaryToOwnerChat(
        sessionId: sessionId,
        runId: runId,
        status: status,
        summary: content,
      );
    } else {
      await (_db.update(_db.devAgentSessionMessages)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        DevAgentSessionMessagesCompanion(
          content: Value(content),
          createdAt: Value(now),
        ),
      );
      await (_db.update(_db.devAgentSessions)
            ..where((t) => t.id.equals(sessionId)))
          .write(DevAgentSessionsCompanion(updatedAt: Value(now)));
    }
  }

  Future<void> _postRunSummaryToOwnerChat({
    required String sessionId,
    required String runId,
    required String status,
    required String summary,
  }) async {
    final session = await getSession(sessionId);
    final characterId = session?.ownerCharacterId;
    if (session == null || characterId == null || characterId.isEmpty) {
      return;
    }
    final run = await getRun(runId);
    final content = _buildOwnerChatMessage(
      agentType: session.agentType,
      status: status,
      summary: summary,
    );
    try {
      await PersonaChatService.instance.addCharacterMessage(
        characterId,
        content,
        isRead: false,
        timestamp: DateTime.now(),
        addenda: [
          {
            'type': 'dev_session',
            'sessionId': session.id,
            'runId': runId,
            'title': session.title,
            'agentType': session.agentType,
            'status': status,
            if (run?.branch != null) 'branch': run!.branch,
            if (run?.worktreePath != null) 'worktreePath': run!.worktreePath,
          },
        ],
      );
      await _insertSessionMessage(
        sessionId: sessionId,
        role: 'character',
        content: content,
        linkedRunId: runId,
      );
    } catch (e, stack) {
      _logger.warning('Failed to post dev session result to chat', e, stack);
    }
  }

  String _buildOwnerChatMessage({
    required String agentType,
    required String status,
    required String summary,
  }) {
    final agentName =
        agentType == DevAgentType.claudeCode.value ? 'Claude Code' : 'Codex';
    final trimmed = summary.trim();
    final body = trimmed.isEmpty ? '这轮没有返回摘要。' : trimmed;
    if (status == 'done') {
      return '我让 $agentName 跑完了，结果回来了：\n\n$body\n\n详情我放在下面这张 Dev Session 卡片里了，你可以点进去继续追问。';
    }
    if (status == 'aborted') {
      return '$agentName 这轮已经停止了：\n\n$body\n\n我把现场留在 Dev Room 里了。';
    }
    return '$agentName 这轮没有顺利完成：\n\n$body\n\n我把详情放在 Dev Room 里了，我们可以点进去看哪里卡住。';
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
