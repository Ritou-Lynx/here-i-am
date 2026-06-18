/// Parses a shared text payload from 小红书 / 微信公众号 / generic links.
///
/// 小红书 share payload typically looks like:
///   `33 复制本条信息，打开【小红书】App查看精彩内容！`
///   `"周末杭州 city walk 路线" 你的好友推荐了一篇笔记 http://xhslink.com/abcd`
///
/// 微信公众号 share payload usually contains a `mp.weixin.qq.com/s/...` URL,
/// often without surrounding 口令 text.
///
/// Generic web link share: just a URL, no platform-specific framing.
///
/// This is a pure function — no I/O, no DB. It only extracts what the user
/// pasted/shared; URL expansion (xhslink → real URL) and content fetching
/// happen elsewhere.
library;

/// Result of parsing a shared text.
class ReadingShareParseResult {
  const ReadingShareParseResult({
    required this.platform,
    required this.url,
    this.title,
    this.capturedNote,
    required this.rawText,
  });

  /// Platform identifier: `xiaohongshu`, `wechat_mp`, `web`.
  final String platform;

  /// Best-guess article URL extracted from the share text.
  /// For 小红书 this is usually a `xhslink.com/*` short link that still
  /// needs HTTP-level expansion to reach the real `xiaohongshu.com/*` URL.
  final String url;

  /// Article title parsed from the framing text. May be null if the share
  /// only contains a bare link.
  final String? title;

  /// Anything the user typed alongside the link before sharing — preserved
  /// so the companion can quote it ("you said: ...").
  /// Currently always null for system-generated 口令 shares; reserved for
  /// future "share with my comment" flows.
  final String? capturedNote;

  /// Original shared payload, kept verbatim for sourceExcerpt evidence.
  final String rawText;

  @override
  String toString() =>
      'ReadingShareParseResult(platform: $platform, url: $url, title: $title)';
}

/// Top-level parser. Returns null when the text does not look like a
/// recognised reading share.
///
/// If [extractCapturedNote] is true, any non-URL non-boilerplate text
/// surrounding the link is preserved as `capturedNote` — useful when the
/// share originates from a chat input where the user typed something
/// alongside the link.
ReadingShareParseResult? parseReadingShare(
  String? rawInput, {
  bool extractCapturedNote = false,
}) {
  final raw = rawInput?.trim();
  if (raw == null || raw.isEmpty) return null;

  // Priority order matters: xhslink > xiaohongshu domain > wechat > generic.
  final result = _parseXiaohongshu(raw) ??
      _parseWechatMp(raw) ??
      _parseGenericLink(raw);
  if (result == null) return null;
  if (!extractCapturedNote) return result;

  final note = _extractCapturedNote(raw, result.url, result.title);
  if (note == null || note.isEmpty) return result;
  return ReadingShareParseResult(
    platform: result.platform,
    url: result.url,
    title: result.title,
    capturedNote: note,
    rawText: result.rawText,
  );
}

/// Strips URLs and platform boilerplate (the "复制本条信息打开【小红书】App"
/// chunk that the system 口令 always carries) from the raw text. What's
/// left is treated as "what the user wrote about this link".
String? _extractCapturedNote(String raw, String url, String? title) {
  var work = raw;

  // Remove the URL itself.
  work = work.replaceAll(url, '');

  // Remove the platform 口令 boilerplate. Patterns vary slightly across
  // versions of the 小红书 share string, so we strip generously.
  final boilerplatePatterns = <RegExp>[
    RegExp(r'\d+\s*复制本条信息[，,]?\s*打开[【\[]?\s*小红书\s*[】\]]?\s*App\s*查看精彩内容[！!]?'),
    RegExp(r'你的好友推荐了一篇笔记[，,]?\s*快去围观吧[！!]?'),
    RegExp(r'复制这段描述后打开\s*小红书\s*App'),
    // wechat doesn't have a fixed 口令 framing, so nothing here.
  ];
  for (final pattern in boilerplatePatterns) {
    work = work.replaceAll(pattern, '');
  }

  // Remove the title chunk so capturedNote doesn't duplicate it.
  if (title != null && title.isNotEmpty) {
    // Strip various quote variants around the title.
    work = work
        .replaceAll('「$title」', '')
        .replaceAll('"$title"', '')
        .replaceAll('"$title"', '')
        .replaceAll(title, '');
  }

  // Collapse whitespace, trim trailing punctuation noise.
  work = work.replaceAll(RegExp(r'\s+'), ' ').trim();
  work = work.replaceAll(RegExp(r'^[,，。.；;\s]+|[,，。.；;\s]+$'), '').trim();

  if (work.isEmpty) return null;
  // Avoid storing meaninglessly short fragments.
  if (work.length < 2) return null;
  return work;
}

