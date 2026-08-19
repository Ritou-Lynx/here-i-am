/// Link ingestor — orchestrates URL canonicalization, safe HTTP fetch,
/// HTML parsing, and [IngestionResult] production.
///
/// This is the core of W3. The ingestor:
///   1. Canonicalizes the input URL;
///   2. Fetches it safely (SSRF checks, redirects, MIME validation);
///   3. Parses the HTML for metadata + body;
///   4. Produces an [IngestionResult] with SourceContent + SourceVersion.
///
/// The ingestor does NOT create Cards or write to User-truth — that's the
/// application layer's job ([LinkIngestionService]).
library;

import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:memex/data/whiteboard/ingestion/html_page_parser.dart';
import 'package:memex/data/whiteboard/ingestion/safe_http_client.dart';
import 'package:memex/data/whiteboard/ingestion/url_canonicalizer.dart';
import 'package:memex/domain/whiteboard/ingestion_result.dart';
import 'package:memex/domain/whiteboard/source_content.dart';
import 'package:memex/domain/whiteboard/whiteboard_ids.dart';

/// Orchestrates link ingestion into [IngestionResult].
class LinkIngestor {
  LinkIngestor({SafeHttpClient? httpClient})
      : _httpClient = httpClient ?? SafeHttpClient();

  final SafeHttpClient _httpClient;

  /// Ingests [rawUrl] and returns an [IngestionResult].
  ///
  /// Never throws — failures are represented as [IngestionStatus.failed] /
  /// [IngestionStatus.unsupported] with [errorMessage].
  Future<IngestionResult> ingest(String rawUrl) async {
    final resolvedAt = DateTime.now().toUtc();

    // 1. Canonicalize.
    final canonical = canonicalizeUrl(rawUrl);
    if (canonical == null) {
      return IngestionResult(
        canonicalUrl: rawUrl,
        status: IngestionStatus.failed,
        errorMessage: 'Invalid or non-http(s) URL',
        resolvedAt: resolvedAt,
      );
    }

    // YouTube is a URL-native W4 source: previewing it needs no fetch and no
    // persistence. The exact IngestionResult is committed only after the user
    // confirms in /import, preserving the F3 unified Card identity.
    if (canonical.provider == 'youtube') {
      return _youtubePreview(canonical, resolvedAt);
    }

    // Bilibili remains link-only because there is no stable public control
    // API. Do not pretend ordinary HTML ingestion makes it study-capable.
    if (canonical.provider == 'bilibili') {
      return IngestionResult(
        canonicalUrl: canonical.normalized,
        provider: canonical.provider,
        originalUrl: canonical.original,
        status: IngestionStatus.unsupported,
        errorMessage: '视频平台链接（${canonical.provider}）由研读模块处理，'
            '普通链接抓取不支持',
        resolvedAt: resolvedAt,
      );
    }

    // 2. Fetch safely.
    final httpResult = await _httpClient.fetch(canonical.normalized);
    if (!httpResult.success) {
      return IngestionResult(
        canonicalUrl: canonical.normalized,
        provider: canonical.provider,
        originalUrl: canonical.original,
        status: httpResult.authRequired
            ? IngestionStatus.needsAuth
            : IngestionStatus.failed,
        errorMessage: httpResult.errorMessage,
        resolvedAt: resolvedAt,
      );
    }

    // 3. Determine final canonical URL after redirects.
    final finalUrl = httpResult.finalUrl ?? canonical.normalized;
    final finalCanonical = canonicalizeUrl(finalUrl) ?? canonical;

    // 4. Parse HTML.
    final html = httpResult.body ?? '';
    final parsed = parseHtmlPage(html, sourceUrl: finalUrl);

    if (parsed.isEmpty) {
      return IngestionResult(
        canonicalUrl: finalCanonical.normalized,
        provider: finalCanonical.provider,
        originalUrl: canonical.original,
        status: IngestionStatus.failed,
        errorMessage:
            'No recognisable content (page may be JS-rendered or gated)',
        resolvedAt: resolvedAt,
      );
    }

    // 5. Build SourceContent + SourceVersion.
    final sourceId = _deriveSourceId(finalCanonical);
    final contentHash = _computeContentHash(html, parsed);
    final versionId = _deriveVersionId(sourceId, contentHash);
    final objectRef = 'ingestion/$sourceId/$versionId.html';

    final source = SourceContent(
      sourceId: sourceId,
      mediaType: SourceMediaType.web,
      title: parsed.title ?? finalCanonical.host,
      ownerSpace: OwnerSpace.user,
      origin: SourceOrigin.externalLink,
      provider: finalCanonical.provider,
      canonicalId: finalCanonical.canonicalId,
      mimeType: httpResult.mimeType,
      currentVersionId: versionId,
      contentHash: contentHash,
      objectRef: objectRef,
      metadata: {
        if (parsed.description != null) 'description': parsed.description,
        if (parsed.ogImage != null) 'og_image': parsed.ogImage,
        if (parsed.siteName != null) 'site_name': parsed.siteName,
        if (parsed.author != null) 'author': parsed.author,
        'canonical_url': finalCanonical.normalized,
        'original_url': canonical.original,
        if (parsed.imageUrls.isNotEmpty) 'images': parsed.imageUrls,
      },
      createdAt: resolvedAt,
      updatedAt: resolvedAt,
    );

    final sourceVersion = SourceVersion(
      versionId: versionId,
      sourceId: sourceId,
      contentHash: contentHash,
      objectRef: objectRef,
      parserVersion: ParsedPageContent.parserVersion,
      createdAt: resolvedAt,
    );

    return IngestionResult(
      resultId: StableId.generate('ingest').value,
      canonicalUrl: finalCanonical.normalized,
      provider: finalCanonical.provider,
      originalUrl: canonical.original,
      status: IngestionStatus.ok,
      source: source,
      sourceVersion: sourceVersion.toJson(),
      hasBody: parsed.bodyText != null && parsed.bodyText!.isNotEmpty,
      hasMedia: parsed.imageUrls.isNotEmpty || parsed.ogImage != null,
      metadata: {
        if (parsed.title != null) 'title': parsed.title,
        if (parsed.description != null) 'description': parsed.description,
        if (parsed.ogImage != null) 'og_image': parsed.ogImage,
        if (parsed.bodyText != null) 'body_text': parsed.bodyText,
        if (parsed.bodyExcerpt != null) 'body_excerpt': parsed.bodyExcerpt,
        if (parsed.imageUrls.isNotEmpty) 'image_urls': parsed.imageUrls,
        'http_status': httpResult.statusCode,
        'mime_type': httpResult.mimeType,
      },
      resolvedAt: resolvedAt,
    );
  }

