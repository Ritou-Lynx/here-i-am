import 'dart:async';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/agent/built_in_tools/initiate_call_tool.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/asr/alibaba_streaming_asr_client.dart';
import 'package:memex/data/services/asr/voice_input_controller.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/streaming_tts_player.dart';
import 'package:memex/data/services/voice_call_audio_session.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/voice_turn_identity.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Phase of the continuous half-duplex companion call (runs in the
/// foreground-service isolate).
enum CallVoicePhase { idle, starting, listening, speaking }

/// Continuous half-duplex voice call that survives app backgrounding.
///
/// Runs inside the foreground-service Dart isolate (same home as
/// [BackgroundVoiceSession]), so the Flutter engine of the main isolate can be
/// suspended without killing the call. The mic stays open the whole call; the
/// NLS server-side VAD emits sentence events, each sentence becomes a chat
/// turn (user message -> companion reply -> streaming TTS). While TTS plays,
/// mic audio feeds the barge-in detector so the user can interrupt.
///
/// The CallKit incoming screen / ongoing notification (and its hang-up button)
/// stay alive for the whole call — we deliberately do NOT end the CallKit
/// session on accept. Hang-up signals arrive here via
/// [CompanionTaskHandler.onReceiveData] (type `call_end` / `call_ended`) and
/// tear down the audio pipeline, then clear the CallKit session.
class CallVoiceSession {
  CallVoiceSession._();

  static final CallVoiceSession instance = CallVoiceSession._();

  static final _log = getLogger('CallVoiceSession');

  static const _defaultOpening = '喂，我在呢。';

  CallVoicePhase _phase = CallVoicePhase.idle;
  VoiceInputController? _controller;
  StreamingTtsSession? _ttsSession;
  bool _ready = false;
  bool _readyInProgress = false;
  int _runSerial = 0;
  int _micRestartAttempts = 0;
  DateTime? _lastActivityAt;

  late final VoiceTurnSequencer _turnSequencer =
      VoiceTurnSequencer('call_${identityHash()}');
  VoiceTurnIdentity? _activeIdentity;
  static int _callCounter = 0;
  int identityHash() => _callCounter++;

  String? _userId;
  String? _characterId;
  String? _characterName;
  String? _voiceId;

  // Sentence batching: consecutive NLS sentences within [batchWindow] merge
  // into one turn so mid-sentence pauses don't split a user utterance.
  final StringBuffer _pendingSentence = StringBuffer();
  Timer? _sentenceTimer;
  static const _batchWindow = Duration(milliseconds: 1500);

  CallVoicePhase get phase => _phase;
  bool get isActive => _phase != CallVoicePhase.idle;
  bool get isListening => _phase == CallVoicePhase.listening;

  /// Last moment of call activity (speech / reply / barge-in). Used by the
  /// foreground-task watchdog to auto-hang-up a call that went silent.
  DateTime? get lastActivityAt => _lastActivityAt;

