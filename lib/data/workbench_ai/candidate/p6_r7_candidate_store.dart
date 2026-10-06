import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../db/app_database.dart';
import '../../memory_v3/models/task_room_enums.dart';
import '../../memory_v3/services/task_room_service.dart';
import '../task_queue/workbench_task_queue_tool_host.dart';
import 'p6_r7_candidate_config.dart';
import 'p6_r7_recovery_identity.dart';

/// Candidate-only ownership metadata is kept beside and inside its private DB.
/// No call here selects an ordinary user, AppDatabase.init or the default path.
class P6R7CandidateStore {
  P6R7CandidateStore._(this.database, this._lock, this.datasetId, this.taskId,
      this.originIdentityHash);
  final AppDatabase database;
  final RandomAccessFile _lock;
  final String datasetId;
  String? taskId;
  final String originIdentityHash;
  bool _closed = false;

  String get conversationId => 'p6-r7-candidate-$datasetId';
  static const databaseName = 'candidate.sqlite';
  static const markerName = 'candidate.json';
  static const lockName = 'candidate.lock';
  static const _schema = 'p6_r7_candidate_dataset_v1';
  static const _table = 'p6_r7_candidate_identity';

  static Map<String, Object> _identity(P6R7CandidateConfiguration config) => {
        'schema': _schema,
        'dataset_id': p.basename(config.dataDirectory).substring(4),
        'directory': config.dataDirectory,
        'database': databaseName,
        'admission_sha256': config.admissionSha256,
        'source_closure_sha256': config.sourceClosureSha256,
        'native_sha256': p6R7NativeHash,
      };

  static void _checkEntries(String directory) {
    for (final entry in Directory(directory).listSync(followLinks: false)) {
      candidateCheck(const {
        databaseName,
        markerName,
        lockName,
        '$databaseName-wal',
        '$databaseName-shm'
      }.contains(p.basename(entry.path)));
      candidateCanonicalPath(entry.path);
      candidateCheck(FileSystemEntity.isFileSync(entry.path));
    }
  }

  /// Read-only pre-spawn inspection. This returns data, never a recovery permit.
  /// The caller supplies the still-live witness's accepted origin hash.
  static P6R7RecoveryInspection inspectOrigin(P6R7TrustedOrigin trusted) {
    final directory = candidateCanonicalPath(trusted.canonicalDirectory);
    _checkEntries(directory);
    final marker = File(p.join(directory, markerName));
    final dbFile = File(p.join(directory, databaseName));
    candidateCheck(marker.existsSync() &&
        dbFile.existsSync() &&
        File(p.join(directory, lockName)).existsSync() &&
        marker.lengthSync() <= 8192 &&
        dbFile.lengthSync() >= 100);
    // A missing WAL/SHM partner or hot rollback journal is not repaired here.
    // _checkEntries rejects rollback journals and any other unexpected file.
    final wal = File('${dbFile.path}-wal');
    final shm = File('${dbFile.path}-shm');
    candidateCheck(wal.existsSync() == shm.existsSync());
    final headerReader = dbFile.openSync(mode: FileMode.read);
    try {
      final header = headerReader.readSync(100);
      candidateCheck(header.length == 100 &&
          latin1.decode(header.sublist(0, 16)) == 'SQLite format 3\u0000');
      if (wal.existsSync()) {
        candidateCheck(header[18] == 2 &&
            header[19] == 2 &&
            (wal.lengthSync() == 0 || wal.lengthSync() >= 32) &&
            shm.lengthSync() >= 32768);
      }
    } finally {
      headerReader.closeSync();
    }
    final inspection =
        sqlite.sqlite3.open(dbFile.path, mode: sqlite.OpenMode.readOnly);
    try {
      final integrity = inspection.select('PRAGMA integrity_check');
      candidateCheck(integrity.length == 1 &&
          integrity.single.values.length == 1 &&
          integrity.single.values.single == 'ok');
      final identityRows =
          inspection.select('SELECT identity_hash, task_id FROM $_table');
      final rows = inspection.select('SELECT id,title,goal,task_type,executor,'
          'conversation_id,permissions_json,context_json FROM task_rooms');
      candidateCheck(rows.length <= 1);
      final taskRows = <Map<String, Object?>>[];
      for (final row in rows) {
        final permissions = P6R7StrictJson.decode(
            utf8.encode(row['permissions_json'] as String));
        final context = P6R7StrictJson.decode(
            utf8.encode(row['context_json'] as String),
            maximumBytes: 256 * 1024);
        candidateCheck(permissions is Map<String, Object?> &&
            context is Map<String, Object?>);
        final pm = permissions as Map<String, Object?>;
        final queue = (context as Map<String, Object?>)['__queue'];
        candidateCheck(queue is Map<String, Object?>);
        final qm = queue as Map<String, Object?>;
        candidateCheck(qm['ownerProfile'] == pm['profile_id'] &&
            qm['scopeType'] == pm['scope_type'] &&
            qm['scopeId'] == pm['scope_id']);
        taskRows.add({
          for (final name in [
            'id',
            'title',
            'goal',
            'task_type',
            'executor',
            'conversation_id'
          ])
            name: row[name],
          for (final name in ['profile_id', 'scope_type', 'scope_id'])
            name: pm[name],
        });
      }
      return P6R7RecoveryInspection.inspect(
          markerBytes: marker.readAsBytesSync(),
          trustedOrigin: trusted,
          projection: P6R7ReadOnlyProjection(
              userVersion: inspection
                  .select('PRAGMA user_version')
                  .single
                  .values
                  .single as int,
              identityRows: identityRows
                  .map((row) => <String, Object?>{
                        'identity_hash': row['identity_hash'],
                        'task_id': row['task_id']
                      })
                  .toList(),
              taskRows: taskRows));
    } finally {
      inspection.dispose();
    }
  }

