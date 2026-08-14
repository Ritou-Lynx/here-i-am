import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/whiteboard/ingestion/html_page_parser.dart';

String _fixture(String name) =>
    File('test/data/whiteboard/ingestion/fixtures/$name').readAsStringSync();

void main() {
  group('HTML page parser', () {
    test('open_graph.html extracts OG metadata', () {
      final html = _fixture('open_graph.html');
      final parsed = parseHtmlPage(html, sourceUrl: 'https://example.com/doc');

      expect(parsed.title, '春雨昼眠主题设计文档');
      expect(parsed.description, contains('色板'));
      expect(parsed.ogImage, 'https://example.com/images/spring-rain.png');
      expect(parsed.siteName, '故我在设计站');
      expect(parsed.author, '林埃');
      expect(parsed.bodyText, isNotNull);
      expect(parsed.bodyText, contains('Lieflat Mono'));
      expect(parsed.bodyText, contains('Palm 绿'));
      expect(parsed.bodyText, isNot(contains('analytics')));
      expect(parsed.bodyText, isNot(contains('导航菜单')));
      expect(parsed.imageUrls.length, 2);
      expect(parsed.imageUrls, contains('https://example.com/images/palette.png'));
    });

    test('plain_body.html extracts from title + meta description', () {
      final html = _fixture('plain_body.html');
      final parsed = parseHtmlPage(html);

      expect(parsed.title, 'A Plain Blog Post About Dart');
      expect(parsed.description, contains('simple blog post'));
      expect(parsed.ogImage, isNull);
      expect(parsed.bodyText, contains('sound null safety'));
      expect(parsed.bodyExcerpt, isNotNull);
      expect(parsed.bodyExcerpt!.length, lessThanOrEqualTo(501));
    });

    test('no_title.html returns empty-ish content', () {
      final html = _fixture('no_title.html');
      final parsed = parseHtmlPage(html);

      expect(parsed.title, isNull);
      expect(parsed.bodyText, isNotNull);
      expect(parsed.isEmpty, isFalse); // has body text
    });

    test('code blocks preserved as fenced markdown', () {
      final html = _fixture('open_graph.html');
      final parsed = parseHtmlPage(html);
      expect(parsed.bodyText, contains('```dart'));
      expect(parsed.bodyText, contains('Color(0xFFF0EFEB)'));
    });

    test('empty html returns empty ParsedPageContent', () {
      final parsed = parseHtmlPage('');
      expect(parsed.isEmpty, isTrue);
      expect(parsed.title, isNull);
    });

    test('garbage html does not crash', () {
      final parsed = parseHtmlPage('<<<not html>>>');
      expect(parsed, isNotNull);
    });

    test('parserVersion is set', () {
      expect(ParsedPageContent.parserVersion, startsWith('w3-html-parser'));
    });
  });
}