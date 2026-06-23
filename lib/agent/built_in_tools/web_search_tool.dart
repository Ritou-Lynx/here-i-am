import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';

/// Build a general-purpose web search tool for the companion agent.
///
/// Uses Bing (cn.bing.com) as the primary provider — accessible in China.
/// Falls back to DuckDuckGo's Instant Answer API and HTML endpoints, which
/// may be unreachable depending on network conditions.
Tool buildWebSearchTool() {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/json',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    },
  ));

  return Tool(
    name: 'web_search',
    description: '''Search the web for current, real-world information.

Use this when:
- The user asks about recent events, news, or facts you are unsure about
- You need up-to-date information beyond your training cutoff
- The question requires information that changes frequently (weather, prices, etc.)

Returns an array of search results, each with:
- title: the page title
- url: the link to the full page
- snippet: a short excerpt matching the query

Tips:
- Be specific with your query — 2–5 keywords works best
- For Chinese queries, use Chinese search terms
- After getting results, synthesize a natural reply in your own words
- Cite the most relevant source URL when the information is factual''',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Search query. Be specific. Examples: "2025年诺贝尔和平奖得主", '
              '"今日北京天气", "Flutter 4.0 release date"',
        },
        'max_results': {
          'type': 'integer',
          'description': 'Max results to return (default 5, max 8)',
        },
      },
      'required': ['query'],
    },
    executable: (String query, int? maxResults) async {
      final limit = (maxResults ?? 5).clamp(1, 8);

      try {
        // ── Bing HTML search (primary — works in China) ─────────────
        final bingResults = await _fetchBingSearch(dio, query);

        // ── DuckDuckGo Instant Answer API (knowledge graph) ──────────
        final apiResults = await _fetchInstantAnswers(dio, query);

        // ── DuckDuckGo HTML search (web results, fallback) ───────────
        final ddgResults = await _fetchHtmlSearch(dio, query);

        // Merge: Bing first (best availability), then DDG API, then DDG HTML
        final merged = [...bingResults, ...apiResults, ...ddgResults];

        if (merged.isEmpty) {
          return jsonEncode({
            'query': query,
            'results': [],
            'note': 'No results found. Try a different or more specific query.',
          });
        }

        // Deduplicate by URL, keep first occurrence
        final seen = <String>{};
        final deduped = <Map<String, String>>[];
        for (final r in merged) {
          final url = (r['url'] ?? '').trim();
          if (url.isEmpty) continue;
          if (seen.contains(url)) continue;
          seen.add(url);
          deduped.add(r);
          if (deduped.length >= limit) break;
        }

        return jsonEncode({
          'query': query,
          'results': deduped,
        });
      } catch (e) {
        return jsonEncode({
          'query': query,
          'results': [],
          'error': 'Search failed: $e',
        });
      }
    },
  );
}

