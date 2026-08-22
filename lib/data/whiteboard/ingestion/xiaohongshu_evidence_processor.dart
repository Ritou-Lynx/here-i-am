import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:memex/data/services/reading/ocr_recognizer.dart';
import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

class XiaohongshuEvidenceProcessor {
  XiaohongshuEvidenceProcessor({
    required RichTextObjectStore objectStore,
    SafeHttpClient? imageClient,
    OcrRecognizer? recognizer,
    DateTime Function()? clock,
    this.maxImagePixels = 40 * 1000 * 1000,
    this.maxImageDimension = 12000,
  })  : _objectStore = objectStore,
        _imageClient = imageClient ??
            SafeHttpClient(
              config: const SafeHttpConfig(
                maxBodyBytes: 12 * 1024 * 1024,
                allowedMimePrefixes: {
                  'image/jpeg',
                  'image/png',
                  'image/webp',
                  'image/gif',
                },
                acceptHeader:
                    'image/avif,image/webp,image/png,image/jpeg,*/*;q=0.1',
              ),
            ),
        _recognizer = recognizer ?? const MlKitChineseOcrRecognizer(),
        _clock = clock ?? DateTime.now;

  final RichTextObjectStore _objectStore;
  final SafeHttpClient _imageClient;
  final OcrRecognizer _recognizer;
  final DateTime Function() _clock;
  final int maxImagePixels;
  final int maxImageDimension;

  /// Enriches an already-previewed public-page result during explicit commit.
  /// Preview remains zero-write; only this method downloads and stores media.
  Future<IngestionResult> process(IngestionResult input) async {
    if (input.provider != 'xiaohongshu' || input.source == null) return input;
    final metadata = Map<String, dynamic>.from(input.metadata);
    final sourceMetadata = Map<String, dynamic>.from(input.source!.metadata);
    final kind = metadata['xhs_note_kind'] as String? ?? 'text';
    if (kind == 'video') {
      final evidence = {
        'kind': 'video',
        'capability': 'link_only',
        'stream_extraction': 'not_attempted',
        'source_url': input.canonicalUrl,
        'observed_at': _clock().toUtc().toIso8601String(),
        'parser_version': metadata['xhs_parser_version'],
      };
      metadata['xhs_media_evidence'] = evidence;
      sourceMetadata['xhs_media_evidence'] = evidence;
      return _copyResult(
        input,
        source: _copySource(
          input.source!,
          mediaType: SourceMediaType.video,
          metadata: sourceMetadata,
        ),
        metadata: metadata,
        hasMedia: true,
        videoCapability: VideoCapabilityLevel.linkOnly,
      );
    }

    final rawCandidates = metadata['xhs_media_candidates'];
    if (rawCandidates is! List || rawCandidates.isEmpty) return input;
    final evidence = <Map<String, dynamic>>[];
    for (final raw in rawCandidates.whereType<Map>()) {
      final url = raw['original_url'] as String?;
      final order = raw['order'] as int?;
      if (url == null || order == null) continue;
      try {
        evidence.add(
          await _processCandidate(
            url: url,
            order: order,
            parserVersion: metadata['xhs_parser_version'] as String? ??
                'xhs-public-evidence-v1',
          ),
        );
      } catch (error) {
        evidence.add({
          'original_url': url,
          'order': order,
          'status': 'failed',
          'failure': error.toString(),
          'fetched_at': _clock().toUtc().toIso8601String(),
          'parser_version': metadata['xhs_parser_version'] as String? ??
              'xhs-public-evidence-v1',
        });
      }
    }
    metadata['xhs_image_evidence'] = evidence;
    sourceMetadata['xhs_image_evidence'] = evidence;
    final stored = evidence.any((item) => item['status'] == 'stored');
    return _copyResult(
      input,
      source: _copySource(
        input.source!,
        mediaType: SourceMediaType.image,
        metadata: sourceMetadata,
      ),
      metadata: metadata,
      hasMedia: stored || input.hasMedia,
      status: input.status,
      errorMessage: input.errorMessage,
    );
  }

  Future<Map<String, dynamic>> _processCandidate({
    required String url,
    required int order,
    required String parserVersion,
  }) async {
    final fetchedAt = _clock().toUtc();
    final fetched = await _imageClient.fetchBytes(url);
    if (!fetched.success || fetched.bytes == null) {
      return {
        'original_url': url,
        'order': order,
        'status': 'rejected',
        'failure': fetched.errorMessage ?? 'empty image response',
        'fetched_at': fetchedAt.toIso8601String(),
        'parser_version': parserVersion,
      };
    }
    final bytes = fetched.bytes!;
    final mime = fetched.mimeType ?? 'application/octet-stream';
    final dimensions = ImageDimensions.tryRead(bytes, mime);
    if (dimensions == null) {
      return {
        'original_url': url,
        'final_url': fetched.finalUrl,
        'mime_type': mime,
        'order': order,
        'status': 'rejected',
        'failure': 'Image dimensions unavailable or malformed',
        'fetched_at': fetchedAt.toIso8601String(),
        'parser_version': parserVersion,
      };
    }
    if (dimensions.width > maxImageDimension ||
        dimensions.height > maxImageDimension ||
        dimensions.pixelCount > maxImagePixels) {
      return {
        'original_url': url,
        'final_url': fetched.finalUrl,
        'mime_type': mime,
        'order': order,
        'status': 'rejected',
        'failure': 'Image pixel limit exceeded',
        'width': dimensions.width,
        'height': dimensions.height,
        'fetched_at': fetchedAt.toIso8601String(),
        'parser_version': parserVersion,
      };
    }
    final ref = await _objectStore.importBytes(
      bytes,
      mimeType: mime,
      width: dimensions.width,
      height: dimensions.height,
    );
    final file = _objectStore.resolveFile(ref);
    final recognition = file == null
        ? const OcrRecognition.unavailable(
            reason: 'Stored object is not resolvable',
          )
        : await _recognizer.recognize(file.path);
    return {
      'original_url': url,
      'final_url': fetched.finalUrl,
      'object_ref': ref.objectRef,
      'sha256': sha256.convert(bytes).toString(),
      'mime_type': mime,
      'order': order,
      'status': 'stored',
      'width': dimensions.width,
      'height': dimensions.height,
      'fetched_at': fetchedAt.toIso8601String(),
      'parser_version': parserVersion,
      'ocr': {
        'status': recognition.availability.name,
        'text': recognition.text,
        if (recognition.confidence != null)
          'confidence': recognition.confidence,
        if (recognition.reason != null) 'reason': recognition.reason,
        'recognizer_version': recognition.recognizerVersion,
        'derived_from_object_ref': ref.objectRef,
      },
    };
  }
}

