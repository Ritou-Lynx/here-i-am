import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/data/services/search/query_matcher.dart';
import 'package:memex/db/app_database.dart';

/// SELECT-only projection. Deliberately does not use the orchestrator: its
/// embedding initialization and query logging are not read-only operations.
class PhoneDreamingReadService {
  PhoneDreamingReadService(this._db);
  final AppDatabase _db;

  Future<Map<String, Object?>> read(String query) async {
    if (query.trim().isEmpty || query.length > 2000) {
      throw const FormatException('invalid_query');
    }
    // A read transaction gives the complete closure one SQLite snapshot and
    // serializes this connection's edits. BEGIN/COMMIT do not mutate data.
    return _db.transaction(() => _readSnapshot(query));
  }

  Future<Map<String, Object?>> _readSnapshot(String query) async {
    // Reuse the existing tokenized FTS SELECTs, then reload current rows. No
    // cached FTS text, audit history, embedding, trace writes, or recency fill.
    final episodeHits = List<Map<String, dynamic>>.of(
        await _db.searchDao.searchMemoryEpisodes(query, limit: 12));
    final fragmentHits = List<Map<String, dynamic>>.of(
        await _db.searchDao.searchMemoryFragments(query, limit: 18));
    final sagaHits = List<Map<String, dynamic>>.of(
        await _db.searchDao.searchMemorySagas(query, limit: 6));
    final keywords =
        (await QueryMatcher.contentKeywords(query)).take(12).toList();
    if (keywords.isNotEmpty) {
      if (episodeHits.isEmpty) {
        final pool = await (_db.select(_db.memoryEpisodes)
              ..where((t) => t.status.equals('active'))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(96))
            .get();
        episodeHits.addAll(_fallback(
            pool.map((r) => (r.id, r.narrative)), keywords, 'episode_id', 12));
      }
      if (fragmentHits.isEmpty) {
        final pool = await (_db.select(_db.memoryFragments)
              ..where((t) => t.status.isIn(const ['active', 'consolidated']))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(144))
            .get();
        fragmentHits.addAll(_fallback(
            pool.map((r) => (r.id, r.content)), keywords, 'fragment_id', 18));
      }
      if (sagaHits.isEmpty) {
        final pool = await (_db.select(_db.memorySagas)
              ..where((t) => t.status.equals('active'))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(32))
            .get();
        sagaHits.addAll(_fallback(
            pool.map((r) => (r.id, '${r.title} ${r.description}')),
            keywords,
            'saga_id',
            6));
      }
    }
    final sagaIds = sagaHits.map((hit) => hit['saga_id'] as String).toSet();
    final sagas = await (_db.select(_db.memorySagas)
          ..where((t) => t.id.isIn(sagaIds) & t.status.equals('active')))
        .get();
    final episodeIds =
        episodeHits.map((hit) => hit['episode_id'] as String).toSet();
    for (final saga in sagas) {
      episodeIds.addAll(_ids<String>(saga.episodeIds, 16) ?? {});
    }
    final episodes = await (_db.select(_db.memoryEpisodes)
          ..where((t) =>
              t.id.isIn(episodeIds.take(24)) & t.status.equals('active')))
        .get();
    final fragmentIds =
        fragmentHits.map((hit) => hit['fragment_id'] as String).toSet();
    for (final episode in episodes) {
      fragmentIds.addAll(_ids<String>(episode.sourceFragmentIds, 24) ?? {});
    }
    final fragments = await (_db.select(_db.memoryFragments)
          ..where((t) =>
              t.id.isIn(fragmentIds.take(96)) &
              t.status.isIn(const ['active', 'consolidated'])))
        .get();
    final validFragments = <String, MemoryFragment>{};
    for (final fragment in fragments) {
      if (await _validFragment(fragment)) {
        validFragments[fragment.id] = fragment;
      }
    }
    final validEpisodes = <String, MemoryEpisode>{};
    for (final episode in episodes) {
      final sources = _ids<String>(episode.sourceFragmentIds, 24);
      if (sources != null && sources.every(validFragments.containsKey)) {
        validEpisodes[episode.id] = episode;
      }
    }
    final validSagas = <String, MemorySaga>{};
    for (final saga in sagas) {
      final sources = _ids<String>(saga.episodeIds, 16);
      if (sources != null && sources.every(validEpisodes.containsKey)) {
        validSagas[saga.id] = saga;
      }
    }
    return {
      'episodes': [
        for (final hit in episodeHits
            .where((h) => validEpisodes.containsKey(h['episode_id']))
            .take(4))
          {
            'id': _clip(hit['episode_id'] as String, 120),
            'narrative':
                _clip(validEpisodes[hit['episode_id']]!.narrative, 900),
            'score': _score(hit)
          },
      ],
      'fragments': [
        for (final hit in fragmentHits
            .where((h) => validFragments.containsKey(h['fragment_id']))
            .take(6))
          {
            'id': _clip(hit['fragment_id'] as String, 120),
            'content': _clip(validFragments[hit['fragment_id']]!.content, 300),
            'score': _score(hit)
          },
      ],
      'sagas': [
        for (final hit in sagaHits
            .where((h) => validSagas.containsKey(h['saga_id']))
            .take(2))
          {
            'id': _clip(hit['saga_id'] as String, 120),
            'title': _clip(validSagas[hit['saga_id']]!.title, 160),
            'description': _clip(validSagas[hit['saga_id']]!.description, 900)
          },
      ],
    };
  }

