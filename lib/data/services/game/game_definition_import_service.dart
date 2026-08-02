import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';

const _uuid = Uuid();
final _log = Logger('GameDefinitionImportService');

/// Parsed preview of a SillyTavern V2 (or V1) character card.
///
/// Only used for gameType = 'card_roleplay'. Other game types may have
/// their own preview classes.
class CharacterCardPreview {
  const CharacterCardPreview({
    required this.name,
    required this.description,
    required this.tags,
    required this.firstMessage,
    required this.hasLorebook,
    required this.lorebookEntryCount,
    required this.spec,
    this.creatorNotes,
  });

  final String name;
  final String description;
  final List<String> tags;
  final String firstMessage;
  final bool hasLorebook;
  final int lorebookEntryCount;
  final String spec; // 'chara_card_v2' | 'V1'
  final String? creatorNotes;
}

/// Imports game definitions (currently only SillyTavern character cards for
/// gameType = 'card_roleplay') into [GameDefinitions].
///
/// Architecture guard: no dependency on CharacterService, FileSystemService,
/// or any other Memex-specific singleton. Avatar files are written to
/// [avatarDirectory] supplied at construction time.
///
/// Future game types (text adventures, tabletop RPG, etc.) will have their
/// own import methods on this same service, all writing to GameDefinitions
/// with different gameType values and different configJson structures.
class GameDefinitionImportService {
  final AppDatabase db;
  final String avatarDirectory; // absolute path to store extracted PNGs

  GameDefinitionImportService(this.db, {required this.avatarDirectory});

  // ── Public API ────────────────────────────────────────────────────────────

  /// Parse a card file and return a lightweight preview (no DB write).
  /// Only for gameType = 'card_roleplay'.
  Future<CharacterCardPreview> previewCardFromFile(String filePath) async {
    final raw = await _loadRawCard(filePath);
    return _buildPreview(raw);
  }

  /// Import a character card file into [GameDefinitions] with gameType = 'card_roleplay'.
  /// Returns the stored row. For PNG files, the image itself is copied to [avatarDirectory].
  Future<GameDefinition> importCardFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw ArgumentError('File not found: $filePath');

    final lower = filePath.toLowerCase();
    final raw = await _loadRawCard(filePath);
    final preview = _buildPreview(raw);

    String? avatarPath;
    if (lower.endsWith('.png')) {
      avatarPath = await _saveAvatarFromPng(filePath);
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = _uuid.v4();
    final definitionJson = jsonEncode(raw);

    await db.into(db.gameDefinitions).insert(
          GameDefinitionsCompanion.insert(
            id: id,
            gameType: const Value('card_roleplay'),
            title: preview.name,
            description: Value(preview.description),
            definitionJson: definitionJson,
            thumbnailPath: Value(avatarPath),
            sourceFilename: Value(p.basename(filePath)),
            importedAt: now,
          ),
        );

    _log.info('Imported card "${preview.name}" as card_roleplay definition (id=$id)');
    return (await _getDefinition(id))!;
  }

  /// List all imported definitions, newest first. Optionally filter by gameType.
  Future<List<GameDefinition>> listDefinitions({String? gameType}) =>
      (db.select(db.gameDefinitions)
            ..where((t) => gameType == null ? const Constant(true) : t.gameType.equals(gameType))
            ..orderBy([(t) => OrderingTerm.desc(t.importedAt)]))
          .get();

  /// Delete a definition. Does NOT cascade to sessions — sessions snapshot
  /// the definition at creation time so they survive deletion.
  Future<void> deleteDefinition(String definitionId) =>
      (db.delete(db.gameDefinitions)
            ..where((t) => t.id.equals(definitionId)))
          .go();

  // ── Card parsing ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _loadRawCard(String filePath) async {
    final lower = filePath.toLowerCase();
    final file = File(filePath);
    if (!await file.exists()) throw ArgumentError('File not found: $filePath');