// ---------------------------------------------------------------------------
// 小红书
// ---------------------------------------------------------------------------

/// Matches xhslink.com/* short URLs and bare xiaohongshu.com note URLs.
/// xhslink format: `http(s)://xhslink.com/<token>` (a/b/c/m/T/... any prefix).
final RegExp _xhsShortLinkPattern = RegExp(
  r'https?://xhslink\.com/[A-Za-z0-9/_\-]+',
  caseSensitive: false,
);

final RegExp _xhsDirectLinkPattern = RegExp(
  r'https?://(?:www\.)?xiaohongshu\.com/[A-Za-z0-9/_\-?&=.%]+',
  caseSensitive: false,
);

/// Pulls a 中文/英文 quoted title out of the 口令 framing.
/// 小红书 share text format: `... 数字 复制本条信息 ... "标题" ... 链接`
/// The title sits between Chinese 「」 or straight quotes.
final RegExp _quotedTitlePattern = RegExp(
  r'[「""]([^「」""]{2,40})[」""]',
);

ReadingShareParseResult? _parseXiaohongshu(String raw) {
  final shortMatch = _xhsShortLinkPattern.firstMatch(raw);
  final directMatch = _xhsDirectLinkPattern.firstMatch(raw);
  final urlMatch = shortMatch ?? directMatch;
  if (urlMatch == null) return null;

  final url = urlMatch.group(0)!;
  final title = _extractQuotedTitle(raw);

  return ReadingShareParseResult(
    platform: 'xiaohongshu',
    url: url,
    title: title,
    rawText: raw,
  );
}

String? _extractQuotedTitle(String raw) {
  final match = _quotedTitlePattern.firstMatch(raw);
  final title = match?.group(1)?.trim();
  if (title == null || title.isEmpty) return null;
  return title;
}

// ---------------------------------------------------------------------------
// 微信公众号
// ---------------------------------------------------------------------------

/// `mp.weixin.qq.com/s/<token>` or `mp.weixin.qq.com/s?__biz=...`.
final RegExp _wechatMpPattern = RegExp(
  r'https?://mp\.weixin\.qq\.com/s[/?][A-Za-z0-9_\-=&%.?#]+',
  caseSensitive: false,
);

ReadingShareParseResult? _parseWechatMp(String raw) {
  final match = _wechatMpPattern.firstMatch(raw);
  if (match == null) return null;

  final url = match.group(0)!;
  // Title sometimes appears as the first non-URL line. Conservative: only
  // accept if the line is short (article-title-like).
  final firstLine = raw.split('\n').first.trim();
  final candidateTitle = firstLine.contains('http') ? null : firstLine;
  final title = (candidateTitle != null &&
          candidateTitle.length >= 4 &&
          candidateTitle.length <= 40)
      ? candidateTitle
      : null;

  return ReadingShareParseResult(
    platform: 'wechat_mp',
    url: url,
    title: title,
    rawText: raw,
  );
}

// ---------------------------------------------------------------------------
// Generic web link fallback
// ---------------------------------------------------------------------------

final RegExp _anyHttpUrlPattern = RegExp(
  r'https?://[A-Za-z0-9._\-~:/?#\[\]@!$&' "'" r'()*+,;=%]+',
  caseSensitive: false,
);

ReadingShareParseResult? _parseGenericLink(String raw) {
  final match = _anyHttpUrlPattern.firstMatch(raw);
  if (match == null) return null;
  final url = match.group(0)!;
  return ReadingShareParseResult(
    platform: 'web',
    url: url,
    rawText: raw,
  );
}
