import 'package:drift/drift.dart';

import 'dev_agent_tables.dart';

/// Durable outputs from a Dev Agent run, such as diffs, test logs, reviews, or
/// PR links. These are Dev Room process artifacts, not User-truth.
class DevAgentArtifacts extends Table {
  TextColumn get id => text()();
  TextColumn get runId => text().references(DevAgentRuns, #id)();
  TextColumn get kind => text()();
  TextColumn get title => text()();
  TextColumn get content => text().nullable()();
  TextColumn get uri => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
