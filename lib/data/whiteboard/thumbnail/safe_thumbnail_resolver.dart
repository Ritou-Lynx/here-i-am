/// Safe, rebuildable thumbnail projection for whiteboard Source cards.
///
/// Remote metadata is only an untrusted candidate. The resolver downloads it
/// through [SafeHttpClient]'s DNS-pinned SSRF boundary, validates MIME against
/// the actual decoder, rejects excessive pixels, decodes one static frame,
/// strips metadata by re-encoding PNG, and stores the result under a
/// content-addressed relative `thumbnail_ref`.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';

typedef _DecodedThumbnail = ({
  Uint8List? bytes,
  int width,
  int height,
  String? error,
});

_DecodedThumbnail _decodeThumbnail({
  required Uint8List bytes,
  required String mime,
  required int maxInputPixels,
  required int maxInputDimension,
  required int maxOutputDimension,
}) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null || !_thumbnailFormatMatchesMime(decoder.format, mime)) {
    return (
      bytes: null,
      width: 0,
      height: 0,
      error: 'Thumbnail MIME does not match decodable image bytes',
    );
  }
  final img.DecodeInfo? info;
  try {
    info = decoder.startDecode(bytes);
  } catch (_) {
    return (
      bytes: null,
      width: 0,
      height: 0,
      error: 'Invalid thumbnail image',
    );
  }
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width > maxInputDimension ||
      info.height > maxInputDimension ||
      info.width * info.height > maxInputPixels) {
    return (
      bytes: null,
      width: 0,
      height: 0,
      error: 'Thumbnail dimensions exceed the safe pixel limit',
    );
  }

  final img.Image? decoded;
  try {
    decoded = decoder.decode(bytes, frame: 0);
  } catch (_) {
    return (
      bytes: null,
      width: 0,
      height: 0,
      error: 'Invalid thumbnail image',
    );
  }
  if (decoded == null) {
    return (
      bytes: null,
      width: 0,
      height: 0,
      error: 'Invalid thumbnail image',
    );
  }
  var staticImage = img.bakeOrientation(decoded);
  if (staticImage.width > maxOutputDimension ||
      staticImage.height > maxOutputDimension) {
    staticImage = staticImage.width >= staticImage.height
        ? img.copyResize(
            staticImage,
            width: maxOutputDimension,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            staticImage,
            height: maxOutputDimension,
            interpolation: img.Interpolation.average,
          );
  }
  return (
    bytes: img.encodePng(staticImage, level: 6),
    width: staticImage.width,
    height: staticImage.height,
    error: null,
  );
}

bool _thumbnailFormatMatchesMime(img.ImageFormat format, String mime) {
  return switch (mime) {
    'image/png' => format == img.ImageFormat.png,
    'image/jpeg' => format == img.ImageFormat.jpg,
    'image/webp' => format == img.ImageFormat.webp,
    'image/gif' => format == img.ImageFormat.gif,
    _ => false,
  };
}

enum ThumbnailResolveStatus { available, missing, rejected, failed }

class ThumbnailResolveRequest {
  const ThumbnailResolveRequest({
    required this.sourceId,
    required this.sourceVersionId,
    required this.candidateUrl,
    required this.canonicalUrl,
    this.cachedObjectRef,
    this.cachedVersionId,
    this.cachedCandidateHash,
  });

  final String sourceId;
  final String sourceVersionId;
  final String? candidateUrl;
  final String? canonicalUrl;
  final String? cachedObjectRef;
  final String? cachedVersionId;
  final String? cachedCandidateHash;
}

class ResolvedThumbnail {
  const ResolvedThumbnail._({
    required this.status,
    this.file,
    this.objectRef,
    this.mimeType,
    this.width,
    this.height,
    this.candidateHash,
    this.errorMessage,
  });

  const ResolvedThumbnail.missing()
      : this._(status: ThumbnailResolveStatus.missing);

  const ResolvedThumbnail.rejected(String message)
      : this._(
          status: ThumbnailResolveStatus.rejected,
          errorMessage: message,
        );

  const ResolvedThumbnail.failed(String message)
      : this._(
          status: ThumbnailResolveStatus.failed,
          errorMessage: message,
        );

  const ResolvedThumbnail.available({
    required File file,
    required String objectRef,
    required int width,
    required int height,
    required String candidateHash,
  }) : this._(
          status: ThumbnailResolveStatus.available,
          file: file,
          objectRef: objectRef,
          mimeType: 'image/png',
          width: width,
          height: height,
          candidateHash: candidateHash,
        );

  final ThumbnailResolveStatus status;
  final File? file;
  final String? objectRef;
  final String? mimeType;
  final int? width;
  final int? height;
  final String? candidateHash;
  final String? errorMessage;

  bool get isAvailable => status == ThumbnailResolveStatus.available;
}

