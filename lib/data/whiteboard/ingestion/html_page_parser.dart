/// HTML content parser for link ingestion.
///
/// Extracts title, description, Open Graph image, and readable body text
/// from an HTML document. Pure parsing — no I/O.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Parsed page metadata and body content.
class ParsedPageContent {
  /// Best available title (og:title → twitter:title → <title>).
  final String? title;

  /// Description (og:description → meta description → first paragraph).
  final String? description;

  /// Open Graph / Twitter card image URL.
  final String? ogImage;

  /// Site name from og:site_name.
  final String? siteName;

  /// Author from og:article:author / meta author.
  final String? author;

  /// Readable plain-text body (nav/script/style stripped, code blocks
  /// preserved as fenced markdown).
  final String? bodyText;

  /// First ~500 chars of [bodyText], for excerpts / search haystack.
  final String? bodyExcerpt;

  /// Inline image URLs found in the body container (capped at 20).
  final List<String> imageUrls;

  /// Parser version — increment when extraction logic changes so
  /// SourceVersion records can distinguish parse generations.
  static const String parserVersion = 'w3-html-parser-v1';

  const ParsedPageContent({
    this.title,
    this.description,
    this.ogImage,
    this.siteName,
    this.author,
    this.bodyText,
    this.bodyExcerpt,
    this.imageUrls = const [],
  });

  bool get isEmpty =>
      (title == null || title!.isEmpty) &&
      (bodyText == null || bodyText!.trim().isEmpty);

  @override
  String toString() =>
      'ParsedPageContent(title=$title, images=${imageUrls.length}, bodyLen=${bodyText?.length ?? 0})';
}

/// Parses an HTML string into [ParsedPageContent].
ParsedPageContent parseHtmlPage(String html, {String? sourceUrl}) {
  if (html.trim().isEmpty) return const ParsedPageContent();

  final dom.Document doc;
  try {
    doc = html_parser.parse(html);
  } catch (_) {
    return const ParsedPageContent();
  }

  final title = _extractTitle(doc, sourceUrl);
  final description = _extractDescription(doc);
  final ogImage = _ogMeta(doc, 'og:image') ?? _ogMeta(doc, 'twitter:image');
  final siteName = _ogMeta(doc, 'og:site_name');
  final author = _extractAuthor(doc);
  final bodyContainer = _extractBodyContainer(doc);
  final imageUrls = _extractImages(bodyContainer);
  final bodyText = _extractText(bodyContainer);
  final excerpt = _buildExcerpt(bodyText);

  return ParsedPageContent(
    title: title,
    description: description,
    ogImage: ogImage,
    siteName: siteName,
    author: author,
    bodyText: bodyText,
    bodyExcerpt: excerpt,
    imageUrls: imageUrls,
  );
}

// ---------------------------------------------------------------------------

String? _extractTitle(dom.Document doc, String? url) {
  final og = _ogMeta(doc, 'og:title');
  if (og != null && og.isNotEmpty) return og;
  final twitter = _ogMeta(doc, 'twitter:title');
  if (twitter != null && twitter.isNotEmpty) return twitter;
  final docTitle = doc.querySelector('title')?.text.trim();
  if (docTitle != null && docTitle.isNotEmpty) {
    // Strip common suffixes like " · GitHub", " | Site Name".
    return docTitle.split(RegExp(r'\s+[·|]\s+')).first.trim();
  }
  // Last resort: first <h1>.
  final h1 = doc.querySelector('h1')?.text.trim();
  if (h1 != null && h1.isNotEmpty) return h1;
  return null;
}

String? _extractDescription(dom.Document doc) {
  final og = _ogMeta(doc, 'og:description');
  if (og != null && og.isNotEmpty) return og;
  final meta = _metaName(doc, 'description');
  if (meta != null && meta.isNotEmpty) return meta;
  return null;
}

String? _extractAuthor(dom.Document doc) {
  return _ogMeta(doc, 'og:article:author') ??
      _ogMeta(doc, 'article:author') ??
      _metaName(doc, 'author') ??
      _ogMeta(doc, 'twitter:creator');
}

// Body container selection — first match wins.
const _bodySelectors = <String>[
  'article',
  '[role="main"]',
  'main',
  '#content',
  '.post-content',
  '.article-content',
  '.entry-content',
  '.post-body',
  '.markdown-body',
  '.content',
];

dom.Element? _extractBodyContainer(dom.Document doc) {
  for (final selector in _bodySelectors) {
    final el = doc.querySelector(selector);
    if (el != null) return el;
  }
  return doc.querySelector('body');
}

String? _extractText(dom.Element? container) {
  if (container == null) return null;
  for (final el in container.querySelectorAll('script, style, noscript, template, nav, header, footer, aside')) {
    el.remove();
  }
  // Preserve <pre> code blocks as fenced markdown.
  for (final pre in container.querySelectorAll('pre')) {
    final codeText = pre.text.trim();
    if (codeText.isEmpty) continue;
    final lang = _inferCodeLang(pre);
    final fenced = '```$lang\n$codeText\n```';
    final replacement = dom.Element.tag('div')..text = fenced;
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

String _inferCodeLang(dom.Element pre) {
  final code = pre.querySelector('code');
  if (code != null) {
    final cls = code.attributes['class'] ?? '';
    final match = RegExp(r'language-([a-z0-9+#]+)').firstMatch(cls);
    if (match != null) return match.group(1)!;
  }
  return '';
}

List<String> _extractImages(dom.Element? container) {
  if (container == null) return const [];
  final results = <String>[];
  final seen = <String>{};
  for (final img in container.querySelectorAll('img')) {
    final candidates = <String?>[
      img.attributes['data-src'],
      img.attributes['data-original-src'],
      img.attributes['src'],
    ];
    for (final raw in candidates) {
      if (raw == null) continue;
      final src = raw.trim();
      if (src.isEmpty || !src.startsWith('http')) continue;
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
  return lower.contains('/avatar') ||
      lower.contains('/favicon') ||
      lower.contains('/icons/') ||
      lower.contains('/icon/') ||
      lower.contains('1x1') ||
      lower.contains('width=1');
}

String? _buildExcerpt(String? body) {
  if (body == null) return null;
  final trimmed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length <= 500) return trimmed;
  return '${trimmed.substring(0, 500)}…';
}

String? _ogMeta(dom.Document doc, String property) {
  final el = doc.querySelector('meta[property="$property"], meta[name="$property"]');
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