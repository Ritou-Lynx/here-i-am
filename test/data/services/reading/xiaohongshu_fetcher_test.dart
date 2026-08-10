import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/reading/fetchers/xiaohongshu_fetcher.dart';
import 'package:memex/data/services/reading/xhs/xhs_hidden_webview_host.dart';

void main() {
  group('buildXiaohongshuContent', () {
    test('appends nickname and text for at most ten comments', () {
      final comments = List.generate(
        12,
        (index) => XhsRawComment(
          nickname: ' 用户 ${index + 1} ',
          content: '第 ${index + 1} 条\n评论',
        ),
      );

      final content = buildXiaohongshuContent(
        body: '笔记正文',
        comments: comments,
      );

      expect(content, startsWith('笔记正文\n\n---\n评论区（前 10 条）：'));
      expect(content, contains('1. 用户 1：第 1 条 评论'));
      expect(content, contains('10. 用户 10：第 10 条 评论'));
      expect(content, isNot(contains('用户 11')));
    });

    test('supports comment-only notes and drops blank comments', () {
      final content = buildXiaohongshuContent(
        body: '   ',
        comments: const [
          XhsRawComment(nickname: '小雨', content: '很有用'),
          XhsRawComment(nickname: '', content: '不应保留'),
          XhsRawComment(nickname: '空内容', content: '  '),
        ],
      );

      expect(content, '---\n评论区（前 1 条）：\n1. 小雨：很有用');
    });

    test('keeps the original body unchanged when there are no comments', () {
      expect(
        buildXiaohongshuContent(body: '  原文内容  ', comments: const []),
        '原文内容',
      );
    });
  });
}