  /// Must be called only after configuration and a live challenged host proof.
  /// Fresh mode claims a nonexisting child directory; partial failures are kept.
  static Future<P6R7CandidateStore> open(
      P6R7CandidateConfiguration config) async {
    candidateCheck(config.liveHostVerified);
    final directory = config.dataDirectory;
    candidateCanonicalPath(directory, mayBeMissing: !config.restart);
    final marker = File(p.join(directory, markerName));
    final dbFile = File(p.join(directory, databaseName));
    final lockFile = File(p.join(directory, lockName));
    final recovered = config.recoveredOrigin;
    final identity = recovered == null
        ? _identity(config)
        : <String, Object>{
            'schema': _schema,
            'dataset_id': recovered.origin.datasetId,
            'directory': recovered.origin.canonicalDirectory,
            'database': databaseName,
            'admission_sha256': recovered.origin.originAdmissionSha256,
            'source_closure_sha256': recovered.origin.sourceClosureSha256,
            'native_sha256': recovered.origin.nativeSha256,
          };
    final identityText = jsonEncode(identity);
    final identityHash = sha256.convert(utf8.encode(identityText)).toString();
    if (recovered != null) {
      candidateCheck(config.restart &&
          recovered.origin.canonicalDirectory == directory &&
          recovered.origin.identityHash == identityHash &&
          recovered.origin.sourceClosureSha256 == config.sourceClosureSha256 &&
          recovered.origin.nativeSha256 == p6R7NativeHash);
    }
    if (!config.restart) {
      candidateCheck(FileSystemEntity.typeSync(directory, followLinks: false) ==
          FileSystemEntityType.notFound);
      // The parent was admitted and is not created recursively.
      Directory(directory).createSync();
      candidateCanonicalPath(directory);
      candidateCheck(Directory(directory).listSync().isEmpty);
      lockFile.createSync(exclusive: true);
    } else {
      _checkEntries(directory);
      candidateCheck(
          marker.existsSync() && dbFile.existsSync() && lockFile.existsSync());
    }
    final lock = lockFile.openSync(mode: FileMode.append);
    AppDatabase? db;
    try {
      lock.lockSync(FileLock.exclusive);
      candidateCanonicalPath(directory);
      _checkEntries(directory);
      if (config.restart) {
        if (recovered != null) {
          final freshInspection = inspectOrigin(P6R7TrustedOrigin(
              identityHash: identityHash,
              sourceClosureSha256: config.sourceClosureSha256,
              nativeSha256: p6R7NativeHash,
              canonicalDirectory: directory,
              datasetId: recovered.origin.datasetId));
          candidateCheck(freshInspection.taskId == recovered.taskId);
        }
        candidateCheck(
            marker.lengthSync() <= 8192 && dbFile.lengthSync() >= 100);
        final existing =
            candidateJson(marker.readAsBytesSync(), identity.keys.toSet());
        candidateCheck(
            identity.entries.every((e) => existing[e.key] == e.value));
        // Read-only admission precedes Drift migrations or recovery writes.
        final inspection =
            sqlite.sqlite3.open(dbFile.path, mode: sqlite.OpenMode.readOnly);
        try {
          candidateCheck(
              inspection.select('PRAGMA user_version').single.values.single ==
                  62);
          final rows =
              inspection.select('SELECT identity_hash, task_id FROM $_table');
          candidateCheck(
              rows.length == 1 && rows.single['identity_hash'] == identityHash);
          final id = rows.single['task_id'];
          candidateCheck(
              id == null || id is String && p6R7CandidateUuid.hasMatch(id));
          final tasks = inspection.select('SELECT id FROM task_rooms');
          candidateCheck(id == null
              ? tasks.isEmpty
              : tasks.length == 1 && tasks.single['id'] == id);
        } finally {
          inspection.dispose();
        }
      } else {
        marker.createSync(exclusive: true);
        final writer = marker.openSync(mode: FileMode.write);
        try {
          writer.writeStringSync('$identityText\n');
          writer.flushSync();
        } finally {
          writer.closeSync();
        }
        candidateCheck(!dbFile.existsSync());
      }
      candidateCanonicalPath(dbFile.path, mayBeMissing: !config.restart);
      db = await AppDatabase.openCandidate(NativeDatabase(dbFile));
      if (!config.restart) {
        await db.customStatement('CREATE TABLE $_table ('
            'singleton INTEGER PRIMARY KEY CHECK(singleton=1), '
            'identity_hash TEXT NOT NULL, task_id TEXT)');
        await db.customStatement(
            'INSERT INTO $_table VALUES (1, ?, NULL)', [identityHash]);
      }
      final rows = await db
          .customSelect('SELECT identity_hash, task_id FROM $_table')
          .get();
      candidateCheck(rows.length == 1 &&
          rows.single.read<String>('identity_hash') == identityHash);
      final id = rows.single.readNullable<String>('task_id');
      final store = P6R7CandidateStore._(
          db, lock, identity['dataset_id']! as String, id, identityHash);
      if (id != null) await store._verifyTask(id);
      return store;
    } on Object {
      try {
        await db?.close();
      } finally {
        lock.closeSync();
      }
      rethrow;
    }
  }

