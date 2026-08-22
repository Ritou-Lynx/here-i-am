/// Object-store bridge for media imported into [RichTextDocument]s.
///
/// Images and attachments are copied into a stable object directory
/// (`<baseDir>/objects/…`) and referenced by a relative, stable `object_ref`
/// (e.g. `objects/a1b2c3.png`) inside [RichTextAssetRef]. The document JSON
/// never carries temporary source paths or binaries — only the object ref.
///
/// Convention (shared with [RichTextStorage]):
/// - `card_<id>/rich_text.json` — per-card documents
/// - `objects/…` — content-addressed media, referenced by `object_ref`
///
/// This module is deliberately decoupled from Drift / MemexRouter: it takes a
/// base directory and copies / resolves files, nothing more.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'rich_text_asset_ref.dart';

/// Copies user-picked media into the object store and resolves object refs
/// back to files for rendering.
class RichTextObjectStore {
  final Directory baseDir;

  RichTextObjectStore(this.baseDir);

  Directory get _objectsDir =>
      Directory('${baseDir.path}${Platform.pathSeparator}objects');

  /// The object directory itself (created lazily by [importFile]).
  Directory get objectsDirectory => _objectsDir;

  /// Imports a local file into the object store and returns a stable
  /// [RichTextAssetRef] whose `object_ref` is relative (`objects/…`).
  ///
  /// The source file is copied; the returned ref never contains the source
  /// path. [mimeType] is inferred from the extension when not provided.
  Future<RichTextAssetRef> importFile(
    String sourcePath, {
    String? mimeType,
    String? alt,
    String? caption,
    int? width,
    int? height,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Source file not found: $sourcePath');
    }
    final ext = _extensionOf(sourcePath);
    final refId = _newRefId();
    final objectRef = 'objects/$refId${ext.isNotEmpty ? '.$ext' : ''}';
    await _objectsDir.create(recursive: true);
    final dest = File(
      '${_objectsDir.path}${Platform.pathSeparator}$refId'
      '${ext.isNotEmpty ? '.$ext' : ''}',
    );
    await source.copy(dest.path);
    return RichTextAssetRef(
      refId: refId,
      objectRef: objectRef,
      mimeType: mimeType ?? mimeTypeForPath(sourcePath),
      alt: alt,
      caption: caption,
      width: width,
      height: height,
    );
  }

  /// Stores [bytes] under their SHA-256 digest and returns a stable ref.
  ///
  /// Re-importing identical bytes is idempotent: it resolves to the same
  /// object path and does not create a second copy. Callers must already have
  /// applied their transport, MIME and size policy before invoking this
  /// storage-only method.
  Future<RichTextAssetRef> importBytes(
    Uint8List bytes, {
    required String mimeType,
    String? extension,
    String? alt,
    String? caption,
    int? width,
    int? height,
  }) async {
    if (bytes.isEmpty) throw StateError('Cannot import an empty object');
    final digest = sha256.convert(bytes).toString();
    final safeExtension = _safeExtension(
      extension ?? extensionForMime(mimeType),
    );
    final objectRef =
        'objects/$digest${safeExtension.isEmpty ? '' : '.$safeExtension'}';
    await _objectsDir.create(recursive: true);
    final dest = File(
      '${_objectsDir.path}${Platform.pathSeparator}$digest'
      '${safeExtension.isEmpty ? '' : '.$safeExtension'}',
    );
    if (!await dest.exists()) {
      final temporary = File(
        '${dest.path}.${DateTime.now().microsecondsSinceEpoch}'
        '.${_random.nextInt(1 << 32)}.tmp',
      );
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(dest.path);
      } on FileSystemException {
        // Another concurrent importer may have won the same digest. The
        // existing content-addressed object is already the desired result.
        if (!await dest.exists()) rethrow;
        if (await temporary.exists()) await temporary.delete();
      }
    }
    return RichTextAssetRef(
      refId: digest,
      objectRef: objectRef,
      mimeType: mimeType,
      width: width,
      height: height,
      alt: alt,
      caption: caption,
    );
  }

  static final Random _random = Random.secure();

  static String _newRefId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final rand =
        List.generate(8, (_) => _random.nextInt(16).toRadixString(16)).join();
    return 'obj_${ts}_$rand';
  }

  /// Resolves an asset ref's [RichTextAssetRef.objectRef] to a [File] under
  /// this store's base directory.
  ///
  /// Returns null for refs whose object ref is malformed, absolute, or
  /// escapes the objects directory (path-traversal guard), or when the file
  /// does not exist.
  File? resolveFile(RichTextAssetRef ref) {
    final normalized = _normalizeObjectRef(ref.objectRef);
    if (normalized == null) return null;
    return _resolvedRegularFile(normalized);
  }

  /// Deletes the object file backing [ref] (if any). No-op for refs that
  /// never pointed into this store. Does not touch the document JSON.
  Future<void> deleteRef(RichTextAssetRef ref) async {
    final normalized = _normalizeObjectRef(ref.objectRef);
    if (normalized == null) return;
    // Digest-addressed objects may be shared by several Cards or ingestion
    // evidence manifests. Without a reference index it is unsafe to delete
    // the physical file for one caller. Keep it for a future mark/sweep GC.
    if (RegExp(r'^objects/[0-9a-f]{64}\.[a-z0-9]{1,8}$').hasMatch(normalized)) {
      return;
    }
    final file = _resolvedRegularFile(normalized);
    if (file != null) await file.delete();
  }

  /// Resolves only a real regular file whose canonical target remains under
  /// this store's real `objects/` directory. Symlink/reparse-point leaves and
  /// directories are rejected before Image.file or delete can follow them.
  File? _resolvedRegularFile(String normalized) {
    final segments = normalized.split('/');
    var current = baseDir.path;
    for (var i = 0; i < segments.length - 1; i++) {
      current = '$current${Platform.pathSeparator}${segments[i]}';
      if (FileSystemEntity.typeSync(current, followLinks: false) !=
          FileSystemEntityType.directory) {
        return null;
      }
    }
    final file = File('${baseDir.path}${Platform.pathSeparator}$normalized');
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    try {
      final root = _canonicalForComparison(
        _objectsDir.resolveSymbolicLinksSync(),
      );
      final target = _canonicalForComparison(file.resolveSymbolicLinksSync());
      final prefix = root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}';
      if (!target.startsWith(prefix)) return null;
      return file;
    } on FileSystemException {
      return null;
    }
  }

  static String _canonicalForComparison(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;

  /// Strips unsafe object refs. Only relative refs inside `objects/` are
  /// accepted: no absolute paths, no `..` traversal, no backslashes.
  String? _normalizeObjectRef(String objectRef) {
    final raw = objectRef.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('/') || raw.contains(':')) return null;
    if (raw.contains('\\') || raw.contains('..')) return null;
    if (!raw.startsWith('objects/')) return null;
    return raw;
  }

  static String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _safeExtension(String value) {
    final normalized = value.trim().toLowerCase().replaceFirst('.', '');
    return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(normalized) ? normalized : '';
  }

  static String extensionForMime(String mimeType) {
    switch (mimeType.toLowerCase().split(';').first.trim()) {
      case 'image/png':
        return 'png';
      case 'image/jpeg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      default:
        return '';
    }
  }

  /// Best-effort mime type from a file path's extension.
  static String mimeTypeForPath(String path) {
    switch (_extensionOf(path)) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'mp3':
        return 'audio/mpeg';
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}
