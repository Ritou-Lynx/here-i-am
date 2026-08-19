import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v59 to v60 adds Codex controls and preserves Dev Room rows', () async {
    final tempDir = Directory.systemTemp.createTempSync('dev_room_v60_');
    final file = File('${tempDir.path}/test.db');
    final raw = sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE dev_projects (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        root_path TEXT NOT NULL,
        default_branch TEXT NOT NULL DEFAULT 'main',
        bridge_url TEXT NOT NULL,
        permission_tier TEXT NOT NULL DEFAULT 'read_only',
        default_opencode_model TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    raw.execute('''
      CREATE TABLE dev_agent_sessions (
        id TEXT PRIMARY KEY NOT NULL,
        project_id TEXT NOT NULL,
        agent_type TEXT NOT NULL,
        title TEXT NOT NULL,
        goal TEXT,
        mode TEXT NOT NULL DEFAULT 'read_only',
        owner_character_id TEXT,
        provider_session_id TEXT,
        default_model TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    raw.execute('''
      CREATE TABLE dev_agent_runs (
        id TEXT PRIMARY KEY NOT NULL,
        project_id TEXT NOT NULL,
        agent_type TEXT NOT NULL,
        dev_session_id TEXT,
        session_id TEXT,
        initial_prompt TEXT NOT NULL,
        status TEXT NOT NULL,
        branch TEXT,
        worktree_path TEXT,
        model TEXT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        summary TEXT
      )
    ''');
    raw.execute("""
      INSERT INTO dev_projects VALUES
      ('p1', 'Here I am', 'D:/memex', 'v3-lab', 'https://bridge.test',
       'read_only', 'provider/model', 1)
    """);
    raw.execute("""
      INSERT INTO dev_agent_sessions
      (id, project_id, agent_type, title, default_model, created_at, updated_at)
      VALUES ('s1', 'p1', 'codex', 'Audit', 'legacy-model', 1, 1)
    """);
    raw.execute("""
      INSERT INTO dev_agent_runs
      (id, project_id, agent_type, initial_prompt, status, model, started_at)
      VALUES ('r1', 'p1', 'codex', 'Review', 'done', 'legacy-model', 1)
    """);
    raw.execute('PRAGMA user_version = 59');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 60);

    Future<Set<String>> columns(String table) async {
      final rows = await db.customSelect('PRAGMA table_info($table)').get();
      return rows.map((row) => row.data['name'] as String).toSet();
    }

    expect(
      await columns('dev_projects'),
      containsAll({
        'default_codex_model',
        'default_codex_reasoning_effort',
        'default_codex_service_tier',
        'default_codex_verbosity',
      }),
    );
    expect(
      await columns('dev_agent_sessions'),
      containsAll({
        'default_reasoning_effort',
        'default_service_tier',
        'default_verbosity',
      }),
    );
    expect(
      await columns('dev_agent_runs'),
      containsAll({'reasoning_effort', 'service_tier', 'verbosity'}),
    );
    expect((await db.select(db.devProjects).getSingle()).name, 'Here I am');
    expect((await db.select(db.devAgentSessions).getSingle()).title, 'Audit');
    expect(
        (await db.select(db.devAgentRuns).getSingle()).model, 'legacy-model');

    await db.close();
    file.deleteSync();
    tempDir.deleteSync();
  });
}