  Future<void> _verifyTask(String id) async {
    candidateCheck(p6R7CandidateUuid.hasMatch(id));
    final service = TaskRoomService(db: database);
    final row = await service.getTaskRoom(id);
    final snapshot = await service.getTaskQueueSnapshot(id);
    final count = await database
        .customSelect('SELECT COUNT(*) AS n FROM task_rooms')
        .getSingle();
    candidateCheck(count.read<int>('n') == 1 &&
        row != null &&
        row.title == p6R7CandidateTitle &&
        row.goal == p6R7CandidateGoal &&
        row.taskType == TaskType.other.value &&
        row.executor == 'workbench_runtime' &&
        row.conversationId == conversationId &&
        snapshot != null &&
        snapshot.belongsTo(TaskQueueHostScope(
            profileId: DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
            scopeType: 'conversation',
            scopeId: conversationId)));
  }

  Future<void> persistTaskId(String id) => database.transaction(() async {
        candidateCheck(!_closed && (taskId == null || taskId == id));
        await _verifyTask(id);
        final row = await database
            .customSelect('SELECT task_id FROM $_table')
            .getSingle();
        candidateCheck(row.readNullable<String>('task_id') == null ||
            row.readNullable<String>('task_id') == id);
        await database.customStatement(
            'UPDATE $_table SET task_id=? WHERE singleton=1', [id]);
        taskId = id;
      });

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await database.close();
    } finally {
      _lock.closeSync();
    }
  }
}
