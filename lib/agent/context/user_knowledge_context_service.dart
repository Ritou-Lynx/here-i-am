import 'dart:io';

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/search/query_matcher.dart';
import 'package:memex/data/services/search_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:path/path.dart' as p;

class UserKnowledgeContextService {
  UserKnowledgeContextService._();

  static final UserKnowledgeContextService instance =
      UserKnowledgeContextService._();

  Future<String> buildKnowledgeCards({
    required String userId,
    required String queryHint,
    int maxCards = 5,
    int maxCharsPerCard = 800,
    int contextRadius = 240,
    bool exhaustiveLegacyFallback = false,
  }) async {
    if (!AppDatabase.isInitialized) return '';
    final fs = FileSystemService.instance;
    final pkmPath = fs.getPkmPath(userId);

    final trimmed = queryHint.trim();
    if (trimmed.isEmpty) return '';
    final cards = <String>[];
    final legacyCards = await _buildTimelineCardContext(
      userId: userId,
      query: trimmed,
      limit: maxCards,
      maxCharsPerCard: maxCharsPerCard,
      contextRadius: contextRadius,
      exhaustiveFallback: exhaustiveLegacyFallback,
    );
    cards.addAll(legacyCards);

    final seen = <String>{};
    final results = <Map<String, dynamic>>[];
    final pkmResults = await SearchService.instance.searchPkmFiles(
      userId,
      trimmed,
      limit: maxCards,
    );
    for (final result in pkmResults) {
      final path = (result['path'] ?? '').toString();
      if (path.isNotEmpty && seen.add(path)) results.add(result);
      if (results.length >= maxCards) break;
    }

    for (final item in results) {
      if (cards.length >= maxCards) break;
      final pathKey = (item['path'] ?? '').toString();
      if (pathKey.isEmpty) continue;
      final snippet = await _expandSnippet(
        pkmPath: pkmPath,
        relativePath: pathKey,
        fallbackSnippet: (item['snippet'] ?? '').toString(),
        maxChars: maxCharsPerCard,
        contextRadius: contextRadius,
      );
      final displayPath = pathKey.replaceAll('\\', '/');
      cards.add(
          '### $displayPath${item['rank'] == null ? '' : ' (rank: ${item['rank']})'}\n$snippet');
    }

    return cards.join('\n\n');
  }

  Future<List<String>> _buildTimelineCardContext({
    required String userId,
    required String query,
    required int limit,
    required int maxCharsPerCard,
    required int contextRadius,
    required bool exhaustiveFallback,
  }) async {
    final fs = FileSystemService.instance;
    final matches = await SearchService.instance.searchCards(
      query,
      limit: limit,
    );
    final cards = <String>[];
    final seen = <String>{};
    for (final match in matches) {
      if (cards.length >= limit) break;
      final factId = (match['fact_id'] ?? '').toString();
      if (factId.isEmpty || !seen.add(factId)) continue;
      final rendered = await _renderTimelineCard(
        userId: userId,
        factId: factId,
        query: query,
        maxCharsPerCard: maxCharsPerCard,
        contextRadius: contextRadius,
      );
      if (rendered != null) cards.add(rendered.text);
    }
    if (cards.isNotEmpty) return cards;

    final cardFiles = await fs.listAllCardFiles(userId);
    final scanLimit = exhaustiveFallback ? cardFiles.length : 120;
    final fallback = <({String text, int score})>[];
    for (final cardPath in cardFiles.take(scanLimit)) {
      final factId = fs.factIdFromCardPath(cardPath);
      if (factId == null || !seen.add(factId)) continue;
      final rendered = await _renderTimelineCard(
        userId: userId,
        factId: factId,
        query: query,
        maxCharsPerCard: maxCharsPerCard,
        contextRadius: contextRadius,
      );
      if (rendered != null && rendered.score > 0) fallback.add(rendered);
    }
    fallback.sort((a, b) => b.score.compareTo(a.score));
    return fallback.take(limit).map((item) => item.text).toList();
  }

  Future<({String text, int score})?> _renderTimelineCard({
    required String userId,
    required String factId,
    required String query,
    required int maxCharsPerCard,
    required int contextRadius,
  }) async {
    final fs = FileSystemService.instance;
    final card = await fs.readCardFile(userId, factId);
    if (card == null || card.deleted == true) return null;
    final fact = await fs.extractFactContentFromFile(userId, factId);
    final rawContent = fact?.content.trim() ?? '';
    final searchable = [
      card.title ?? '',
      card.tags.join(' '),
      card.address ?? '',
      rawContent,
      card.insight?.summary ?? '',
      card.insight?.text ?? '',
    ].where((text) => text.isNotEmpty).join('\n');
    final matched = await QueryMatcher.match(query, searchable);
    final snippet = QueryMatcher.snippet(
      content: searchable,
      matchIndexes: matched.indexes,
      maxChars: maxCharsPerCard,
      contextRadius: contextRadius,
    );
    return (
      text: '### Timeline card · $factId\n$snippet',
      score: matched.score,
    );
  }

  Future<String> _expandSnippet({
    required String pkmPath,
    required String relativePath,
    required String fallbackSnippet,
    required int maxChars,
    required int contextRadius,
  }) async {
    final file = File(p.join(pkmPath, relativePath));
    if (!await file.exists()) return fallbackSnippet;
    final content = await file.readAsString();
    if (content.length <= maxChars) return content;
    if (fallbackSnippet.trim().isEmpty) {
      return '${content.substring(0, maxChars)}...';
    }
    final plainSnippet = fallbackSnippet
        .replaceAll('<b>', '')
        .replaceAll('</b>', '')
        .replaceAll('...', '')
        .trim();
    final idx = plainSnippet.isEmpty ? -1 : content.indexOf(plainSnippet);
    if (idx < 0) {
      return fallbackSnippet.length > maxChars
          ? '${fallbackSnippet.substring(0, maxChars)}...'
          : fallbackSnippet;
    }
    final start = (idx - contextRadius).clamp(0, content.length);
    final end =
        (idx + plainSnippet.length + contextRadius).clamp(0, content.length);
    final text = content.substring(start, end).replaceAll('\n', ' ');
    return '${start > 0 ? '...' : ''}$text${end < content.length ? '...' : ''}';
  }
}
