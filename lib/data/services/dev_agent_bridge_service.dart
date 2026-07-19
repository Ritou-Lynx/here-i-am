import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/memory_v3/services/project_memory_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';
import 'package:uuid/uuid.dart';

enum DevAgentType {
  claudeCode('claude_code'),
  codex('codex'),
  opencode('opencode');

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
    this.features = const [],
  });

  final bool ok;
  final String bridgeId;
  final String version;
  final List<String> agents;
  final List<String> features;

  bool get supportsGitOps => features.contains('git_pull');
}

class DevAgentBridgeException implements Exception {
  const DevAgentBridgeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Result of [DevAgentBridgeService.listOpencodeModels]. `models` is the
/// `provider/model` strings OpenCode knows about; `warning` carries any
/// non-fatal stderr the Bridge surfaced so the UI can show "OpenCode
/// isn't in PATH" / "opencode models returned empty" hints without the
/// caller having to know the failure modes.
class DevAgentOpencodeModels {
  const DevAgentOpencodeModels({
    this.models = const [],
    this.warning,
  });

  final List<String> models;
  final String? warning;

  bool get isEmpty => models.isEmpty;
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

class DevProjectGitStatus {
  const DevProjectGitStatus({
    required this.branch,
    required this.ahead,
    required this.behind,
    this.lastFetch,
    this.hasUncommittedChanges = false,
  });

  final String branch;
  final int ahead;
  final int behind;
  final int? lastFetch;
  final bool hasUncommittedChanges;

  factory DevProjectGitStatus.fromJson(Map<String, dynamic> json) {
    return DevProjectGitStatus(
      branch: json['branch']?.toString() ?? '',
      ahead: (json['ahead'] as num?)?.toInt() ?? 0,
      behind: (json['behind'] as num?)?.toInt() ?? 0,
      lastFetch: (json['lastFetch'] as num?)?.toInt(),
      hasUncommittedChanges: json['hasUncommittedChanges'] == true,
    );
  }
}

class DevGitOperationResult {
  const DevGitOperationResult({
    required this.ok,
    this.message,
    this.commits,
  });

  final bool ok;
  final String? message;
  final List<Map<String, dynamic>>? commits;

  factory DevGitOperationResult.fromJson(Map<String, dynamic> json) {
    final rawCommits = json['commits'];
    return DevGitOperationResult(
      ok: json['ok'] == true,
      message: json['message']?.toString(),
      commits: rawCommits is List
          ? rawCommits.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : null,
    );
  }
}

class ProjectMemorySyncResult {
  const ProjectMemorySyncResult({
    required this.received,
    required this.inserted,
    required this.duplicates,
    required this.asOf,
  });

  final int received;
  final int inserted;
  final int duplicates;
  final String? asOf;
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
  static bool get isInitialized => _instance != null;
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

