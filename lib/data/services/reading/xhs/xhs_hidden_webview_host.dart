import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:memex/data/services/reading/xhs/xhs_cookie_repository.dart';
import 'package:memex/utils/logger.dart';

/// Result of running the in-page extractor on a 小红书 note page.
class XhsRawContent {
  const XhsRawContent({
    required this.success,
    this.title,
    this.author,
    this.coverUrl,
    this.imageUrls = const [],
    this.contentFull,
    this.errorMessage,
  });

  const XhsRawContent.failure(String message)
      : success = false,
        title = null,
        author = null,
        coverUrl = null,
        imageUrls = const [],
        contentFull = null,
        errorMessage = message;

  final bool success;
  final String? title;
  final String? author;
  final String? coverUrl;

  /// All note images in document order (deduplicated). May overlap with
  /// [coverUrl]. Empty when the note is text-only.
  final List<String> imageUrls;

  final String? contentFull;
  final String? errorMessage;
}

class _XhsFetchRequest {
  _XhsFetchRequest(this.url) : completer = Completer<XhsRawContent>();
  final String url;
  final Completer<XhsRawContent> completer;
}

/// Globally-accessible off-screen WebView for the 小红书 fetch pipeline.
///
/// The widget is mounted once near the root of the app (inside MaterialApp
/// builder's Stack) at 1×1 pixels off-screen — the platform view is
/// created and lives across navigation, so `WebViewController` can navigate
/// + run JS at any time. webview_flutter 4.x doesn't ship a headless
/// mode; this is the next-best thing on top of stock dependencies.
///
/// Fetch requests are queued through the static [fetch] entry point;
/// the host processes them one at a time (the 小红书 anti-bot is more
/// forgiving with sequential navigation than with parallel hits anyway).
///
/// Login state is observed by running a tiny `document.cookie` probe on
/// the xiaohongshu.com origin and pushing the result into
/// [XhsCookieRepository].
class XhsHiddenWebViewHost extends StatefulWidget {
  const XhsHiddenWebViewHost({super.key});

  static final StreamController<_XhsFetchRequest> _requestStream =
      StreamController<_XhsFetchRequest>.broadcast();

  /// Public entry point — XhsWebViewFetcher calls this. Returns a Future
  /// that completes when the hidden host processes this URL.
  static Future<XhsRawContent> fetch(String url) {
    final req = _XhsFetchRequest(url);
    _requestStream.add(req);
    // Hard timeout in case the host widget is never mounted (e.g. running
    // in a non-app context like background isolate) — we don't want
    // callers to await forever.
    return req.completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => const XhsRawContent.failure(
        'Fetch timed out (hidden WebView host not responding)',
      ),
    );
  }

  /// Triggers a probe of the current session cookie. Used at startup and
  /// after the login page closes.
  static final StreamController<void> _probeStream =
      StreamController<void>.broadcast();

  static void probeLoginState() {
    _probeStream.add(null);
  }

  @override
  State<XhsHiddenWebViewHost> createState() => _XhsHiddenWebViewHostState();
}

