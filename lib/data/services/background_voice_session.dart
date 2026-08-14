import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/asr/voice_input_controller.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/notification_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/services/streaming_tts_player.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/domain/models/voice_turn_identity.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Phase of the half-duplex background voice conversation.
enum BackgroundVoicePhase { idle, recording, processing, speaking }

/// Half-duplex voice conversation driven by the media button (headset middle
/// key), running inside the foreground-service Dart isolate.
///
/// Flow: press once → start recording → press again → send as a chat message
/// → the companion replies → reply is spoken aloud via streaming TTS. A press
/// while the companion is replying interrupts the reply and starts a new
/// recording (barge-in). Works with the app backgrounded because this isolate
/// is hosted by the persistent foreground service.
///
/// This isolate has NO UI; state transitions are surfaced through the
/// foreground-service notification text via [FlutterForegroundTask.updateService].
class BackgroundVoiceSession {
  BackgroundVoiceSession._();

  static final BackgroundVoiceSession instance = BackgroundVoiceSession._();

  static final _log = getLogger('BackgroundVoiceSession');

  BackgroundVoicePhase _phase = BackgroundVoicePhase.idle;
  VoiceInputController? _controller;
  StreamingTtsSession? _ttsSession;
  bool _ready = false;
  bool _readyInProgress = false;
  int _runSerial = 0;

  /// Identity sequencer for voice turns. Call session is fixed for the
  /// lifetime of this background session; each turn gets a new identity.
  late final VoiceTurnSequencer _turnSequencer =
      VoiceTurnSequencer('bg_call_${identityHash()}');
  VoiceTurnIdentity? _activeIdentity;

  static int _callCounter = 0;
  int identityHash() => _callCounter++;

  String? _userId;
  String? _characterId;
  String? _characterName;
  String? _voiceId;

  BackgroundVoicePhase get phase => _phase;
  bool get isBusy => _phase != BackgroundVoicePhase.idle;