abstract interface class ThumbnailResolver {
  Future<ResolvedThumbnail> resolve(ThumbnailResolveRequest request);
}

typedef ThumbnailReferenceProvider = Future<Set<String>> Function();

class SafeThumbnailResolver implements ThumbnailResolver {
  SafeThumbnailResolver({
    required this.whiteboardRoot,
    SafeHttpClient? httpClient,
    this.maxInputPixels = 16 * 1024 * 1024,
    this.maxInputDimension = 8192,
    this.maxOutputDimension = 1024,
    this.maxCacheBytes = 128 * 1024 * 1024,
    this.maxConcurrentResolutions = 1,
    this.orphanGracePeriod = const Duration(hours: 24),
    this.referencedObjectRefs,
  }) : _httpClient = httpClient ?? SafeHttpClient(config: httpConfig);

  static const httpConfig = SafeHttpConfig(
    maxBodyBytes: 5 * 1024 * 1024,
    maxRetries: 1,
    allowedMimePrefixes: {
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
    },
    acceptHeader: 'image/png,image/jpeg,image/webp,image/gif;q=0.9',
  );

  final Directory whiteboardRoot;
  final SafeHttpClient _httpClient;
  final int maxInputPixels;
  final int maxInputDimension;
  final int maxOutputDimension;
  final int maxCacheBytes;
  final int maxConcurrentResolutions;
  final Duration orphanGracePeriod;
  final ThumbnailReferenceProvider? referencedObjectRefs;
  final Map<String, Future<ResolvedThumbnail>> _inFlight = {};
  Future<void> _writeTail = Future<void>.value();
  int _activeResolutions = 0;
  final Queue<Completer<void>> _resolutionWaiters = Queue();

  Directory get _cacheDirectory => Directory(
        '${whiteboardRoot.path}${Platform.pathSeparator}objects'
        '${Platform.pathSeparator}thumbnails',
      );

  static String? candidateHashFor(String? candidate, String? canonicalUrl) {
    final normalized = _normalizeCandidate(candidate, canonicalUrl);
    return normalized == null
        ? null
        : sha256.convert(normalized.toString().codeUnits).toString();
  }

  @override
  Future<ResolvedThumbnail> resolve(ThumbnailResolveRequest request) async {
    try {
      return await _resolve(request);
    } catch (_) {
      return const ResolvedThumbnail.failed('Thumbnail resolution failed');
    }
  }

