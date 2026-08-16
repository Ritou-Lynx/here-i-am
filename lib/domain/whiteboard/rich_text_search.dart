/// Plain-text search over saved [RichTextDocument]s.
///
/// After a card's rich text is saved, [RichTextSearchIndex] makes its
/// [RichTextDocument.toPlainText] projection searchable: it walks the same
/// storage convention as [RichTextStorage] (`card_<id>/rich_text.json`),
/// migrates each document, and matches the query (case-insensitive substring)
/// against the projection — including list markers, quote prefixes, nested
/// indentation and media alt/caption text.
///
/// The index is stateless and reads documents on demand (synchronous local
/// JSON reads — card documents are small), so a saved document is
/// immediately searchable with no separate indexing step. Deliberately
/// decoupled from Drift / MemexRouter.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'rich_text_storage.dart';

/// A search hit: the card id and its plain-text projection.
class RichTextSearchHit {
  final String cardId;
  final String plainText;

  const RichTextSearchHit({required this.cardId, required this.plainText});

  /// The first non-empty line of the projection, used as a display title.
  String get title {
    for (final line in plainText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return cardId;
  }
}

/// Searches the plain-text projections of saved rich text documents.
class RichTextSearchIndex {
  final Directory baseDir;
  final RichTextStorage _storage;

  RichTextSearchIndex(this.baseDir) : _storage = RichTextStorage(baseDir);

  /// Returns all card ids that have a saved rich text document.
  List<String> allCardIds() {
    if (!baseDir.existsSync()) return const [];
    final ids = <String>[];
    for (final entity in baseDir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('card_')) {
        ids.add(name.substring('card_'.length));
      }
    }
    return ids;
  }

  /// The plain-text projection of a single card, or null when absent.
  String? plainTextOf(String cardId) {
    final doc = _storage.loadSync(cardId);
    if (doc == null) return null;
    return doc.toPlainText();
  }

  /// Searches all saved documents. Returns hits whose projection contains
  /// [query] (case-insensitive). Empty query matches nothing; hits are
  /// ordered by card id for determinism.
  List<RichTextSearchHit> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = <RichTextSearchHit>[];
    for (final cardId in allCardIds()) {
      final text = plainTextOf(cardId);
      if (text != null && text.toLowerCase().contains(q)) {
        hits.add(RichTextSearchHit(cardId: cardId, plainText: text));
      }
    }
    hits.sort((a, b) => a.cardId.compareTo(b.cardId));
    return hits;
  }
}
