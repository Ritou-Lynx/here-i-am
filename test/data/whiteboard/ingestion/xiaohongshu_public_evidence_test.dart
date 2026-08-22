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
}
