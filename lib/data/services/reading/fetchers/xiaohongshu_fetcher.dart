import 'package:logging/logging.dart';

import 'package:memex/data/services/reading/fetchers/reading_fetcher.dart';
import 'package:memex/data/services/reading/xhs/xhs_cookie_repository.dart';
import 'package:memex/data/services/reading/xhs/xhs_hidden_webview_host.dart';
import 'package:memex/utils/logger.dart';

/// Reading fetcher for 小红书 notes.
///
/// Delegates to [XhsHiddenWebViewHost.fetch] — that widget owns a hidden
/// WebView that handles login persistence, anti-bot stealth, and the
/// JS-side DOM extractor. This file is just the adapter that translates
/// [XhsRawContent] into a [ReadingFetchResult].
///
/// The fetcher is only registered with ReadingFetchCoordinator after the
/// cookie probe confirms a live login session — otherwise navigating to
/// the note URL would land on the login wall and we'd waste a request.
class XiaohongshuFetcher implements ReadingFetcher {
  XiaohongshuFetcher();

  final Logger _logger = getLogger('XiaohongshuFetcher');

  @override
  String get platform => 'xiaohongshu';

  @override
  Future<ReadingFetchResult> fetch(String url) async {
    // Short-circuit when the user hasn't connected a 小红书 account yet:
    // navigating to a note URL without a session would land on the login
    // wall and waste 12s before timing out. Surface the precise reason so
    // the LLM / UI can prompt the user to connect.
    if (!XhsCookieRepository.instance.isLoggedIn.value) {
      return const ReadingFetchResult.failure(
        '尚未连接小红书账号，去「设置」连接后即可自动抓取',
      );
    }
    try {
      final raw = await XhsHiddenWebViewHost.fetch(url);
      if (!raw.success) {
        return ReadingFetchResult.failure(
          raw.errorMessage ?? 'XHS fetch failed',
        );
      }
      if ((raw.title == null || raw.title!.isEmpty) &&
          (raw.contentFull == null || raw.contentFull!.isEmpty) &&
          raw.comments.isEmpty) {
        return const ReadingFetchResult.failure(
          'XHS note returned empty content (login expired? note deleted?)',
        );
      }
      final contentFull = buildXiaohongshuContent(
        body: raw.contentFull,
        comments: raw.comments,
      );
      return ReadingFetchResult(
        success: true,
        title: raw.title,
        author: raw.author,
        coverUrl: raw.coverUrl,
        imageUrls: raw.imageUrls,
        contentExcerpt: buildContentExcerpt(contentFull),
        contentFull: contentFull,
      );
    } catch (e, stack) {
      _logger.warning('XHS fetch crashed', e, stack);
      return ReadingFetchResult.failure('XHS fetch crashed: $e');
    }
  }
}

/// Combines the note description with the first visible top-level comments.
/// Comment images and nested replies never enter this representation.
String? buildXiaohongshuContent({
  required String? body,
  required List<XhsRawComment> comments,
}) {
  final cleanBody = body?.trim();
  final cleanComments = comments
      .where((comment) =>
          comment.nickname.trim().isNotEmpty &&
          comment.content.trim().isNotEmpty)
      .take(10)
      .toList(growable: false);
  if ((cleanBody == null || cleanBody.isEmpty) && cleanComments.isEmpty) {
    return null;
  }

  final buffer = StringBuffer();
  if (cleanBody != null && cleanBody.isNotEmpty) {
    buffer.write(cleanBody);
  }
  if (cleanComments.isNotEmpty) {
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.writeln('---');
    buffer.writeln('评论区（前 ${cleanComments.length} 条）：');
    for (var i = 0; i < cleanComments.length; i++) {
      final comment = cleanComments[i];
      final nickname = _collapseWhitespace(comment.nickname);
      final content = _collapseWhitespace(comment.content);
      buffer.writeln('${i + 1}. $nickname：$content');
    }
  }
  return buffer.toString().trimRight();
}

String _collapseWhitespace(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();
