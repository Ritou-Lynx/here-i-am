import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/data/services/audio_route_service.dart';
import 'package:memex/data/services/callkit_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/companion_foreground_task.dart';
import 'package:memex/utils/logger.dart';

/// Main-isolate router for the global companion call (runs in the
/// foreground-service isolate via [CallVoiceSession]).
///
/// Responsibilities:
/// - [startCall] — fire `call_start` into the foreground-task isolate
///   (queued behind the task_ready handshake), and remember the active call's
///   character metadata for the overlay UI.
/// - [hangUp] — fire `call_end` so the isolate tears down the audio pipeline
///   (and clears the CallKit session itself).
/// - Relay call status / end events from the isolate to the UI via
///   [onStatusChanged] / [onCallEnded].
class CallVoiceRouter {
  CallVoiceRouter._() {
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is! Map) return;
      final type = data['type'];
      switch (type) {
        case 'task_ready':
          _taskReady = true;
          debugPrint('[CallVoiceRouter] task ready');
        case 'call_status':
          final status = data['status'] as String?;
          if (status != null) {
            _status = status;
            final muted = data['muted'] as bool?;
            if (muted != null) _micMuted = muted;
            final speaker = data['speaker'] as bool?;
            if (speaker != null) _speakerOn = speaker;
            final transcript = data['transcript'] as String?;
            if (transcript != null && transcript.isNotEmpty) {
              _lastTranscript = transcript;
            }
            onStatusChanged?.call(
              CallVoiceStatus(
                status: status,
                transcript: _lastTranscript,
                isReply: data['reply'] == true,
                muted: _micMuted,
                speaker: _speakerOn,
              ),
            );
          }
        case 'call_ended':
          _status = 'ended';
          final reason = data['reason'] as String?;
          _clearActive();
          onCallEnded?.call(reason);
      }
    });
  }

  static final CallVoiceRouter instance = CallVoiceRouter._();

  static final _log = getLogger('CallVoiceRouter');

  /// Current call status string (starting / listening / speaking / ended).
  String? _status;
  String _lastTranscript = '';
  bool _taskReady = false;
  bool _micMuted = false;
  bool _speakerOn = true;

  /// Messages queued until the foreground-task isolate handshakes. FIFO so a
  /// rapid call_start → call_end sequence keeps its order.
  final List<Map<String, dynamic>> _pendingMessages = [];

  String? _activeCharacterId;
  String? _activeCharacterName;
  String? _activeCharacterAvatar;

  /// Fired on every isolate call-status push (listening / speaking + subtitle).
  void Function(CallVoiceStatus status)? onStatusChanged;

  /// Fired when the isolate reports the call ended. [reason] is a short
  /// user-facing message (e.g. "麦克风不可用，通话已结束") or null on hang-up.
  void Function(String? reason)? onCallEnded;

  bool get isCallActive => _activeCharacterId != null;
  String? get activeCharacterId => _activeCharacterId;
  String? get activeCharacterName => _activeCharacterName;
  String? get activeCharacterAvatar => _activeCharacterAvatar;
  String? get status => _status;

  /// Initialize at app startup (wire the task data callback — done in the
  /// constructor; kept for symmetry with [VoiceSessionRouter]).
  Future<void> init() async {
    _taskReady = await FlutterForegroundTask.isRunningService;
    if (_taskReady) {
      debugPrint('[CallVoiceRouter] service already running — task ready');
    }
  }

  /// Start a global call for [characterId]. Ensures the foreground service is
  /// running (mic permission must already be granted), then fires `call_start`
  /// into the isolate. The overlay UI can be shown immediately — the isolate
  /// drives the actual audio.
  Future<void> startCall(String characterId) async {
    if (_activeCharacterId != null) {
      _log.warning('startCall ignored: call already active '
          '($_activeCharacterId)');
      return;
    }

    // Resolve character metadata for the overlay.
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');
      if (userId != null) {
        final character =
            await CharacterService.instance.getPrimaryCompanion(userId);
        if (character != null && character.id == characterId) {
          _activeCharacterName = character.name;
          _activeCharacterAvatar = character.avatar;
        }
      }
    } catch (e) {
      _log.warning('resolve character metadata failed: $e');
    }
    _activeCharacterName ??= '林埃';

    _activeCharacterId = characterId;
    _status = 'starting';
    _lastTranscript = '';

    // Remembered speaker default (外放 by default), applied on the isolate.
    final speakerOn = await AudioRouteService.instance.loadSpeakerPreference();
    _speakerOn = speakerOn;

    // The persistent service is the host of the call isolate. If it can't
    // start (mic permission missing), the call cannot run — notify the UI so
    // it can surface a hint instead of a silent failure.
    var started = true;
    try {
      await CompanionForegroundService.startPersistent();
    } catch (e) {
      _log.warning('startPersistent failed: $e');
      started = false;
    }
    if (started) {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) started = false;
    }
    if (!started) {
      _log.warning('foreground service not running — call cannot start');
      _clearActive();
      // No isolate can run the call; end the CallKit session so the user is
      // not left with a phantom ongoing notification.
      try {
        await CallkitService.instance.endAll();
      } catch (e) {
        _log.warning('endAll on failed start: $e');
      }
      onCallEnded?.call('麦克风权限未授予，无法开始通话');
      return;
    }

    _queueOrSend({
      'type': 'call_start',
      'characterId': characterId,
      'speaker': speakerOn,
    });
  }

  /// Hang up from the app UI. The isolate tears down the audio pipeline and
  /// clears the CallKit session itself.
  Future<void> hangUp() async {
    if (_activeCharacterId == null) return;
    _log.info('hangUp requested');
    await _queueOrSend({'type': 'call_end'});
  }

  /// Mute / unmute the call mic (from the in-app overlay).
  Future<void> setMuted(bool muted) async {
    if (_activeCharacterId == null) return;
    _micMuted = muted;
    await _queueOrSend({'type': 'call_mute', 'muted': muted});
  }

  /// Switch speaker route from the in-app overlay. Also remembers the choice
  /// as the default for future calls.
  Future<void> setSpeakerphone(bool enabled) async {
    _speakerOn = enabled;
    await AudioRouteService.instance.setSpeakerphone(enabled);
    await AudioRouteService.instance.saveSpeakerPreference(enabled);
    if (_activeCharacterId != null) {
      await _queueOrSend({'type': 'call_speaker', 'enabled': enabled});
    }
  }

  /// Current mute state (mirror of what the isolate reports / we requested).
  bool get micMuted => _micMuted;

  /// Current speaker route (loudspeaker = true).
  bool get speakerOn => _speakerOn;

  /// Whether a call is currently active; used by the app resume path to
  /// re-show the overlay after the engine comes back.
  bool isActive() => _activeCharacterId != null;

  /// Queue a task message until the foreground-task isolate is ready
  /// (task_ready handshake), then forward it. Messages are sent in FIFO order
  /// so a call_start followed quickly by call_end cannot be reordered. Drops
  /// everything after ~10s without the handshake.
  Future<void> _queueOrSend(Map<String, dynamic> data) async {
    if (!_taskReady) {
      _pendingMessages.add(data);
      for (var i = 0; i < 40; i++) {
        if (_taskReady) break;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      // Once the handshake is seen, wait until this message reaches the head
      // of the queue (older messages are sent first).
      while (_pendingMessages.isNotEmpty && !identical(_pendingMessages.first, data)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_pendingMessages.isNotEmpty) {
        _pendingMessages.removeAt(0);
      }
    }
    if (_taskReady) {
      FlutterForegroundTask.sendDataToTask(data);
    } else {
      _log.warning('task not ready within 10s; drop $data');
    }
  }

  void _clearActive() {
    _activeCharacterId = null;
    _activeCharacterName = null;
    _activeCharacterAvatar = null;
  }
}

/// A snapshot of the isolate call status for the overlay UI.
class CallVoiceStatus {
  const CallVoiceStatus({
    required this.status,
    required this.transcript,
    this.isReply = false,
    this.muted = false,
    this.speaker = true,
  });

  /// starting / listening / speaking / ended
  final String status;
  final String transcript;
  final bool isReply;
  final bool muted;
  final bool speaker;
}
