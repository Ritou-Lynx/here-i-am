import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';

/// Build a general-purpose web search tool for the companion agent.
///
/// Uses Bing (cn.bing.com) HTML search — accessible in China, no API key required.
/// Returns structured results with title, URL, and snippet so the LLM can
/// incorporate current information into its replies.
Tool buildWebSearchTool() {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
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
        final results = await _fetchBingSearch(dio, query);

        if (results.isEmpty) {
          return jsonEncode({
            'query': query,
            'results': [],
            'note': 'No results found. Try a different or more specific query.',
          });
        }

        // Deduplicate by URL and trim to requested limit
        final seen = <String>{};
        final deduped = <Map<String, String>>[];
        for (final r in results) {
          final url = (r['url'] ?? '').trim();
          if (url.isEmpty || seen.contains(url)) continue;
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
/// Parses `<li class="b_algo">` result blocks for titles, URLs, and snippets.
Future<List<Map<String, String>>> _fetchBingSearch(
  Dio dio,
  String query,
) async {
  final results = <Map<String, String>>[];
  try {
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

      // Skip Bing's own internal links (ads, related searches, etc.)
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
    // Let the error surface through the tool's return value.
  }
  return results;
}

/// Strip HTML tags and common entities from a string.
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
