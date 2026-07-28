import 'package:drift/drift.dart';
import 'package:memex/data/services/search/query_matcher.dart';

/// DAO for full-text search using SQLite FTS5.
///
/// Manages two FTS5 virtual tables:
/// - `card_fts`: indexes timeline card titles, tags, content, and insight text
/// - `pkm_fts`: indexes PKM knowledge base file names and content
///
/// Chinese text is segmented using jieba (dictionary-based DAG + DP).
/// English text is handled natively by FTS5's unicode61 tokenizer.
class SearchDao {
  final GeneratedDatabase _db;

  SearchDao(this._db);

  // ---------------------------------------------------------------------------
  // Table creation
  // ---------------------------------------------------------------------------

  /// Create FTS5 virtual tables. Called from migration `onCreate` / `onUpgrade`.
  Future<void> createFtsTables() async {
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS card_fts USING fts5(
        fact_id UNINDEXED,
        title,
        tags,
        content,
        insight,
        tokenize='unicode61'
      )
    ''');
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS pkm_fts USING fts5(
        file_path UNINDEXED,
        file_name,
        content,
        tokenize='unicode61'
      )
    ''');
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS shared_life_fts USING fts5(
        entity_id UNINDEXED,
        title,
        tags,
        summary,
        tokenize='unicode61'
      )
    ''');
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS memory_v3_fts USING fts5(
        card_id UNINDEXED,
        droplet_label,
        title,
        retrieval_text,
        tokenize='unicode61'
      )
    ''');
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS memory_episodes_fts USING fts5(
        episode_id UNINDEXED,
        narrative,
        topic_id,
        tokenize='unicode61'
      )
    ''');
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS memory_fragments_fts USING fts5(
        fragment_id UNINDEXED,
        content,
        tokenize='unicode61'
      )
    ''');
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS memory_sagas_fts USING fts5(
        saga_id UNINDEXED,
        title,
        description,
        tokenize='unicode61'
      )
    ''');
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS project_memory_fts USING fts5(
        item_id UNINDEXED,
        project_id UNINDEXED,
        project_key UNINDEXED,
        summary,
        decisions,
        open_loops,
        artifact_refs,
        tokenize='unicode61'
      )
    ''');
    await createCharacterFtsTables();
  }

  Future<void> createCharacterFtsTables() async {
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS character_world_fts USING fts5(
        character_id UNINDEXED,
        entry_id UNINDEXED,
        keys,
        comment,
        content,
        tokenize='unicode61'
      )
    ''');
    await _db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS character_timeline_fts USING fts5(
        character_id UNINDEXED,
        event_id UNINDEXED,
        source UNINDEXED,
        scene UNINDEXED,
        thread_id UNINDEXED,
        ts UNINDEXED,
        event_type,
        content,
        fact_id,
        tokenize='unicode61'
      )
    ''');
  }

  // ---------------------------------------------------------------------------
  // Tokenization (jieba for CJK, passthrough for English)
  // ---------------------------------------------------------------------------

  /// Prepare text for FTS5 indexing.
  ///
  /// If jieba is initialized and text contains CJK, uses `cutForSearch` to
  /// produce fine-grained tokens (bigrams + trigrams + full words).
  /// Otherwise falls back to per-character CJK splitting.
  /// English text is left as-is for FTS5's unicode61 tokenizer.
  static Future<String> tokenizeForIndex(String text) {
    return QueryMatcher.tokenizeForIndex(text);
  }

  /// Prepare a search query for FTS5.
  ///
  /// Uses jieba `cut` (not cutForSearch) to segment the query into words,
  /// then wraps English tokens with prefix matching and joins with OR.
  /// FTS5's BM25 ranking naturally scores documents higher when more
  /// tokens match, similar to Elasticsearch's default behavior.
  static Future<String> tokenizeForQuery(String query) {
    return QueryMatcher.tokenizeForFtsQuery(query);
  }

  // ---------------------------------------------------------------------------
  // Card FTS
  // ---------------------------------------------------------------------------

  Future<void> upsertCardFts({
    required String factId,
    required String title,
    required String tags,
    required String content,
    required String insight,
  }) async {
    await deleteCardFts(factId);
    await _db.customStatement(
      'INSERT INTO card_fts(fact_id, title, tags, content, insight) VALUES (?, ?, ?, ?, ?)',
      [
        factId,
        await tokenizeForIndex(title),
        await tokenizeForIndex(tags),
        await tokenizeForIndex(content),
        await tokenizeForIndex(insight)
      ],
    );
  }

  Future<void> deleteCardFts(String factId) async {
    await _db
        .customStatement('DELETE FROM card_fts WHERE fact_id = ?', [factId]);
  }

  Future<void> clearCardFts() async {
    await _db.customStatement('DELETE FROM card_fts');
  }

  /// Search cards via FTS5. Returns `fact_id`, snippets, and rank.
  Future<List<Map<String, dynamic>>> searchCards(String query,
      {int limit = 50}) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final results = await _db.customSelect(
      '''SELECT fact_id,
             snippet(card_fts, 2, '<b>', '</b>', '...', 32) AS content_snippet,
             snippet(card_fts, 1, '<b>', '</b>', '...', 32) AS title_snippet,
             rank
      FROM card_fts WHERE card_fts MATCH ? ORDER BY rank LIMIT ?''',
      variables: [Variable<String>(ftsQuery), Variable<int>(limit)],
    ).get();
    return results
        .map((row) => {
              'fact_id': row.read<String>('fact_id'),
              'content_snippet': row.read<String>('content_snippet'),
              'title_snippet': row.read<String>('title_snippet'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // PKM FTS
  // ---------------------------------------------------------------------------

  Future<void> upsertPkmFts({
    required String filePath,
    required String fileName,
    required String content,
  }) async {
    await deletePkmFts(filePath);
    await _db.customStatement(
      'INSERT INTO pkm_fts(file_path, file_name, content) VALUES (?, ?, ?)',
      [
        filePath,
        await tokenizeForIndex(fileName),
        await tokenizeForIndex(content)
      ],
    );
  }

  Future<void> deletePkmFts(String filePath) async {
    await _db
        .customStatement('DELETE FROM pkm_fts WHERE file_path = ?', [filePath]);
  }

  Future<void> clearPkmFts() async {
    await _db.customStatement('DELETE FROM pkm_fts');
  }

  /// Search PKM files via FTS5.
  Future<List<Map<String, dynamic>>> searchPkmFiles(String query,
      {int limit = 50}) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final results = await _db.customSelect(
      '''SELECT file_path,
             snippet(pkm_fts, 2, '<b>', '</b>', '...', 64) AS snippet, rank
      FROM pkm_fts WHERE pkm_fts MATCH ? ORDER BY rank LIMIT ?''',
      variables: [Variable<String>(ftsQuery), Variable<int>(limit)],
    ).get();
    return results.map((row) {
      final filePath = row.read<String>('file_path');
      // Derive display name from the original (untokenized) file_path
      final name = filePath.contains('/')
          ? filePath.substring(filePath.lastIndexOf('/') + 1)
          : filePath;
      return {
        'name': name,
        'path': filePath,
        'snippet': row.read<String>('snippet'),
        'rank': row.read<double>('rank'),
      };
    }).toList();
  }

  Future<void> upsertCharacterWorldFts({
    required String characterId,
    required String entryId,
    required String keys,
    required String comment,
    required String content,
  }) async {
    await deleteCharacterWorldFts(characterId, entryId);
    await _db.customStatement(
      'INSERT INTO character_world_fts(character_id, entry_id, keys, comment, content) VALUES (?, ?, ?, ?, ?)',
      [
        characterId,
        entryId,
        await tokenizeForIndex(keys),
        await tokenizeForIndex(comment),
        await tokenizeForIndex(content),
      ],
    );
  }

  Future<void> deleteCharacterWorldFts(
      String characterId, String entryId) async {
    await _db.customStatement(
      'DELETE FROM character_world_fts WHERE character_id = ? AND entry_id = ?',
      [characterId, entryId],
    );
  }

  Future<void> clearCharacterWorldFts(String characterId) async {
    await _db.customStatement(
      'DELETE FROM character_world_fts WHERE character_id = ?',
      [characterId],
    );
  }

  Future<List<Map<String, dynamic>>> searchCharacterWorldEntries(
    String characterId,
    String query, {
    int limit = 12,
  }) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final rows = await _db.customSelect(
      '''SELECT entry_id, rank
      FROM character_world_fts
      WHERE character_id = ? AND character_world_fts MATCH ?
      ORDER BY rank LIMIT ?''',
      variables: [
        Variable<String>(characterId),
        Variable<String>(ftsQuery),
        Variable<int>(limit),
      ],
    ).get();
    return rows
        .map((row) => {
              'id': row.read<String>('entry_id'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }

  Future<void> upsertCharacterTimelineFts({
    required String characterId,
    required String eventId,
    required String source,
    required String scene,
    required String threadId,
    required String ts,
    required String eventType,
    required String content,
    required String factId,
  }) async {
    await deleteCharacterTimelineFts(characterId, eventId, source);
    await _db.customStatement(
      'INSERT INTO character_timeline_fts(character_id, event_id, source, scene, thread_id, ts, event_type, content, fact_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        characterId,
        eventId,
        source,
        scene,
        threadId,
        ts,
        await tokenizeForIndex(eventType),
        await tokenizeForIndex(content),
        await tokenizeForIndex(factId),
      ],
    );
  }

  Future<void> deleteCharacterTimelineFts(
    String characterId,
    String eventId,
    String source,
  ) async {
    await _db.customStatement(
      'DELETE FROM character_timeline_fts WHERE character_id = ? AND event_id = ? AND source = ?',
      [characterId, eventId, source],
    );
  }

  Future<void> clearCharacterTimelineFts(String characterId,
      {String? source}) async {
    if (source == null) {
      await _db.customStatement(
        'DELETE FROM character_timeline_fts WHERE character_id = ?',
        [characterId],
      );
    } else {
      await _db.customStatement(
        'DELETE FROM character_timeline_fts WHERE character_id = ? AND source = ?',
        [characterId, source],
      );
    }
  }

  Future<List<Map<String, dynamic>>> searchCharacterTimeline(
    String characterId,
    String query, {
    int limit = 8,
    String? scene,
    String? threadId,
    bool includeArchived = true,
  }) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final clauses = <String>[
      'character_id = ?',
      'character_timeline_fts MATCH ?',
    ];
    final variables = <Variable>[
      Variable<String>(characterId),
      Variable<String>(ftsQuery),
    ];
    if (scene != null && scene.isNotEmpty) {
      clauses.add('scene = ?');
      variables.add(Variable<String>(scene));
    }
    if (threadId != null && threadId.isNotEmpty) {
      clauses.add('thread_id = ?');
      variables.add(Variable<String>(threadId));
    }
    if (!includeArchived) {
      clauses.add('source = ?');
      variables.add(const Variable<String>('recent'));
    }
    variables.add(Variable<int>(limit));
    final rows = await _db.customSelect(
      '''SELECT event_id, source, rank
      FROM character_timeline_fts
      WHERE ${clauses.join(' AND ')}
      ORDER BY rank LIMIT ?''',
      variables: variables,
    ).get();
    return rows
        .map((row) => {
              'event_id': row.read<String>('event_id'),
              'source': row.read<String>('source'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Shared Life FTS
  // ---------------------------------------------------------------------------

  Future<void> upsertSharedLifeFts({
    required String entityId,
    required String title,
    required String tags,
    required String summary,
  }) async {
    await deleteSharedLifeFts(entityId);
    await _db.customStatement(
      'INSERT INTO shared_life_fts(entity_id, title, tags, summary) VALUES (?, ?, ?, ?)',
      [
        entityId,
        await tokenizeForIndex(title),
        await tokenizeForIndex(tags),
        await tokenizeForIndex(summary),
      ],
    );
  }

  Future<void> deleteSharedLifeFts(String entityId) async {
    await _db.customStatement(
      'DELETE FROM shared_life_fts WHERE entity_id = ?',
      [entityId],
    );
  }

  Future<void> clearSharedLifeFts() async {
    await _db.customStatement('DELETE FROM shared_life_fts');
  }

  // ---------------------------------------------------------------------------
  // Memory V3 FTS
  // ---------------------------------------------------------------------------

  Future<void> upsertMemoryV3Fts({
    required String cardId,
    required String dropletLabel,
    required String title,
    required String retrievalText,
  }) async {
    await deleteMemoryV3Fts(cardId);
    await _db.customStatement(
      'INSERT INTO memory_v3_fts(card_id, droplet_label, title, retrieval_text) '
      'VALUES (?, ?, ?, ?)',
      [
        cardId,
        await tokenizeForIndex(dropletLabel),
        await tokenizeForIndex(title),
        await tokenizeForIndex(retrievalText),
      ],
    );
  }

  Future<void> deleteMemoryV3Fts(String cardId) async {
    await _db.customStatement(
      'DELETE FROM memory_v3_fts WHERE card_id = ?',
      [cardId],
    );
  }

  /// Search Memory V3 cards via FTS5. Returns card IDs, snippets, and rank.
  Future<List<Map<String, dynamic>>> searchMemoryV3Cards(
    String query, {
    int limit = 20,
  }) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final results = await _db.customSelect(
      '''SELECT card_id,
             snippet(memory_v3_fts, 1, '<b>', '</b>', '...', 32) AS label_snippet,
             snippet(memory_v3_fts, 3, '<b>', '</b>', '...', 64) AS text_snippet,
             rank
      FROM memory_v3_fts WHERE memory_v3_fts MATCH ?
      ORDER BY rank LIMIT ?''',
      variables: [Variable<String>(ftsQuery), Variable<int>(limit)],
    ).get();
    return results
        .map((row) => {
              'card_id': row.read<String>('card_id'),
              'label_snippet': row.read<String>('label_snippet'),
              'text_snippet': row.read<String>('text_snippet'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }

  Future<void> upsertProjectMemoryFts({
    required String itemId,
    required String projectId,
    required String projectKey,
    required String summary,
    required String decisions,
    required String openLoops,
    required String artifactRefs,
  }) async {
    await deleteProjectMemoryFts(itemId);
    await _db.customStatement(
      'INSERT INTO project_memory_fts('
      'item_id, project_id, project_key, summary, decisions, open_loops, artifact_refs'
      ') VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        itemId,
        projectId,
        projectKey,
        await tokenizeForIndex(summary),
        await tokenizeForIndex(decisions),
        await tokenizeForIndex(openLoops),
        await tokenizeForIndex(artifactRefs),
      ],
    );
  }

  Future<void> deleteProjectMemoryFts(String itemId) async {
    await _db.customStatement(
      'DELETE FROM project_memory_fts WHERE item_id = ?',
      [itemId],
    );
  }

  /// Project filtering is part of candidate generation, before rank/limit.
  Future<List<Map<String, dynamic>>> searchProjectMemory(
    String query, {
    required Set<String> allowedProjectIds,
    int limit = 20,
  }) async {
    if (allowedProjectIds.isEmpty) return [];
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final placeholders = List.filled(allowedProjectIds.length, '?').join(',');
    final results = await _db.customSelect(
      '''SELECT item_id, project_id, project_key,
                snippet(project_memory_fts, 3, '<b>', '</b>', '...', 64) AS summary_snippet,
                rank
         FROM project_memory_fts
         WHERE project_memory_fts MATCH ?
           AND project_id IN ($placeholders)
         ORDER BY rank LIMIT ?''',
      variables: [
        Variable<String>(ftsQuery),
        ...allowedProjectIds.map(Variable<String>.new),
        Variable<int>(limit),
      ],
    ).get();
    return results
        .map((row) => {
              'item_id': row.read<String>('item_id'),
              'project_id': row.read<String>('project_id'),
              'project_key': row.read<String>('project_key'),
              'summary_snippet': row.read<String>('summary_snippet'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Memory V3 Dreaming FTS (episodes + fragments)
  // ---------------------------------------------------------------------------

  Future<void> upsertMemoryEpisodeFts({
    required String episodeId,
    required String narrative,
    required String topicId,
  }) async {
    await deleteMemoryEpisodeFts(episodeId);
    await _db.customStatement(
      'INSERT INTO memory_episodes_fts(episode_id, narrative, topic_id) '
      'VALUES (?, ?, ?)',
      [
        episodeId,
        await tokenizeForIndex(narrative),
        await tokenizeForIndex(topicId),
      ],
    );
  }

  Future<void> deleteMemoryEpisodeFts(String episodeId) async {
    await _db.customStatement(
      'DELETE FROM memory_episodes_fts WHERE episode_id = ?',
      [episodeId],
    );
  }

  Future<void> clearMemoryEpisodeFts() async {
    await _db.customStatement('DELETE FROM memory_episodes_fts');
  }

  /// Search Dreaming episodes via FTS5. Returns `episode_id` and `rank`
  /// (bm25 — lower is better). Narrative is weighted higher than topic id.
  Future<List<Map<String, dynamic>>> searchMemoryEpisodes(
    String query, {
    int limit = 40,
  }) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final results = await _db.customSelect(
      '''SELECT episode_id, bm25(memory_episodes_fts, 4.0, 1.0) AS rank
      FROM memory_episodes_fts
      WHERE memory_episodes_fts MATCH ?
      ORDER BY rank LIMIT ?''',
      variables: [Variable<String>(ftsQuery), Variable<int>(limit)],
    ).get();
    return results
        .map((row) => {
              'episode_id': row.read<String>('episode_id'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }

  Future<void> upsertMemoryFragmentFts({
    required String fragmentId,
    required String content,
  }) async {
    await deleteMemoryFragmentFts(fragmentId);
    await _db.customStatement(
      'INSERT INTO memory_fragments_fts(fragment_id, content) VALUES (?, ?)',
      [fragmentId, await tokenizeForIndex(content)],
    );
  }

  Future<void> deleteMemoryFragmentFts(String fragmentId) async {
    await _db.customStatement(
      'DELETE FROM memory_fragments_fts WHERE fragment_id = ?',
      [fragmentId],
    );
  }

  Future<void> clearMemoryFragmentFts() async {
    await _db.customStatement('DELETE FROM memory_fragments_fts');
  }

  /// Search Dreaming fragments via FTS5. Returns `fragment_id` and `rank`
  /// (bm25 — lower is better).
  Future<List<Map<String, dynamic>>> searchMemoryFragments(
    String query, {
    int limit = 60,
  }) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final results = await _db.customSelect(
      '''SELECT fragment_id, bm25(memory_fragments_fts) AS rank
      FROM memory_fragments_fts
      WHERE memory_fragments_fts MATCH ?
      ORDER BY rank LIMIT ?''',
      variables: [Variable<String>(ftsQuery), Variable<int>(limit)],
    ).get();
    return results
        .map((row) => {
              'fragment_id': row.read<String>('fragment_id'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Memory V3 Saga FTS
  // ---------------------------------------------------------------------------

  Future<void> upsertMemorySagaFts({
    required String sagaId,
    required String title,
    required String description,
  }) async {
    await deleteMemorySagaFts(sagaId);
    await _db.customStatement(
      'INSERT INTO memory_sagas_fts(saga_id, title, description) '
      'VALUES (?, ?, ?)',
      [
        sagaId,
        await tokenizeForIndex(title),
        await tokenizeForIndex(description),
      ],
    );
  }

  Future<void> deleteMemorySagaFts(String sagaId) async {
    await _db.customStatement(
      'DELETE FROM memory_sagas_fts WHERE saga_id = ?',
      [sagaId],
    );
  }

  Future<void> clearMemorySagaFts() async {
    await _db.customStatement('DELETE FROM memory_sagas_fts');
  }

  /// Search Dreaming sagas via FTS5. Returns `saga_id` and `rank`
  /// (bm25 — lower is better). Description is weighted higher than title.
  Future<List<Map<String, dynamic>>> searchMemorySagas(
    String query, {
    int limit = 20,
  }) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final results = await _db.customSelect(
      '''SELECT saga_id, bm25(memory_sagas_fts, 1.0, 4.0) AS rank
      FROM memory_sagas_fts
      WHERE memory_sagas_fts MATCH ?
      ORDER BY rank LIMIT ?''',
      variables: [Variable<String>(ftsQuery), Variable<int>(limit)],
    ).get();
    return results
        .map((row) => {
              'saga_id': row.read<String>('saga_id'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }

  /// Search SharedLife entities via FTS5.
  Future<List<Map<String, dynamic>>> searchSharedLifeEntities(
    String query, {
    int limit = 30,
  }) async {
    final ftsQuery = await tokenizeForQuery(query);
    if (ftsQuery.isEmpty) return [];
    final results = await _db.customSelect(
      '''SELECT entity_id,
             snippet(shared_life_fts, 0, '<b>', '</b>', '...', 32) AS title_snippet,
             snippet(shared_life_fts, 2, '<b>', '</b>', '...', 32) AS summary_snippet,
             rank
      FROM shared_life_fts WHERE shared_life_fts MATCH ? ORDER BY rank LIMIT ?''',
      variables: [Variable<String>(ftsQuery), Variable<int>(limit)],
    ).get();
    return results
        .map((row) => {
              'entity_id': row.read<String>('entity_id'),
              'title_snippet': row.read<String>('title_snippet'),
              'summary_snippet': row.read<String>('summary_snippet'),
              'rank': row.read<double>('rank'),
            })
        .toList();
  }
}
