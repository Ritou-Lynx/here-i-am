import 'package:drift/drift.dart';

/// Projects that can be controlled from Dev Room.
///
/// These rows describe remote development machines/projects only. They are
/// process/control data and must not be treated as User-truth.
class DevProjects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get rootPath => text()();
  TextColumn get defaultBranch => text().withDefault(const Constant('main'))();
  TextColumn get bridgeUrl => text()();
  TextColumn get permissionTier =>
      text().withDefault(const Constant('read_only'))();

  /// Default OpenCode `provider/model` used when the user does not specify
  /// one in chat and the active session has no override. NULL = fall back
  /// to opencode.jsonc / DEV_AGENT_OPENCODE_MODEL. The companion UI in
  /// Dev Room exposes this as a dropdown so users can switch between their
  /// ollama-cloud / opencode-go / minimax-cn-coding-plan quotas without
  /// restarting the bridge.
  TextColumn get defaultOpencodeModel => text().nullable()();

  /// Codex defaults are independent from OpenCode. NULL means inherit the
  /// development computer's Codex config.toml.
  TextColumn get defaultCodexModel => text().nullable()();
  TextColumn get defaultCodexReasoningEffort => text().nullable()();
  TextColumn get defaultCodexServiceTier => text().nullable()();
  TextColumn get defaultCodexVerbosity => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One remote Claude Code / Codex execution.
class DevAgentRuns extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(DevProjects, #id)();
  TextColumn get agentType => text()();
  TextColumn get devSessionId => text().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get initialPrompt => text()();
  TextColumn get status => text()();
  TextColumn get branch => text().nullable()();
  TextColumn get worktreePath => text().nullable()();

  /// Model requested for this run. OpenCode uses provider/model; Codex uses
  /// its model slug. NULL means the development computer chose its default.
  TextColumn get model => text().nullable()();
  TextColumn get reasoningEffort => text().nullable()();
  TextColumn get serviceTier => text().nullable()();
  TextColumn get verbosity => text().nullable()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  TextColumn get summary => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A multi-turn control thread around one or more remote agent runs.
///
/// The provider-side session id still lives on [DevAgentRuns.sessionId]. This
/// table is the app-side conversation shell used by Dev Room and companion
/// roles to keep follow-up tasks together.
class DevAgentSessions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(DevProjects, #id)();
  TextColumn get agentType => text()();
  TextColumn get title => text()();
  TextColumn get goal => text().nullable()();
  TextColumn get mode => text().withDefault(const Constant('read_only'))();
  TextColumn get ownerCharacterId => text().nullable()();
  TextColumn get providerSessionId => text().nullable()();

  /// Session-level model override (e.g. set by `use ollama-cloud/... for
  /// this run` in chat). Wins over the project's default and persists
  /// across every run started from this session, so a user saying
  /// "继续刚才那个" doesn't have to repeat the model every turn.
  TextColumn get defaultModel => text().nullable()();
  TextColumn get defaultReasoningEffort => text().nullable()();
  TextColumn get defaultServiceTier => text().nullable()();
  TextColumn get defaultVerbosity => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User / character / agent messages inside a Dev Session.
class DevAgentSessionMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(DevAgentSessions, #id)();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get linkedRunId => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Which companion roles may summon which project agent tool.
class DevAgentToolBindings extends Table {
  TextColumn get characterId => text()();
  TextColumn get projectId => text().references(DevProjects, #id)();
  TextColumn get agentType => text()();
  TextColumn get defaultPermissionTier =>
      text().withDefault(const Constant('read_only'))();
  TextColumn get defaultMode =>
      text().withDefault(const Constant('read_only'))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {characterId, projectId, agentType};
}

/// Normalized stream events emitted by the bridge.
class DevAgentEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get runId => text().references(DevAgentRuns, #id)();
  IntColumn get ts => integer()();
  TextColumn get kind => text()();
  TextColumn get payloadJson => text()();
}

/// One approval request, answered independently.
class DevAgentApprovals extends Table {
  TextColumn get id => text()();
  TextColumn get runId => text().references(DevAgentRuns, #id)();
  TextColumn get kind => text()();
  TextColumn get descriptionJson => text()();
  TextColumn get status => text()();
  IntColumn get createdAt => integer()();
  IntColumn get respondedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
