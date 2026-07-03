/// Lightweight append-only query log for Memory V3 retrieval tuning.
///
/// Every call to [MemoryCardQueryService.searchCardsResolved] writes one entry.
/// Zero-result entries are the primary signal for synonym-table tuning
/// (Phase 3 Lite+). The log lives as a JSON file in the app documents dir
/// and is capped at [_maxEntries] to avoid unbounded growth.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:memex/utils/logger.dart';
import 'package:path_provider/path_provider.dart';

final _logger = getLogger('QueryLogService');

class QueryLogEntry {
  const QueryLogEntry({
    required this.query,
    required this.timestamp,
    required this.resultCount,
    required this.topStrategy,
  });

  final String query;
  final int timestamp; // ms since epoch
  final int resultCount;
  final String topStrategy; // "original" | "expanded" | "relaxed" | "none"

  Map<String, dynamic> toJson() => {
        'query': query,
        'timestamp': timestamp,
        'resultCount': resultCount,
        'topStrategy': topStrategy,
      };

  factory QueryLogEntry.fromJson(Map<String, dynamic> json) => QueryLogEntry(
        query: json['query'] as String? ?? '',
        timestamp: json['timestamp'] as int? ?? 0,
        resultCount: json['resultCount'] as int? ?? 0,
        topStrategy: json['topStrategy'] as String? ?? 'none',
      );

  bool get isZeroResult => resultCount == 0;

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}

class QueryLogService {
  QueryLogService._();

  static const int _maxEntries = 200;
  static const String _fileName = 'memory_v3_query_log.json';

  static Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Append one query log entry.
  static Future<void> log(QueryLogEntry entry) async {
    try {
      final file = await _logFile();
      final entries = await _readAll(file);
      entries.add(entry);

      // Trim oldest entries when over the cap.
      while (entries.length > _maxEntries) {
        entries.removeAt(0);
      }

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          entries.map((e) => e.toJson()).toList(),
        ),
        flush: true,
      );
    } catch (e, stack) {
      // Never throw from logging — it must be transparent to the caller.
      _logger.warning('Failed to write query log', e, stack);
    }
  }

  /// Read all log entries, newest first.
  static Future<List<QueryLogEntry>> readAll() async {
    try {
      final file = await _logFile();
      final entries = await _readAll(file);
      return entries.reversed.toList();
    } catch (e, stack) {
      _logger.warning('Failed to read query log', e, stack);
      return [];
    }
  }

  /// Count of zero-result entries.
  static Future<int> zeroResultCount() async {
    final all = await readAll();
    return all.where((e) => e.isZeroResult).length;
  }

  /// Delete all log entries.
  static Future<void> clear() async {
    try {
      final file = await _logFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, stack) {
      _logger.warning('Failed to clear query log', e, stack);
    }
  }

  static Future<List<QueryLogEntry>> _readAll(File file) async {
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => QueryLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
