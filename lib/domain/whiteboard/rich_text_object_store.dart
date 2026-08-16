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
    if (!_objectsDir.existsSync()) {
      await _objectsDir.create(recursive: true);
    }
    final dest = File('${_objectsDir.path}${Platform.pathSeparator}$refId'
        '${ext.isNotEmpty ? '.$ext' : ''}');
    await source.copy(dest.path);
    return RichTextAssetRef(
      refId: refId,
      objectRef: objectRef,
      mimeType: mimeType ?? mimeTypeForPath(sourcePath),
      width: width,
      height: height,
      alt: alt,
      caption: caption,
    );
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
    final file = File('${baseDir.path}${Platform.pathSeparator}$normalized');
    if (!file.existsSync()) return null;
    return file;
  }

  /// Deletes the object file backing [ref] (if any). No-op for refs that
  /// never pointed into this store. Does not touch the document JSON.
  Future<void> deleteRef(RichTextAssetRef ref) async {
    final normalized = _normalizeObjectRef(ref.objectRef);
    if (normalized == null) return;
    final file = File('${baseDir.path}${Platform.pathSeparator}$normalized');
    if (await file.exists()) {
      await file.delete();
    }
  }

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

  static final Random _random = Random.secure();

  static String _newRefId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final rand =
        List.generate(8, (_) => _random.nextInt(16).toRadixString(16)).join();
    return 'obj_${ts}_$rand';
  }

  static String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
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
