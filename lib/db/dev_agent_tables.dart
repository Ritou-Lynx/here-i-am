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
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One remote Claude Code / Codex execution.
class DevAgentRuns extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(DevProjects, #id)();
  TextColumn get agentType => text()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get initialPrompt => text()();
  TextColumn get status => text()();
  TextColumn get branch => text().nullable()();
  TextColumn get worktreePath => text().nullable()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  TextColumn get summary => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
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