  static String? validateBridgeUrlError(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority) {
      return 'Bridge URL must be a complete address.';
    }
    if (uri.scheme == 'https') {
      return null;
    }
    if (kDebugMode && uri.scheme == 'http' && _isDebugLoopbackHost(uri.host)) {
      return null;
    }
    return 'Bridge URL must be HTTPS. Debug builds also allow loopback HTTP for USB testing.';
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
    String? defaultOpencodeModel,
  }) async {
    final projectId = id ?? _uuid.v4();
    _validateBridgeUrl(bridgeUrl);
    _validatePermissionTier(permissionTier);

    final trimmedModel = defaultOpencodeModel?.trim();

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
            defaultOpencodeModel: Value(
              trimmedModel != null && trimmedModel.isNotEmpty
                  ? trimmedModel
                  : null,
            ),
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

  /// Fetches git status from the bridge for a project.
  ///
  /// Returns ahead/behind counts and branch info. The bridge runs
  /// `git fetch` (if configured) and `git status` on the main working copy.
  Future<DevProjectGitStatus> getGitStatus(String projectId) async {
    final project = await getProject(projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }
    try {
      final query = Uri(
        queryParameters: {
          'root_path': project.rootPath,
          'default_branch': project.defaultBranch,
          'name': project.name,
          'permission_tier': project.permissionTier,
        },
      ).query;
      final response = await _dio.getUri<Map<String, dynamic>>(
        _bridgeUri(
          project.bridgeUrl,
          '/v1/projects/$projectId/git-status?$query',
        ),
      );
      return DevProjectGitStatus.fromJson(response.data ?? {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const DevAgentBridgeException(
          'Bridge does not support git operations. Update the bridge to the latest version.',
        );
      }
      throw DevAgentBridgeException(_describeError(e));
    } catch (e, stack) {
      _logger.warning('Failed to fetch git status for $projectId', e, stack);
      rethrow;
    }
  }

  /// Pulls remote changes for a project's default branch (fast-forward only).
  ///
  /// Requires [DevProjectPermissionTier.workspaceWrite] or higher.
  /// The bridge executes `git fetch && git merge --ff-only origin/<branch>`
  /// on the main working copy (not a worktree).
  Future<DevGitOperationResult> pullGit(String projectId) async {
    final project = await getProject(projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }
    _validateBridgeUrl(project.bridgeUrl);
    final tier = project.permissionTier;
    if (tier == 'read_only') {
      throw const DevAgentBridgeException(
        'Git pull requires workspace_write or higher permission tier.',
      );
    }
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        _bridgeUri(project.bridgeUrl, '/v1/projects/$projectId/git-pull'),
      );
      return DevGitOperationResult.fromJson(response.data ?? {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const DevAgentBridgeException(
          'Bridge does not support git operations. Update the bridge to the latest version.',
        );
      }
      throw DevAgentBridgeException(_describeError(e));
    } catch (e, stack) {
      _logger.warning('Failed to pull git for $projectId', e, stack);
      rethrow;
    }
  }

  /// Pushes local commits for a project's default branch.
  ///
  /// Requires [DevProjectPermissionTier.releaseOps]. The bridge executes
  /// `git push origin <branch>` on the main working copy.
  Future<DevGitOperationResult> pushGit(String projectId) async {
    final project = await getProject(projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }
    _validateBridgeUrl(project.bridgeUrl);
    final tier = project.permissionTier;
    if (tier != 'release_ops') {
      throw const DevAgentBridgeException(
        'Git push requires release_ops permission tier.',
      );
    }
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        _bridgeUri(project.bridgeUrl, '/v1/projects/$projectId/git-push'),
      );
      return DevGitOperationResult.fromJson(response.data ?? {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const DevAgentBridgeException(
          'Bridge does not support git operations. Update the bridge to the latest version.',
        );
      }
      throw DevAgentBridgeException(_describeError(e));
    } catch (e, stack) {
      _logger.warning('Failed to push git for $projectId', e, stack);
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
    String? defaultModel,
  }) async {
    final project = await getProject(projectId);
    if (project == null) {
      throw const DevAgentBridgeException('Dev project not found.');
    }
    final trimmedTitle = title.trim().isEmpty ? 'Dev Session' : title.trim();
    final trimmedModel = defaultModel?.trim();
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
            // A session-level override (e.g. set from chat "use <model> for
            // this run") wins over the project's default. We store it on the
            // session so every run started from this session reuses it.
            defaultModel: Value(
              trimmedModel != null && trimmedModel.isNotEmpty
                  ? trimmedModel
                  : project.defaultOpencodeModel,
            ),
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
    String? model,
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
      model: model,
    );
    // If the user explicitly chose a model mid-session, persist it on the
    // session so the next continue without args reuses the same one.
    final trimmedModel = model?.trim();
    if (trimmedModel != null && trimmedModel.isNotEmpty) {
      await (_db.update(_db.devAgentSessions)
            ..where((t) => t.id.equals(sessionId)))
          .write(
        DevAgentSessionsCompanion(
          defaultModel: Value(trimmedModel),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        ),
      );
    }
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
    final Map<String, dynamic> data;
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        _bridgeUri(bridgeUrl, '/v1/health'),
      );
      data = response.data ?? {};
    } on DioException catch (e) {
      throw DevAgentBridgeException(_describeError(e));
    }
    final agents = data['agents'];
    final features = data['features'];
    final health = DevAgentBridgeHealth(
      ok: data['ok'] == true,
      bridgeId: data['bridge_id']?.toString() ?? 'unknown',
      version: data['version']?.toString() ?? 'unknown',
      agents: agents is List ? agents.map((e) => e.toString()).toList() : [],
      features: features is List
          ? features.map((e) => e.toString()).toList()
          : const [],
    );
    if (health.ok && health.features.contains('project_memory_projection')) {
      unawaited(syncProjectMemory(bridgeUrl).catchError((Object error) {
        _logger.warning('Background Project Memory sync skipped: $error');
        return const ProjectMemorySyncResult(
          received: 0,
          inserted: 0,
          duplicates: 0,
          asOf: null,
        );
      }));
    }
    return health;
  }

  /// Lists every `provider/model` OpenCode currently exposes. Used by the
  /// DevRoom project-settings dropdown. Returns an empty list (with a
  /// warning message, if any) when the Bridge can't enumerate models —
  /// callers should fall back to letting the user type the model id by
  /// hand in that case.
  Future<DevAgentOpencodeModels> listOpencodeModels(String bridgeUrl) async {
    _validateBridgeUrl(bridgeUrl);
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        _bridgeUri(bridgeUrl, '/v1/opencode-models'),
      );
      final data = response.data ?? const <String, dynamic>{};
      final raw = data['models'];
      final models = raw is List
          ? raw.map((e) => e.toString()).where((s) => s.contains('/')).toList()
          : const <String>[];
      return DevAgentOpencodeModels(
        models: models,
        warning: data['warning']?.toString(),
      );
    } on DioException catch (e) {
      _logger.fine('opencode-models probe failed: ${e.message}');
      return const DevAgentOpencodeModels();
    }
  }

  /// Best-effort startup refresh for every configured Bridge endpoint.
  ///
  /// Multiple Dev Room projects may share one Bridge, so each normalized URL
  /// is contacted only once. Callers should not block app startup on failure.
  Future<ProjectMemorySyncResult> syncConfiguredProjectMemory() async {
    final projects = await listProjects();
    final bridgeUrls = projectMemoryBridgeUrlsForTesting(
      projects.map((project) => project.bridgeUrl),
      includeDebugLoopback: kDebugMode,
    );
    var received = 0;
    var inserted = 0;
    var duplicates = 0;
    String? latestAsOf;
    for (final bridgeUrl in bridgeUrls) {
      try {
        final result = await syncProjectMemory(bridgeUrl);
        received += result.received;
        inserted += result.inserted;
        duplicates += result.duplicates;
        latestAsOf = result.asOf ?? latestAsOf;
      } catch (error) {
        _logger.warning(
          'Startup Project Memory sync skipped for $bridgeUrl: $error',
        );
      }
    }
    return ProjectMemorySyncResult(
      received: received,
      inserted: inserted,
      duplicates: duplicates,
      asOf: latestAsOf,
    );
  }

  @visibleForTesting
  static Set<String> projectMemoryBridgeUrlsForTesting(
    Iterable<String> configuredUrls, {
    required bool includeDebugLoopback,
  }) {
    final urls = configuredUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet();
    // USB reverse maps the phone's loopback port to the trusted development
    // machine. This keeps debug Project Memory usable even when the Dev Room
    // project table is empty (for example after restoring/reinstalling data).
    if (includeDebugLoopback) {
      urls.add('http://127.0.0.1:47831');
    }
    return urls;
  }

  /// Pulls only policy-approved Project Memory projections from the trusted
  /// Dev Room Bridge. The projection service revalidates every envelope and
  /// writes idempotently; no raw Gateway ledger or transcript reaches the app.
  Future<ProjectMemorySyncResult> syncProjectMemory(
    String bridgeUrl, {
    DateTime? after,
    int limit = 100,
  }) async {
    _validateBridgeUrl(bridgeUrl);
    final uri = _bridgeUri(bridgeUrl, '/v1/project-memory/projections').replace(
      queryParameters: {
        if (after != null) 'after': after.toUtc().toIso8601String(),
        'limit': limit.clamp(1, 500).toString(),
      },
    );
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(uri);
      final data = response.data ?? const <String, dynamic>{};
      final raw = data['projections'];
      final projections = raw is List ? raw : const [];
      final service = ProjectMemoryService(_db);
      var inserted = 0;
      var duplicates = 0;
      for (final value in projections) {
        if (value is! Map) continue;
        final envelope = ProjectMemoryProjectionEnvelope.fromJson(
          Map<String, dynamic>.from(value),
        );
        if (await service.project(envelope)) {
          inserted += 1;
        } else {
          duplicates += 1;
        }
      }
      return ProjectMemorySyncResult(
        received: projections.length,
        inserted: inserted,
        duplicates: duplicates,
        asOf: data['as_of']?.toString(),
      );
    } catch (error, stack) {
      _logger.warning('Project Memory sync failed', error, stack);
      throw DevAgentBridgeException('Project Memory sync failed: $error');
    }
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
    String? model,
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

    // Resolve model in priority order: explicit `model` arg > project
    // default. For OpenCode runs the Bridge will further fall back to
    // DEV_AGENT_OPENCODE_MODEL / opencode.jsonc default when we don't
    // send anything. We always persist the resolved model on the run row
    // so the App can show "OpenCode / qwen3.7-max" without re-querying
    // the bridge.
    final resolvedModel = _resolveModel(
      explicitModel: model,
      projectDefault: project.defaultOpencodeModel,
    );

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
            model: Value(resolvedModel),
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
          if (resolvedModel != null) 'model': resolvedModel,
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

    // B-path: assemble the run's text events into a single chat message,
    // authored by the character but written in the coding agent's own
    // voice. No LLM second-narration — engineering results flow through
    // verbatim, which is what the user explicitly asked for.
    final textEvents = await _loadRunTextEvents(runId);
    final body = textEvents.isNotEmpty
        ? textEvents.join('\n\n').trim()
        : (summary.trim().isEmpty ? '这轮没有返回内容。' : summary.trim());
    final content = _buildOwnerChatMessage(
      agentType: session.agentType,
      status: status,
      summary: body,
    );

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
    // Also keep the dev session message record in sync (used by Dev Room
    // screen to show what was said about each run).
    await _insertSessionMessage(
      sessionId: session.id,
      role: 'character',
      content: content,
      linkedRunId: runId,
    );
  }

  /// Loads all `text`-kind events for [runId] in chronological order and
  /// returns their payloads as plain strings. The result is concatenated
  /// by the caller to form the chat message body.
  Future<List<String>> _loadRunTextEvents(String runId) async {
    final rows = await (_db.select(_db.devAgentEvents)
          ..where((t) => t.runId.equals(runId) & t.kind.equals('text'))
          ..orderBy([(t) => OrderingTerm.asc(t.ts)]))
        .get();
    final out = <String>[];
    for (final row in rows) {
      try {
        final payload = jsonDecode(row.payloadJson);
        if (payload is Map) {
          final text = payload['text']?.toString();
          if (text != null && text.trim().isNotEmpty) out.add(text.trim());
        }
      } catch (_) {
        // ignore un-parseable rows
      }
    }
    return out;
  }

  // Note: _postTemplateRunSummaryToOwnerChat was removed when we switched
  // the run-completion flow to the B-path (direct text-event passthrough
  // instead of an LLM-driven follow-up task). If you ever need the old
  // template-driven fallback again, see git history for restore.

  String _buildOwnerChatMessage({
    required String agentType,
    required String status,
    required String summary,
  }) {
    final agentName = _agentDisplayName(agentType);
    final trimmed = summary.trim();
    final body = trimmed.isEmpty ? '这轮没有返回内容。' : trimmed;
    // B-path messaging: engineering results flow through verbatim. The
    // character introduces the run result with the agent's name so the
    // chat shows it as a delivered work item, not as 林埃's own narration.
    // Worktree state (branch / accept / discard) lives in the addendum
    // card below the message — no need to verbally send users to Dev
    // Room anymore.
    if (status == 'done') {
      return '$agentName 跑完了：\n\n$body';
    }
    if (status == 'aborted') {
      return '$agentName 这轮被停了：\n\n$body';
    }
    return '$agentName 这轮没成功：\n\n$body';
  }

  /// Human-readable agent name for chat messages and UI labels.
  static String _agentDisplayName(String agentType) {
    return switch (agentType) {
      'claude_code' => 'Claude Code',
      'opencode' => 'OpenCode',
      _ => 'Codex',
    };
  }

  /// Pick the model id for a new run. Explicit overrides (per-call or
  /// session-level) win; project default is the next fall-through; null
  /// here means "let the Bridge pick" (DEV_AGENT_OPENCODE_MODEL /
  /// opencode.jsonc default).
  static String? _resolveModel({
    String? explicitModel,
    String? projectDefault,
  }) {
    String? chosen = explicitModel?.trim();
    if (chosen == null || chosen.isEmpty) {
      chosen = projectDefault?.trim();
    }
    if (chosen == null || chosen.isEmpty) return null;
    return chosen;
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
    final error = validateBridgeUrlError(value);
    if (error != null) {
      throw DevAgentBridgeException(error);
    }
  }

  void _validatePermissionTier(String value) {
    final allowed = DevProjectPermissionTier.values.map((e) => e.value).toSet();
    if (!allowed.contains(value)) {
      throw DevAgentBridgeException('Unsupported permission tier: $value');
    }
  }
}
