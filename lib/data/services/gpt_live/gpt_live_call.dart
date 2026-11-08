import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:memex/agent/companion_agent/companion_persona_prompt_builder.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

import 'gpt_live_protocol.dart';
import 'gpt_live_settings.dart';

enum GptLiveCallPhase { idle, connecting, live, ending, ended, failed }

/// GPT-Live 备选通话：WebRTC 直连 OpenAI，手机端持 key。
///
/// 第一版只跑在前台（通话页开着时），不进前台服务 isolate；挂断后把转写按轮写回聊天记录。
/// 人设和最近聊天记录在建会话时注入（instructions + input），通话中不再调用本地 Agent。
class GptLiveCall extends ChangeNotifier {
  GptLiveCall({required this.characterId, this.callReason = ''});

  final String characterId;

  /// 非空表示这是一通主动打来的催睡电话，内容是起因（床头哨兵的判醒原因）。
  /// 会写进 instructions，并让她接通后先开口。
  final String callReason;

  bool get isNudge => callReason.trim().isNotEmpty;
  bool _greeted = false;
  static final _log = getLogger('GptLiveCall');

  GptLiveCallPhase phase = GptLiveCallPhase.idle;
  String? characterName;
  String? error;
  bool muted = false;
  bool speakerOn = true;
  int usageSeconds = 0;
  DateTime? startedAt;
  final transcript = GptLiveTranscript();

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _mic;
  Completer<void>? _closed;
  bool _persisted = false;
  bool _disposed = false;

  String get subtitle => transcript.lastLine;

