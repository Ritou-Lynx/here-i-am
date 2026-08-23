import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/video/windows_bilibili_player_adapter.dart';

void main() {
  test('extracts the Wave 3 acceptance BV id from canonical forms', () {
    expect(
      WindowsBilibiliPlayerAdapter.extractBvid('BV1E8KV6QEu7'),
      'BV1E8KV6QEu7',
    );
    expect(
      WindowsBilibiliPlayerAdapter.extractBvid(
        'https://www.bilibili.com/video/BV1E8KV6QEu7?spm_id_from=333',
      ),
      'BV1E8KV6QEu7',
    );
    expect(WindowsBilibiliPlayerAdapter.extractBvid('https://example.com'),
        isNull);
  });

  test('builds a platform player URL without download or login parameters',
      () {
    final uri = Uri.parse(
      WindowsBilibiliPlayerAdapter.buildEmbedUrl('BV1E8KV6QEu7'),
    );
    expect(uri.host, 'player.bilibili.com');
    expect(uri.queryParameters['bvid'], 'BV1E8KV6QEu7');
    expect(uri.queryParameters['autoplay'], '0');
    expect(uri.queryParameters, isNot(contains('download')));
    expect(uri.queryParameters, isNot(contains('token')));
  });
}
