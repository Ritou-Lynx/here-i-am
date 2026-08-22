import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'html_page_parser.dart';

enum XiaohongshuNoteKind { image, video, text }

class XiaohongshuMediaCandidate {
  const XiaohongshuMediaCandidate({
    required this.originalUrl,
    required this.order,
    required this.source,
  });

  final String originalUrl;
  final int order;
  final String source;

  Map<String, dynamic> toJson() => {
        'original_url': originalUrl,
        'order': order,
        'source': source,
      };
}

class XiaohongshuPublicComment {
  const XiaohongshuPublicComment({
    required this.author,
    required this.text,
    required this.order,
    required this.sourceUrl,
    required this.selector,
    this.publishedAt,
    this.publishedAtRaw,
  });

  final String author;
  final String text;
  final int order;
  final String sourceUrl;
  final String selector;
  final DateTime? publishedAt;
  final String? publishedAtRaw;

  Map<String, dynamic> toJson() => {
        'author': author,
        'text': text,
        'order': order,
        'source_url': sourceUrl,
        'selector': selector,
        if (publishedAt != null)
          'published_at': publishedAt!.toUtc().toIso8601String(),
        if (publishedAtRaw != null) 'published_at_raw': publishedAtRaw,
        'access': 'anonymous_public_page',
      };
}

class XiaohongshuPublicEvidence {
  const XiaohongshuPublicEvidence({
    required this.noteKind,
    required this.mediaCandidates,
    required this.comments,
    required this.parserVersion,
  });

  static const currentParserVersion = 'xhs-public-evidence-v1';

  final XiaohongshuNoteKind noteKind;
  final List<XiaohongshuMediaCandidate> mediaCandidates;
  final List<XiaohongshuPublicComment> comments;
  final String parserVersion;
}

/// Extracts only evidence already present in the anonymously fetched HTML.
/// It never consults cookies, a WebView profile or private APIs.
XiaohongshuPublicEvidence parseXiaohongshuPublicEvidence(
  String html, {
  required String sourceUrl,
  required ParsedPageContent parsedPage,
}) {
  final document = html_parser.parse(html);
  final hasVideo = _hasVideoEvidence(document);
  final candidates = _collectCandidates(parsedPage, sourceUrl);
  final comments = _collectComments(document, sourceUrl);
  return XiaohongshuPublicEvidence(
    noteKind: hasVideo
        ? XiaohongshuNoteKind.video
        : candidates.isNotEmpty
            ? XiaohongshuNoteKind.image
            : XiaohongshuNoteKind.text,
    mediaCandidates: candidates,
    comments: comments,
    parserVersion: XiaohongshuPublicEvidence.currentParserVersion,
  );
}

bool _hasVideoEvidence(dom.Document document) {
  if (document.querySelector('video, video source') != null) return true;
  for (final meta in document.querySelectorAll('meta')) {
    final key = (meta.attributes['property'] ?? meta.attributes['name'] ?? '')
        .trim()
        .toLowerCase();
    final value = (meta.attributes['content'] ?? '').trim().toLowerCase();
    if ((key == 'og:type' && value.contains('video')) ||
        key == 'og:video' ||
        key.startsWith('og:video:') ||
        key == 'twitter:player') {
      return true;
    }
  }
  return false;
}

List<XiaohongshuMediaCandidate> _collectCandidates(
  ParsedPageContent parsed,
  String sourceUrl,
) {
  final ordered = <(String, String)>[
    for (final url in parsed.imageUrls) (url, 'image_urls'),
    if (parsed.ogImage != null) (parsed.ogImage!, 'og_image'),
  ];
  final seen = <String>{};
  final result = <XiaohongshuMediaCandidate>[];
  for (final entry in ordered) {
    final resolved = Uri.tryParse(sourceUrl)?.resolve(entry.$1);
    if (resolved == null ||
        (resolved.scheme != 'https' && resolved.scheme != 'http')) {
      continue;
    }
    final url = resolved.toString().split('#').first;
    if (!seen.add(url)) continue;
    result.add(
      XiaohongshuMediaCandidate(
        originalUrl: url,
        order: result.length,
        source: entry.$2,
      ),
    );
  }
  return result;
}

List<XiaohongshuPublicComment> _collectComments(
  dom.Document document,
  String sourceUrl,
) {
  const selectors = <String>[
    '.comments-container .comment-item',
    '[class*="comments-container"] [class*="comment-item"]',
    '[data-testid="comment"]',
    'article.comment',
  ];
  final nodes = <(dom.Element, String)>[];
  final seenNodes = <dom.Element>{};
  for (final selector in selectors) {
    for (final node in document.querySelectorAll(selector)) {
      if (seenNodes.add(node)) nodes.add((node, selector));
    }
    if (nodes.isNotEmpty) break;
  }
  final comments = <XiaohongshuPublicComment>[];
  final seenContent = <String>{};
  for (final entry in nodes) {
    if (comments.length >= 10) break;
    final node = entry.$1;
    if (_hasCommentItemAncestor(node)) continue;
    final author = _firstText(node, const [
          '.author .name',
          '.author',
          '.user-info .name',
          '.username',
          '[data-author]',
        ]) ??
        _clean(node.attributes['data-user-name']);
    final text = _firstText(node, const [
      '.comment-content',
      '.content',
      '.note-text',
      '[data-comment-text]',
    ]);
    if (author == null || text == null) continue;
    if (!seenContent.add('$author\n$text')) continue;
    final timeElement = _firstElement(node, const [
      'time',
      '.date',
      '.time',
      '[data-created-at]',
    ]);
    final rawTime = _clean(timeElement?.attributes['datetime']) ??
        _clean(timeElement?.attributes['data-created-at']) ??
        _clean(timeElement?.text);
    comments.add(
      XiaohongshuPublicComment(
        author: author,
        text: text,
        order: comments.length,
        sourceUrl: sourceUrl,
        selector: entry.$2,
        publishedAt: rawTime == null ? null : DateTime.tryParse(rawTime),
        publishedAtRaw: rawTime,
      ),
    );
  }
  return comments;
}

bool _hasCommentItemAncestor(dom.Element node) {
  dom.Node? current = node.parent;
  while (current is dom.Element) {
    final classes = current.className.split(RegExp(r'\s+'));
    if (classes.any((value) => value.contains('comment-item'))) return true;
    current = current.parent;
  }
  return false;
}

dom.Element? _firstElement(dom.Element root, List<String> selectors) {
  for (final selector in selectors) {
    final element = root.querySelector(selector);
    if (element != null) return element;
  }
  return null;
}

String? _firstText(dom.Element root, List<String> selectors) {
  for (final selector in selectors) {
    final element = root.querySelector(selector);
    if (element == null) continue;
    final attributeValue = selector == '[data-author]'
        ? element.attributes['data-author']
        : selector == '[data-comment-text]'
            ? element.attributes['data-comment-text']
            : null;
    final value = _clean(attributeValue ?? element.text);
    if (value != null) return value;
  }
  return null;
}

String? _clean(String? value) {
  final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
