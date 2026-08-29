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

import 'recoverable_file_exchange.dart';
import 'rich_text_document.dart';
import 'rich_text_migration.dart';

enum RichTextLoadStatus { available, missing, corrupt }

class RichTextUnsafeCardIdError extends ArgumentError {
  RichTextUnsafeCardIdError(String cardId)
      : super.value(cardId, 'cardId', 'unsafe card id');
}

class RichTextLoadResult {
  const RichTextLoadResult({required this.status, this.document, this.error});

  final RichTextLoadStatus status;
  final RichTextDocument? document;
  final String? error;
}

/// Saves and loads [RichTextDocument]s as JSON files.
class RichTextStorage {
  static final RegExp _legacyRuntimeCardId = RegExp(
    r'^card:([0-9a-f]{24}):([0-9]+)$',
  );
  static const String _legacyRuntimeDirectory = 'legacy_runtime_cards';

  final Directory baseDir;

  RichTextStorage(this.baseDir);

  /// The directory for a given card id.
  Directory _cardDir(String cardId) {
    final legacy = _legacyRuntimeCardId.firstMatch(cardId);
    if (legacy != null) {
      return Directory(
        '${baseDir.path}${Platform.pathSeparator}$_legacyRuntimeDirectory'
        '${Platform.pathSeparator}card_${legacy.group(1)}_${legacy.group(2)}',
      );
    }
    _validateCardId(cardId);
    return Directory('${baseDir.path}${Platform.pathSeparator}card_$cardId');
  }

  File _file(String cardId) =>
      File('${_cardDir(cardId).path}${Platform.pathSeparator}rich_text.json');

  /// Saves a document for [cardId]. Creates directories as needed.
  Future<void> save(String cardId, RichTextDocument doc) async {
    final dir = _cardDir(cardId);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    await RecoverableFileExchange.write(
      _file(cardId),
      jsonEncode(doc.toJson()),
      validator: _isValidDocument,
    );
  }

  /// Loads a document for [cardId], migrating it to the current schema.
  ///
  /// Returns null if no file exists. Degrades to an empty document if the
  /// file is corrupt, never throws.
  Future<RichTextDocument?> load(String cardId) async {
    final result = await loadWithStatus(cardId);
    return result.document ??
        (result.status == RichTextLoadStatus.corrupt
            ? RichTextDocument.empty()
            : null);
  }

  /// Loads a document without hiding missing/corrupt filesystem state.
  Future<RichTextLoadResult> loadWithStatus(String cardId) async {
    final file = _file(cardId);
    await RecoverableFileExchange.recover(
      file,
      validator: _isValidDocument,
    );
    if (!file.existsSync()) {
      return const RichTextLoadResult(status: RichTextLoadStatus.missing);
    }
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return RichTextLoadResult(
        status: RichTextLoadStatus.available,
        document: migrateRichTextDocument(json),
      );
    } catch (error) {
      return RichTextLoadResult(
        status: RichTextLoadStatus.corrupt,
        error: error.toString(),
      );
    }
  }

  /// Synchronous save for tests and synchronous init paths.
  void saveSync(String cardId, RichTextDocument doc) {
    final dir = _cardDir(cardId);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    RecoverableFileExchange.writeSync(
      _file(cardId),
      jsonEncode(doc.toJson()),
      validator: _isValidDocument,
    );
  }

  /// Synchronous load for tests and synchronous init paths.
  RichTextDocument? loadSync(String cardId) {
    final result = loadWithStatusSync(cardId);
    return result.document ??
        (result.status == RichTextLoadStatus.corrupt
            ? RichTextDocument.empty()
            : null);
  }

  RichTextLoadResult loadWithStatusSync(String cardId) {
    final file = _file(cardId);
    RecoverableFileExchange.recoverSync(
      file,
      validator: _isValidDocument,
    );
    if (!file.existsSync()) {
      return const RichTextLoadResult(status: RichTextLoadStatus.missing);
    }
    try {
      final raw = file.readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return RichTextLoadResult(
        status: RichTextLoadStatus.available,
        document: migrateRichTextDocument(json),
      );
    } catch (error) {
      return RichTextLoadResult(
        status: RichTextLoadStatus.corrupt,
        error: error.toString(),
      );
    }
  }

  /// Returns true if a saved document exists for [cardId].
  bool exists(String cardId) {
    final file = _file(cardId);
    RecoverableFileExchange.recoverSync(
      file,
      validator: _isValidDocument,
    );
    return file.existsSync();
  }

  /// Repairs interrupted replacements for all discovered card directories.
  Future<void> recoverAll() async {
    if (!await baseDir.exists()) return;
    await for (final entity in baseDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name =
          entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
      if (name.startsWith('card_')) {
        await _recoverDirectory(entity);
        continue;
      }
      if (name == _legacyRuntimeDirectory) {
        await for (final legacyDir in entity.list(followLinks: false)) {
          if (legacyDir is! Directory) continue;
          final legacyName = legacyDir.uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .last;
          if (!RegExp(r'^card_[0-9a-f]{24}_[0-9]+$')
              .hasMatch(legacyName)) {
            continue;
          }
          await _recoverDirectory(legacyDir);
        }
      }
    }
  }

  Future<void> _recoverDirectory(Directory directory) async {
    try {
      await RecoverableFileExchange.recover(
        File('${directory.path}${Platform.pathSeparator}rich_text.json'),
        validator: _isValidDocument,
      );
    } catch (_) {
      // One damaged card must not block recovery of the remaining cards.
    }
  }

  /// Deletes the saved document for [cardId]. No-op if absent.
  Future<void> delete(String cardId) async {
    final dir = _cardDir(cardId);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  static bool _isValidDocument(String contents) {
    try {
      final json = jsonDecode(contents) as Map<String, dynamic>;
      migrateRichTextDocument(json);
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _validateCardId(String cardId) {
    if (cardId.trim().isEmpty ||
        cardId.contains('/') ||
        cardId.contains('\\') ||
        cardId.contains('..') ||
        cardId.contains(':')) {
      throw RichTextUnsafeCardIdError(cardId);
    }
  }
}
