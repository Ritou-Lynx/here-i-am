import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:logging/logging.dart';

import 'package:memex/data/services/reading/fetchers/reading_fetcher.dart';
import 'package:memex/utils/logger.dart';

/// HTML fetcher for 微信公众号 articles (mp.weixin.qq.com/s/*).
///
/// 公众号 articles are server-rendered and publicly accessible — no login
/// required, no JS execution needed. A single GET + DOM scrape is enough.
///
/// UA / Referer notes:
/// - We deliberately do NOT pretend to be MicroMessenger. The server cross-
///   checks UA against Referer; a MicroMessenger UA paired with an empty /
///   external Referer trips its "not actually opened from WeChat" gate and
///   serves a "请在微信客户端打开本链接" interstitial instead of the article.
/// - A vanilla desktop Chrome UA + Referer of mp.weixin.qq.com behaves like
///   "user opened this in their browser", which is allowed for public posts.
/// - Falls back to og:* meta tags if structured selectors miss (some
///   articles have inconsistent classnames across the platform's history).
class WechatMpFetcher implements ReadingFetcher {
  WechatMpFetcher({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                        'AppleWebKit/537.36 (KHTML, like Gecko) '
                        'Chrome/120.0.0.0 Safari/537.36',
                'Referer': 'https://mp.weixin.qq.com/',
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
              },
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
            ));

  final Dio _dio;
  final Logger _logger = getLogger('WechatMpFetcher');

  @override
  String get platform => 'wechat_mp';

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

      // Interstitial / gating pages return 200 OK with a known body — detect
      // before parsing so we can give the user a precise reason instead of
      // a generic "no content".
      final interstitial = _detectInterstitial(html);
      if (interstitial != null) {
        return ReadingFetchResult.failure(interstitial);
      }

      final doc = html_parser.parse(html);

      // 公众号文章 metadata — primary selectors with og: fallbacks.
      final title = _extractTitle(doc);
      final author = _extractAuthor(doc);
      final coverUrl = _extractCover(doc);
      final imageUrls = _extractAllImages(doc);
      final contentFull = _extractContent(doc);

      // If we couldn't extract a meaningful title AND no body, treat as
      // failed — the page is probably a not-yet-known interstitial format.
      if ((title == null || title.isEmpty) &&
          (contentFull == null || contentFull.trim().isEmpty)) {
        return const ReadingFetchResult.failure(
          'No recognisable article content (page format may have changed)',
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
      _logger.warning('Wechat MP fetch network error: ${e.message}');
      return ReadingFetchResult.failure('Network error: ${e.message}');
    } catch (e, stack) {
      _logger.warning('Wechat MP fetch parse error', e, stack);
      return ReadingFetchResult.failure('Parse error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Interstitial detection. Common gating pages the server returns instead
  // of the article body, in plain Chinese — substring match is sufficient
  // because the wording is stable across years.
  // -------------------------------------------------------------------------

  /// Returns a human-readable reason if the response is a known
  /// non-article page, null if it looks like article HTML.
  String? _detectInterstitial(String html) {
    if (html.contains('请在微信客户端打开链接') ||
        html.contains('请在微信客户端打开本链接') ||
        html.contains('请在微信里打开')) {
      return '需要在微信里打开（公众号反爬拦截）';
    }
    if (html.contains('该内容已被发布者删除') ||
        html.contains('此内容因违规无法查看') ||
        html.contains('此内容发送失败无法查看')) {
      return '文章已被删除或下架';
    }
    if (html.contains('该公众号已迁移') ||
        html.contains('该公众号已注销')) {
      return '公众号已注销';
    }
    if (html.contains('环境异常') && html.contains('完成验证')) {
      return '触发了微信的安全验证（环境异常）';
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Extractors. Selectors are best-effort: the platform changes class names
  // periodically, so we always have an og:* meta-tag fallback.
  // -------------------------------------------------------------------------

  String? _extractTitle(dom.Document doc) {
    final byId = doc.querySelector('#activity-name')?.text.trim();
    if (byId != null && byId.isNotEmpty) return byId;
    final byClass = doc.querySelector('.rich_media_title')?.text.trim();
    if (byClass != null && byClass.isNotEmpty) return byClass;
    return _ogMeta(doc, 'og:title');
  }

  String? _extractAuthor(dom.Document doc) {
    // The byline node is `#js_name` (公众号 name) or the
    // `.rich_media_meta_nickname` text. Either one is fine for our purposes.
    final byJs = doc.querySelector('#js_name')?.text.trim();
    if (byJs != null && byJs.isNotEmpty) return byJs;
    final byClass =
        doc.querySelector('.rich_media_meta_nickname')?.text.trim();
    if (byClass != null && byClass.isNotEmpty) return byClass;
    return _ogMeta(doc, 'og:article:author') ?? _ogMeta(doc, 'twitter:creator');
  }

  String? _extractCover(dom.Document doc) {
    final og = _ogMeta(doc, 'og:image');
    if (og != null && og.isNotEmpty) return og;
    // 公众号 articles often inline cover via `msg_cdn_url` data-attribute
    // on the first `<img>` of #js_content. Best-effort, may be null.
    final firstImg = doc.querySelector('#js_content img');
    final dataSrc = firstImg?.attributes['data-src'];
    if (dataSrc != null && dataSrc.isNotEmpty) return dataSrc;
    return firstImg?.attributes['src'];
  }

  /// Collects every <img> inside #js_content in document order, deduped,
  /// capped at 20 to keep the OCR pipeline bounded. Returns absolute
  /// URLs only (skips data: URIs and empty srcs).
  List<String> _extractAllImages(dom.Document doc) {
    final results = <String>[];
    final seen = <String>{};
    final imgs = doc.querySelectorAll('#js_content img');
    for (final img in imgs) {
      final candidates = <String?>[
        img.attributes['data-src'],
        img.attributes['src'],
        img.attributes['data-original'],
      ];
      for (final raw in candidates) {
        if (raw == null) continue;
        final src = raw.trim();
        if (src.isEmpty || !src.startsWith('http')) continue;
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

  String? _extractContent(dom.Document doc) {
    final content = doc.querySelector('#js_content');
    if (content == null) return null;
    // Strip script / style nodes that the parser may have left in.
    for (final el in content.querySelectorAll('script, style')) {
      el.remove();
    }
    final text = content.text;
    // Collapse multi-line whitespace runs into single newlines so the
    // excerpt isn't dominated by HTML indentation. Preserve paragraph
    // breaks (double newline) where possible.
    final normalised = text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalised.isEmpty) return null;
    return normalised;
  }

  String? _ogMeta(dom.Document doc, String property) {
    final selector = 'meta[property="$property"], meta[name="$property"]';
    final el = doc.querySelector(selector);
    final value = el?.attributes['content']?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
