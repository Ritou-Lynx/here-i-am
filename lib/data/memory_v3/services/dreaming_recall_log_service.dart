/// Lightweight append-only log for Dreaming context injection.
///
/// This is a debug aid for Memory V3 Lab. It records what Dreaming episodes
/// and fragments were selected before a companion turn, without affecting
/// retrieval or chat generation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:memex/utils/logger.dart';
import 'package:path_provider/path_provider.dart';

final _logger = getLogger('DreamingRecallLogService');

class DreamingRecallLogEntry {
  const DreamingRecallLogEntry({
    required this.query,
    required this.timestamp,
    required this.episodeCount,
    required this.fragmentCount,
    required this.injectedContext,
    this.episodes = const [],
    this.fragments = const [],
  });

  final String query;
  final int timestamp; // ms since epoch
  final int episodeCount;
  final int fragmentCount;
  final String injectedContext;
  final List<DreamingRecallEpisodeHit> episodes;
  final List<DreamingRecallFragmentHit> fragments;

  int get totalCount => episodeCount + fragmentCount;

  bool get hasEpisodeMatch => episodes.any((e) => e.score > 0);

  bool get hasFragmentMatch => fragments.any((e) => e.score > 0);

  bool get isZeroResult => !hasEpisodeMatch && !hasFragmentMatch;

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  String get actualSummary {
    final labels = <String>[
      ...episodes.take(3).map((e) => e.shortLabel),
      ...fragments.take(3).map((f) => f.shortLabel),
    ];
    if (labels.isEmpty) return '无 Dreaming 召回';
    return labels.join(' / ');
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'timestamp': timestamp,
        'episodeCount': episodeCount,
        'fragmentCount': fragmentCount,
        'injectedContext': injectedContext,
        'episodes': episodes.map((e) => e.toJson()).toList(),
        'fragments': fragments.map((e) => e.toJson()).toList(),
      };

  factory DreamingRecallLogEntry.fromJson(Map<String, dynamic> json) =>
      DreamingRecallLogEntry(
        query: json['query'] as String? ?? '',
        timestamp: json['timestamp'] as int? ?? 0,
        episodeCount: json['episodeCount'] as int? ?? 0,
        fragmentCount: json['fragmentCount'] as int? ?? 0,
        injectedContext: json['injectedContext'] as String? ?? '',
        episodes: (json['episodes'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(DreamingRecallEpisodeHit.fromJson)
                .toList() ??
            const [],
        fragments: (json['fragments'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(DreamingRecallFragmentHit.fromJson)
                .toList() ??
            const [],
      );
}

/// Coverage breakdown for deciding which part of the Dreaming pipeline needs
/// attention: episode consolidation, fragment extraction, or retrieval.
class DreamingRecallCoverage {
  const DreamingRecallCoverage({
    required this.episodeMatched,
    required this.fragmentOnly,
    required this.zeroResult,
  });

  final int episodeMatched;
  final int fragmentOnly;
  final int zeroResult;

  int get total => episodeMatched + fragmentOnly + zeroResult;

  factory DreamingRecallCoverage.fromEntries(
    Iterable<DreamingRecallLogEntry> entries,
  ) {
    var episodeMatched = 0;
    var fragmentOnly = 0;
    var zeroResult = 0;

    for (final entry in entries) {
      if (entry.hasEpisodeMatch) {
        episodeMatched++;
      } else if (entry.hasFragmentMatch) {
        fragmentOnly++;
      } else {
        zeroResult++;
      }
    }

    return DreamingRecallCoverage(
      episodeMatched: episodeMatched,
      fragmentOnly: fragmentOnly,
      zeroResult: zeroResult,
    );
  }
}

class DreamingRecallEpisodeHit {
  const DreamingRecallEpisodeHit({
    required this.id,
    required this.narrative,
    required this.score,
    required this.significance,
    this.topicId,
  });

  final String id;
  final String narrative;
  final int score;
  final int significance;
  final String? topicId;

  String get shortLabel {
    final topic = topicId?.trim();
    final prefix = topic == null || topic.isEmpty || topic == '__ungrouped__'
        ? 'episode'
        : topic;
    return '$prefix:$score';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'narrative': narrative,
        'score': score,
        'significance': significance,
        'topicId': topicId,
      };

  factory DreamingRecallEpisodeHit.fromJson(Map<String, dynamic> json) =>
      DreamingRecallEpisodeHit(
        id: json['id'] as String? ?? '',
        narrative: json['narrative'] as String? ?? '',
        score: json['score'] as int? ?? 0,
        significance: json['significance'] as int? ?? 0,
        topicId: json['topicId'] as String?,
      );
}

class DreamingRecallFragmentHit {
  const DreamingRecallFragmentHit({
    required this.id,
    required this.content,
    required this.score,
    required this.emotionalWeight,
    required this.isUserTruthCandidate,
  });

  final String id;
  final String content;
  final int score;
  final double emotionalWeight;
  final bool isUserTruthCandidate;

  String get shortLabel =>
      isUserTruthCandidate ? 'fragment*: $score' : 'fragment:$score';

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'score': score,
        'emotionalWeight': emotionalWeight,
        'isUserTruthCandidate': isUserTruthCandidate,
      };

  factory DreamingRecallFragmentHit.fromJson(Map<String, dynamic> json) =>
      DreamingRecallFragmentHit(
        id: json['id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        score: json['score'] as int? ?? 0,
        emotionalWeight: (json['emotionalWeight'] as num?)?.toDouble() ?? 0,
        isUserTruthCandidate: json['isUserTruthCandidate'] as bool? ?? false,
      );
}

class DreamingRecallLogService {
  DreamingRecallLogService._();

  static const int _maxEntries = 200;
  static const String _fileName = 'memory_v3_dreaming_recall_log.json';

  static Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> log(DreamingRecallLogEntry entry) async {
    try {
      final file = await _logFile();
      final entries = await _readAll(file);
      entries.add(entry);

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
      _logger.warning('Failed to write Dreaming recall log', e, stack);
    }
  }

  static Future<List<DreamingRecallLogEntry>> readAll() async {
    try {
      final file = await _logFile();
      final entries = await _readAll(file);
      return entries.reversed.toList();
    } catch (e, stack) {
      _logger.warning('Failed to read Dreaming recall log', e, stack);
      return [];
    }
  }

  static Future<int> zeroResultCount() async {
    final all = await readAll();
    return all.where((e) => e.isZeroResult).length;
  }

  static Future<void> clear() async {
    try {
      final file = await _logFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, stack) {
      _logger.warning('Failed to clear Dreaming recall log', e, stack);
    }
  }

  static Future<List<DreamingRecallLogEntry>> _readAll(File file) async {
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
              (e) => DreamingRecallLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