    if (lower.endsWith('.json')) {
      final text = await file.readAsString();
      final obj = jsonDecode(text);
      if (obj is! Map) throw ArgumentError('Invalid card JSON');
      return Map<String, dynamic>.from(obj);
    } else if (lower.endsWith('.png')) {
      return _extractCardFromPng(await file.readAsBytes());
    }
    throw ArgumentError('Unsupported format (expected .json or .png)');
  }

  CharacterCardPreview _buildPreview(Map<String, dynamic> raw) {
    final data = _normalizeCardData(raw);
    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) throw ArgumentError('Card is missing a name');

    final desc = _joinFields(data, ['description', 'personality', 'scenario']);
    final tags = (data['tags'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        <String>[];
    final firstMsg = (data['first_mes'] as String?)?.trim() ?? '';
    final notes = (data['creator_notes'] as String?)?.trim();

    final book = data['character_book'];
    final entries =
        (book is Map ? (book['entries'] as List?) : null) ?? const [];

    final spec =
        (raw['spec'] as String?)?.trim().toLowerCase() == 'chara_card_v2'
            ? 'chara_card_v2'
            : 'V1';

    return CharacterCardPreview(
      name: name,
      description: desc,
      tags: tags,
      firstMessage: firstMsg,
      hasLorebook: entries.isNotEmpty,
      lorebookEntryCount: entries.length,
      spec: spec,
      creatorNotes: notes,
    );
  }

  // ── PNG parsing (ported from TavernCharacterImportService) ──────────────

  Map<String, dynamic> _extractCardFromPng(Uint8List bytes) {
    const pngSig = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 8 ||
        !List.generate(8, (i) => bytes[i] == pngSig[i]).every((e) => e)) {
      throw ArgumentError('Not a valid PNG file');
    }
    int offset = 8;
    String? jsonText;
    while (offset + 8 <= bytes.length) {
      final length = _readUint32(bytes, offset);
      offset += 4;
      final type = ascii.decode(bytes.sublist(offset, offset + 4));
      offset += 4;
      if (offset + length + 4 > bytes.length) break;
      final chunkData = bytes.sublist(offset, offset + length);
      offset += length + 4; // data + crc
      if (type == 'tEXt') {
        final zero = chunkData.indexOf(0);
        if (zero > 0) {
          final key = latin1.decode(chunkData.sublist(0, zero));
          final value = latin1.decode(chunkData.sublist(zero + 1));
          jsonText = _parseEmbeddedValue(key, value);
          if (jsonText != null) break;
        }
      } else if (type == 'iTXt') {
        jsonText = _parseITXt(chunkData);
        if (jsonText != null) break;
      } else if (type == 'IEND') {
        break;
      }
    }
    if (jsonText == null) throw ArgumentError('No embedded card found in PNG');
    final obj = jsonDecode(jsonText);
    if (obj is! Map) throw ArgumentError('Invalid embedded card JSON');
    return Map<String, dynamic>.from(obj);
  }

  String? _parseEmbeddedValue(String key, String value) {
    if (key.toLowerCase().contains('chara')) {
      try {
        return utf8.decode(base64.decode(value.trim()));
      } catch (_) {
        if (value.trim().startsWith('{')) return value;
      }
    }
    if (value.trim().startsWith('{') && value.contains('"name"')) return value;
    return null;
  }

  String? _parseITXt(Uint8List data) {
    final firstZero = data.indexOf(0);
    if (firstZero <= 0) return null;
    final keyword = latin1.decode(data.sublist(0, firstZero));
    if (!keyword.toLowerCase().contains('chara')) return null;
    if (firstZero + 2 >= data.length) return null;
    final compressionFlag = data[firstZero + 1];
    if (compressionFlag != 0) return null; // skip compressed
    int pos = firstZero + 3;
    while (pos < data.length && data[pos] != 0) { pos++; }
    pos++;
    while (pos < data.length && data[pos] != 0) { pos++; }
    pos++;
    if (pos >= data.length) return null;
    final value = utf8.decode(data.sublist(pos), allowMalformed: true);
    return _parseEmbeddedValue(keyword, value);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// V2 card wraps fields under `data`; V1 puts them at top level.
  Map<String, dynamic> _normalizeCardData(Map<String, dynamic> input) {
    if (input['data'] case final Map data
        when data.isNotEmpty &&
            (data['name'] != null || data['description'] != null)) {
      return Map<String, dynamic>.from(data);
    }
    return Map<String, dynamic>.from(input);
  }

  /// Concatenate character fields into a single description string.
  String _joinFields(Map<String, dynamic> data, List<String> keys) {
    final parts = <String>[];
    for (final key in keys) {
      final val = (data[key] as String?)?.trim();
      if (val != null && val.isNotEmpty) parts.add(val);
    }
    return parts.join('\n\n');
  }

  /// Copy the source PNG to [avatarDirectory] and return the new path.
  Future<String> _saveAvatarFromPng(String sourcePath) async {
    final dir = Directory(avatarDirectory);
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = p.join(avatarDirectory, 'card_avatar_${_uuid.v4()}.png');
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<GameDefinition?> _getDefinition(String id) =>
      (db.select(db.gameDefinitions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