  /// Lazily prepare the session: DB, character, controller. Safe to call
  /// repeatedly (idempotent). Runs once per foreground-service lifetime.
  Future<bool> ensureReady() async {
    if (_ready) return true;
    if (_readyInProgress) {
      // Another call is preparing; poll until it finishes.
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
      // 5-minute press-to-talk watchdog: treat like a manual stop & send.
      controller.onPressToTalkAutoComplete = (text) async {
        if (_phase != BackgroundVoicePhase.recording) return;
        final trimmed = text?.trim() ?? '';
        if (trimmed.isEmpty) {
          _phase = BackgroundVoicePhase.idle;
          await _updateNotification('在后台陪着你');
          return;
        }
        await _sendAndReply(trimmed);
      };

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

  /// Handle one media-button toggle (headset middle key / play-pause).
  Future<void> handleToggle() async {
    _log.info('handleToggle phase=$_phase');
    switch (_phase) {
      case BackgroundVoicePhase.idle:
        if (!await ensureReady()) {
          await _updateNotification('语音会话不可用');
          return;
        }
        await _startRecording();
      case BackgroundVoicePhase.recording:
        await _stopRecordingAndSend();
      case BackgroundVoicePhase.processing:
      case BackgroundVoicePhase.speaking:
        // Pressing while the companion is replying = barge-in: interrupt the
        // current reply and start a fresh recording.
        await _interruptReply();
        await _startRecording();
    }
  }

  /// Handle a media-button cancel (previous key).
  Future<void> handleCancel() async {
    _log.info('handleCancel phase=$_phase');
    switch (_phase) {
      case BackgroundVoicePhase.recording:
        try {
          await _controller?.cancelPressToTalk();
        } catch (e) {
          _log.warning('cancelPressToTalk error: $e');
        }
        _phase = BackgroundVoicePhase.idle;
        await _updateNotification('在后台陪着你');
      case BackgroundVoicePhase.processing:
      case BackgroundVoicePhase.speaking:
        await _interruptReply();
        _phase = BackgroundVoicePhase.idle;
        await _updateNotification('在后台陪着你');
      case BackgroundVoicePhase.idle:
        break;
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.startPressToTalk();
    } catch (e) {
      _log.warning('startPressToTalk error: $e');
      _phase = BackgroundVoicePhase.idle;
      await _updateNotification('语音不可用');
      return;
    }
    if (!controller.isPressToTalk) {
      _phase = BackgroundVoicePhase.idle;
      final err = controller.lastError;
      // A missing mic permission can't be resolved from the background (no
      // system dialog is shown for background apps), so surface an actionable
      // hint instead of a bare error. Android 11+ "While in use" grants are
      // auto-revoked when the app leaves the foreground — the fix is to pick
      // "Allow all the time" in system settings.
      final text = (err == null || err.isEmpty)
          ? '语音不可用'
          : (err.contains('麦克风') || err.contains('权限'))
              ? '麦克风权限未授予：请到手机设置 → 应用 → 故我在 V3 → 权限 → 麦克风，选择「允许所有时间」'
              : err;
      await _updateNotification(text);
      return;
    }
    _phase = BackgroundVoicePhase.recording;
    unawaited(_playBeep(880, 0.10));
    await _updateNotification('🎤 聆听中…（再按一下发送）');
  }

  Future<void> _stopRecordingAndSend() async {
    final controller = _controller;
    if (controller == null) {
      _phase = BackgroundVoicePhase.idle;
      return;
    }
    _phase = BackgroundVoicePhase.processing;
    await _updateNotification('💭 正在理解…');
    String? text;
    try {
      text = await controller.stopPressToTalk();
    } catch (e) {
      _log.warning('stopPressToTalk error: $e');
    }
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) {
      _phase = BackgroundVoicePhase.idle;
      await _updateNotification('在后台陪着你');
      return;
    }
    unawaited(_playBeep(660, 0.10));
    await _sendAndReply(trimmed);
  }

  /// Send [text] as a user chat message, stream the companion reply, persist
  /// it, and speak it aloud. Guarded by identity protocol so an interrupting
  /// toggle/cancel invalidates the in-flight run.
  Future<void> _sendAndReply(String text) async {
    final serial = ++_runSerial;
    final turnIdentity = _turnSequencer.nextTurn();
    _activeIdentity = turnIdentity;
    final userId = _userId;
    final characterId = _characterId;
    if (userId == null || characterId == null) {
      _phase = BackgroundVoicePhase.idle;
      return;
    }
    _phase = BackgroundVoicePhase.processing;

    StreamingTtsSession? tts;
    final voiceId = _voiceId;
    try {
      // Persist the user's voice message first (returns its id so time-gap
      // awareness in the agent can exclude this message).
      final userMessageId = await PersonaChatService.instance.addUserMessage(
        characterId,
        text,
        timestamp: DateTime.now(),
        appendTimeline: false,
      );

      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );

      if (voiceId != null && voiceId.isNotEmpty) {
        tts = StreamingTtsSession(
          voiceId: voiceId,
          identity: turnIdentity,
        );
        await tts.start();
        _ttsSession = tts;
        _phase = BackgroundVoicePhase.speaking;
        await _updateNotification('🔊 正在回复…');
      } else {
        await _updateNotification('💬 正在回复…');
      }

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
          // Interrupted mid-stream: stop feeding TTS and bail.
          await tts?.cancel();
          return;
        }
        buffer.write(chunk);
        tts?.feedText(chunk);
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
        _phase = BackgroundVoicePhase.speaking;
        await tts.finishAndWait();
      }
    } catch (e, st) {
      _log.severe('reply failed: $e\n$st');
    } finally {
      if (serial == _runSerial && turnIdentity.isCurrent(_activeIdentity)) {
        _ttsSession = null;
        _activeIdentity = null;
        _phase = BackgroundVoicePhase.idle;
        await _updateNotification('在后台陪着你');
      }
    }
  }

  /// Invalidate the in-flight reply run and cancel TTS playback.
  Future<void> _interruptReply() async {
    _runSerial++;
    _activeIdentity = null;
    final tts = _ttsSession;
    _ttsSession = null;
    if (tts != null) {
      try {
        await tts.cancel();
      } catch (e) {
        _log.warning('tts cancel error: $e');
      }
    }
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

  /// Play a short beep as recording start/stop feedback. Uses the audio focus
  /// already held by MediaButtonBridge (no session activation) so it works in
  /// the background isolate.
  Future<void> _playBeep(int freqHz, double durationSec) async {
    AudioPlayer? player;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/hereiam_bg_beep.wav');
      await file.writeAsBytes(
        _buildToneWav(freqHz: freqHz, durationSec: durationSec, amp: 0.3),
        flush: true,
      );
      player = AudioPlayer(
        handleAudioSessionActivation: false,
        androidApplyAudioAttributes: false,
      );
      await player.setFilePath(file.path);
      await player.play();
      await player.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      _log.fine('playBeep failed: $e');
    } finally {
      await player?.dispose();
    }
  }
}

/// Builds a WAV (16 kHz, mono, 16-bit PCM) tone for background beeps.
Uint8List _buildToneWav({
  required int freqHz,
  required double durationSec,
  required double amp,
}) {
  const sampleRate = 16000;
  const fadeMs = 12;
  final fadeSamples = (sampleRate * fadeMs / 1000).round();
  final n = (sampleRate * durationSec).round();

  final samples = <int>[];
  for (var i = 0; i < n; i++) {
    double env;
    if (i < fadeSamples) {
      env = i / fadeSamples;
    } else if (i > n - fadeSamples) {
      env = (n - i) / fadeSamples;
    } else {
      env = 1.0;
    }
    final v = math.sin(2 * math.pi * freqHz * i / sampleRate);
    final s = (v * amp * env * 32767).round().clamp(-32768, 32767);
    samples.add(s);
  }

  final dataLen = samples.length * 2;
  final buf = ByteData(44 + dataLen);
  _writeAscii(buf, 0, 'RIFF');
  buf.setUint32(4, 36 + dataLen, Endian.little);
  _writeAscii(buf, 8, 'WAVE');
  _writeAscii(buf, 12, 'fmt ');
  buf.setUint32(16, 16, Endian.little);
  buf.setUint16(20, 1, Endian.little);
  buf.setUint16(22, 1, Endian.little);
  buf.setUint32(24, sampleRate, Endian.little);
  buf.setUint32(28, sampleRate * 2, Endian.little);
  buf.setUint16(32, 2, Endian.little);
  buf.setUint16(34, 16, Endian.little);
  _writeAscii(buf, 36, 'data');
  buf.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    buf.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return buf.buffer.asUint8List();
}

void _writeAscii(ByteData buf, int offset, String s) {
  for (var i = 0; i < s.length; i++) {
    buf.setUint8(offset + i, s.codeUnitAt(i));
  }
}