class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;
  int get pixelCount => width * height;

  static ImageDimensions? tryRead(Uint8List bytes, String mimeType) {
    try {
      switch (mimeType.toLowerCase().split(';').first.trim()) {
        case 'image/png':
          if (bytes.length < 24 ||
              bytes[0] != 0x89 ||
              bytes[1] != 0x50 ||
              bytes[2] != 0x4e ||
              bytes[3] != 0x47) {
            return null;
          }
          return ImageDimensions(_u32be(bytes, 16), _u32be(bytes, 20));
        case 'image/gif':
          if (bytes.length < 10) return null;
          return ImageDimensions(_u16le(bytes, 6), _u16le(bytes, 8));
        case 'image/jpeg':
          return _jpeg(bytes);
        case 'image/webp':
          return _webp(bytes);
        default:
          return null;
      }
    } on RangeError {
      return null;
    }
  }

  static ImageDimensions? _jpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
    var offset = 2;
    const sof = {
      0xc0,
      0xc1,
      0xc2,
      0xc3,
      0xc5,
      0xc6,
      0xc7,
      0xc9,
      0xca,
      0xcb,
      0xcd,
      0xce,
      0xcf,
    };
    while (offset + 8 < bytes.length) {
      if (bytes[offset] != 0xff) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (sof.contains(marker)) {
        return ImageDimensions(
          _u16be(bytes, offset + 7),
          _u16be(bytes, offset + 5),
        );
      }
      if (marker == 0xd8 || marker == 0xd9) {
        offset += 2;
        continue;
      }
      final length = _u16be(bytes, offset + 2);
      if (length < 2) return null;
      offset += length + 2;
    }
    return null;
  }

  static ImageDimensions? _webp(Uint8List bytes) {
    if (bytes.length < 30 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WEBP') {
      return null;
    }
    final type = String.fromCharCodes(bytes.sublist(12, 16));
    if (type == 'VP8X') {
      return ImageDimensions(_u24le(bytes, 24) + 1, _u24le(bytes, 27) + 1);
    }
    if (type == 'VP8 ' &&
        bytes.length >= 30 &&
        bytes[23] == 0x9d &&
        bytes[24] == 0x01 &&
        bytes[25] == 0x2a) {
      return ImageDimensions(
        _u16le(bytes, 26) & 0x3fff,
        _u16le(bytes, 28) & 0x3fff,
      );
    }
    if (type == 'VP8L' && bytes.length >= 25 && bytes[20] == 0x2f) {
      final bits =
          bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
      return ImageDimensions((bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1);
    }
    return null;
  }

  static int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static int _u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u24le(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
  static int _u32be(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
}

SourceContent _copySource(
  SourceContent source, {
  required SourceMediaType mediaType,
  required Map<String, dynamic> metadata,
}) =>
    SourceContent(
      sourceId: source.sourceId,
      mediaType: mediaType,
      title: source.title,
      ownerSpace: source.ownerSpace,
      origin: source.origin,
      provider: source.provider,
      canonicalId: source.canonicalId,
      mimeType: source.mimeType,
      currentVersionId: source.currentVersionId,
      contentHash: source.contentHash,
      objectRef: source.objectRef,
      metadata: metadata,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      deletedAt: source.deletedAt,
    );

IngestionResult _copyResult(
  IngestionResult input, {
  required SourceContent source,
  required Map<String, dynamic> metadata,
  bool? hasMedia,
  IngestionStatus? status,
  String? errorMessage,
  VideoCapabilityLevel? videoCapability,
}) =>
    IngestionResult(
      resultId: input.resultId,
      canonicalUrl: input.canonicalUrl,
      provider: input.provider,
      originalUrl: input.originalUrl,
      status: status ?? input.status,
      errorMessage: errorMessage,
      source: source,
      sourceVersion: input.sourceVersion,
      hasBody: input.hasBody,
      hasMedia: hasMedia ?? input.hasMedia,
      hasTranscript: input.hasTranscript,
      videoCapability: videoCapability ?? input.videoCapability,
      metadata: metadata,
      resolvedAt: input.resolvedAt,
    );
