import 'dart:convert';

import 'package:memex/data/services/call_engine_settings.dart';

/// 催睡来电（G-Nudge）的纯逻辑：解析 ntfy 消息、判断这一通能不能打、拼开场说明。
/// 不碰数据库、网络和 UI，方便单测。
///
/// 链路：床头哨兵（小米）判醒 → 推 ntfy 私有 topic → 本 App 常驻服务轮询 topic →
/// 排一通待拨电话 → CallKit 全屏响铃 → 接听走 GPT-Live（或原通话）。

class SleepNudgeConfig {
  const SleepNudgeConfig({
    this.enabled = false,
    this.server = defaultServer,
    this.topic = '',
    this.engine = CallEngine.gptLive,
    this.minGapMinutes = defaultMinGapMinutes,
    this.maxPerNight = defaultMaxPerNight,
    this.maxCallMinutes = defaultMaxCallMinutes,
  });

  static const defaultServer = 'https://ntfy.sh';
  static const defaultMinGapMinutes = 20;
  static const defaultMaxPerNight = 4;
  static const defaultMaxCallMinutes = 15;

  final bool enabled;
  final String server;
  final String topic;
  final CallEngine engine;
  final int minGapMinutes;
  final int maxPerNight;
  final int maxCallMinutes;

  /// 开关打开且填了合法的 https 地址和 topic 才去轮询。
  bool get ready =>
      enabled && SleepNudgePolicy.pollUri(server, topic, null) != null;
}

/// 本晚已打的电话（“一晚”按中午 12 点切分，跨零点仍算同一晚）。
class SleepNudgeHistory {
  const SleepNudgeHistory(
      {this.lastCallAt, this.nightKey, this.nightCount = 0});
  final DateTime? lastCallAt;
  final String? nightKey;
  final int nightCount;
}

class NtfyMessage {
  const NtfyMessage({
    required this.id,
    required this.time,
    this.title = '',
    this.message = '',
  });
  final String id;
  final DateTime time;
  final String title;
  final String message;
}

sealed class SleepNudgeDecision {
  const SleepNudgeDecision();
}

class SleepNudgeRing extends SleepNudgeDecision {
  const SleepNudgeRing(this.message);
  final NtfyMessage message;
}

class SleepNudgeSkip extends SleepNudgeDecision {
  const SleepNudgeSkip(this.reason);
  final String reason;
}

class SleepNudgePolicy {
  SleepNudgePolicy._();

  /// 推送过了这么久才收到（手机断网、服务没跑）就不再响，免得白天补响。
  static const staleAfter = Duration(minutes: 5);

  /// ntfy 轮询地址：`<server>/<topic>/json?poll=1&since=<id 或 unix 秒>`。
  /// 地址不合法返回 null。
  static Uri? pollUri(String server, String topic, String? since) {
    final s = server.trim();
    final t = topic.trim();
    if (t.isEmpty || t == '.' || t == '..' || t.contains('/')) return null;
    final base = Uri.tryParse(s);
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      return null;
    }
    final root = s.endsWith('/') ? s.substring(0, s.length - 1) : s;
    return Uri.parse('$root/${Uri.encodeComponent(t)}/json').replace(
      queryParameters: {
        'poll': '1',
        if (since != null && since.isNotEmpty) 'since': since,
      },
    );
  }

  /// 解析 ntfy 的逐行 JSON，只保留 event=message 的条目，按时间正序。
  static List<NtfyMessage> parseLines(String body) {
    final out = <NtfyMessage>[];
    for (final line in const LineSplitter().convert(body)) {
      if (line.trim().isEmpty) continue;
      Object? json;
      try {
        json = jsonDecode(line);
      } catch (_) {
        continue;
      }
      if (json is! Map) continue;
      if (json['event'] != 'message') continue;
      final id = json['id'];
      final time = json['time'];
      if (id is! String || id.isEmpty || time is! num) continue;
      out.add(NtfyMessage(
        id: id,
        time: DateTime.fromMillisecondsSinceEpoch(time.toInt() * 1000),
        title: json['title'] is String ? json['title'] as String : '',
        message: json['message'] is String ? json['message'] as String : '',
      ));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// 床头哨兵推送的标记词（三星例程原来也靠它触发）。
  static const callKeyword = '林埃来电';

  static bool isCallMessage(NtfyMessage m) =>
      m.title.contains(callKeyword) || m.message.contains(callKeyword);

  /// 一晚的标识：往前推 12 小时取日期，所以 23:00 和次日 03:00 同属一晚。
  static String nightKeyOf(DateTime now) {
    final d = now.subtract(const Duration(hours: 12));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 从这批新消息里决定要不要响：取最新的一条，再过新鲜度、间隔、每晚上限。
  static SleepNudgeDecision decide({
    required List<NtfyMessage> messages,
    required DateTime now,
    required SleepNudgeConfig config,
    required SleepNudgeHistory history,
    bool callAlreadyRinging = false,
  }) {
    // topic 可能和其他提醒（如日摘要推送）共用，只认带“林埃来电”的消息。
    final calls = messages.where(isCallMessage).toList();
    if (calls.isEmpty) return const SleepNudgeSkip('no_message');
    final latest = calls.last;
    if (now.difference(latest.time) > staleAfter) {
      return const SleepNudgeSkip('stale');
    }
    if (callAlreadyRinging) return const SleepNudgeSkip('already_ringing');
    final last = history.lastCallAt;
    if (last != null &&
        now.difference(last) < Duration(minutes: config.minGapMinutes)) {
      return const SleepNudgeSkip('min_gap');
    }
    final tonight = nightKeyOf(now);
    final count = history.nightKey == tonight ? history.nightCount : 0;
    if (config.maxPerNight > 0 && count >= config.maxPerNight) {
      return const SleepNudgeSkip('night_cap');
    }
    return SleepNudgeRing(latest);
  }

  /// 响过一通后更新的历史。
  static SleepNudgeHistory afterRing(SleepNudgeHistory h, DateTime now) {
    final tonight = nightKeyOf(now);
    final count = h.nightKey == tonight ? h.nightCount : 0;
    return SleepNudgeHistory(
      lastCallAt: now,
      nightKey: tonight,
      nightCount: count + 1,
    );
  }

  /// 存进待拨电话的开场说明（GPT-Live 当作这通电话的起因；原通话当开场白）。
  static String openingFor(NtfyMessage m, {required int nightCount}) {
    final reason = m.message.trim().isEmpty ? '床头哨兵判断你还醒着。' : m.message.trim();
    final nth = nightCount <= 1 ? '' : '这是今晚第 $nightCount 通。';
    return '$nth$reason';
  }

  /// 原通话（非 GPT-Live）接起来直接念的开场白。
  static String classicOpening({required int nightCount}) =>
      nightCount <= 1 ? '宝，这么晚了还醒着？我打过来催你睡觉啦。' : '宝，怎么还没睡？我又打过来了，乖，放下手机好不好。';
}
