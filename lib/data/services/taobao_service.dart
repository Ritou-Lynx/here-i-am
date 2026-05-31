import 'dart:convert';
import 'package:http/http.dart' as http;

/// Lightweight HTTP client for Taobao product search.
///
/// Uses Taobao's public suggest API — no authentication required.
/// For v1, returns search suggestions and constructs product/search URLs.
/// Full autonomous ordering (add to cart → checkout → cashier URL) requires
/// authenticated API calls or WebView automation, deferred to a later version.
class TaobaoService {
  static const _suggestBase = 'https://suggest.taobao.com/sug';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; SM-S908B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36';

  /// Search Taobao suggest API.
  ///
  /// Returns a list of `{title, search_query}` maps.
  /// Note: suggest API returns autocomplete titles only (no prices or IDs).
  /// For actual purchase, use [buildSearchUrl] to let the user browse results.
  Future<List<Map<String, String>>> searchSuggestions({
    required String query,
    int limit = 8,
  }) async {
    final uri = Uri.parse(_suggestBase).replace(queryParameters: {
      'code': 'utf-8',
      'q': query,
      'type': '1',
    });

    try {
      final resp = await http
          .get(uri, headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final result = (data['result'] as List<dynamic>?) ?? [];

      return result
          .take(limit)
          .map((item) {
            final arr = item as List<dynamic>;
            return {'title': arr[0].toString(), 'category': arr[1].toString()};
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  String buildSearchUrl(String query) =>
      Uri.parse('https://s.taobao.com/search')
          .replace(queryParameters: {'q': query, 'sort': 'sale-desc'})
          .toString();

  String buildProductUrl(String itemId) =>
      'https://item.taobao.com/item.htm?id=$itemId';
}
