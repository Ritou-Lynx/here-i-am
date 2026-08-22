import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/whiteboard/ingestion/html_page_parser.dart';
import 'package:memex/data/whiteboard/ingestion/xiaohongshu_public_evidence.dart';

String _fixture(String name) =>
    File('test/data/whiteboard/ingestion/fixtures/$name').readAsStringSync();

void main() {
  test('public image note keeps ordered media and comment provenance', () {
    final html = _fixture('xiaohongshu_public_image_note.html');
    final page = parseHtmlPage(
      html,
      sourceUrl: 'https://www.xiaohongshu.com/explore/public-note',
    );
    final evidence = parseXiaohongshuPublicEvidence(
      html,
      sourceUrl: 'https://www.xiaohongshu.com/explore/public-note',
      parsedPage: page,
    );

    expect(evidence.noteKind, XiaohongshuNoteKind.image);
    expect(evidence.mediaCandidates.map((item) => item.originalUrl), [
      'https://sns-img.example/first.png',
      'https://sns-img.example/cover.png',
    ]);
    expect(evidence.mediaCandidates.map((item) => item.order), [0, 1]);
    expect(evidence.comments, hasLength(2));
    expect(evidence.comments.first.author, '小雨');
    expect(evidence.comments.first.text, '这条评论公开可见');
    expect(
      evidence.comments.first.publishedAt,
      DateTime.utc(2026, 8, 20, 3, 4, 5),
    );
    expect(evidence.comments.first.toJson()['access'], 'anonymous_public_page');
    expect(
      evidence.comments.first.sourceUrl,
      'https://www.xiaohongshu.com/explore/public-note',
    );
    expect(evidence.comments[1].publishedAt, isNull);
    expect(evidence.comments[1].publishedAtRaw, '昨天');
  });

  test('video note is capability evidence and not an image note', () {
    final html = _fixture('xiaohongshu_public_video_note.html');
    final page = parseHtmlPage(html);
    final evidence = parseXiaohongshuPublicEvidence(
      html,
      sourceUrl: 'https://www.xiaohongshu.com/explore/video-note',
      parsedPage: page,
    );

    expect(evidence.noteKind, XiaohongshuNoteKind.video);
    expect(evidence.mediaCandidates, hasLength(1));
  });

  test('recommendations, avatars and site OG are not note media', () {
    const html = '''
      <meta property="og:image" content="https://site.example/share.png">
      <main data-testid="note-content"><p>纯文字笔记</p></main>
      <aside><video src="https://site.example/recommend.mp4"></video></aside>
      <section class="comments-container">
        <div class="comment-item"><span class="author">甲</span>
          <span class="comment-content">评论</span>
          <img src="https://site.example/avatar-user.png"></div>
      </section>
    ''';
    final page = parseHtmlPage(html);
    final evidence = parseXiaohongshuPublicEvidence(
      html,
      sourceUrl: 'https://www.xiaohongshu.com/explore/text-note',
      parsedPage: page,
    );
    expect(evidence.noteKind, XiaohongshuNoteKind.text);
    expect(evidence.mediaCandidates, hasLength(1));
    expect(evidence.mediaCandidates.single.source, 'og_image');
    expect(evidence.mediaCandidates.single.confidence, 'low');
  });

  test('body content outside a comments container is never a comment', () {
    const html = '''
      <article class="comment">
        <span class="author">正文作者</span>
        <div class="content">这是正文，不是评论</div>
      </article>
      <section class="comments-container">
        <div class="comment-item">
          <span class="author">评论者</span>
          <div class="content">宽泛 content 也不应被采集</div>
        </div>
      </section>
    ''';
    final evidence = parseXiaohongshuPublicEvidence(
      html,
      sourceUrl: 'https://www.xiaohongshu.com/explore/note',
      parsedPage: parseHtmlPage(html),
    );
    expect(evidence.comments, isEmpty);
  });

  test('limited structured note state keeps note media but ignores feed', () {
    const html = '''
      <script id="xhs-note-state" data-xhs-note-state type="application/json">
        {"note":{"imageList":[{"urlDefault":"https://img.example/note.png"}]},
         "feed":{"video":{"url":"https://media.example/recommend.mp4"},
                  "images":["https://img.example/recommend.png"]}}
      </script>
      <main><p>客户端壳正文</p></main>
    ''';
    final evidence = parseXiaohongshuPublicEvidence(
      html,
      sourceUrl: 'https://www.xiaohongshu.com/explore/structured-note',
      parsedPage: parseHtmlPage(html),
    );
    expect(evidence.noteKind, XiaohongshuNoteKind.image);
    expect(evidence.mediaCandidates.map((item) => item.originalUrl), [
      'https://img.example/note.png',
    ]);
  });
}