class _XhsHiddenWebViewHostState extends State<XhsHiddenWebViewHost> {
  // Match XhsConnectPage's desktop UA so the session cookie minted at
  // login time is recognised here. (Mobile UA would land on the
  // download-the-App shell where login controls don't even exist.)
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  /// JS snippet that:
  ///   1. Hides the webview footprint (navigator.webdriver etc.)
  ///   2. Reads note title / author / cover / body from the DOM
  ///   3. Posts the result back to Dart via the `XhsBridge` channel
  ///
  /// 小红书 keeps adding selector variants — we walk multiple candidates
  /// before giving up.
  static const _extractScript = r'''
(function() {
  function pickText(selectors) {
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el && el.textContent && el.textContent.trim().length > 0) {
        return el.textContent.trim();
      }
    }
    return null;
  }
  function pickAttr(selectors, attr) {
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el) {
        const v = el.getAttribute(attr);
        if (v && v.trim().length > 0) return v.trim();
      }
    }
    return null;
  }
  // Collect every image URL on the note page. XHS uses three patterns:
  //   (a) <img src> / data-src (rare on detail pages)
  //   (b) lazy-load attrs on <img> like data-xhs-img / data-original-src
  //   (c) CSS background-image on divs inside the swiper carousel
  // We try all three. Returns { urls, debug } so failures are diagnosable
  // from LogViewer instead of being silent.
  function collectImageUrls() {
    const urls = [];
    const seen = new Set();
    const debug = { candidates: 0, skipped_non_http: 0,
                    skipped_avatar: 0, skipped_icon: 0,
                    skipped_dup: 0, by_source: {},
                    total_img: 0, total_bg_scanned: 0,
                    total_html_matches: 0 };
    function consider(src, source) {
      debug.candidates++;
      if (!src || typeof src !== 'string') {
        debug.skipped_non_http++; return;
      }
      src = src.trim();
      if (!src.startsWith('http')) { debug.skipped_non_http++; return; }
      // Avatars / emoji / sprite-style icons.
      if (src.includes('/avatar/') || src.includes('avatar.xiaohongshu')) {
        debug.skipped_avatar++; return;
      }
      if (src.includes('/emoji/') || src.includes('/sprite/') ||
          src.includes('/icon/') || src.includes('/pinyin')) {
        debug.skipped_icon++; return;
      }
      const baseKey = src.split('?')[0];
      if (seen.has(baseKey)) { debug.skipped_dup++; return; }
      seen.add(baseKey);
      urls.push(src);
      debug.by_source[source] = (debug.by_source[source] || 0) + 1;
    }
    // Pass A: every <img>'s src + ALL its data-* attributes (covers
    // lazy-load patterns where the real CDN URL is hidden in a custom
    // attribute like data-original-src or data-xhs-img).
    const allImgs = document.querySelectorAll('img');
    debug.total_img = allImgs.length;
    allImgs.forEach(img => {
      consider(img.getAttribute('src'), 'img.src');
      for (const attr of img.attributes) {
        const name = attr.name;
        if (!name.startsWith('data-')) continue;
        consider(attr.value, 'img.' + name);
      }
    });
    // Pass B: background-image CSS inside likely note containers.
    const containerSelectors = [
      '[class*="swiper"]',
      '[class*="carousel"]',
      '[class*="note"]',
      '[class*="image"]',
      '[class*="picture"]',
      '[class*="media"]',
    ];
    const containers = new Set();
    for (const sel of containerSelectors) {
      document.querySelectorAll(sel).forEach(el => containers.add(el));
    }
    containers.forEach(container => {
      container.querySelectorAll('*').forEach(el => {
        debug.total_bg_scanned++;
        try {
          const bg = window.getComputedStyle(el).backgroundImage;
          if (!bg || bg === 'none') return;
          const m = bg.match(/url\(["']?(https?:\/\/[^"'\)]+)["']?\)/);
          if (m) consider(m[1], 'bg');
        } catch (_) {}
      });
    });
    // Pass C: scan the page's outerHTML for XHS image CDN URLs. Swiper
    // carousels lazy-render slides, so the DOM only contains the current
    // visible image — but React typically embeds the full URL list in the
    // initial server-rendered state inside script tags or props. Regex
    // over the whole HTML catches them even when they aren't in any
    // rendered element.
    try {
      const html = document.documentElement.outerHTML;
      const pattern = /https?:\/\/(?:sns-webpic[^"'\\\s)<>]+|sns-img[^"'\\\s)<>]+|ci\.xiaohongshu\.com[^"'\\\s)<>]+|picasso-static\.xiaohongshu\.com[^"'\\\s)<>]+|xhscdn\.com[^"'\\\s)<>]+)/g;
      const matches = html.match(pattern) || [];
      debug.total_html_matches = matches.length;
      for (const url of matches) {
        // Strip JSON-escaped trailing characters that occasionally leak
        // through the regex (e.g. \").
        const cleaned = url.replace(/\\+$/, '');
        consider(cleaned, 'html');
      }
    } catch (_) {}
    return { urls: urls.slice(0, 12), debug };
  }
  // Wait for the note container — the page is React-rendered, so the
  // body may not be ready when onPageFinished fires.
  function tryExtract() {
    const title = pickText([
      '#detail-title',
      'div.note-content .title',
      'meta[property="og:title"]',
    ]) || pickAttr(['meta[property="og:title"]'], 'content');
    const author = pickText([
      'div.author-wrapper .username',
      'a.user-link .username',
      '.author-container .name',
    ]);
    const cover = pickAttr([
      'meta[property="og:image"]',
      'meta[name="twitter:image"]',
    ], 'content') || pickAttr(
      ['div.swiper-slide img', 'div.note-content img'],
      'src',
    );
    const imageResult = collectImageUrls();
    // Note body: prefer the explicit detail-desc container; fall back to
    // the desc paragraphs and finally to a generic note-content scrape.
    const body = pickText([
      '#detail-desc',
      'div.desc',
      'div.note-content .content',
    ]);
    return {
      title, author, cover, body,
      images: imageResult.urls,
      imagesDebug: imageResult.debug,
    };
  }
  const initial = tryExtract();
  if (initial.title || initial.body) {
    XhsBridge.postMessage(JSON.stringify({ ok: true, data: initial }));
    return;
  }
  // Otherwise retry up to 6 times at 400ms intervals.
  let attempts = 0;
  const t = setInterval(() => {
    attempts++;
    const got = tryExtract();
    if (got.title || got.body) {
      clearInterval(t);
      XhsBridge.postMessage(JSON.stringify({ ok: true, data: got }));
      return;
    }
    if (attempts >= 6) {
      clearInterval(t);
      XhsBridge.postMessage(JSON.stringify({
        ok: false,
        error: 'no_content_after_retries',
      }));
    }
  }, 400);
})();
''';