  Future<ResolvedThumbnail> _resolve(ThumbnailResolveRequest request) async {
    final normalized = _normalizeCandidate(
      request.candidateUrl,
      request.canonicalUrl,
    );
    final candidateHash = normalized == null
        ? request.cachedCandidateHash
        : sha256.convert(normalized.toString().codeUnits).toString();

    final cachedRef = request.cachedObjectRef;
    final cachedVersionMatches =
        request.cachedVersionId == request.sourceVersionId;
    final cachedCandidateMatches = normalized == null ||
        (candidateHash != null && request.cachedCandidateHash == candidateHash);
    if (cachedRef != null && cachedVersionMatches && cachedCandidateMatches) {
      final cached = await resolveCached(cachedRef);
      if (cached != null) {
        return ResolvedThumbnail.available(
          file: cached.file!,
          objectRef: cached.objectRef!,
          width: cached.width!,
          height: cached.height!,
          candidateHash: candidateHash ?? '',
        );
      }
    }

    if (normalized == null || candidateHash == null) {
      return const ResolvedThumbnail.missing();
    }
    final key = '${request.sourceId}\n${request.sourceVersionId}\n'
        '$candidateHash';
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _withResolutionPermit(
      () => _downloadAndCache(normalized, candidateHash),
    );
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  /// Resolves only the content-addressed cache namespace. Arbitrary local
  /// paths, legacy thumbnail paths, symlinks, corrupt files and hash-mismatched
  /// files are rejected before a File reaches UI code.
  Future<ResolvedThumbnail?> resolveCached(String? objectRef) async {
    try {
      return await _resolveCached(objectRef);
    } catch (_) {
      return null;
    }
  }

  Future<ResolvedThumbnail?> _resolveCached(String? objectRef) async {
    final ref = objectRef?.trim();
    final match = ref == null
        ? null
        : RegExp(r'^objects/thumbnails/([0-9a-f]{64})\.png$').firstMatch(ref);
    if (match == null) return null;
    if (!_cacheNamespaceIsTrusted()) return null;
    final fileName = '${match.group(1)}.png';
    final file = File(
      '${_cacheDirectory.path}${Platform.pathSeparator}$fileName',
    );
    if (!await file.exists() || FileSystemEntity.isLinkSync(file.path)) {
      return null;
    }
    final length = await file.length();
    if (length <= 0 || length > httpConfig.maxBodyBytes) return null;
    try {
      final bytes = await file.readAsBytes();
      if (sha256.convert(bytes).toString() != match.group(1)) return null;
      final decoder = img.PngDecoder();
      final info = decoder.startDecode(bytes);
      if (info == null ||
          info.width <= 0 ||
          info.height <= 0 ||
          info.width > maxOutputDimension ||
          info.height > maxOutputDimension) {
        return null;
      }
      return ResolvedThumbnail.available(
        file: file,
        objectRef: ref!,
        width: info.width,
        height: info.height,
        candidateHash: '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<ResolvedThumbnail> _downloadAndCache(
    Uri candidate,
    String candidateHash,
  ) async {
    final fetched = await _httpClient.fetchBytes(candidate.toString());
    if (!fetched.success) {
      final message = fetched.errorMessage ?? 'thumbnail fetch failed';
      return _isPolicyFailure(message)
          ? ResolvedThumbnail.rejected(message)
          : ResolvedThumbnail.failed(message);
    }
    final bytes = fetched.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const ResolvedThumbnail.rejected('Empty thumbnail body');
    }
    final mime = fetched.mimeType ?? '';
    final inputPixels = maxInputPixels;
    final inputDimension = maxInputDimension;
    final outputDimension = maxOutputDimension;
    final decoded = await Isolate.run(
      () => _decodeThumbnail(
        bytes: bytes,
        mime: mime,
        maxInputPixels: inputPixels,
        maxInputDimension: inputDimension,
        maxOutputDimension: outputDimension,
      ),
    );
    if (decoded.error != null || decoded.bytes == null) {
      return ResolvedThumbnail.rejected(
        decoded.error ?? 'Invalid thumbnail image',
      );
    }
    return _writeContentAddressed(
      decoded.bytes!,
      width: decoded.width,
      height: decoded.height,
      candidateHash: candidateHash,
    );
  }

  Future<ResolvedThumbnail> _withResolutionPermit(
    Future<ResolvedThumbnail> Function() action,
  ) async {
    if (maxConcurrentResolutions <= 0) {
      return const ResolvedThumbnail.failed(
        'Thumbnail resolution concurrency is disabled',
      );
    }
    if (_activeResolutions >= maxConcurrentResolutions) {
      final waiter = Completer<void>();
      _resolutionWaiters.add(waiter);
      await waiter.future;
    } else {
      _activeResolutions++;
    }
    try {
      return await action();
    } finally {
      if (_resolutionWaiters.isNotEmpty) {
        // Transfer this permit directly. Decrementing before wake-up would
        // let a newly arriving request steal the slot and briefly exceed the
        // configured full-pipeline concurrency bound.
        _resolutionWaiters.removeFirst().complete();
      } else {
        _activeResolutions--;
      }
    }
  }

  Future<ResolvedThumbnail> _writeContentAddressed(
    Uint8List bytes, {
    required int width,
    required int height,
    required String candidateHash,
  }) {
    final operation = _writeTail.then(
      (_) => _writeContentAddressedOnce(
        bytes,
        width: width,
        height: height,
        candidateHash: candidateHash,
      ),
    );
    _writeTail = operation.then<void>(
      (_) {},
      onError: (_, __) {},
    );
    return operation;
  }

  Future<ResolvedThumbnail> _writeContentAddressedOnce(
    Uint8List bytes, {
    required int width,
    required int height,
    required String candidateHash,
  }) async {
    final hash = sha256.convert(bytes).toString();
    final objectRef = 'objects/thumbnails/$hash.png';
    final directory = _cacheDirectory;
    if (!_cacheNamespaceIsTrusted()) {
      return const ResolvedThumbnail.rejected(
        'Thumbnail cache directory is not trusted',
      );
    }
    await directory.create(recursive: true);
    final target = File(
      '${directory.path}${Platform.pathSeparator}$hash.png',
    );
    if (await target.exists()) {
      final existing = await resolveCached(objectRef);
      if (existing != null) {
        return ResolvedThumbnail.available(
          file: target,
          objectRef: objectRef,
          width: width,
          height: height,
          candidateHash: candidateHash,
        );
      }
      if (FileSystemEntity.isLinkSync(target.path)) {
        return const ResolvedThumbnail.rejected(
          'Thumbnail cache object failed integrity validation',
        );
      }
      // A corrupt regular cache object is rebuildable. Remove only the exact
      // content-addressed target after namespace and symlink checks, then
      // atomically replace it with the freshly decoded bytes below.
      await target.delete();
    }
    if (!await _ensureCapacity(bytes.length)) {
      return const ResolvedThumbnail.failed(
        'Thumbnail cache reached its size limit',
      );
    }

    final temp = File(
      '${target.path}.${pid}_${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      try {
        await temp.rename(target.path);
      } on FileSystemException {
        if (!await target.exists()) rethrow;
      }
      final resolved = await resolveCached(objectRef);
      if (resolved == null) {
        return const ResolvedThumbnail.rejected(
          'Thumbnail cache write failed integrity validation',
        );
      }
      return ResolvedThumbnail.available(
        file: target,
        objectRef: objectRef,
        width: width,
        height: height,
        candidateHash: candidateHash,
      );
    } catch (_) {
      return const ResolvedThumbnail.failed('Thumbnail cache write failed');
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<bool> _ensureCapacity(int incomingBytes) async {
    var used = 0;
    final cacheFiles = <File>[];
    final reclaimable = <({
      File file,
      String objectRef,
      DateTime modifiedAt,
    })>[];
    if (await _cacheDirectory.exists()) {
      await for (final entity in _cacheDirectory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.png')) continue;
        used += await entity.length();
        cacheFiles.add(entity);
      }
    }
    if (used + incomingBytes <= maxCacheBytes) return true;

    final provider = referencedObjectRefs;
    if (provider == null || !_cacheNamespaceIsTrusted()) return false;
    final Set<String> referenced;
    try {
      referenced = await provider();
    } catch (_) {
      // Reference discovery is the deletion authority. If it is unavailable,
      // fail closed and retain every cache object.
      return false;
    }
    final cutoff = DateTime.now().subtract(orphanGracePeriod);
    for (final file in cacheFiles) {
      if (FileSystemEntity.isLinkSync(file.path)) continue;
      final fileName = file.uri.pathSegments.last;
      if (!RegExp(r'^[0-9a-f]{64}\.png$').hasMatch(fileName)) continue;
      final objectRef = 'objects/thumbnails/$fileName';
      if (referenced.contains(objectRef)) continue;
      final modifiedAt = await file.lastModified();
      // A resolver may have atomically written an object just before its
      // Repository projection commits. The grace period protects that
      // bounded hand-off window and recent cross-process writes.
      if (!modifiedAt.isBefore(cutoff)) continue;
      reclaimable.add((
        file: file,
        objectRef: objectRef,
        modifiedAt: modifiedAt,
      ));
    }

    reclaimable.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
    for (final candidate in reclaimable) {
      if (!_cacheNamespaceIsTrusted()) return false;
      final Set<String> latestReferenced;
      try {
        // Re-read immediately before deletion so a reference committed while
        // the sweep was being prepared cannot be removed from under its Card
        // or Source projection.
        latestReferenced = await provider();
      } catch (_) {
        return false;
      }
      if (latestReferenced.contains(candidate.objectRef)) continue;
      try {
        if (!await candidate.file.exists() ||
            FileSystemEntity.isLinkSync(candidate.file.path)) {
          continue;
        }
        final currentModifiedAt = await candidate.file.lastModified();
        if (currentModifiedAt != candidate.modifiedAt ||
            !currentModifiedAt.isBefore(cutoff) ||
            referenced.contains(candidate.objectRef)) {
          continue;
        }
        final currentLength = await candidate.file.length();
        await candidate.file.delete();
        used -= currentLength;
        if (used + incomingBytes <= maxCacheBytes) return true;
      } catch (_) {
        // An object that changed or became unreadable during the sweep is not
        // safe to delete. Continue with other proven orphan candidates.
      }
    }
    return used + incomingBytes <= maxCacheBytes;
  }

  bool _cacheNamespaceIsTrusted() {
    final objects = Directory(
      '${whiteboardRoot.path}${Platform.pathSeparator}objects',
    );
    for (final directory in [whiteboardRoot, objects, _cacheDirectory]) {
      if (directory.existsSync() &&
          FileSystemEntity.isLinkSync(directory.path)) {
        return false;
      }
    }
    return true;
  }

  static Uri? _normalizeCandidate(String? raw, String? canonicalUrl) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed == null) return null;
    Uri resolved = parsed;
    if (!parsed.hasScheme) {
      final base = Uri.tryParse(canonicalUrl ?? '');
      if (base == null ||
          (base.scheme != 'http' && base.scheme != 'https') ||
          base.host.isEmpty) {
        return null;
      }
      resolved = base.resolveUri(parsed);
    }
    if ((resolved.scheme != 'http' && resolved.scheme != 'https') ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty) {
      return null;
    }
    return resolved;
  }

  static bool _isPolicyFailure(String message) {
    return message.startsWith('SSRF blocked:') ||
        message.startsWith('DNS resolution failed') ||
        message.startsWith('Disallowed scheme:') ||
        message.startsWith('Unsupported MIME type:') ||
        message.startsWith('Response body exceeds max size') ||
        message.startsWith('Too many redirects') ||
        message.startsWith('Redirect');
  }
}
