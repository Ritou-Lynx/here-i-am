import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/whiteboard/ingestion/url_canonicalizer.dart';

void main() {
  group('URL canonicalizer', () {
    test('normalizes https URL with trailing params', () {
      final c = canonicalizeUrl(
          'HTTPS://Example.COM/path/?utm_source=x&b=2&a=1#frag');
      expect(c, isNotNull);
      expect(c!.scheme, 'https');
      expect(c.host, 'example.com');
      // utm_source stripped, query sorted
      expect(c.normalized, contains('a=1'));
      expect(c.normalized, contains('b=2'));
      expect(c.normalized, isNot(contains('utm_source')));
      expect(c.normalized, isNot(contains('#frag')));
      expect(c.provider, 'web');
    });

    test('strips default port 443', () {
      final c = canonicalizeUrl('https://example.com:443/path');
      expect(c, isNotNull);
      expect(c!.normalized, isNot(contains(':443')));
    });

    test('preserves non-default port', () {
      final c = canonicalizeUrl('https://example.com:8443/path');
      expect(c, isNotNull);
      expect(c!.normalized, contains(':8443'));
    });

    test('rejects non-http schemes', () {
      expect(canonicalizeUrl('file:///etc/passwd'), isNull);
      expect(canonicalizeUrl('ftp://example.com'), isNull);
      expect(canonicalizeUrl('javascript:alert(1)'), isNull);
    });

    test('rejects empty and malformed', () {
      expect(canonicalizeUrl(''), isNull);
      expect(canonicalizeUrl('   '), isNull);
      const notUrl = 'not a url';
      expect(canonicalizeUrl(notUrl), isNull);
      expect(canonicalizeUrl('://no-scheme'), isNull);
    });

    test('preserves original url verbatim', () {
      const raw = 'https://Example.COM/Path?X=1';
      final c = canonicalizeUrl(raw);
      expect(c, isNotNull);
      expect(c!.original, raw);
    });
  });

  group('provider identification', () {
    test('bilibili BV id', () {
      final c = canonicalizeUrl('https://www.bilibili.com/video/BV1xx411c7mD');
      expect(c, isNotNull);
      expect(c!.provider, 'bilibili');
      expect(c.canonicalId, 'BV1xx411c7mD');
    });

    test('desktop bilibili share URL keeps its stable BV id', () {
      final c = canonicalizeUrl(
        'https://www.bilibili.com/video/BV1E8KV6QEu7/?spm_id_from=333.1387.upload.video_card.click&vd_source=share-source',
      );
      expect(c, isNotNull);
      expect(c!.provider, 'bilibili');
      expect(c.canonicalId, 'BV1E8KV6QEu7');
    });

    test('bilibili short link', () {
      final c = canonicalizeUrl('https://b23.tv/abc123');
      expect(c, isNotNull);
      expect(c!.provider, 'bilibili');
      expect(c.canonicalId, 'b23:abc123');
    });

    test('xiaohongshu note id', () {
      final c = canonicalizeUrl(
          'https://www.xiaohongshu.com/explore/65f0a1b2c3d4e5f6a7b8c9d0');
      expect(c, isNotNull);
      expect(c!.provider, 'xiaohongshu');
      expect(c.canonicalId, '65f0a1b2c3d4e5f6a7b8c9d0');
    });

    test('desktop xiaohongshu share URL keeps its note id', () {
      final c = canonicalizeUrl(
        'https://www.xiaohongshu.com/discovery/item/6a8881480000000018019591?source=webshare&xhsshare=pc_web&xsec_token=REDACTED&xsec_source=pc_share',
      );
      expect(c, isNotNull);
      expect(c!.provider, 'xiaohongshu');
      expect(c.canonicalId, '6a8881480000000018019591');
    });

    test('youtube watch v', () {
      final c = canonicalizeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(c, isNotNull);
      expect(c!.provider, 'youtube');
      expect(c.canonicalId, 'dQw4w9WgXcQ');
    });

    test('youtube youtu.be', () {
      final c = canonicalizeUrl('https://youtu.be/dQw4w9WgXcQ');
      expect(c, isNotNull);
      expect(c!.provider, 'youtube');
      expect(c.canonicalId, 'dQw4w9WgXcQ');
    });

    test('equivalent YouTube URL shapes share one canonical video id', () {
      const urls = [
        'https://www.youtube.com/watch?v=M7lc1UVf-VE',
        'https://www.youtube.com/watch?v=M7lc1UVf-VE&t=43s&si=share-token',
        'https://youtu.be/M7lc1UVf-VE?si=share-token&t=43',
        'https://www.youtube.com/shorts/M7lc1UVf-VE?si=share-token',
      ];

      final ids = urls.map((url) => canonicalizeUrl(url)!.canonicalId).toSet();
      expect(ids, {'M7lc1UVf-VE'});
    });

    test('wechat mp with biz+mid', () {
      final c =
          canonicalizeUrl('https://mp.weixin.qq.com/s?__biz=abc&mid=123&idx=1');
      expect(c, isNotNull);
      expect(c!.provider, 'wechat_mp');
      expect(c.canonicalId, 'wx:abc:123:1');
    });

    test('generic web has no canonicalId', () {
      final c = canonicalizeUrl('https://blog.example.com/post/42');
      expect(c, isNotNull);
      expect(c!.provider, 'web');
      expect(c.canonicalId, isNull);
    });
  });

  group('tracking param stripping', () {
    test('removes all known tracking params', () {
      final c = canonicalizeUrl(
          'https://example.com/p?utm_source=x&utm_medium=y&fbclid=z&gclid=w&keep=this');
      expect(c, isNotNull);
      expect(c!.normalized, contains('keep=this'));
      expect(c.normalized, isNot(contains('utm_')));
      expect(c.normalized, isNot(contains('fbclid')));
      expect(c.normalized, isNot(contains('gclid')));
    });
  });
}