  Future<bool> _validFragment(MemoryFragment fragment) async {
    if (!const {'main_chat', 'script_session'}.contains(fragment.sourceScope) ||
        !const {'active', 'consolidated'}.contains(fragment.status)) {
      return false;
    }
    if (fragment.sourceMessageIds == null && fragment.sourceSyncIds == null) {
      return false;
    }
    if (fragment.sourceMessageIds != null) {
      final ids = _ids<int>(fragment.sourceMessageIds, 16);
      if (ids == null) return false;
      final rows = await (_db.select(_db.personaChatMessages)
            ..where((t) =>
                t.id.isIn(ids) &
                t.characterId.equals('i') &
                t.taskRoomId.isNull() &
                t.messageType.equals('chat')))
          .get();
      if (rows.length != ids.length) return false;
    }
    if (fragment.sourceSyncIds != null) {
      final ids = _ids<String>(fragment.sourceSyncIds, 16);
      if (ids == null) return false;
      final rows = await (_db.select(_db.personaChatMessages)
            ..where((t) =>
                t.syncId.isIn(ids) &
                t.characterId.equals('i') &
                t.taskRoomId.isNull() &
                t.messageType.equals('chat')))
          .get();
      if (rows.length != ids.length ||
          rows.map((r) => r.syncId).toSet().length != ids.length) {
        return false;
      }
    }
    return true;
  }

  static Set<T>? _ids<T>(String? raw, int limit) {
    if (raw == null || raw.length > 8192) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! List || value.isEmpty || value.length > limit) return null;
      final ids = <T>{};
      for (final item in value) {
        if (item is! T ||
            (item is String && item.trim().isEmpty) ||
            (item is int && item <= 0) ||
            !ids.add(item)) {
          return null;
        }
      }
      return ids;
    } on FormatException {
      return null;
    }
  }

  static int _score(Map<String, dynamic> hit) =>
      (-((hit['rank'] as num).toDouble()) * 10).round().clamp(0, 9999);
  static String _clip(String text, int limit) {
    if (text.length <= limit) return text;
    var end = limit;
    final last = text.codeUnitAt(end - 1);
    if (last >= 0xd800 && last <= 0xdbff) end--;
    return text.substring(0, end);
  }

  static Iterable<Map<String, dynamic>> _fallback(
    Iterable<(String, String)> rows,
    List<String> keywords,
    String idKey,
    int limit,
  ) =>
      rows
          .where((r) => keywords.any(r.$2.toLowerCase().contains))
          .take(limit)
          .map((r) => {idKey: r.$1, 'rank': -0.5});
}
