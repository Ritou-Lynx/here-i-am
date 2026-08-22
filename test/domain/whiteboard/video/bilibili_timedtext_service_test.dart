import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/video/bilibili_timedtext_service.dart';

void main() {
  const service = BilibiliTimedTextService();

  test('extracts a stable BV identity from supported link shapes', () {
    expect(
      service.extractBvid(
        'https://www.bilibili.com/video/BV1E8KV6QEu7/?spm_id_from=share',
      ),
      'BV1E8KV6QEu7',
    );
    expect(service.extractBvid('BV1E8KV6QEu7'), 'BV1E8KV6QEu7');
  });

  test(
    'invalid source is classified without attempting a login fallback',
    () async {
      final result = await service.fetchForVideo(
        'https://www.bilibili.com/video/not-a-bv',
        sourceId: 'src_bili_invalid',
      );

      expect(result.track, isNull);
      expect(result.failureKind, BilibiliTimedTextFailureKind.invalidVideo);
      expect(result.error, contains('来源无效'));
    },
  );

  test('public subtitle discovery is honestly unsupported', () async {
    final result = await service.fetchForVideo(
      'https://www.bilibili.com/video/BV1E8KV6QEu7',
      sourceId: 'src_bili_BV1E8KV6QEu7',
      sourceVersionId: 'ver_bili_v1',
    );

    expect(result.track, isNull);
    expect(result.failureKind, BilibiliTimedTextFailureKind.unsupported);
    expect(result.error, contains('未提供稳定公开'));
    expect(result.error, contains('不会读取嵌入页登录态'));
    expect(result.error, contains('SRT / VTT'));
  });
}
