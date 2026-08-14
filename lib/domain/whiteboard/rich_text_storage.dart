/// Filesystem persistence for [RichTextDocument].
///
/// Documents are stored as JSON files under a per-card directory. The storage
/// is append-on-save (overwrite), and the JSON always carries the current
/// `schema_version`, so a restart recovery can migrate older files. This
/// module is deliberately decoupled from Drift / MemexRouter — it takes a
/// directory path and reads/writes JSON, nothing more.
library;

import 'dart:convert';
import 'dart:io';

import 'rich_text_document.dart';
import 'rich_text_migration.dart';

/// Saves and loads [RichTextDocument]s as JSON files.
class RichTextStorage {
  final Directory baseDir;

  RichTextStorage(this.baseDir);

  /// The directory for a given card id.
  Directory _cardDir(String cardId) =>
      Directory('${baseDir.path}${Platform.pathSeparator}card_$cardId');

  File _file(String cardId) =>
      File('${_cardDir(cardId).path}${Platform.pathSeparator}rich_text.json');

  /// Saves a document for [cardId]. Creates directories as needed.
  Future<void> save(String cardId, RichTextDocument doc) async {
    final dir = _cardDir(cardId);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final file = _file(cardId);
    final json = doc.toJson();
    await file.writeAsString(jsonEncode(json), flush: true);
  }

  /// Loads a document for [cardId], migrating it to the current schema.
  ///
  /// Returns null if no file exists. Degrades to an empty document if the
  /// file is corrupt, never throws.
  Future<RichTextDocument?> load(String cardId) async {
    final file = _file(cardId);
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return migrateRichTextDocument(json);
    } catch (_) {
      return RichTextDocument.empty();
    }
  }

  /// Synchronous save for tests and synchronous init paths.
  void saveSync(String cardId, RichTextDocument doc) {
    final dir = _cardDir(cardId);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = _file(cardId);
    file.writeAsStringSync(jsonEncode(doc.toJson()), flush: true);
  }

  /// Synchronous load for tests and synchronous init paths.
  RichTextDocument? loadSync(String cardId) {
    final file = _file(cardId);
    if (!file.existsSync()) return null;
    try {
      final raw = file.readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return migrateRichTextDocument(json);
    } catch (_) {
      return RichTextDocument.empty();
    }
  }

  /// Returns true if a saved document exists for [cardId].
  bool exists(String cardId) => _file(cardId).existsSync();

  /// Deletes the saved document for [cardId]. No-op if absent.
  Future<void> delete(String cardId) async {
    final dir = _cardDir(cardId);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}