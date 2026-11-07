import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/data/services/call_voice_session.dart';
import 'package:memex/data/services/callkit_service.dart';
import 'package:memex/data/services/character_service.dart';

import 'sleep_nudge_policy.dart';
import 'sleep_nudge_store.dart';

/// 常驻前台服务每个 tick 调一次：轮询 ntfy，有新的“林埃来电”就排待拨电话并响铃。
///
/// 和 check-in 开关无关：check-in 停了照样能催睡（待拨电话按非主动来电排队）。
class SleepNudgeService {
  SleepNudgeService._();
  static final SleepNudgeService instance = SleepNudgeService._();

  /// ntfy.sh 匿名限流约每 5 秒 1 次；常驻服务 15 秒一个 tick，这里再限到 30 秒。
  static const pollInterval = Duration(seconds: 30);

  DateTime? _lastPoll;
  http.Client Function() clientFactory = http.Client.new;

  /// 返回 true 表示这次响铃了（调用方可以就此结束本 tick）。
  Future<bool> tick(String userId) async {
    final config = await SleepNudgeStore.loadConfig();
    if (!config.ready) return false;
    final now = DateTime.now();
    if (_lastPoll != null && now.difference(_lastPoll!) < pollInterval) {
      return false;
    }
    _lastPoll = now;

    final lastId = await SleepNudgeStore.lastMessageId();
    // 第一次（或换了 topic）只看最近 2 分钟的消息。
    final since =
        lastId ?? ((now.millisecondsSinceEpoch ~/ 1000) - 120).toString();
    final uri = SleepNudgePolicy.pollUri(config.server, config.topic, since);
    if (uri == null) return false;

    final List<NtfyMessage> messages;
    final client = clientFactory();
    try {
      final resp = await client.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        await SleepNudgeStore.setLastStatus('ntfy 返回 ${resp.statusCode}');
        return false;
      }
      messages = SleepNudgePolicy.parseLines(
          utf8.decode(resp.bodyBytes, allowMalformed: true));
    } catch (e) {
      // 不记地址和 topic，只记错误类型。
      debugPrint('[SleepNudge] poll failed: ${e.runtimeType}');
      return false;
    } finally {
      client.close();
    }
    if (messages.isEmpty) return false;
    await SleepNudgeStore.setLastMessageId(messages.last.id);

    final history = await SleepNudgeStore.loadHistory();
    final decision = SleepNudgePolicy.decide(
      messages: messages,
      now: DateTime.now(),
      config: config,
      history: history,
      callAlreadyRinging: CallVoiceSession.instance.isActive ||
          await isPendingCallAlreadyNotified(),
    );
    switch (decision) {
      case SleepNudgeSkip(:final reason):
        debugPrint('[SleepNudge] skip: $reason');
        await SleepNudgeStore.setLastStatus('收到推送，未响铃（${_skipText(reason)}）');
        return false;
      case SleepNudgeRing(:final message):
        return _ring(userId, config, history, message);
    }
  }

  Future<bool> _ring(
    String userId,
    SleepNudgeConfig config,
    SleepNudgeHistory history,
    NtfyMessage message,
  ) async {
    final character =
        await CharacterService.instance.getPrimaryCompanion(userId);
    if (character == null) {
      await SleepNudgeStore.setLastStatus('收到推送，但没有主角色');
      return false;
    }
    final next = SleepNudgePolicy.afterRing(history, DateTime.now());
    final opening = config.engine == SleepNudgeEngine.gptLive
        ? SleepNudgePolicy.openingFor(message, nightCount: next.nightCount)
        : SleepNudgePolicy.classicOpening(nightCount: next.nightCount);
    await queuePendingCall(
      characterId: character.id,
      openingMessage: opening,
      engine: config.engine == SleepNudgeEngine.gptLive
          ? pendingEngineGptLive
          : null,
    );
    final showed = await CallkitService.instance.showPendingIncomingCall(
      characterId: character.id,
      nameCaller: character.name,
      avatarUrl: character.avatar,
    );
    await SleepNudgeStore.saveHistory(next);
    await SleepNudgeStore.setLastStatus(
      showed ? '已响铃（今晚第 ${next.nightCount} 通）' : '已排队，响铃未弹出',
    );
    debugPrint('[SleepNudge] ring showed=$showed night=${next.nightCount}');
    return showed;
  }

  static String _skipText(String reason) => switch (reason) {
        'stale' => '推送太旧',
        'already_ringing' => '已有来电',
        'min_gap' => '离上一通太近',
        'night_cap' => '今晚已达上限',
        _ => reason,
      };
}
