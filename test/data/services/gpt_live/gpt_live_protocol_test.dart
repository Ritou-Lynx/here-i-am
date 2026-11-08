import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/data/services/gpt_live/gpt_live_call.dart';
import 'package:memex/data/services/gpt_live/gpt_live_protocol.dart';
import 'package:memex/data/services/gpt_live/gpt_live_settings.dart';

void main() {
  group('buildSessionRequest', () {
    test('带人设、声音、历史和 SDP', () {
      final body = GptLiveProtocol.buildSessionRequest(
        offerSdp: 'v=0 offer',
        instructions: '你是林埃',
        voice: 'cedar',
        history: const [
          GptLiveHistoryMessage('user', '在吗'),
          GptLiveHistoryMessage('assistant', '在'),
        ],
      );
      final session = body['session'] as Map;
      expect(session['model'], 'gpt-live-1');
      expect(session['instructions'], '你是林埃');
      expect(session['audio'], {
        'output': {'voice': 'cedar'},
      });
      expect(session['input'], [
        {
          'type': 'message',
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': '在吗'},
          ],
        },
        {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': '在'},
          ],
        },
      ]);
      expect(body['transport'], {'type': 'webrtc', 'sdp': 'v=0 offer'});
    });

    test('不支持的声音名退回默认', () {
      expect(GptLiveProtocol.normalizeVoice(' Cedar '), 'cedar');
      expect(
        GptLiveProtocol.normalizeVoice('ember'),
        GptLiveProtocol.defaultVoice,
      );
      expect(
        GptLiveProtocol.normalizeVoice('hanul'),
        GptLiveProtocol.defaultVoice,
      );
    });

    test('没有历史时不带 input，超长人设被截断', () {
      final body = GptLiveProtocol.buildSessionRequest(
        offerSdp: 'sdp',
        instructions: 'a' * (GptLiveProtocol.maxInstructionChars + 50),
      );
      final session = body['session'] as Map;
      expect(session.containsKey('input'), isFalse);
      expect(
        (session['instructions'] as String).length,
        GptLiveProtocol.maxInstructionChars,
      );
    });
  });

  group('trimHistory', () {
    test('保留最近的、跳过空消息、保持正序', () {
      final history = [
        for (var i = 0; i < GptLiveProtocol.maxHistoryMessages + 10; i++)
          GptLiveHistoryMessage(i.isEven ? 'user' : 'assistant', 'm$i'),
        const GptLiveHistoryMessage('user', '   '),
      ];
      final kept = GptLiveProtocol.trimHistory(history);
      expect(kept.length, GptLiveProtocol.maxHistoryMessages);
      expect(kept.last.content, 'm${GptLiveProtocol.maxHistoryMessages + 9}');
      expect(kept.first.content, 'm10');
    });

    test('按总字数截断，丢掉最旧的', () {
      final long = 'x' * (GptLiveProtocol.maxHistoryChars - 10);
      final kept = GptLiveProtocol.trimHistory([
        const GptLiveHistoryMessage('user', '最旧的一条消息内容'),
        GptLiveHistoryMessage('assistant', long),
        const GptLiveHistoryMessage('user', '最新'),
      ]);
      expect(kept.map((m) => m.content), [long, '最新']);
    });
  });

  group('createSession', () {
    test('201 返回 answer SDP 和会话 id，带 Bearer key', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'session': {'id': 'sess_1'},
            'transport': {'type': 'webrtc', 'sdp': 'v=0 answer'},
          }),
          201,
        );
      });
      final created = await GptLiveProtocol.createSession(
        apiKey: 'k',
        body: {'session': {}},
        client: client,
      );
      expect(created.id, 'sess_1');
      expect(created.answerSdp, 'v=0 answer');
      expect(seen.url.toString(), GptLiveProtocol.endpoint);
      expect(seen.headers['Authorization'], 'Bearer k');
    });

    test('错误码带上服务端的错误信息', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'insufficient_quota'},
          }),
          429,
        ),
      );
      expect(
        () => GptLiveProtocol.createSession(
          apiKey: 'k',
          body: const {},
          client: client,
        ),
        throwsA(
          isA<GptLiveException>()
              .having((e) => e.code, 'code', 'http_429')
              .having((e) => e.detail, 'detail', 'insufficient_quota'),
        ),
      );
    });

    test('没有 SDP 时报 no_sdp', () async {
      final client = MockClient((_) async => http.Response('{}', 201));
      expect(
        () => GptLiveProtocol.createSession(
          apiKey: 'k',
          body: const {},
          client: client,
        ),
        throwsA(
          isA<GptLiveException>().having((e) => e.code, 'code', 'no_sdp'),
        ),
      );
    });
  });

  group('GptLiveEvent.parse', () {
    test('解析通话需要的事件', () {
      expect(
        GptLiveEvent.parse('{"type":"session.started"}'),
        isA<GptLiveStarted>(),
      );
      final user =
          GptLiveEvent.parse(
                '{"type":"session.input_transcript.delta","delta":"你好","start_ms":120}',
              )
              as GptLiveTranscriptDelta;
      expect(user.fromUser, isTrue);
      expect(user.delta, '你好');
      expect(user.startMs, 120);
      final ai =
          GptLiveEvent.parse(
                '{"type":"session.output_transcript.delta","delta":"嗯"}',
              )
              as GptLiveTranscriptDelta;
      expect(ai.fromUser, isFalse);
      expect(
        (GptLiveEvent.parse(
                  '{"type":"session.usage.updated","usage":{"seconds":42}}',
                )
                as GptLiveUsage)
            .seconds,
        42,
      );
      final closed =
          GptLiveEvent.parse(
                '{"type":"session.closed","reason":"expired","usage":{"seconds":3600}}',
              )
              as GptLiveClosed;
      expect(closed.reason, 'expired');
      expect(closed.seconds, 3600);
      final err =
          GptLiveEvent.parse(
                '{"type":"error","error":{"code":"bad","message":"oops"}}',
              )
              as GptLiveError;
      expect(err.code, 'bad');
      expect(err.message, 'oops');
    });

    test('未知事件和坏 JSON 返回 null', () {
      expect(
        GptLiveEvent.parse('{"type":"session.delegation.created"}'),
        isNull,
      );
      expect(GptLiveEvent.parse('not json'), isNull);
      expect(GptLiveEvent.parse('[1,2]'), isNull);
    });

    test('closeEvent', () {
      expect(jsonDecode(GptLiveProtocol.closeEvent()), {
        'type': 'session.close',
      });
    });
  });

  group('GptLiveTranscript', () {
    GptLiveTranscriptDelta d(bool user, String text) =>
        GptLiveTranscriptDelta(fromUser: user, delta: text);

    test('同一说话方的增量拼成一轮，换人开新轮', () {
      final t = GptLiveTranscript()
        ..add(d(true, '今天'))
        ..add(d(true, '好累'))
        ..add(d(false, '怎么了'))
        ..add(d(false, '？'))
        ..add(d(true, '加班'));
      expect(t.turns.map((e) => e.text.toString()), ['今天好累', '怎么了？', '加班']);
      expect(t.turns.map((e) => e.fromUser), [true, false, true]);
      expect(t.lastLine, '加班');
    });

    test('空增量忽略，空白轮不写回', () {
      final t = GptLiveTranscript()
        ..add(d(true, ''))
        ..add(d(false, '  '))
        ..add(d(true, '在'));
      expect(t.turns.length, 2);
      expect(t.finished.map((e) => e.text.toString()), ['在']);
    });
  });

  test('buildInstructions 带名字、人设和时间', () {
    final s = GptLiveCall.buildInstructions(
      name: '林埃',
      persona: '温柔',
      now: DateTime(2026, 11, 1, 9, 5),
    );
    expect(s, contains('你是林埃'));
    expect(s, contains('温柔'));
    expect(s, contains('2026-11-01 09:05'));
    expect(s, isNot(contains('用户补充说明')));
  });

  test('buildInstructions 把附加说明放在最后', () {
    final s = GptLiveCall.buildInstructions(
      name: '林埃',
      persona: '温柔',
      now: DateTime(2026, 11, 1, 9, 5),
      extra: '  叫我小橙  ',
    );
    expect(s.trimRight(), endsWith('## 用户补充说明\n叫我小橙'));
  });

  test('通话记录可存可读，原因文字可读', () {
    final r = GptLiveCallRecord(
      startedAt: DateTime(2026, 11, 7, 23, 5),
      seconds: 602,
      reason: 'server:max_session_duration',
      serverError: 'session_expired bye',
    );
    final back = GptLiveCallRecord.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
    expect(back.seconds, 602);
    expect(back.describe(), contains('10 分 2 秒'));
    expect(back.describe(), contains('OpenAI 结束了会话（max_session_duration）'));
    expect(back.describe(), contains('session_expired bye'));
    expect(
      GptLiveCallRecord(
        startedAt: DateTime(2026),
        seconds: 5,
        reason: 'user',
      ).reasonText,
      '你挂断',
    );
  });
}

