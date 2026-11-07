import 'dart:convert';

import 'package:http/http.dart' as http;

/// OpenAI GPT-Live（gpt-live-1）协议层：建会话请求、解析数据通道事件、把转写增量拼成轮次。
/// 不碰 WebRTC 和 UI，方便单测。
///
/// 接口：POST https://api.openai.com/v1/live/sessions，body
/// `{session: {...}, transport: {type: "webrtc", sdp: <offer>}}`，201 返回
/// `{session: {id}, transport: {type: "webrtc", sdp: <answer>}}`。
/// 事件走名为 `oai-events` 的数据通道。
class GptLiveProtocol {
  GptLiveProtocol._();

  static const endpoint = 'https://api.openai.com/v1/live/sessions';
  static const model = 'gpt-live-1';
  static const dataChannelLabel = 'oai-events';
  static const defaultVoice = 'marin';

  /// 服务端上限：instructions 16384 token、input 128 条且合计 8192 token。
  /// 这里按字符保守截断（中文 1 字约 1 token 以上）。
  static const maxInstructionChars = 12000;
  static const maxHistoryMessages = 40;
  static const maxHistoryChars = 6000;

  static Map<String, dynamic> buildSessionRequest({
    required String offerSdp,
    required String instructions,
    List<GptLiveHistoryMessage> history = const [],
    String voice = defaultVoice,
  }) {
    return {
      'session': {
        'model': model,
        'instructions': _clip(instructions, maxInstructionChars),
        'audio': {
          'output': {'voice': normalizeVoice(voice)},
        },
        if (history.isNotEmpty)
          'input': [
            for (final m in trimHistory(history))
              {
                'type': 'message',
                'role': m.role,
                'content': [
                  {
                    'type': m.role == 'assistant' ? 'output_text' : 'input_text',
                    'text': m.content,
                  },
                ],
              },
          ],
      },
      'transport': {'type': 'webrtc', 'sdp': offerSdp},
    };
  }

  /// API 内置声音（ChatGPT App 里的 ember、hanul 等不在其中）。
  static const builtInVoices = {
    'alloy', 'ash', 'ballad', 'beacon', 'bossa', 'cedar', 'cinder', 'coral',
    'delta', 'echo', 'gleam', 'marin', 'meridian', 'quartz', 'ripple', 'sage',
    'shida', 'shimmer', 'stone', 'tempo', 'verse', 'vesper', 'willow',
  };

  /// 填了不支持的声音名时退回默认，免得整通电话建不起来。
  static String normalizeVoice(String voice) {
    final v = voice.trim().toLowerCase();
    return builtInVoices.contains(v) ? v : defaultVoice;
  }

  /// 只留最近的、总字数在上限内的消息，保持时间正序。
  static List<GptLiveHistoryMessage> trimHistory(
      List<GptLiveHistoryMessage> history) {
    final kept = <GptLiveHistoryMessage>[];
    var chars = 0;
    for (final m in history.reversed) {
      final content = m.content.trim();
      if (content.isEmpty) continue;
      if (kept.length >= maxHistoryMessages) break;
      if (chars + content.length > maxHistoryChars) break;
      chars += content.length;
      kept.add(GptLiveHistoryMessage(m.role, content));
    }
    return kept.reversed.toList();
  }

  /// 建会话，返回 SDP answer 和会话 id；失败抛 [GptLiveException]。
  static Future<GptLiveSessionCreated> createSession({
    required String apiKey,
    required Map<String, dynamic> body,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final c = client ?? http.Client();
    try {
      final resp = await c
          .post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw GptLiveException(
            'http_${resp.statusCode}', _errorMessage(resp.body));
      }
      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      final sdp = _dig(json, 'transport', 'sdp');
      final id = _dig(json, 'session', 'id');
      if (sdp is! String || sdp.isEmpty) {
        throw const GptLiveException('no_sdp', '服务端没有返回 SDP');
      }
      return GptLiveSessionCreated(
          id: id is String ? id : null, answerSdp: sdp);
    } finally {
      if (client == null) c.close();
    }
  }

  static String closeEvent() => jsonEncode({'type': 'session.close'});

