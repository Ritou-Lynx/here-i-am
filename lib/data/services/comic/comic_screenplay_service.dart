import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';

/// Reads page screenplays for the comic co-reading feature.
///
/// Used by Lin Ai's `comic_current_page` tool to get "who said what"
/// for the page the user is currently reading, without re-running Vision.
///
/// Architecture guard: constructor-injected db, no MemexRouter import.
class ComicScreenplayService {
  final AppDatabase _db;
  ComicScreenplayService({required AppDatabase db}) : _db = db;

  static ComicScreenplayService? _instance;
  static ComicScreenplayService get instance {
    if (_instance == null) {
      throw Exception(
          'ComicScreenplayService not initialized. Call init() first.');
    }
    return _instance!;
  }

  static bool get isInitialized => _instance != null;

  static void init({required AppDatabase db}) {
    _instance = ComicScreenplayService(db: db);
  }

  /// Get the screenplay for a single page.
  Future<ComicPageScreenplay?> getPageScreenplay(
    String chapterId,
    int pageNum,
  ) async {
    return (_db.select(_db.comicPageScreenplays)
          ..where((t) =>
              t.chapterId.equals(chapterId) & t.pageNum.equals(pageNum)))
        .getSingleOrNull();
  }

  /// Get all page screenplays for a chapter, ordered by page number.
  Future<List<ComicPageScreenplay>> getChapterScreenplay(
    String chapterId,
  ) async {
    return (_db.select(_db.comicPageScreenplays)
          ..where((t) => t.chapterId.equals(chapterId))
          ..orderBy([(t) => OrderingTerm.asc(t.pageNum)]))
        .get();
  }

  /// Parse the screenplay JSON into a list of panels.
  /// Returns [{panel_id, speaker, text, panel_desc}].
  static List<Map<String, dynamic>> parsePanels(String screenplayJson) {
    final data = jsonDecode(screenplayJson);
    if (data is Map && data['panels'] is List) {
      return (data['panels'] as List).cast<Map<String, dynamic>>();
    }
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Get a compact text summary of a chapter's screenplay for Lin Ai
  /// context injection. Format: page-by-page, panel-by-panel.
  Future<String> getChapterScreenplayText(String chapterId) async {
    final pages = await getChapterScreenplay(chapterId);
    final buf = StringBuffer();
    for (final page in pages) {
      buf.writeln('— Page ${page.pageNum} —');
      final panels = parsePanels(page.screenplayJson);
      for (final panel in panels) {
        final speaker = panel['speaker'] ?? '?';
        final text = panel['text'] ?? '';
        final desc = panel['panel_desc'] ?? '';
        buf.writeln('  [$speaker] $text');
        if (desc.toString().isNotEmpty) {
          buf.writeln('  (画面: $desc)');
        }
      }
    }
    return buf.toString();
  }

  /// Get a compact text for a single page (for "边看边聊" context injection).
  Future<String> getPageScreenplayText(
    String chapterId,
    int pageNum,
  ) async {
    final page = await getPageScreenplay(chapterId, pageNum);
    if (page == null) return '';
    final panels = parsePanels(page.screenplayJson);
    final buf = StringBuffer('— Page $pageNum —\n');
    for (final panel in panels) {
      final speaker = panel['speaker'] ?? '?';
      final text = panel['text'] ?? '';
      final desc = panel['panel_desc'] ?? '';
      buf.writeln('[$speaker] $text');
      if (desc.toString().isNotEmpty) {
        buf.writeln('(画面: $desc)');
      }
    }
    return buf.toString();
  }
}