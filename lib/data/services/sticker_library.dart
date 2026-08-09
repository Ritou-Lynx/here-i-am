import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A single sticker entry parsed from `assets/stickers/manifest.json`.
class Sticker {
  final String id;
  final String packId;
  final String packName;
  final String file;
  final String desc;

  const Sticker({
    required this.id,
    required this.packId,
    required this.packName,
    required this.file,
    required this.desc,
  });

  String get assetPath => 'assets/stickers/$file';
}

/// Singleton that loads and indexes sticker packs from
/// `assets/stickers/manifest.json`.
///
/// Call [load] once during app start (or before the companion agent builds its
/// tools).  The call is idempotent so it is safe to call again.
class StickerLibrary {
  StickerLibrary._();
  static final StickerLibrary instance = StickerLibrary._();

  final Map<String, Sticker> _byId = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get isEmpty => _byId.isEmpty;
  bool get isNotEmpty => _byId.isNotEmpty;
  int get count => _byId.length;

  /// Load (or re-load) the manifest from assets.  Idempotent: a no-op if
  /// already loaded unless [force] is true.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _byId.clear();
    try {
      final raw = await rootBundle.loadString('assets/stickers/manifest.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final packs = data['packs'] as List<dynamic>? ?? [];
      for (final pack in packs) {
        final p = pack as Map<String, dynamic>;
        final packId = p['id'] as String;
        final packName = p['name'] as String? ?? packId;
        final stickers = p['stickers'] as List<dynamic>? ?? [];
        for (final s in stickers) {
          final sm = s as Map<String, dynamic>;
          final id = sm['id'] as String;
          _byId[id] = Sticker(
            id: id,
            packId: packId,
            packName: packName,
            file: sm['file'] as String,
            desc: sm['desc'] as String? ?? id,
          );
        }
      }
      _loaded = true;
      debugPrint('[StickerLibrary] Loaded ${_byId.length} stickers from ${packs.length} packs');
    } catch (e) {
      debugPrint('[StickerLibrary] Failed to load manifest: $e');
      _loaded = true; // mark loaded to avoid retry loop on missing manifest
    }
  }

  /// Look up a sticker by its full id (e.g. "test/hello").
  Sticker? get(String id) => _byId[id];

  /// All sticker ids, used to build the `enum` for the `send_sticker` tool.
  List<String> get ids => _byId.keys.toList();

  /// A human-readable list for per-turn system-reminder injection.
  /// Format: one line per sticker, "- <id>  <desc>"
  String get reminderList {
    final b = StringBuffer();
    String? lastPack;
    for (final s in _byId.values) {
      if (s.packId != lastPack) {
        if (lastPack != null) b.writeln();
        b.writeln('[${s.packName}]');
        lastPack = s.packId;
      }
      b.writeln('- ${s.id}  ${s.desc}');
    }
    return b.toString().trimRight();
  }
}
