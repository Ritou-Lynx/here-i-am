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

  test('builds the top-level video URL without download or login parameters',
      () {
    final uri = Uri.parse(
      WindowsBilibiliPlayerAdapter.buildVideoPageUrl('BV1E8KV6QEu7'),
    );
    expect(uri.host, 'www.bilibili.com');
    expect(uri.path, '/video/BV1E8KV6QEu7');
    expect(uri.queryParameters, isNot(contains('download')));
    expect(uri.queryParameters, isNot(contains('token')));
  });

  test('decodes candidate and time messages emitted as JSON strings', () {
    expect(
      WindowsBilibiliPlayerAdapter.decodeWebMessage(
        '{"type":"hereiam:bilibili-media","event":"candidate"}',
      ),
      <String, dynamic>{
        'type': 'hereiam:bilibili-media',
        'event': 'candidate',
      },
    );
    expect(
      WindowsBilibiliPlayerAdapter.decodeWebMessage(
        '{"type":"hereiam:bilibili-media","event":"time",'
        '"position_ms":1200,"duration_ms":6400}',
      ),
      <String, dynamic>{
        'type': 'hereiam:bilibili-media',
        'event': 'time',
        'position_ms': 1200,
        'duration_ms': 6400,
      },
    );
  });

  test('malformed WebView messages fail closed', () {
    expect(
      WindowsBilibiliPlayerAdapter.decodeWebMessage('{not-json'),
      isNull,
    );
    expect(
      WindowsBilibiliPlayerAdapter.decodeWebMessage('["candidate"]'),
      isNull,
    );
    expect(
      WindowsBilibiliPlayerAdapter.decodeWebMessage(<Object?, Object?>{
        'type': 'hereiam:bilibili-media',
        1: 'non-string-key',
      }),
      isNull,
    );
  });
}