  IngestionResult _youtubePreview(
    CanonicalUrl canonical,
    DateTime resolvedAt,
  ) {
    final videoId = canonical.canonicalId;
    if (videoId == null) {
      return IngestionResult(
        canonicalUrl: canonical.normalized,
        provider: canonical.provider,
        originalUrl: canonical.original,
        status: IngestionStatus.unsupported,
        errorMessage: '无法从这个 YouTube 链接识别 video id',
        resolvedAt: resolvedAt,
      );
    }
    final sourceId = _deriveSourceId(canonical);
    final contentHash = sha256
        .convert(utf8.encode('youtube\n$videoId\n${canonical.normalized}'))
        .toString()
        .substring(0, 32);
    final versionId = _deriveVersionId(sourceId, contentHash);
    final objectRef = 'ingestion/$sourceId/$versionId.json';
    final embedUrl = 'https://www.youtube.com/watch?v=$videoId';
    final source = SourceContent(
      sourceId: sourceId,
      mediaType: SourceMediaType.video,
      title: 'YouTube 视频 · $videoId',
      ownerSpace: OwnerSpace.user,
      origin: SourceOrigin.externalLink,
      provider: 'youtube',
      canonicalId: videoId,
      mimeType: 'text/uri-list',
      currentVersionId: versionId,
      contentHash: contentHash,
      objectRef: objectRef,
      metadata: {
        'canonical_url': embedUrl,
        'original_url': canonical.original,
        'embed_url': embedUrl,
        'provider': 'youtube',
        'video_id': videoId,
      },
      createdAt: resolvedAt,
      updatedAt: resolvedAt,
    );
    final sourceVersion = SourceVersion(
      versionId: versionId,
      sourceId: sourceId,
      contentHash: contentHash,
      objectRef: objectRef,
      parserVersion: 'w4-youtube-url-v1',
      createdAt: resolvedAt,
    );
    return IngestionResult(
      resultId: StableId.generate('ingest').value,
      canonicalUrl: embedUrl,
      provider: 'youtube',
      originalUrl: canonical.original,
      status: IngestionStatus.ok,
      source: source,
      sourceVersion: sourceVersion.toJson(),
      hasMedia: true,
      videoCapability: VideoCapabilityLevel.playbackStudy,
      metadata: {
        'title': source.title,
        'provider': 'youtube',
        'video_id': videoId,
        'embed_url': embedUrl,
      },
      resolvedAt: resolvedAt,
    );
  }

  /// Derives a stable source_id from the canonical URL.
  ///
  /// For provider URLs with a canonical_id, uses `provider:canonicalId`.
  /// For generic web, uses a hash of the normalized URL.
  String _deriveSourceId(CanonicalUrl canonical) {
    if (canonical.canonicalId != null) {
      return 'src_${canonical.provider}_${canonical.canonicalId}';
    }
    final hash = sha256
        .convert(utf8.encode(canonical.normalized))
        .toString()
        .substring(0, 16);
    return 'src_web_$hash';
  }

  String _computeContentHash(String html, ParsedPageContent parsed) {
    final basis = <String>[
      parsed.title ?? '',
      parsed.bodyText ?? '',
      parsed.ogImage ?? '',
    ].join('\n');
    return sha256.convert(utf8.encode(basis)).toString().substring(0, 32);
  }

  String _deriveVersionId(String sourceId, String contentHash) {
    return '${sourceId.replaceAll('src_', 'ver_')}_$contentHash';
  }
}
