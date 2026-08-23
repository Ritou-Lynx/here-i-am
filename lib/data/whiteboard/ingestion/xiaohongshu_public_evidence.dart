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
    required this.noteLocated,
    this.limitationCode,
    this.limitationReason,
  });

  static const currentParserVersion = 'xhs-public-evidence-v3';

  final XiaohongshuNoteKind noteKind;
  final List<XiaohongshuMediaCandidate> mediaCandidates;
  final List<XiaohongshuPublicComment> comments;
  final String parserVersion;
  final bool noteLocated;
  final String? limitationCode;
  final String? limitationReason;
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
  final structured = _structuredNoteMedia(document, sourceUrl);
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
    noteLocated: noteRoot != null || structured.noteLocated,
    limitationCode: noteRoot != null || structured.noteLocated
        ? null
        : structured.initialStateLocated
            ? 'note_not_in_public_state'
            : 'public_note_payload_missing',
    limitationReason: noteRoot != null || structured.noteLocated
        ? null
        : structured.initialStateLocated
            ? '匿名页面已返回，但其中没有当前笔记的公开详情；链接可能缺少有效分享参数、已失效或受地区限制。'
            : '匿名页面没有提供可解析的笔记详情；页面可能需要动态加载或受到平台访问限制。',
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
  const _StructuredNoteMedia({
    this.imageUrls = const [],
    this.hasVideo = false,
    this.noteLocated = false,
    this.initialStateLocated = false,
  });

  final List<String> imageUrls;
  final bool hasVideo;
  final bool noteLocated;
  final bool initialStateLocated;
}

_StructuredNoteMedia _structuredNoteMedia(
  dom.Document document,
  String sourceUrl,
) {
  final images = <String>[];
  var hasVideo = false;
  var noteLocated = false;
  var initialStateLocated = false;
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
      noteLocated = true;
      images.addAll(_noteImageUrls(note));
      hasVideo = hasVideo || _noteHasVideo(note);
    } catch (_) {
      // Malformed/unexpected state is ignored rather than broadening the DOM
      // fallback to unrelated whole-page media.
    }
  }

  // Production note pages expose their SSR payload as a plain public
  // `window.__INITIAL_STATE__` script. Restrict traversal to the exact note
  // id from the requested URL: the same state also contains recommendations,
  // avatars and unrelated feed media which must never become evidence.
  final initialState = _readInitialState(document);
  if (initialState != null) {
    initialStateLocated = true;
    final note = _exactNoteFromInitialState(initialState, sourceUrl);
    if (note != null) {
      noteLocated = true;
      images.addAll(_noteImageUrls(note));
      hasVideo = hasVideo || _noteHasVideo(note);
    }
  }

  return _StructuredNoteMedia(
    imageUrls: images,
    hasVideo: hasVideo,
    noteLocated: noteLocated,
    initialStateLocated: initialStateLocated,
  );
}

Map<String, dynamic>? _readInitialState(dom.Document document) {
  for (final script in document.querySelectorAll('script')) {
    final text = script.text.trim();
    final marker = text.indexOf('window.__INITIAL_STATE__');
    if (marker < 0) continue;
    final equals = text.indexOf('=', marker);
    if (equals < 0) continue;
    var raw = text.substring(equals + 1).trim();
    if (raw.endsWith(';')) raw = raw.substring(0, raw.length - 1).trim();
    if (!raw.startsWith('{') || !raw.endsWith('}')) continue;
    try {
      final decoded = jsonDecode(_replaceUndefinedTokens(raw));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // An unexpected/new state encoding is a limitation, not permission to
      // recursively scan every script or all DOM images.
    }
  }
  return null;
}

String _replaceUndefinedTokens(String source) {
  final output = StringBuffer();
  var index = 0;
  var inString = false;
  var escaped = false;
  while (index < source.length) {
    final char = source[index];
    if (inString) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      index++;
      continue;
    }
    if (char == '"') {
      inString = true;
      output.write(char);
      index++;
      continue;
    }
    if (source.startsWith('undefined', index)) {
      final before = index == 0 ? '' : source[index - 1];
      final afterIndex = index + 'undefined'.length;
      final after = afterIndex >= source.length ? '' : source[afterIndex];
      final identifier = RegExp(r'[A-Za-z0-9_$]');
      if ((before.isEmpty || !identifier.hasMatch(before)) &&
          (after.isEmpty || !identifier.hasMatch(after))) {
        output.write('null');
        index = afterIndex;
        continue;
      }
    }
    output.write(char);
    index++;
  }
  return output.toString();
}

Map? _exactNoteFromInitialState(Map<String, dynamic> state, String sourceUrl) {
  final noteId = RegExp(
    r'/(?:explore|note|discovery/item)/([0-9a-f]{24})',
  ).firstMatch(Uri.tryParse(sourceUrl)?.path ?? '')?.group(1);
  if (noteId == null) return null;
  final noteState = state['note'];
  if (noteState is! Map) return null;
  final detailMap = noteState['noteDetailMap'];
  if (detailMap is! Map) return null;
  final exact = detailMap[noteId];
  if (exact is Map && exact['note'] is Map) return exact['note'] as Map;
  // Some SSR revisions key the map differently. A fallback is allowed only
  // when the payload itself carries the exact requested note id.
  for (final raw in detailMap.values.whereType<Map>()) {
    final note = raw['note'];
    if (note is! Map) continue;
    final candidateId = note['noteId'] ?? note['note_id'] ?? note['id'];
    if (candidateId == noteId) return note;
  }
  return null;
}

List<String> _noteImageUrls(Map note) {
  final result = <String>[];
  final rawImages = note['imageList'] ?? note['images'];
  if (rawImages is! List) return result;
  for (final raw in rawImages) {
    if (raw is String) {
      final value = _clean(raw);
      if (value != null) result.add(value);
      continue;
    }
    if (raw is! Map) continue;
    var directAdded = false;
    for (final key in const ['urlDefault', 'originalUrl', 'url', 'urlPre']) {
      final value = _clean(raw[key]?.toString());
      if (value != null) {
        result.add(value);
        directAdded = true;
        break;
      }
    }
    if (directAdded) continue;
    final infoList = raw['infoList'];
    if (infoList is List) {
      for (final info in infoList.whereType<Map>()) {
        final value = _clean((info['url'] ?? info['urlDefault'])?.toString());
        if (value != null) {
          result.add(value);
          break;
        }
      }
    }
  }
  return result;
}

bool _noteHasVideo(Map note) {
  final type = _clean(note['type']?.toString())?.toLowerCase();
  final video = note['video'];
  return type == 'video' ||
      (video is Map && video.isNotEmpty) ||
      (video is String && video.trim().isNotEmpty);
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
    '.comment-list',
  ];
  final nodes = <(dom.Element, String)>[];
  final seenNodes = <dom.Element>{};
  for (final containerSelector in containerSelectors) {
    for (final container in document.querySelectorAll(containerSelector)) {
      for (final node in container.querySelectorAll(
        '.parent-comment, .comment-item, [data-testid="comment"]',
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
          '.user-name',
          '.username',
          '[data-author]',
        ]) ??
        _clean(node.attributes['data-user-name']);
    final text = _firstText(node, const [
      '.comment-content',
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
    if (classes
        .any((value) => value == 'comment-item' || value == 'parent-comment')) {
      return true;
    }
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