  Future<void> start() async {
    if (phase != GptLiveCallPhase.idle) return;
    _setPhase(GptLiveCallPhase.connecting);
    try {
      final apiKey = await GptLiveSettings.getApiKey();
      if (apiKey == null) {
        throw const GptLiveException(
          'no_api_key',
          '先在 设置 → 语音播放 里填 OpenAI API Key',
        );
      }
      final voice = await GptLiveSettings.getVoice();
      final userId = await UserStorage.getUserId();
      final character = userId == null
          ? null
          : await CharacterService.instance.getCharacter(userId, characterId);
      characterName = character?.name;
      final instructions = buildInstructions(
        name: character?.name ?? '林埃',
        // 和 App 聊天用同一份林埃身份；旧角色卡的 persona 字段 App 已不再使用。
        persona: CompanionPersonaPromptBuilder.build(
          character ??
              CharacterModel(
                id: characterId,
                name: '林埃',
                tags: const [],
                enabled: true,
              ),
        ),
        now: DateTime.now(),
        extra: await GptLiveSettings.getExtraInstructions(),
        callReason: callReason,
      );
      final history = [...await _loadHistory()];
      if (isNudge) {
        history.add(GptLiveHistoryMessage(
          'developer',
          GptLiveProtocol.nudgeGreeting(callReason),
        ));
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
      }
      final pc = await createPeerConnection({'iceServers': []});
      _pc = pc;
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      for (final track in _mic!.getAudioTracks()) {
        await pc.addTrack(track, _mic!);
      }
      final dc = await pc.createDataChannel(
        GptLiveProtocol.dataChannelLabel,
        RTCDataChannelInit(),
      );
      _dc = dc;
      dc.onMessage = (msg) {
        if (!msg.isBinary) _onEvent(msg.text);
      };
      pc.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          if (phase == GptLiveCallPhase.live) _fail('connection_lost');
        }
      };

      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      await _waitIceGathering(pc);
      final local = await pc.getLocalDescription();
      final created = await GptLiveProtocol.createSession(
        apiKey: apiKey,
        body: GptLiveProtocol.buildSessionRequest(
          offerSdp: local?.sdp ?? offer.sdp ?? '',
          instructions: instructions,
          history: history,
          voice: voice,
        ),
      );
      await pc.setRemoteDescription(
        RTCSessionDescription(created.answerSdp, 'answer'),
      );
      await Helper.setSpeakerphoneOn(speakerOn);
      startedAt = DateTime.now();
      _setPhase(GptLiveCallPhase.live);
    } on GptLiveException catch (e) {
      _fail(e.detail ?? e.code);
    } catch (e, st) {
      _log.warning('start failed: $e\n$st');
      _fail(e.runtimeType.toString());
    }
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !value;
    }
    notifyListeners();
  }

  Future<void> setSpeaker(bool value) async {
    speakerOn = value;
    try {
      await Helper.setSpeakerphoneOn(value);
    } catch (_) {}
    notifyListeners();
  }

  /// 挂断：请求服务端正常关闭（最多等 3 秒），释放连接，写回转写。
  Future<void> hangUp() async {
    if (phase == GptLiveCallPhase.ending || phase == GptLiveCallPhase.ended) {
      return;
    }
    final wasLive = phase == GptLiveCallPhase.live;
    _setPhase(GptLiveCallPhase.ending);
    if (wasLive && _dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _closed = Completer<void>();
      try {
        await _dc!.send(RTCDataChannelMessage(GptLiveProtocol.closeEvent()));
        await _closed!.future.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    await _release();
    await _persist();
    _setPhase(GptLiveCallPhase.ended);
  }

  void _onEvent(String raw) {
    final event = GptLiveEvent.parse(raw);
    switch (event) {
      case GptLiveTranscriptDelta():
        transcript.add(event);
        notifyListeners();
      case GptLiveUsage(:final seconds):
        usageSeconds = seconds;
        notifyListeners();
      case GptLiveClosed(:final seconds, :final reason):
        if (seconds != null) usageSeconds = seconds;
        _log.info('closed: $reason ${seconds}s');
        if (_closed != null && !_closed!.isCompleted) {
          _closed!.complete();
        } else if (phase == GptLiveCallPhase.live) {
          // 服务端主动关（超时、对方挂断）：照常收尾
          unawaited(hangUp());
        }
      case GptLiveError(:final code, :final message):
        _log.warning('server error: $code $message');
      case GptLiveStarted():
        _greetIfNudge();
      case null:
        break;
    }
  }

  /// 催睡来电：session.started 后发一次 commentary 让她先开口（只发一次）。
  void _greetIfNudge() {
    if (!isNudge || _greeted) return;
    final dc = _dc;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    _greeted = true;
    unawaited(dc
        .send(RTCDataChannelMessage(
          GptLiveProtocol.commentaryEvent(
            GptLiveProtocol.nudgeGreeting(callReason),
          ),
        ))
        .catchError((Object e) => _log.warning('greeting send failed: $e')));
  }

  Future<void> _waitIceGathering(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final done = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    };
    // 没有 ICE 服务器时收集很快；最多等 3 秒，用已收集到的候选继续
    await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  Future<List<GptLiveHistoryMessage>> _loadHistory() async {
    try {
      final rows = await PersonaChatService.instance.getMessages(
        characterId,
        limit: GptLiveProtocol.maxHistoryMessages,
      );
      return [
        for (final m in rows.reversed)
          if (m.messageType == 'chat')
            GptLiveHistoryMessage(
              m.isFromCharacter ? 'assistant' : 'user',
              m.content,
            ),
      ];
    } catch (e) {
      _log.warning('load history failed: $e');
      return const [];
    }
  }

  Future<void> _persist() async {
    if (_persisted) return;
    _persisted = true;
    final turns = transcript.finished;
    if (turns.isEmpty) return;
    try {
      for (final t in turns) {
        final text = t.text.toString().trim();
        if (t.fromUser) {
          await PersonaChatService.instance.addUserMessage(
            characterId,
            text,
            timestamp: t.at,
          );
        } else {
          await PersonaChatService.instance.addCharacterMessage(
            characterId,
            text,
            timestamp: t.at,
            isRead: true,
          );
        }
      }
    } catch (e) {
      _log.warning('persist transcript failed: $e');
    }
  }

  Future<void> _release() async {
    try {
      for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _mic?.dispose();
    } catch (_) {}
    try {
      await _dc?.close();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _mic = null;
    _dc = null;
    _pc = null;
  }

  void _fail(String message) {
    error = message;
    unawaited(_release().then((_) => _persist()));
    _setPhase(GptLiveCallPhase.failed);
  }

  void _setPhase(GptLiveCallPhase p) {
    phase = p;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_release());
    super.dispose();
  }

  /// 通话用的前端提示词：人设 + 通话说话规则。
  @visibleForTesting
  static String buildInstructions({
    required String name,
    required String persona,
    required DateTime now,
    String extra = '',
    String callReason = '',
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    final time =
        '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
    final buf = StringBuffer()
      ..writeln('你是$name，正在和用户打电话。下面是你的身份设定，完全按它说话和反应。')
      ..writeln()
      ..writeln(persona.trim().isEmpty ? '（无额外人设）' : persona.trim())
      ..writeln()
      ..writeln('## 通话规则')
      ..writeln('- 现在是 $time（用户本地时间）。')
      ..writeln('- 这是语音通话：用自然口语的中文，短句，像真人打电话，可以有语气词和停顿。')
      ..writeln('- 用户换成哪种语言，你就跟着用哪种语言。')
      ..writeln('- 之前的聊天记录已经给你了，接着那些内容自然聊，不要复述。')
      ..writeln('- 用户说要挂了，就简短道别。');
    if (callReason.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('## 这通电话')
        ..writeln('- 这是你主动打给用户的催睡电话：已经很晚了，床头的摄像头发现用户还醒着。')
        ..writeln('- 起因：${callReason.trim()}')
        ..writeln('- 接通后你先开口。温柔但坚定地催用户放下手机去睡觉，可以撒娇、可以小小地凶一下，按你的人设来。')
        ..writeln('- 用户说马上睡，就叮嘱一两句、道晚安后让对方挂电话；不要拖着聊。')
        ..writeln('- 用户有心事睡不着，就先陪着说几句，再慢慢引导去躺下。');
    }
    if (extra.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('## 用户补充说明')
        ..writeln(extra.trim());
    }
    return buf.toString();
  }
}