  /// Lazily prepare DB / character / ASR controller. Idempotent; once per
  /// foreground-service lifetime.
  Future<bool> ensureReady() async {
    if (_ready) return true;
    if (_readyInProgress) {
      while (_readyInProgress) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _ready;
    }
    _readyInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');
      if (userId == null) {
        _log.warning('ensureReady: no current_user_id');
        return false;
      }
      if (!AppDatabase.isInitialized) {
        await AppDatabase.init(userId);
      }
      await UserStorage.initL10n();
      final dataRoot = await UserStorage.resolveDataRoot(userId);
      await FileSystemService.init(dataRoot);
      await NotificationService.instance.initialize();

      final character =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (character == null) {
        _log.warning('ensureReady: no primary companion');
        return false;
      }

      final controller = VoiceInputController();
      controller.onStreamingEvent = _onStreamingEvent;
      controller.onBargeInDuck = _onBargeInDuck;
      controller.onBargeInDetected = _onBargeInDetected;
      controller.onBargeInRestore = _onBargeInRestore;
      controller.onStreamingSessionLost = _onStreamingSessionLost;

      _controller = controller;
      _userId = userId;
      _characterId = character.id;
      _characterName = character.name;
      _voiceId = await UserStorage.getActiveTtsVoiceId();
      _ready = true;
      _log.info(
          'ready: character=${character.id} voiceId=${_voiceId ?? 'none'}');
      return true;
    } catch (e, st) {
      _log.severe('ensureReady failed: $e\n$st');
      return false;
    } finally {
      _readyInProgress = false;
    }
  }

  /// Start a continuous call for [characterId]. Idempotent.
  Future<void> start(String characterId) async {
    if (_phase != CallVoicePhase.idle) {
      _log.info('start ignored: already active (phase=$_phase)');
      return;
    }
    if (!await ensureReady()) {
      await _failWith('通话初始化失败');
      return;
    }
    if (characterId != _characterId) {
      _log.warning('start character mismatch: expected=$_characterId '
          'got=$characterId — using ready character anyway');
    }

    _runSerial++;
    _phase = CallVoicePhase.starting;
    _micRestartAttempts = 0;
    await _updateNotification('📞 通话中…');

    // Enter the VoIP call audio session BEFORE the mic opens so the platform
    // routes both mic + speaker through STREAM_VOICE_CALL (AEC applies).
    await VoiceCallAudioSession.instance.enter();

    final ok = await _armMic();
    if (!ok) {
      await _failWith('麦克风不可用，通话已结束');
      return;
    }

    // Clear the pending call bookkeeping — the call is now answered.
    try {
      await clearPendingCall(characterId: characterId);
    } catch (e) {
      _log.warning('clearPendingCall failed: $e');
    }

    _phase = CallVoicePhase.listening;
    await _updateNotification('📞 通话中…（随时可以说话）');
    _notifyMain({'type': 'call_status', 'status': 'listening'});

    // Opening line: read the queued opening message (agent-composed) or fall
    // back to a default greeting. Spoken through TTS while the mic listens.
    final opening = await _resolveOpening();
    await _speakAndPersist(opening, isOpening: true);
  }

  /// Handle a hang-up request (from the app UI or the CallKit notification).
  Future<void> end() async {
    if (_phase == CallVoicePhase.idle) return;
    _log.info('end (phase=$_phase)');
    _runSerial++;
    _activeIdentity = null;
    _phase = CallVoicePhase.idle;

    _sentenceTimer?.cancel();
    _sentenceTimer = null;
    _pendingSentence.clear();

    final tts = _ttsSession;
    _ttsSession = null;
    if (tts != null) {
      try {
        await tts.cancel();
      } catch (e) {
        _log.warning('tts cancel on end: $e');
      }
    }

    final controller = _controller;
    if (controller != null) {
      try {
        if (controller.isStreaming) {
          await controller.cancelStreaming();
        } else {
          await controller.cancel();
        }
      } catch (e) {
        _log.warning('mic teardown on end: $e');
      }
    }

    await VoiceCallAudioSession.instance.exit();
    await _updateNotification('📞 通话已结束');
    // Clear the CallKit ongoing session + notification so no stale "in call"
    // notification survives the hang-up. Safe to call even if already ended.
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      _log.warning('endAllCalls failed: $e');
    }
    _notifyMain({'type': 'call_ended'});
    await _restoreNotification();
  }

  // ── Mic / ASR loop ───────────────────────────────────────────────────────

  Future<bool> _armMic() async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      await controller.startStreaming(useVoiceCommunication: true);
    } catch (e) {
      _log.warning('startStreaming failed: $e');
      return false;
    }
    return controller.isStreaming;
  }

  Future<void> _onStreamingSessionLost() async {
    if (_phase == CallVoicePhase.idle) return;
    _micRestartAttempts++;
    if (_micRestartAttempts > 3) {
      _log.warning('mic lost $_micRestartAttempts times — ending call');
      await end();
      return;
    }
    _log.info('mic session lost — re-arming (attempt $_micRestartAttempts)');
    await Future.delayed(const Duration(milliseconds: 800));
    if (_phase == CallVoicePhase.idle) return;
    await _armMic();
  }

  void _onStreamingEvent(StreamingAsrEvent event) {
    switch (event) {
      case SentenceBeginEvent():
        // NLS detected speech start. If the companion is speaking, treat it
        // as a barge-in (the platform AEC should cancel TTS echo; anything
        // that reaches NLS VAD is real user speech).
        if (_phase == CallVoicePhase.speaking) {
          _log.info('SentenceBegin during TTS — barge-in');
          unawaited(_interruptReply());
        }
      case SentenceEndEvent():
        final text = event.text.trim();
        if (text.isEmpty) return;
        _lastActivityAt = DateTime.now();
        _log.info('sentence: '
            '"${text.length > 60 ? text.substring(0, 60) : text}"');
        _notifyMain({
          'type': 'call_status',
          'status':
              _phase == CallVoicePhase.speaking ? 'speaking' : 'listening',
          'transcript': text,
        });
        if (_pendingSentence.isNotEmpty) {
          _pendingSentence.write(' ');
        }
        _pendingSentence.write(text);
        _sentenceTimer?.cancel();
        _sentenceTimer = Timer(_batchWindow, () => unawaited(_dispatchTurn()));
      default:
        break;
    }
  }

  void _onBargeInDuck() {
    // Lower TTS volume is handled by the UI side in the main isolate; in the
    // background we simply keep playing (the NLS VAD + AEC do the work).
  }

  void _onBargeInDetected() {
    _log.info('barge-in detected');
    unawaited(_interruptReply());
  }

  void _onBargeInRestore() {}

  /// Stop the in-flight reply and return the mic to listening so the user's
  /// follow-up sentence can start a fresh turn.
  Future<void> _interruptReply() async {
    _runSerial++;
    _activeIdentity = null;
    final tts = _ttsSession;
    _ttsSession = null;
    if (tts != null) {
      try {
        await tts.cancel();
      } catch (e) {
        _log.warning('tts cancel on barge-in: $e');
      }
    }
    final controller = _controller;
    if (controller != null && controller.isStreaming) {
      controller.resumeAudioForwarding();
    }
    if (_phase == CallVoicePhase.speaking) {
      _phase = CallVoicePhase.listening;
      await _updateNotification('📞 通话中…（随时可以说话）');
    }
  }

  // ── Turn dispatch ────────────────────────────────────────────────────────

  Future<void> _dispatchTurn() async {
    final text = _pendingSentence.toString().trim();
    _pendingSentence.clear();
    if (text.isEmpty || _phase == CallVoicePhase.idle) return;
    if (_phase != CallVoicePhase.listening) {
      // The user spoke while a reply was in flight — interrupt it. The stale
      // agent stream is invalidated by the _runSerial bump inside _runTurn.
      _log.info('dispatch while phase=$_phase — interrupting reply');
      await _interruptReply();
    }
    await _runTurn(text);
  }

  Future<void> _runTurn(String text) async {
    final serial = ++_runSerial;
    final turnIdentity = _turnSequencer.nextTurn();
    _activeIdentity = turnIdentity;
    _lastActivityAt = DateTime.now();
    final userId = _userId;
    final characterId = _characterId;
    if (userId == null || characterId == null) {
      _phase = CallVoicePhase.idle;
      return;
    }

    _phase = CallVoicePhase.speaking;
    _notifyMain({
      'type': 'call_status',
      'status': 'speaking',
      'transcript': text,
    });

    StreamingTtsSession? tts;
    final voiceId = _voiceId;
    try {
      final userMessageId = await PersonaChatService.instance.addUserMessage(
        characterId,
        text,
        timestamp: DateTime.now(),
        appendTimeline: false,
      );

      if (voiceId != null && voiceId.isNotEmpty) {
        tts = StreamingTtsSession(
          voiceId: voiceId,
          identity: turnIdentity,
          voiceMode: true,
        );
        await tts.start();
        _ttsSession = tts;
        await _updateNotification('🔊 正在回复…');
        // While TTS plays, mic audio feeds the barge-in detector (echo loop
        // defense-in-depth on top of the platform AEC).
        final controller = _controller;
        if (controller != null && controller.isStreaming) {
          controller.pauseAudioForwarding();
        }
      } else {
        await _updateNotification('💬 正在回复…');
      }

      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final buffer = StringBuffer();
      await for (final chunk in CompanionAgent.chat(
        client: resources.client,
        modelConfig: resources.modelConfig,
        userId: userId,
        characterId: characterId,
        userMessage: text,
        userMessageId: userMessageId,
        userMessageTime: DateTime.now(),
        voiceMode: true,
      )) {
        if (serial != _runSerial || !turnIdentity.isCurrent(_activeIdentity)) {
          await tts?.cancel();
          return;
        }
        buffer.write(chunk);
        tts?.feedText(chunk);
        _notifyMain({
          'type': 'call_status',
          'status': 'speaking',
          'transcript': buffer.toString(),
          'reply': true,
        });
      }
      if (serial != _runSerial || !turnIdentity.isCurrent(_activeIdentity)) {
        return;
      }

      final reply = buffer.toString().trim();
      if (reply.isNotEmpty) {
        await PersonaChatService.instance
            .addCharacterMessage(characterId, reply);
      }
      if (tts != null) {
        _phase = CallVoicePhase.speaking;
        await tts.finishAndWait();
      }
    } catch (e, st) {
      _log.severe('turn failed: $e\n$st');
    } finally {
      if (serial == _runSerial && turnIdentity.isCurrent(_activeIdentity)) {
        _ttsSession = null;
        _activeIdentity = null;
        // Back to listening only if the call is still alive.
        if (_phase != CallVoicePhase.idle) {
          _phase = CallVoicePhase.listening;
          final controller = _controller;
          if (controller != null && controller.isStreaming) {
            controller.resumeAudioForwarding();
          }
          await _updateNotification('📞 通话中…（随时可以说话）');
          _notifyMain({'type': 'call_status', 'status': 'listening'});
        }
      }
    }
  }

  // ── Opening line ─────────────────────────────────────────────────────────

  Future<String> _resolveOpening() async {
    try {
      final pending = await readPendingCall();
      final opening = pending?.opening.trim() ?? '';
      if (opening.isNotEmpty) return opening;
    } catch (e) {
      _log.warning('readPendingCall failed: $e');
    }
    return _defaultOpening;
  }

  /// Speak [text] through TTS and persist it as a character message so the
  /// chat transcript (and the character's memory) includes the opening line.
  Future<void> _speakAndPersist(String text, {required bool isOpening}) async {
    final voiceId = _voiceId;
    final characterId = _characterId;
    if (characterId == null) return;

    try {
      await PersonaChatService.instance
          .addCharacterMessage(characterId, text);
    } catch (e) {
      _log.warning('persist opening failed: $e');
    }

    if (voiceId == null || voiceId.isEmpty) return;
    final serial = _runSerial;
    final turnIdentity = _turnSequencer.nextTurn();
    _activeIdentity = turnIdentity;
    final tts = StreamingTtsSession(
      voiceId: voiceId,
      identity: turnIdentity,
      voiceMode: true,
    );
    _ttsSession = tts;
    try {
      await tts.start();
      final controller = _controller;
      if (controller != null && controller.isStreaming) {
        controller.pauseAudioForwarding();
      }
      tts.feedText(text);
      await tts.finishAndWait();
    } catch (e, st) {
      _log.severe('opening TTS failed: $e\n$st');
    } finally {
      if (serial == _runSerial && turnIdentity.isCurrent(_activeIdentity)) {
        _ttsSession = null;
        _activeIdentity = null;
        final controller = _controller;
        if (controller != null && controller.isStreaming) {
          controller.resumeAudioForwarding();
        }
        if (_phase != CallVoicePhase.idle) {
          await _updateNotification('📞 通话中…（随时可以说话）');
          _notifyMain({'type': 'call_status', 'status': 'listening'});
        }
      }
    }
  }

  // ── Failure / notification helpers ───────────────────────────────────────

  Future<void> _failWith(String text) async {
    _log.warning('call failed: $text');
    _phase = CallVoicePhase.idle;
    await _updateNotification(text);
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      _log.warning('endAllCalls on fail: $e');
    }
    _notifyMain({'type': 'call_ended', 'reason': text});
    await _restoreNotification();
  }

  Future<void> _updateNotification(String text) async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: _characterName ?? 'Memex',
        notificationText: text,
      );
    } catch (e) {
      _log.fine('updateService failed: $e');
    }
  }

  Future<void> _restoreNotification() async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: _characterName ?? 'Memex',
        notificationText: '在后台陪着你',
      );
    } catch (e) {
      _log.fine('restore notification failed: $e');
    }
  }

  void _notifyMain(Map<String, dynamic> data) {
    try {
      FlutterForegroundTask.sendDataToMain(data);
    } catch (e) {
      _log.fine('sendDataToMain failed: $e');
    }
  }
}
