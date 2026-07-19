import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:logging/logging.dart';

import 'package:memex/data/services/reading/fetchers/reading_fetcher.dart';
import 'package:memex/utils/logger.dart';

/// Generic web-page fetcher for the Reading Companion.
///
/// Falls in between the platform-specific fetchers (wechat_mp, xiaohongshu)
/// and handles arbitrary URLs the user shares — github.com README / issue /
/// PR pages, blog posts, documentation pages, news articles, etc.
///
/// Strategy:
///   1. Single GET with a desktop Chrome UA. Most public sites render server-
///      side and don't gate on JS for the main article body.
///   2. Title from <title> / og:title / twitter:title.
///   3. Body from a list of candidate selectors in priority order:
///        - GitHub-specific:  article.markdown-body, .markdown-body,
///                            #readme, .js-repo-meta, .comment-body
///                            (covers README, issue, PR, gist).
///        - Generic article:   <article>, [role="main"], main, #content,
///                            .post-content, .article-content, .entry-content.
///        - Fallback:          <body> with nav/header/footer/script/style
///                            stripped.
///   4. Author from og:article:author / meta[name=author] / twitter:creator.
///   5. Cover from og:image / twitter:image.
///   6. Inline images collected from the chosen body container (capped at 20)
///      so OCR still runs on screenshot-heavy blog posts.
///
/// Non-goals: SPA / JS-rendered content (Twitter threads, Notion public
/// pages, React/Vue SPAs without SSR). Those need a WebView fetcher and a
/// login story we don't have here. The transient cache will record such
/// URLs as `failed` and the companion falls back to discussing the link
/// metadata.
class WebFetcher implements ReadingFetcher {
  WebFetcher({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                        'AppleWebKit/537.36 (KHTML, like Gecko) '
                        'Chrome/120.0.0.0 Safari/537.36',
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
              },
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
            ));

  final Dio _dio;
  final Logger _logger = getLogger('WebFetcher');

  @override
  String get platform => 'web';

  @override
  Future<ReadingFetchResult> fetch(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data;
      if (html == null || html.isEmpty) {
        return const ReadingFetchResult.failure('Empty response body');
      }
      final doc = html_parser.parse(html);

      final title = _extractTitle(doc, url);
      final author = _extractAuthor(doc);
      final coverUrl = _extractCover(doc);
      final bodyContainer = _extractBodyContainer(doc);
      final imageUrls = _extractImages(bodyContainer);
      final contentFull = _extractText(bodyContainer);

      if ((title == null || title.isEmpty) &&
          (contentFull == null || contentFull.trim().isEmpty)) {
        return const ReadingFetchResult.failure(
          'No recognisable article content (page may be JS-rendered or gated)',
        );
      }

      return ReadingFetchResult(
        success: true,
        title: title,
        author: author,
        coverUrl: coverUrl,
        imageUrls: imageUrls,
        contentExcerpt: buildContentExcerpt(contentFull),
        contentFull: contentFull,
      );
    } on DioException catch (e) {
      _logger.warning('Web fetch network error: ${e.message}');
      return ReadingFetchResult.failure('Network error: ${e.message}');
    } catch (e, stack) {
      _logger.warning('Web fetch parse error', e, stack);
      return ReadingFetchResult.failure('Parse error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Title
  // -------------------------------------------------------------------------

  String? _extractTitle(dom.Document doc, String url) {
    // GitHub README pages put the repo name in <title> as "owner/repo"; the
    // first <h1> inside the README is the actual article title.
    final isGitHub = Uri.tryParse(url)?.host.endsWith('github.com') ?? false;
    if (isGitHub) {
      final readme = doc.querySelector('#readme');
      if (readme != null) {
        final h1 = readme.querySelector('h1')?.text.trim();
        if (h1 != null && h1.isNotEmpty) return h1;
      }
    }
    final og = _ogMeta(doc, 'og:title');
    if (og != null && og.isNotEmpty) return og;
    final twitter = _ogMeta(doc, 'twitter:title');
    if (twitter != null && twitter.isNotEmpty) return twitter;
    final docTitle = doc.querySelector('title')?.text.trim();
    if (docTitle != null && docTitle.isNotEmpty) {
      // GitHub appends " · GitHub" / " · Issue · owner/repo · GitHub" — trim
      // the suffix so the title stays readable.
      return docTitle.split(' · ').first.trim();
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Body container — candidate list, first match wins.
  // -------------------------------------------------------------------------

  static const _gitHubBodySelectors = <String>[
    'article.markdown-body',
    '.markdown-body',
    '#readme',
    '.js-repo-meta',
    '.comment-body',
    '.timeline-comment',
    '.blob-wrapper',
  ];

  static const _genericBodySelectors = <String>[
    'article',
    '[role="main"]',
    'main',
    '#content',
    '.post-content',
    '.article-content',
    '.entry-content',
    '.post-body',
    '.content',
  ];

  dom.Element? _extractBodyContainer(dom.Document doc) {
    for (final selector in _gitHubBodySelectors) {
      final el = doc.querySelector(selector);
      if (el != null) return el;
    }
    for (final selector in _genericBodySelectors) {
      final el = doc.querySelector(selector);
      if (el != null) return el;
    }
    return doc.querySelector('body');
  }

  // -------------------------------------------------------------------------
  // Text extraction
  // -------------------------------------------------------------------------

  String? _extractText(dom.Element? container) {
    if (container == null) return null;
    for (final el in container.querySelectorAll('script, style, noscript, template')) {
      el.remove();
    }
    // Preserve code blocks as fenced markdown so GitHub README code snippets
    // stay readable after extraction (otherwise they get flattened into the
    // surrounding paragraph). We only touch <pre><code> blocks since GitHub
    // uses that pair for both README fenced code and source file views.
    for (final pre in container.querySelectorAll('pre')) {
      final codeText = pre.text.trim();
      if (codeText.isEmpty) continue;
      final lang = _inferCodeLang(pre);
      final fenced = '```$lang\n$codeText\n```';
      final replacement = dom.Element.tag('div')
        ..text = fenced;
      pre.replaceWith(replacement);
    }
    final text = container.text;
    final normalised = text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalised.isEmpty) return null;
    return normalised;
  }

  /// Best-effort language tag for a <pre><code> block. GitHub annotates code
  /// blocks via `class="language-xxx"` on the inner <code>. We fall back to
  /// empty (so the fence becomes ```) when no language is detected.
  String _inferCodeLang(dom.Element pre) {
    final code = pre.querySelector('code');
    if (code != null) {
      final cls = code.attributes['class'] ?? '';
      final match = RegExp(r'language-([a-z0-9+#]+)').firstMatch(cls);
      if (match != null) return match.group(1)!;
    }
    return '';
  }

  // -------------------------------------------------------------------------
  // Images
  // -------------------------------------------------------------------------

  List<String> _extractImages(dom.Element? container) {
    if (container == null) return const [];
    final results = <String>[];
    final seen = <String>{};
    final imgs = container.querySelectorAll('img');
    for (final img in imgs) {
      final candidates = <String?>[
        img.attributes['data-src'],
        img.attributes['data-original-src'],
        img.attributes['src'],
      ];
      for (final raw in candidates) {
        if (raw == null) continue;
        final src = raw.trim();
        if (src.isEmpty || !src.startsWith('http')) continue;
        // Skip avatar / icon / tracking-pixel noise.
        if (_looksLikeAvatarOrIcon(src)) continue;
        final baseKey = src.split('?').first;
        if (seen.contains(baseKey)) break;
        seen.add(baseKey);
        results.add(src);
        break;
      }
      if (results.length >= 20) break;
    }
    return results;
  }

  bool _looksLikeAvatarOrIcon(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('/avatar') || lower.contains('avatar.github')) {
      return true;
    }
    if (lower.contains('/favicon') || lower.contains('favicon.')) {
      return true;
    }
    if (lower.contains('/icons/') || lower.contains('/icon/')) {
      return true;
    }
    // 1x1 tracking pixels.
    final widthAttr = url.toLowerCase();
    if (widthAttr.contains('width=1') || widthAttr.contains('1x1')) {
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Author + cover
  // -------------------------------------------------------------------------

  String? _extractAuthor(dom.Document doc) {
    return _ogMeta(doc, 'og:article:author') ??
        _ogMeta(doc, 'article:author') ??
        _metaName(doc, 'author') ??
        _ogMeta(doc, 'twitter:creator');
  }

  String? _extractCover(dom.Document doc) {
    return _ogMeta(doc, 'og:image') ?? _ogMeta(doc, 'twitter:image');
  }

  String? _ogMeta(dom.Document doc, String property) {
    final selector = 'meta[property="$property"], meta[name="$property"]';
    final el = doc.querySelector(selector);
    final value = el?.attributes['content']?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _metaName(dom.Document doc, String name) {
    final el = doc.querySelector('meta[name="$name"]');
    final value = el?.attributes['content']?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}