import 'package:flutter_test/flutter_test.dart';

import 'package:memex/data/whiteboard/ingestion/shared_link_input_parser.dart';

void main() {
  test('extracts a Xiaohongshu URL from the full desktop share copy', () {
    const input = '57 【我做了个「此地无银三百两」Skill - rm_rf | 小红书 - '
        '你的生活兴趣社区】 😆 m34sB8YjLisVXDk 😆 '
        'https://www.xiaohongshu.com/discovery/item/'
        '6a8868500000000028027af2?source=webshare&xhsshare=pc_web'
        '&xsec_token=REDACTED='
        '&xsec_source=pc_share';

    final parsed = parseSharedLinkInput(input);

    expect(parsed, isNotNull);
    expect(parsed!.urls, hasLength(1));
    expect(
      parsed.preferredUrl,
      startsWith(
        'https://www.xiaohongshu.com/discovery/item/'
        '6a8868500000000028027af2',
      ),
    );
    expect(parsed.platform, 'xiaohongshu');
    expect(parsed.sharedTitle, contains('此地无银三百两'));
  });

  test('normalizes escaped ampersands copied from Markdown', () {
    final parsed = parseSharedLinkInput(
      r'说明 https://example.com/page?a=1\&b=2。',
    );

    expect(parsed!.preferredUrl, 'https://example.com/page?a=1&b=2');
  });

  test('discovers and deduplicates multiple links in clipboard order', () {
    final parsed = parseSharedLinkInput(
      '正文 https://example.com/a，备选 https://example.com/b；'
      '重复 https://example.com/a',
    );

    expect(parsed!.urls, [
      'https://example.com/a',
      'https://example.com/b',
    ]);
  });

  test('rejects prose without an HTTP(S) link', () {
    expect(parseSharedLinkInput('只有分享文案，没有链接'), isNull);
  });
}
