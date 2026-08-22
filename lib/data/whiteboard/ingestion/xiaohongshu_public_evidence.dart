import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'html_page_parser.dart';

enum XiaohongshuNoteKind { image, video, text }

class XiaohongshuMediaCandidate {
  const XiaohongshuMediaCandidate({
    required this.originalUrl,
    required this.order,
    required this.source,
    this.confidence = 'high',
  });

  final String originalUrl;
  final int order;
  final String source;
  final String confidence;

  Map<String, dynamic> toJson() => {
        'original_url': originalUrl,
        'order': order,
        'source': source,
        'confidence': confidence,
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

  static const currentParserVersion = 'xhs-public-evidence-v2';

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
  final noteRoot = _noteRoot(document);
  final structured = _structuredNoteMedia(document);
  final hasVideo = structured.hasVideo || _hasVideoEvidence(noteRoot);
  final candidates = _collectCandidates(
    noteRoot,
    structured.imageUrls,
    parsedPage,
    sourceUrl,
  );
  final comments = _collectComments(document, sourceUrl);
  return XiaohongshuPublicEvidence(
    noteKind: hasVideo
        ? XiaohongshuNoteKind.video
        : candidates.any((candidate) => candidate.confidence == 'high')
            ? XiaohongshuNoteKind.image
            : XiaohongshuNoteKind.text,
    mediaCandidates: candidates,
    comments: comments,
    parserVersion: XiaohongshuPublicEvidence.currentParserVersion,
  );
}

dom.Element? _noteRoot(dom.Document document) {
  for (final selector in const [
    '[data-testid="note-content"]',
    '[data-note-id]',
    'article.note',
    '.note-content',
    '.note-container',
  ]) {
    final root = document.querySelector(selector);
    if (root != null) return root;
  }
  return null;
}

bool _hasVideoEvidence(dom.Element? noteRoot) =>
    noteRoot?.querySelector('video, video source') != null;

List<XiaohongshuMediaCandidate> _collectCandidates(
  dom.Element? noteRoot,
  List<String> structuredUrls,
  ParsedPageContent parsed,
  String sourceUrl,
) {
  final ordered = <(String, String)>[
    for (final url in structuredUrls) (url, 'structured_note_state'),
    if (noteRoot != null)
      for (final image in noteRoot.querySelectorAll('img'))
        if (_imageUrl(image) case final String url) (url, 'note_root'),
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
  // Preserve OG as explicitly low-confidence fallback evidence. It is not
  // sufficient to classify or download a note because many pages use a
  // site-wide sharing image.
  if (parsed.ogImage != null) {
    final resolved = Uri.tryParse(sourceUrl)?.resolve(parsed.ogImage!);
    if (resolved != null &&
        (resolved.scheme == 'https' || resolved.scheme == 'http')) {
      final url = resolved.toString().split('#').first;
      if (seen.add(url)) {
        result.add(XiaohongshuMediaCandidate(
          originalUrl: url,
          order: result.length,
          source: 'og_image',
          confidence: 'low',
        ));
      }
    }
  }
  return result;
}

class _StructuredNoteMedia {
  const _StructuredNoteMedia(
      {this.imageUrls = const [], this.hasVideo = false});

  final List<String> imageUrls;
  final bool hasVideo;
}

_StructuredNoteMedia _structuredNoteMedia(dom.Document document) {
  final images = <String>[];
  var hasVideo = false;
  for (final script in document.querySelectorAll(
    'script[data-xhs-note-state], script#xhs-note-state',
  )) {
    try {
      final decoded = jsonDecode(script.text);
      if (decoded is! Map) continue;
      // Only explicitly scoped note payloads are inspected. We deliberately
      // do not recursively scan the complete app state, which also contains
      // recommendations, avatars and unrelated feed videos.
      final note = decoded['note'] ?? decoded['noteDetail'];
      if (note is! Map) continue;
      final rawImages = note['imageList'] ?? note['images'];
      if (rawImages is List) {
        for (final raw in rawImages) {
          final value = raw is String
              ? raw
              : raw is Map
                  ? raw['urlDefault'] ?? raw['originalUrl'] ?? raw['url']
                  : null;
          if (value is String && value.trim().isNotEmpty) {
            images.add(value.trim());
          }
        }
      }
      final video = note['video'];
      hasVideo = hasVideo ||
          (video is Map && video.isNotEmpty) ||
          (video is String && video.trim().isNotEmpty);
    } catch (_) {
      // Malformed/unexpected state is ignored rather than broadening the DOM
      // fallback to unrelated whole-page media.
    }
  }
  return _StructuredNoteMedia(imageUrls: images, hasVideo: hasVideo);
}

String? _imageUrl(dom.Element image) {
  for (final key in const ['data-src', 'data-original-src', 'src']) {
    final value = _clean(image.attributes[key]);
    if (value != null) return value;
  }
  return null;
}

List<XiaohongshuPublicComment> _collectComments(
  dom.Document document,
  String sourceUrl,
) {
  const containerSelectors = <String>[
    '.comments-container',
    '[data-testid="comments-container"]',
  ];
  final nodes = <(dom.Element, String)>[];
  final seenNodes = <dom.Element>{};
  for (final containerSelector in containerSelectors) {
    for (final container in document.querySelectorAll(containerSelector)) {
      for (final node in container.querySelectorAll(
        '.comment-item, [data-testid="comment"]',
      )) {
        if (seenNodes.add(node)) {
          nodes.add((node, '$containerSelector > comment'));
        }
      }
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
