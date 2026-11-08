import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/call_engine_settings.dart';
import 'package:memex/data/services/gpt_live/gpt_live_call.dart';
import 'package:memex/data/services/gpt_live/gpt_live_protocol.dart';
import 'package:memex/data/services/sleep_nudge/sleep_nudge_policy.dart';

void main() {
  final now = DateTime(2026, 11, 8, 1, 30);
  NtfyMessage msg(DateTime t, [String body = '01:29 检测到睁眼']) => NtfyMessage(
      id: 'id${t.millisecondsSinceEpoch}',
      time: t,
      title: '林埃来电',
      message: body);
  const config = SleepNudgeConfig(enabled: true, topic: 't');

  group('pollUri', () {
    test('builds poll url with encoded topic and since', () {
      final uri = SleepNudgePolicy.pollUri('https://ntfy.sh/', 'a b', 'abc')!;
      expect(uri.toString(), 'https://ntfy.sh/a%20b/json?poll=1&since=abc');
    });
    test('rejects non-https, credentials, empty or slashed topic', () {
      expect(SleepNudgePolicy.pollUri('http://ntfy.sh', 't', null), isNull);
      expect(
          SleepNudgePolicy.pollUri('https://u:p@ntfy.sh', 't', null), isNull);
      expect(SleepNudgePolicy.pollUri('https://ntfy.sh', ' ', null), isNull);
      expect(SleepNudgePolicy.pollUri('https://ntfy.sh', 'a/b', null), isNull);
    });
    test('config.ready needs enabled + valid topic', () {
      expect(config.ready, isTrue);
      expect(const SleepNudgeConfig(topic: 't').ready, isFalse);
      expect(const SleepNudgeConfig(enabled: true).ready, isFalse);
    });
  });

  test('parseLines keeps message events only, sorted, skips junk', () {
    final body = [
      jsonEncode({
        'id': 'b',
        'time': 200,
        'event': 'message',
        'title': '林埃来电',
        'message': '醒着'
      }),
      jsonEncode({'id': 'k', 'time': 150, 'event': 'keepalive'}),
      'not json',
      jsonEncode({'id': 'a', 'time': 100, 'event': 'message'}),
      '',
    ].join('\n');
    final out = SleepNudgePolicy.parseLines(body);
    expect(out.map((m) => m.id), ['a', 'b']);
    expect(out.last.message, '醒着');
    expect(out.first.message, '');
  });

  group('decide', () {
    test('rings on fresh message', () {
      final d = SleepNudgePolicy.decide(
        messages: [msg(now.subtract(const Duration(seconds: 20)))],
        now: now,
        config: config,
        history: const SleepNudgeHistory(),
      );
      expect(d, isA<SleepNudgeRing>());
    });
    test('skips stale, ringing, min gap and night cap', () {
      String reason(SleepNudgeDecision d) => (d as SleepNudgeSkip).reason;
      final fresh = [msg(now)];
      expect(
          reason(SleepNudgePolicy.decide(
              messages: [msg(now.subtract(const Duration(minutes: 6)))],
              now: now,
              config: config,
              history: const SleepNudgeHistory())),
          'stale');
      expect(
          reason(SleepNudgePolicy.decide(
              messages: fresh,
              now: now,
              config: config,
              history: const SleepNudgeHistory(),
              callAlreadyRinging: true)),
          'already_ringing');
      expect(
          reason(SleepNudgePolicy.decide(
              messages: fresh,
              now: now,
              config: config,
              history: SleepNudgeHistory(
                  lastCallAt: now.subtract(const Duration(minutes: 10))))),
          'min_gap');
      expect(
          reason(SleepNudgePolicy.decide(
              messages: fresh,
              now: now,
              config: config,
              history: SleepNudgeHistory(
                  nightKey: SleepNudgePolicy.nightKeyOf(now), nightCount: 4))),
          'night_cap');
      expect(
          SleepNudgePolicy.decide(
              messages: const [],
              now: now,
              config: config,
              history: const SleepNudgeHistory()),
          isA<SleepNudgeSkip>());
    });
    test('ignores shared-topic pushes without the call keyword', () {
      final other =
          NtfyMessage(id: 'x', time: now, title: '林埃', message: '中午没吃饭哦');
      expect(
          (SleepNudgePolicy.decide(
                  messages: [other],
                  now: now,
                  config: config,
                  history: const SleepNudgeHistory()) as SleepNudgeSkip)
              .reason,
          'no_message');
      // 关键词在正文里也认；混在一起时取最新的来电消息。
      final inBody = NtfyMessage(
          id: 'y',
          time: now.subtract(const Duration(seconds: 30)),
          message: '林埃来电：醒着');
      final d = SleepNudgePolicy.decide(
          messages: [inBody, other],
          now: now,
          config: config,
          history: const SleepNudgeHistory());
      expect((d as SleepNudgeRing).message.id, 'y');
    });
    test('last night count does not block tonight', () {
      final d = SleepNudgePolicy.decide(
        messages: [msg(now)],
        now: now,
        config: config,
        history: const SleepNudgeHistory(nightKey: '2026-11-01', nightCount: 9),
      );
      expect(d, isA<SleepNudgeRing>());
    });
  });

  test('night key spans midnight; afterRing counts per night', () {
    expect(SleepNudgePolicy.nightKeyOf(DateTime(2026, 11, 7, 23)),
        SleepNudgePolicy.nightKeyOf(DateTime(2026, 11, 8, 3)));
    expect(SleepNudgePolicy.nightKeyOf(DateTime(2026, 11, 8, 13)),
        isNot(SleepNudgePolicy.nightKeyOf(DateTime(2026, 11, 8, 3))));
    var h = SleepNudgePolicy.afterRing(const SleepNudgeHistory(), now);
    h = SleepNudgePolicy.afterRing(h, now.add(const Duration(minutes: 30)));
    expect(h.nightCount, 2);
    h = SleepNudgePolicy.afterRing(h, DateTime(2026, 11, 9, 1));
    expect(h.nightCount, 1);
  });

  test('opening carries reason and nth call', () {
    expect(SleepNudgePolicy.openingFor(msg(now, '睁眼'), nightCount: 1), '睁眼');
    expect(SleepNudgePolicy.openingFor(msg(now, ''), nightCount: 2),
        startsWith('这是今晚第 2 通。'));
    expect(CallEngine.parse('classic'), CallEngine.classic);
    expect(CallEngine.parse(null), CallEngine.gptLive);
  });

  group('GPT-Live nudge', () {
    test('instructions include call section only with reason', () {
      final plain =
          GptLiveCall.buildInstructions(name: '林埃', persona: 'p', now: now);
      final nudge = GptLiveCall.buildInstructions(
          name: '林埃', persona: 'p', now: now, callReason: '01:29 检测到睁眼');
      expect(plain, isNot(contains('## 这通电话')));
      expect(nudge, contains('## 这通电话'));
      expect(nudge, contains('01:29 检测到睁眼'));
    });
    test('commentary event shape', () {
      final json = jsonDecode(GptLiveProtocol.commentaryEvent(
          GptLiveProtocol.nudgeGreeting('睁眼'))) as Map;
      expect(json['type'], 'session.commentary.append');
      expect(json.containsKey('delegation_id'), isTrue);
      expect(json['delegation_id'], isNull);
      expect(json['content'], contains('先开口'));
    });
    test('developer greeting survives history trim as last item', () {
      final req = GptLiveProtocol.buildSessionRequest(
        offerSdp: 'sdp',
        instructions: 'x',
        history: [
          const GptLiveHistoryMessage('user', 'hi'),
          GptLiveHistoryMessage(
              'developer', GptLiveProtocol.nudgeGreeting('r')),
        ],
      );
      final input = (req['session'] as Map)['input'] as List;
      expect((input.last as Map)['role'], 'developer');
    });
  });
}
