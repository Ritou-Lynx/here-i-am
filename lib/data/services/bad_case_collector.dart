/// Lightweight bad-case collector.
///
/// Saves flagged chat messages + surrounding context to a JSON file so the
/// user can periodically review and fix recurring prompt/model issues.
library;

import 'dart:convert';
import 'dart:io';

import 'package:memex/utils/logger.dart';
import 'package:path_provider/path_provider.dart';

final _logger = getLogger('BadCaseCollector');

class BadCaseEntry {
  BadCaseEntry({
    required this.collectedAt,
    required this.characterId,
    required this.targetMessageId,
    required this.targetContent,
    required this.targetTimestamp,
    this.contextBefore = const [],
    this.contextAfter = const [],
    this.note,
  });

  final DateTime collectedAt;
  final String characterId;
  final int targetMessageId;
  final String targetContent;
  final DateTime? targetTimestamp;
  final List<String> contextBefore;
  final List<String> contextAfter;
  final String? note;

  Map<String, dynamic> toJson() => {
        'collectedAt': collectedAt.toIso8601String(),
        'characterId': characterId,
        'targetMessageId': targetMessageId,
        'targetContent': targetContent,
        'targetTimestamp': targetTimestamp?.toIso8601String(),
        'contextBefore': contextBefore,
        'contextAfter': contextAfter,
        if (note != null) 'note': note,
      };

  factory BadCaseEntry.fromJson(Map<String, dynamic> json) => BadCaseEntry(
        collectedAt: DateTime.parse(json['collectedAt'] as String),
        characterId: json['characterId'] as String,
        targetMessageId: json['targetMessageId'] as int,
        targetContent: json['targetContent'] as String,
        targetTimestamp: json['targetTimestamp'] != null
            ? DateTime.parse(json['targetTimestamp'] as String)
            : null,
        contextBefore:
            (json['contextBefore'] as List?)?.cast<String>() ?? const [],
        contextAfter:
            (json['contextAfter'] as List?)?.cast<String>() ?? const [],
        note: json['note'] as String?,
      );
}

class BadCaseCollector {
  BadCaseCollector._();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/bad_cases.json');
  }

  static Future<List<BadCaseEntry>> readAll() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => BadCaseEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.warning('BadCaseCollector: failed to read entries', e);
      return [];
    }
  }

  static Future<void> collect({
    required String characterId,
    required int targetMessageId,
    required String targetContent,
    required DateTime? targetTimestamp,
    List<String> contextBefore = const [],
    List<String> contextAfter = const [],
    String? note,
  }) async {
    final entries = await readAll();
    entries.insert(
      0,
      BadCaseEntry(
        collectedAt: DateTime.now(),
        characterId: characterId,
        targetMessageId: targetMessageId,
        targetContent: targetContent,
        targetTimestamp: targetTimestamp,
        contextBefore: contextBefore,
        contextAfter: contextAfter,
        note: note,
      ),
    );
    await _writeAll(entries);
    _logger.info(
      'BadCaseCollector: saved case #$targetMessageId (total: ${entries.length})',
    );
  }

  static Future<void> delete(int index) async {
    final entries = await readAll();
    if (index >= 0 && index < entries.length) {
      entries.removeAt(index);
      await _writeAll(entries);
    }
  }

  static Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) {
      await file.delete();
    }
  }

  static Future<int> count() async {
    final entries = await readAll();
    return entries.length;
  }

  static Future<void> _writeAll(List<BadCaseEntry> entries) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        entries.map((e) => e.toJson()).toList(),
      ),
      flush: true,
    );
  }
}