  /// Anti-bot stub: removes the most obvious "this is a webview" tells
  /// before the page's own JS runs. Injected on every navigation start.
  static const _stealthScript = r'''
Object.defineProperty(navigator, 'webdriver', { get: () => false });
window.chrome = window.chrome || { runtime: {} };
''';

  late final WebViewController _controller;
  late final StreamSubscription<_XhsFetchRequest> _requestSub;
  late final StreamSubscription<void> _probeSub;
  final Logger _logger = getLogger('XhsHiddenWebViewHost');

  Completer<XhsRawContent>? _activeRequest;
  bool _isProbing = false;
  final List<_XhsFetchRequest> _queue = [];

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUserAgent)
      ..addJavaScriptChannel(
        'XhsBridge',
        onMessageReceived: _onBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Block deep-link schemes the note page tries to trigger
            // (xhsdiscover://, intent://). Otherwise the WebView surfaces
            // ERR_UNKNOWN_URL_SCHEME which we then read as a fetch failure.
            final url = request.url;
            if (!url.startsWith('http://') &&
                !url.startsWith('https://')) {
              _logger.fine('Blocked non-http navigation: $url');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) async {
            await _controller.runJavaScript(_stealthScript);
          },
          onPageFinished: (_) async {
            if (_isProbing) {
              await _runCookieProbe();
            } else if (_activeRequest != null) {
              await _controller.runJavaScript(_extractScript);
            }
          },
          onWebResourceError: (err) {
            _logger.warning(
                'WebView resource error: ${err.description} (${err.errorType})');
            _completeActiveWithFailure(
                'WebView error: ${err.description}');
          },
        ),
      );

    _requestSub = XhsHiddenWebViewHost._requestStream.stream.listen((req) {
      _queue.add(req);
      _drainQueue();
    });
    _probeSub = XhsHiddenWebViewHost._probeStream.stream.listen((_) {
      _scheduleProbe();
    });

    // Kick off an initial probe so we know the login state right after
    // app boot.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleProbe());
  }

  @override
  void dispose() {
    _requestSub.cancel();
    _probeSub.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Queue / state machine
  // ---------------------------------------------------------------------

  Future<void> _drainQueue() async {
    if (_activeRequest != null) return;
    if (_isProbing) return;
    if (_queue.isEmpty) return;
    final req = _queue.removeAt(0);
    _activeRequest = req.completer;
    try {
      _logger.info('XHS hidden fetch: ${req.url}');
      await _controller.loadRequest(Uri.parse(req.url));
      // Safety timeout — if extract never fires (page redirected to login
      // wall, infinite loader, etc.), fail loudly so the queue moves on.
      Future.delayed(const Duration(seconds: 12), () {
        if (_activeRequest == req.completer && !req.completer.isCompleted) {
          _completeActiveWithFailure('Extract timed out');
        }
      });
    } catch (e) {
      _completeActiveWithFailure('loadRequest failed: $e');
    }
  }

  void _completeActiveWithFailure(String message) {
    final active = _activeRequest;
    _activeRequest = null;
    if (active != null && !active.isCompleted) {
      active.complete(XhsRawContent.failure(message));
    }
    _drainQueue();
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    final active = _activeRequest;
    if (active == null) {
      // Likely a stray probe response — ignore.
      return;
    }
    try {
      final payload = jsonDecode(message.message);
      if (payload is! Map) {
        _completeActiveWithFailure('Bridge payload not an object');
        return;
      }
      final ok = payload['ok'] == true;
      if (!ok) {
        _completeActiveWithFailure(
            'Extractor returned no content: ${payload['error']}');
        return;
      }
      final data = payload['data'];
      if (data is! Map) {
        _completeActiveWithFailure('Bridge data missing');
        return;
      }
      final rawImages = data['images'];
      final imageUrls = <String>[
        if (rawImages is List)
          ...rawImages.whereType<String>().where((s) => s.isNotEmpty),
      ];
      // Always log image extractor stats so we can see (in LogViewer)
      // whether the JS scraper actually found pictures and why not when
      // it doesn't.
      final imagesDebug = data['imagesDebug'];
      _logger.info(
          'XHS extracted: title=${(data['title'] as String?)?.length ?? 0}c '
          'body=${(data['body'] as String?)?.length ?? 0}c '
          'images=${imageUrls.length} debug=$imagesDebug');
      final content = XhsRawContent(
        success: true,
        title: (data['title'] as String?)?.trim(),
        author: (data['author'] as String?)?.trim(),
        coverUrl: (data['cover'] as String?)?.trim(),
        imageUrls: imageUrls,
        contentFull: (data['body'] as String?)?.trim(),
      );
      _activeRequest = null;
      if (!active.isCompleted) active.complete(content);
      _drainQueue();
    } catch (e) {
      _completeActiveWithFailure('Bridge parse failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Login probe — loads xiaohongshu.com once and reads document.cookie
  // ---------------------------------------------------------------------

  void _scheduleProbe() {
    if (_isProbing) return;
    if (_activeRequest != null) return;
    _isProbing = true;
    _controller
        .loadRequest(Uri.parse('https://www.xiaohongshu.com/'))
        .catchError((e) {
      _logger.warning('Probe loadRequest failed: $e');
      _isProbing = false;
      _drainQueue();
    });
  }

  Future<void> _runCookieProbe() async {
    try {
      final result = await _controller
          .runJavaScriptReturningResult('document.cookie');
      // result comes back as a JSON-encoded string on Android.
      String raw = result.toString();
      // Strip surrounding quotes if present.
      if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
        raw = raw.substring(1, raw.length - 1).replaceAll(r'\"', '"');
      }
      _logger.fine('Cookie probe: ${raw.length} chars');

      // Soft heuristic: post-login cookie string is much longer due to
      // server-set tokens (webId, gid, etc). XHS marks `web_session`
      // HttpOnly so we can never see it from JS — its absence is NOT
      // evidence of being logged out, so this probe only ever upgrades
      // false→true. Disconnect must go through XhsCookieRepository.clear()
      // (driven by the user tapping "disconnect" in settings).
      final alreadyConnected =
          XhsCookieRepository.instance.isLoggedIn.value;
      if (!alreadyConnected && raw.length > 350) {
        _logger.info('Probe detected logged-in cookie state.');
        XhsCookieRepository.instance
            .recordSessionCookie('<probe-detected>');
      }
    } catch (e) {
      _logger.fine('Cookie probe failed (likely first run): $e');
    } finally {
      _isProbing = false;
      _drainQueue();
    }
  }

  // ---------------------------------------------------------------------
  // Build: a 1×1 widget tucked under everything else.
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Opacity(
        opacity: 0,
        child: SizedBox(
          width: 1,
          height: 1,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
