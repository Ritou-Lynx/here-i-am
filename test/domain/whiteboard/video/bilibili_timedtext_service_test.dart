import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:memex/domain/whiteboard/player_adapter.dart';
import 'package:memex/domain/whiteboard/video/bilibili_safe_http_transport.dart';
import 'package:memex/domain/whiteboard/video/bilibili_timedtext_service.dart';

class _FakeTransport implements BilibiliHttpTransport {
  _FakeTransport(this.responses);

  final List<FutureOr<Object?>> responses;
  final List<String> urls = [];
  final List<Map<String, String>?> headers = [];
  final List<int> maxByteBudgets = [];
  var _index = 0;
  var disposed = false;

  @override
  Future<BilibiliHttpFetchResult> getText(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async {
    urls.add(uri.toString());
    this.headers.add(headers);
    maxByteBudgets.add(maxBytes);
    if (_index >= responses.length) {
      return const BilibiliHttpFetchResult(
        failureKind: BilibiliHttpFailureKind.network,
      );
    }
    final value = await Future<Object?>.value(responses[_index++]);
    if (value is BilibiliHttpFetchResult) return value;
    if (value is String) return BilibiliHttpFetchResult(body: value);
    return const BilibiliHttpFetchResult(
      failureKind: BilibiliHttpFailureKind.network,
    );
  }

  @override
  void dispose() => disposed = true;
}

String _metadata({int cid = 22}) => jsonEncode({
      'code': 0,
      'data': {
        'aid': 11,
        'cid': 21,
        'pages': [
          {'page': 1, 'cid': 21},
          {'page': 2, 'cid': cid},
        ],
      },
    });

String _player({
  List<Map<String, Object?>> tracks = const [],
  bool needsLogin = false,
}) =>
    jsonEncode({
      'code': 0,
      'data': {
        'subtitle': {'need_login_subtitle': needsLogin, 'subtitles': tracks},
      },
    });

Map<String, Object?> _track({
  String language = 'ai-zh',
  String url = '//aisubtitle.hdslb.com/bcc/track.json?auth_key=secret',
  int type = 1,
}) =>
    {'lan': language, 'lan_doc': language, 'subtitle_url': url, 'type': type};

void main() {
  test('extracts a stable BV identity from supported link shapes', () {
    final service = BilibiliTimedTextService(transport: _FakeTransport([]));
    expect(
      service.extractBvid(
        'https://www.bilibili.com/video/BV1E8KV6QEu7/?spm_id_from=share',
      ),
      'BV1E8KV6QEu7',
    );
    expect(service.extractBvid('BV1E8KV6QEu7'), 'BV1E8KV6QEu7');
  });

  test(
    'loads anonymous BV metadata, selected page, track list and BCC cues',
    () async {
      const signedUrl =
          'https://aisubtitle.hdslb.com/bcc/track.json?auth_key=secret';
      final transport = _FakeTransport([
        _metadata(),
        _player(tracks: [_track()]),
        jsonEncode({
          'body': [
            {'from': 0.125, 'to': 1.75, 'content': ' 第一句 '},
            {'from': 1.75, 'to': 3.0, 'content': '第二句'},
          ],
        }),
      ]);
      final service = BilibiliTimedTextService(transport: transport);

      final result = await service.fetchForVideo(
        'https://www.bilibili.com/video/BV1E8KV6QEu7?p=2',
        sourceId: 'src_bili',
        sourceVersionId: 'ver_bili_v1',
      );

      expect(result.isSuccess, isTrue);
      expect(result.track!.sourceKind, TimedTextSourceKind.platform);
      expect(result.track!.sourceId, 'src_bili');
      expect(result.track!.sourceVersionId, 'ver_bili_v1');
      expect(result.track!.language, 'ai-zh');
      expect(result.track!.format, 'bcc-json');
      expect(result.track!.reliability, TimedTextReliability.partial);
      expect(result.track!.cues, hasLength(2));
      expect(result.track!.cues.first.startMs, 125);
      expect(result.track!.cues.first.endMs, 1750);
      expect(result.track!.cues.first.text, '第一句');
      expect(transport.urls[1], contains('cid=22'));
      expect(transport.urls.last, signedUrl);
      expect(
        transport.headers.every((headers) => !headers!.containsKey('Cookie')),
        isTrue,
      );
      expect(jsonEncode(result.track!.toJson()), isNot(contains('auth_key')));
      expect(jsonEncode(result.track!.toJson()), isNot(contains(signedUrl)));
    },
  );

  test('prefers a manual track in the preferred language', () async {
    final transport = _FakeTransport([
      _metadata(),
      _player(
        tracks: [
          _track(),
          _track(
            language: 'zh-CN',
            url: '//aisubtitle.hdslb.com/bcc/manual.json?token=short',
            type: 0,
          ),
        ],
      ),
      jsonEncode({
        'body': [
          {'from': 0, 'to': 1, 'content': '人工字幕'},
        ],
      }),
    ]);

    final result = await BilibiliTimedTextService(
      transport: transport,
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');

    expect(result.track!.language, 'zh-CN');
    expect(result.track!.reliability, TimedTextReliability.reliable);
    expect(transport.urls.last, contains('manual.json'));
  });

  test('keeps anonymous no-track and login-only visibility distinct', () async {
    final noTrack = await BilibiliTimedTextService(
      transport: _FakeTransport([_metadata(), _player()]),
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');
    final loginOnly = await BilibiliTimedTextService(
      transport: _FakeTransport([_metadata(), _player(needsLogin: true)]),
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');

    expect(noTrack.failureKind, BilibiliTimedTextFailureKind.noTrack);
    expect(noTrack.error, contains('SRT / VTT'));
    expect(
      loginOnly.failureKind,
      BilibiliTimedTextFailureKind.needsAuthorization,
    );
    expect(loginOnly.error, contains('匿名不可见'));
    expect(loginOnly.error, contains('不读取 Cookie'));
  });

  test('classifies invalid, permission, network and parser failures', () async {
    final invalid = await BilibiliTimedTextService(
      transport: _FakeTransport([]),
    ).fetchForVideo('not-a-video', sourceId: 'src');
    final permission = await BilibiliTimedTextService(
      transport: _FakeTransport([
        _metadata(),
        jsonEncode({'code': -403, 'message': '访问受限'}),
      ]),
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');
    final network = await BilibiliTimedTextService(
      transport: _FakeTransport([null]),
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');
    final parser = await BilibiliTimedTextService(
      transport: _FakeTransport(['not-json']),
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');

    expect(invalid.failureKind, BilibiliTimedTextFailureKind.invalidVideo);
    expect(
      permission.failureKind,
      BilibiliTimedTextFailureKind.needsAuthorization,
    );
    expect(network.failureKind, BilibiliTimedTextFailureKind.network);
    expect(parser.failureKind, BilibiliTimedTextFailureKind.parserFailure);
  });

  test('classifies oversized metadata and BCC before parsing', () async {
    const oversized = BilibiliHttpFetchResult(
      failureKind: BilibiliHttpFailureKind.responseTooLarge,
      message: 'too large',
    );
    final metadata = await BilibiliTimedTextService(
      transport: _FakeTransport([oversized]),
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');
    final bcc = await BilibiliTimedTextService(
      transport: _FakeTransport([
        _metadata(),
        _player(tracks: [_track()]),
        oversized,
      ]),
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');

    expect(
      metadata.failureKind,
      BilibiliTimedTextFailureKind.responseTooLarge,
    );
    expect(metadata.error, contains('视频元数据'));
    expect(bcc.failureKind, BilibiliTimedTextFailureKind.responseTooLarge);
    expect(bcc.error, contains('字幕内容'));
  });

  test('rejects excess cue count, single cue text and total text budget',
      () async {
    Future<BilibiliTimedTextResult> fetchWithBody(
      List<Map<String, Object>> body, {
      int maxCueCount = 10,
      int maxCueTextChars = 10,
      int maxTotalTextChars = 20,
    }) =>
        BilibiliTimedTextService(
          transport: _FakeTransport([
            _metadata(),
            _player(tracks: [_track()]),
            jsonEncode({'body': body}),
          ]),
          maxCueCount: maxCueCount,
          maxCueTextChars: maxCueTextChars,
          maxTotalTextChars: maxTotalTextChars,
        ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');

    final excessCues = await fetchWithBody(
      [
        {'from': 0, 'to': 1, 'content': '一'},
        {'from': 1, 'to': 2, 'content': '二'},
      ],
      maxCueCount: 1,
    );
    final longCue = await fetchWithBody(
      [
        {'from': 0, 'to': 1, 'content': '12345'},
      ],
      maxCueTextChars: 4,
    );
    final excessTotal = await fetchWithBody(
      [
        {'from': 0, 'to': 1, 'content': '123'},
        {'from': 1, 'to': 2, 'content': '456'},
      ],
      maxTotalTextChars: 5,
    );

    for (final result in [excessCues, longCue, excessTotal]) {
      expect(result.track, isNull);
      expect(
        result.failureKind,
        BilibiliTimedTextFailureKind.responseTooLarge,
      );
      expect(result.error, contains('安全预算'));
    }
  });

  test('rejects an untrusted subtitle host as a parser failure', () async {
    final result = await BilibiliTimedTextService(
      transport: _FakeTransport([
        _metadata(),
        _player(
          tracks: [_track(url: 'https://example.com/private?auth_key=secret')],
        ),
      ]),
    ).fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');

    expect(result.failureKind, BilibiliTimedTextFailureKind.parserFailure);
    expect(result.error, isNot(contains('auth_key')));
  });

  test(
    'dispose prevents a late response from becoming a usable track',
    () async {
      final metadata = Completer<String?>();
      final service = BilibiliTimedTextService(
        transport: _FakeTransport([metadata.future]),
      );
      final pending = service.fetchForVideo('BV1E8KV6QEu7', sourceId: 'src');

      service.dispose();
      metadata.complete(_metadata());
      final result = await pending;

      expect((service.transport as _FakeTransport).disposed, isTrue);
      expect(result.track, isNull);
      expect(result.failureKind, BilibiliTimedTextFailureKind.network);
      expect(result.error, contains('已结束'));
    },
  );
}
