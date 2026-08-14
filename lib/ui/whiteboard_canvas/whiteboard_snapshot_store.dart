/// Whiteboard snapshot persistence service.
///
/// Saves and loads [WhiteboardSnapshot]s to/from the local file system as JSON.
/// This service does NOT import MemexRouter or Drift — it uses a simple
/// file-based approach for the W1 vertical slice. Production persistence
/// will be handled by W0 integration with proper Drift tables.
library;

import 'dart:convert';
import 'dart:io';

import 'package:memex/domain/whiteboard/snapshot_integrity.dart';
import 'package:memex/domain/whiteboard/whiteboard_snapshot.dart';

/// Result of a snapshot load attempt.
class SnapshotLoadResult {
  final WhiteboardSnapshot? snapshot;
  final String? error;
  final SnapshotIntegrityResult? integrity;

  const SnapshotLoadResult({
    this.snapshot,
    this.error,
    this.integrity,
  });

  bool get isSuccess => snapshot != null;
  bool get hasIntegrityIssues => integrity != null && !integrity!.isValid;
}

/// File-based whiteboard snapshot store.
///
/// Saves one snapshot per file, named by board ID. Handles:
/// - Normal save/load
/// - Empty board file
/// - Corrupted JSON (returns error, does not throw)
/// - Old schema migration via [loadSnapshot]
/// - Integrity validation after load
class WhiteboardSnapshotStore {
  final String baseDir;

  WhiteboardSnapshotStore(this.baseDir);

  String _filePath(String boardId) => '$baseDir/whiteboard_$boardId.json';

  /// Saves a snapshot to the file system.
  /// Returns true on success, false on failure.
  bool save(String boardId, WhiteboardSnapshot snapshot) {
    try {
      final dir = Directory(baseDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File(_filePath(boardId));
      final json = snapshot.toJson();
      json['updated_at'] = DateTime.now().toUtc().toIso8601String();
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Loads a snapshot from the file system.
  ///
  /// Handles:
  /// - Missing file → returns empty result with error "file not found"
  /// - Corrupted JSON → returns error
  /// - Old schema → migrates via [loadSnapshot]
  /// - Invalid dangling refs → returns snapshot + integrity warnings
  SnapshotLoadResult load(String boardId) {
    final file = File(_filePath(boardId));
    if (!file.existsSync()) {
      return SnapshotLoadResult(
        error: 'File not found for board: $boardId',
      );
    }

    try {
      final raw = file.readAsStringSync();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return const SnapshotLoadResult(
          error: 'Snapshot file is not a JSON object',
        );
      }

      final snapshot = loadSnapshot(json);
      final integrity = validateSnapshotIntegrity(snapshot);

      return SnapshotLoadResult(
        snapshot: snapshot,
        integrity: integrity,
      );
    } on FormatException catch (e) {
      return SnapshotLoadResult(
        error: 'Corrupted JSON: ${e.message}',
      );
    } on ArgumentError catch (e) {
      return SnapshotLoadResult(
        error: 'Unsupported schema: ${e.message}',
      );
    } catch (e) {
      return SnapshotLoadResult(
        error: 'Failed to load snapshot: $e',
      );
    }
  }

  /// Checks if a snapshot file exists for the given board.
  bool exists(String boardId) => File(_filePath(boardId)).existsSync();

  /// Deletes a snapshot file. Returns true if deleted, false if not found.
  bool delete(String boardId) {
    final file = File(_filePath(boardId));
    if (!file.existsSync()) return false;
    file.deleteSync();
    return true;
  }
}