/// URL canonicalization and provider identification.
///
/// Pure functions — no I/O. The canonicalizer normalizes a raw URL into a
/// stable form (the *canonical key* used for de-duplication), classifies it
/// into a provider, and extracts a provider-specific stable id.
///
/// Redirect resolution happens in [SafeHttpClient] — this module only
/// normalizes what the user typed / pasted.
library;

/// Result of canonicalizing a URL.
class CanonicalUrl {
  /// Fully-normalized URL string (scheme lowercased, host lowercased,
  /// default ports stripped, trailing slash on root path, query sorted,
  /// fragment dropped, common tracking params removed).
  final String normalized;

  /// Host without port (lowercased).
  final String host;

  /// Scheme (lowercased): `http` or `https`.
  final String scheme;

  /// Provider identifier: `bilibili`, `xiaohongshu`, `youtube`,
  /// `wechat_mp`, or `web` for everything else.
  final String provider;

  /// Provider-specific stable id (e.g. BV id, note id, video id), or null
  /// when the URL is generic web or the id can't be extracted.
  final String? canonicalId;

  /// Original URL as provided by the caller (verbatim, before
  /// normalization) — preserved for audit / display.
  final String original;

  const CanonicalUrl({
    required this.normalized,
    required this.host,
    required this.scheme,
    required this.provider,
    this.canonicalId,
    required this.original,
  });

  @override
  String toString() =>
      'CanonicalUrl($normalized, provider=$provider, id=$canonicalId)';
}

/// Tracking / analytics query parameters that should be stripped during
/// canonicalization so the same page doesn't appear as two sources.
const _trackingParams = <String>{
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'fbclid',
  'gclid',
  'ref',
  'ref_src',
  'spm',
  'share_source',
  'share_token',
};

/// Canonicalizes a raw URL string.
///
/// Returns `null` if [raw] is not a valid http/https URL.
CanonicalUrl? canonicalizeUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (!uri.hasScheme) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  final host = (uri.host).toLowerCase();
  if (host.isEmpty) return null;

  // Reconstruct a normalized URL.
  final port = uri.port;
  final defaultPort = scheme == 'https' ? 443 : 80;
  final hasDefaultPort = port == defaultPort || port == 0;

  // Path normalization: empty path -> '/', collapse trailing slash on root.
  var path = uri.path.isEmpty ? '/' : uri.path;
  // Don't add trailing slash if the path already ends with a file-like
  // segment (contains '.'); only normalize bare host paths.
  if (path == '' ) path = '/';

  // Query: filter tracking params, sort keys for stable comparison.
  final queryParams = <String, List<String>>{};
  final sortedKeys = uri.queryParametersAll.keys.toList()..sort();
  for (final key in sortedKeys) {
    if (_trackingParams.contains(key.toLowerCase())) continue;
    queryParams[key] = uri.queryParametersAll[key]!;
  }
  final normalizedQuery = queryParams.isEmpty
      ? ''
      : Uri(queryParameters: queryParams).query;

  final normalized = Uri(
    scheme: scheme,
    host: host,
    port: hasDefaultPort ? null : port,
    path: path,
    query: normalizedQuery.isEmpty ? null : normalizedQuery,
  ).toString();

  final provider = _identifyProvider(host);
  final canonicalId = _extractCanonicalId(provider, uri);

  return CanonicalUrl(
    normalized: normalized,
    host: host,
    scheme: scheme,
    provider: provider,
    canonicalId: canonicalId,
    original: trimmed,
  );
}

String _identifyProvider(String host) {
  if (host.endsWith('bilibili.com') || host == 'b23.tv' ||
      host.endsWith('biligame.com')) {
    return 'bilibili';
  }
  if (host.endsWith('xiaohongshu.com') || host == 'xhslink.com' ||
      host.endsWith('xhscdn.com')) {
    return 'xiaohongshu';
  }
  if (host.endsWith('youtube.com') || host.endsWith('youtu.be') ||
      host == 'm.youtube.com' || host == 'music.youtube.com') {
    return 'youtube';
  }
  if (host.endsWith('mp.weixin.qq.com')) {
    return 'wechat_mp';
  }
  return 'web';
}

String? _extractCanonicalId(String provider, Uri uri) {
  switch (provider) {
    case 'bilibili':
      return _bilibiliId(uri);
    case 'xiaohongshu':
      return _xiaohongshuId(uri);
    case 'youtube':
      return _youtubeId(uri);
    case 'wechat_mp':
      return _wechatMpId(uri);
    default:
      return null;
  }
}

String? _bilibiliId(Uri uri) {
  final path = uri.path;
  // /video/BV1xx411c7mD  or  /video/av12345
  final bvMatch = RegExp(r'/video/(BV[0-9A-Za-z]{10})').firstMatch(path);
  if (bvMatch != null) return bvMatch.group(1);
  final avMatch = RegExp(r'/video/av(\d+)', caseSensitive: false)
      .firstMatch(path);
  if (avMatch != null) return 'av${avMatch.group(1)}';
  // Short link b23.tv/xxx — id is the token; resolved later.
  if (uri.host == 'b23.tv') {
    final token = path.replaceAll('/', '');
    if (token.isNotEmpty) return 'b23:$token';
  }
  return null;
}

String? _xiaohongshuId(Uri uri) {
  // /explore/{id} or /discovery/item/{id} or /note/{id}
  final patterns = [
    RegExp(r'/(?:explore|note)/([0-9a-f]{24})'),
    RegExp(r'/discovery/item/([0-9a-f]{24})'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(uri.path);
    if (m != null) return m.group(1);
  }
  if (uri.host == 'xhslink.com') {
    final token = uri.path.replaceAll('/', '');
    if (token.isNotEmpty) return 'xhslink:$token';
  }
  return null;
}

String? _youtubeId(Uri uri) {
  // youtu.be/{id}, youtube.com/watch?v={id}, /shorts/{id}, /embed/{id}
  if (uri.host == 'youtu.be') {
    final id = uri.path.replaceAll('/', '');
    if (RegExp(r'^[0-9A-Za-z_-]{11}$').hasMatch(id)) return id;
  }
  final watchV = uri.queryParameters['v'];
  if (watchV != null && RegExp(r'^[0-9A-Za-z_-]{11}$').hasMatch(watchV)) {
    return watchV;
  }
  final shortsMatch = RegExp(r'/shorts/([0-9A-Za-z_-]{11})')
      .firstMatch(uri.path);
  if (shortsMatch != null) return shortsMatch.group(1);
  final embedMatch = RegExp(r'/embed/([0-9A-Za-z_-]{11})')
      .firstMatch(uri.path);
  if (embedMatch != null) return embedMatch.group(1);
  return null;
}

String? _wechatMpId(Uri uri) {
  // mp.weixin.qq.com/s?__biz=...&mid=...&idx=... — use biz+mid+idx as id.
  // Or /s/{token} short form (no stable id extractable, returns null).
  final biz = uri.queryParameters['__biz'];
  final mid = uri.queryParameters['mid'];
  final idx = uri.queryParameters['idx'];
  if (biz != null && mid != null) {
    return 'wx:$biz:$mid${idx != null ? ':$idx' : ''}';
  }
  final sMatch = RegExp(r'^/s/([A-Za-z0-9_-]+)$').firstMatch(uri.path);
  if (sMatch != null) return 'wxshort:${sMatch.group(1)}';
  return null;
}