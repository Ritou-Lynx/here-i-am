/// Parses clipboard/share text into one or more HTTP(S) link candidates.
///
/// The phone reading flow already accepts Xiaohongshu command text, WeChat
/// share copy and ordinary prose around a URL.  The desktop importer reuses
/// that pure parser here, then adds multi-link discovery for the desktop
/// selection UI.  No network or persistence happens in this layer.
library;

import 'package:memex/data/services/reading/reading_share_parser.dart';

class SharedLinkInput {
  const SharedLinkInput({
    required this.rawText,
    required this.urls,
    this.preferredUrl,
    this.platform,
    this.sharedTitle,
    this.capturedNote,
  });

  final String rawText;
  final List<String> urls;
  final String? preferredUrl;
  final String? platform;
  final String? sharedTitle;
  final String? capturedNote;
}

final RegExp _httpUrlPattern = RegExp(
  r'https?://[^\s<>"“”。，；！、【】《》]+',
  caseSensitive: false,
);

/// Returns null when [rawInput] contains no usable HTTP(S) link.
SharedLinkInput? parseSharedLinkInput(String? rawInput) {
  var raw = rawInput?.trim();
  if (raw == null || raw.isEmpty) return null;

  // Markdown-rendered clipboard text can escape ampersands.  A backslash is
  // not part of the real query string, so remove only this narrow escape.
  raw = raw.replaceAll(r'\&', '&');
  final reading = parseReadingShare(raw, extractCapturedNote: true);
  final urls = <String>[];

  void add(String? candidate) {
    if (candidate == null) return;
    final cleaned = _trimUrlPunctuation(candidate);
    final uri = Uri.tryParse(cleaned);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        urls.contains(cleaned)) {
      return;
    }
    urls.add(cleaned);
  }

  // Keep the platform-aware phone parser's candidate first.
  add(reading?.url);
  for (final match in _httpUrlPattern.allMatches(raw)) {
    add(match.group(0));
  }
  if (urls.isEmpty) return null;

  return SharedLinkInput(
    rawText: raw,
    urls: List.unmodifiable(urls),
    preferredUrl:
        reading?.url == null ? urls.first : _trimUrlPunctuation(reading!.url),
    platform: reading?.platform,
    sharedTitle: reading?.title,
    capturedNote: reading?.capturedNote,
  );
}

String _trimUrlPunctuation(String value) {
  var result = value.trim();
  const proseSeparators = <String>{'。', '，', '；', '！', '、', '【', '】', '《', '》'};
  final separatorIndex = result.codeUnits.indexWhere(
    (unit) => proseSeparators.contains(String.fromCharCode(unit)),
  );
  if (separatorIndex >= 0) {
    result = result.substring(0, separatorIndex);
  }
  const trailing = <String>{
    '.',
    ',',
    ';',
    '!',
    '。',
    '，',
    '；',
    '！',
    '】',
    '》',
    '」',
    '』',
    '"',
    "'",
  };
  while (result.isNotEmpty && trailing.contains(result[result.length - 1])) {
    result = result.substring(0, result.length - 1);
  }

  // A Markdown link contributes one unmatched closing parenthesis. Preserve
  // balanced parentheses that legitimately belong to the URL path/query.
  while (result.endsWith(')') &&
      '('.allMatches(result).length < ')'.allMatches(result).length) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