/// Fetch web results from Bing (cn.bing.com) HTML search.
///
/// Bing is accessible in China, unlike DuckDuckGo which is often blocked.
/// Parses the `<li class="b_algo">` result blocks for titles, URLs, and snippets.
Future<List<Map<String, String>>> _fetchBingSearch(
  Dio dio,
  String query,
) async {
  final results = <Map<String, String>>[];
  try {
    // Use cn.bing.com for China accessibility. For English-heavy queries
    // the international endpoint still works from within China.
    final response = await dio.get<String>(
      'https://cn.bing.com/search',
      queryParameters: {
        'q': query,
        'setlang': 'zh-Hans',
      },
      options: Options(responseType: ResponseType.plain),
    );

    final html = response.data ?? '';
    if (html.isEmpty) return results;

    // Bing wraps each result in <li class="b_algo">…</li>.
    // Each block contains:
    //   <h2><a href="URL">Title</a></h2>
    //   <div class="b_caption"><p class="b_lineclamp2">snippet</p></div>
    final blockPattern = RegExp(
      r'<li\s+class="b_algo"[^>]*>(.*?)</li>',
      caseSensitive: false,
      dotAll: true,
    );

    final titlePattern = RegExp(
      r'<h2[^>]*>\s*<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );

    final snippetPattern = RegExp(
      r'<p\s+class="b_lineclamp2"[^>]*>(.*?)</p>',
      caseSensitive: false,
      dotAll: true,
    );

    final blocks = blockPattern.allMatches(html).take(10);
    for (final block in blocks) {
      if (results.length >= 8) break;

      final blockHtml = block.group(1) ?? '';
      if (blockHtml.isEmpty) continue;

      // Extract title + URL from the first <h2><a> in this block
      final titleMatch = titlePattern.firstMatch(blockHtml);
      if (titleMatch == null) continue;

      final url = titleMatch.group(1) ?? '';
      final title = _stripHtml(titleMatch.group(2) ?? '').trim();
      if (title.isEmpty || url.isEmpty) continue;

      // Skip Bing's own internal links
      if (url.contains('bing.com') && !url.contains('//www.bing.com')) continue;

      // Extract snippet from the first b_lineclamp2 <p> in this block
      final snippetMatch = snippetPattern.firstMatch(blockHtml);
      final snippet =
          _stripHtml(snippetMatch?.group(1) ?? '').trim();

      results.add({
        'title': title,
        'url': url,
        'snippet': snippet,
      });
    }
  } catch (_) {
    // Non-fatal — other providers may still return results.
  }
  return results;
}

/// Fetch structured results from DuckDuckGo Instant Answer API.
Future<List<Map<String, String>>> _fetchInstantAnswers(
  Dio dio,
  String query,
) async {
  final results = <Map<String, String>>[];
  try {
    final response = await dio.get<dynamic>(
      'https://api.duckduckgo.com/',
      queryParameters: {
        'q': query,
        'format': 'json',
        'no_html': '1',
        'no_redirect': '1',
        'skip_disambig': '1',
      },
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) return results;

    // Abstract (knowledge graph entry)
    final abstract = (data['Abstract'] ?? '').toString().trim();
    final abstractUrl = (data['AbstractURL'] ?? '').toString().trim();
    if (abstract.isNotEmpty && abstractUrl.isNotEmpty) {
      results.add({
        'title': (data['Heading'] ?? '').toString().trim(),
        'url': abstractUrl,
        'snippet': abstract,
      });
    }

    // Related Topics
    final relatedTopics = data['RelatedTopics'];
    if (relatedTopics is List) {
      for (final topic in relatedTopics) {
        if (topic is Map<String, dynamic>) {
          final text = (topic['Text'] ?? '').toString().trim();
          final url = (topic['FirstURL'] ?? '').toString().trim();
          if (text.isNotEmpty && url.isNotEmpty) {
            results.add({
              'title': '',
              'url': url,
              'snippet': text,
            });
          }
        }
      }
    }

    // External Results
    final extResults = data['Results'];
    if (extResults is List) {
      for (final r in extResults) {
        if (r is Map<String, dynamic>) {
          final text = (r['Text'] ?? '').toString().trim();
          final url = (r['FirstURL'] ?? '').toString().trim();
          if (text.isNotEmpty && url.isNotEmpty) {
            results.add({
              'title': '',
              'url': url,
              'snippet': text,
            });
          }
        }
      }
    }
  } catch (_) {
    // API failure is non-fatal — HTML search may still return results.
  }
  return results;
}

/// Fetch web results from DuckDuckGo's non-JS HTML endpoint.
Future<List<Map<String, String>>> _fetchHtmlSearch(
  Dio dio,
  String query,
) async {
  final results = <Map<String, String>>[];
  try {
    final response = await dio.get<String>(
      'https://html.duckduckgo.com/html/',
      queryParameters: {'q': query},
      options: Options(responseType: ResponseType.plain),
    );

    final html = response.data ?? '';
    if (html.isEmpty) return results;

    // Parse result blocks: each result has a link (class="result__a") and
    // a snippet (class="result__snippet").
    // The HTML structure is simple and consistent enough for regex.

    // Find all result links: <a ... class="result__a" href="URL">Title</a>
    final linkPattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*(?:<[^/][^>]*>[^<]*</[^>]*>)?[^<]*)</a>',
      caseSensitive: false,
    );
    final snippetPattern = RegExp(
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );

    final linkMatches = linkPattern.allMatches(html).toList();
    final snippetMatches = snippetPattern.allMatches(html).toList();

    for (var i = 0; i < linkMatches.length && i < 8; i++) {
      final linkMatch = linkMatches[i];
      var url = linkMatch.group(1) ?? '';
      var title = linkMatch.group(2) ?? '';

      // Clean up the URL (DuckDuckGo wraps URLs in redirects)
      url = _cleanUrl(url);
      title = _stripHtml(title).trim();

      // Get corresponding snippet
      var snippet = '';
      if (i < snippetMatches.length) {
        snippet = _stripHtml(snippetMatches[i].group(1) ?? '').trim();
      }

      if (title.isNotEmpty && url.isNotEmpty) {
        results.add({
          'title': title,
          'url': url,
          'snippet': snippet,
        });
      }
    }
  } catch (_) {
    // Non-fatal — API results may still be available.
  }
  return results;
}

/// Strip HTML tags from a string.
String _stripHtml(String input) {
  return input
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();
}

/// Extract the real URL from DuckDuckGo's redirect wrapper.
String _cleanUrl(String url) {
  // DuckDuckGo wraps external URLs like: //duckduckgo.com/l/?uddg=REAL_URL&rut=...
  final uddgMatch = RegExp(r'uddg=([^&]+)').firstMatch(url);
  if (uddgMatch != null) {
    return Uri.decodeComponent(uddgMatch.group(1)!);
  }
  return url;
}
