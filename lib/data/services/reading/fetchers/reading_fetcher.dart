/// Abstract interface for platform-specific article content fetchers.
///
/// One implementation per content platform. Implementations live in
/// sibling files (wechat_mp_fetcher.dart, xiaohongshu_fetcher.dart,
/// web_fetcher.dart). The fetch coordinator picks the right one based on
/// the reading_item's platform field.
///
/// Fetchers MUST be:
/// - Non-throwing at the public surface — return a failed
///   `ReadingFetchResult` instead of propagating exceptions, so the
///   coordinator can record fetch_status without crashing the background
///   isolate that triggered it.
/// - Side-effect free: don't touch DB / file system. Persistence is the
///   coordinator's job. This keeps fetchers easy to unit-test.
library;

/// Outcome of a single fetch attempt.
class ReadingFetchResult {
  const ReadingFetchResult({
    required this.success,
    this.title,
    this.author,
    this.coverUrl,
    this.imageUrls = const [],
    this.contentExcerpt,
    this.contentFull,
    this.errorMessage,
  });

  /// Convenience constructor for failed attempts. `errorMessage` is for
  /// debugging only; user-facing copy is rendered downstream.
  const ReadingFetchResult.failure(String message)
      : success = false,
        title = null,
        author = null,
        coverUrl = null,
        imageUrls = const [],
        contentExcerpt = null,
        contentFull = null,
        errorMessage = message;

  final bool success;

  /// Refined title (may be different / fuller than the placeholder title
  /// extracted from share text). Null if the fetcher couldn't improve on
  /// the placeholder.
  final String? title;

  /// Article author / public account name / 小红书 user nickname.
  final String? author;

  /// Cover image URL (full http(s) URL, suitable to drop into
  /// `Image.network`).
  final String? coverUrl;

  /// All article images in document order (deduplicated). The cover URL
  /// is also included as the first entry if it was found in the page —
  /// downstream consumers should expect overlap between [coverUrl] and
  /// [imageUrls.first]. May be empty for text-only articles.
  ///
  /// The coordinator downloads these and runs on-device OCR against each,
  /// appending the recognised text to the article body file so the
  /// agent can discuss image content during chat (Reading Companion's
  /// 小红书 use case is heavy on screenshot-style 图文 notes).
  final List<String> imageUrls;

  /// First ~500 chars of plain text body. Persisted into the entity's
  /// stateJson so `queryRelevantEntities` haystack can match content
  /// keywords, not just title.
  final String? contentExcerpt;

  /// Full plain-text article body. Saved to disk by the coordinator
  /// (entity stateJson only stores the file path) to avoid bloating the
  /// SharedLifeEntities table.
  final String? contentFull;

  /// Diagnostic message for failed fetches. Never null when success is false.
  final String? errorMessage;
}

/// Platform-specific fetcher contract.
abstract class ReadingFetcher {
  /// Identifier matching ReadingShareParseResult.platform.
  String get platform;

  /// Fetch the article from [url]. Implementations choose the appropriate
  /// transport (Dio HTML for static pages, hidden WebView for JS-rendered
  /// pages requiring login).
  ///
  /// MUST NOT throw — return `ReadingFetchResult.failure(...)` instead.
  Future<ReadingFetchResult> fetch(String url);
}

/// Trims a string to [maxChars]. Used by fetchers to produce the
/// stateJson-friendly excerpt without each one re-implementing trimming.
String? buildContentExcerpt(String? plainText, {int maxChars = 500}) {
  if (plainText == null) return null;
  final trimmed = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length <= maxChars) return trimmed;
  return '${trimmed.substring(0, maxChars)}…';
}

/// Picks a fetcher for the platform inferred by the parser. Concrete
/// dispatch lives in the coordinator (which holds the wired fetcher
/// instances); this is just a type alias for clarity downstream.
typedef ReadingFetcherResolver = ReadingFetcher? Function(String platform);

/// Platform identifiers — must match ReadingShareParseResult.platform.
const String xhsPlatformId = 'xiaohongshu';
const String wechatMpPlatformId = 'wechat_mp';
const String webPlatformId = 'web';