  static String? _errorMessage(String body) {
    try {
      final json = jsonDecode(body);
      final msg = _dig(json, 'error', 'message');
      if (msg is String) return msg;
    } catch (_) {}
    return null;
  }

  static Object? _dig(Object? json, String a, String b) {
    if (json is! Map) return null;
    final inner = json[a];
    return inner is Map ? inner[b] : null;
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}

class GptLiveHistoryMessage {
  const GptLiveHistoryMessage(this.role, this.content);

  /// developer / user / assistant
  final String role;
  final String content;
}

class GptLiveSessionCreated {
  const GptLiveSessionCreated({required this.id, required this.answerSdp});
  final String? id;
  final String answerSdp;
}

class GptLiveException implements Exception {
  const GptLiveException(this.code, [this.detail]);
  final String code;
  final String? detail;

  @override
  String toString() =>
      'GptLiveException($code${detail != null ? ': $detail' : ''})';
}

/// 数据通道上的服务端事件，只解析通话需要的几种。
sealed class GptLiveEvent {
  const GptLiveEvent();

  static GptLiveEvent? parse(String raw) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      json = decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    switch (json['type']) {
      case 'session.started':
        return const GptLiveStarted();
      case 'session.input_transcript.delta':
        return GptLiveTranscriptDelta(
          fromUser: true,
          delta: json['delta'] as String? ?? '',
          startMs: (json['start_ms'] as num?)?.toInt(),
        );
      case 'session.output_transcript.delta':
        return GptLiveTranscriptDelta(
          fromUser: false,
          delta: json['delta'] as String? ?? '',
          startMs: (json['start_ms'] as num?)?.toInt(),
        );
      case 'session.usage.updated':
        return GptLiveUsage(
            (GptLiveProtocol._dig(json, 'usage', 'seconds') as num?)?.toInt() ??
                0);
      case 'session.closed':
        return GptLiveClosed(
          reason: json['reason'] as String?,
          seconds:
              (GptLiveProtocol._dig(json, 'usage', 'seconds') as num?)?.toInt(),
        );
      case 'error':
        final err = json['error'];
        return GptLiveError(
          code: err is Map ? err['code'] as String? : null,
          message: err is Map ? err['message'] as String? : null,
        );
      default:
        return null;
    }
  }
}

class GptLiveStarted extends GptLiveEvent {
  const GptLiveStarted();
}

class GptLiveTranscriptDelta extends GptLiveEvent {
  const GptLiveTranscriptDelta(
      {required this.fromUser, required this.delta, this.startMs});
  final bool fromUser;
  final String delta;
  final int? startMs;
}

class GptLiveUsage extends GptLiveEvent {
  const GptLiveUsage(this.seconds);
  final int seconds;
}

class GptLiveClosed extends GptLiveEvent {
  const GptLiveClosed({this.reason, this.seconds});
  final String? reason;
  final int? seconds;
}

class GptLiveError extends GptLiveEvent {
  const GptLiveError({this.code, this.message});
  final String? code;
  final String? message;
}

/// 把转写增量拼成轮次。服务端没有“一轮结束”事件，按说话方切换来分轮：
/// 用户的增量接在用户轮上，林埃的接在林埃轮上，换人就开新轮。
class GptLiveTranscript {
  final List<GptLiveTurn> turns = [];

  void add(GptLiveTranscriptDelta d) {
    if (d.delta.isEmpty) return;
    if (turns.isNotEmpty && turns.last.fromUser == d.fromUser) {
      turns.last.text.write(d.delta);
    } else {
      turns.add(GptLiveTurn(fromUser: d.fromUser, at: DateTime.now())
        ..text.write(d.delta));
    }
  }

  /// 去掉空白轮，供写回聊天记录。
  List<GptLiveTurn> get finished =>
      turns.where((t) => t.text.toString().trim().isNotEmpty).toList();

  String get lastLine {
    if (turns.isEmpty) return '';
    return turns.last.text.toString().trim();
  }
}

class GptLiveTurn {
  GptLiveTurn({required this.fromUser, required this.at});
  final bool fromUser;
  final DateTime at;
  final StringBuffer text = StringBuffer();
}
