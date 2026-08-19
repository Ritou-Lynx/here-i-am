import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memex/data/services/audio_route_service.dart';
import 'package:memex/data/services/callkit_service.dart';
import 'package:memex/data/services/call_voice_state_bridge.dart';
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
      _handleTaskData(Map<String, dynamic>.from(data));
    });
  }

  static final CallVoiceRouter instance = CallVoiceRouter._();

  static final _log = getLogger('CallVoiceRouter');

  /// Current call status string (starting / listening / speaking / ended).
  String? _status;
  String _lastTranscript = '';
  bool _lastIsReply = false;
  int _lastBridgeVersion = 0;
  Timer? _statePollTimer;
  bool _statePollInProgress = false;
  bool _taskReady = false;
  bool _micMuted = false;
  bool _speakerOn = true;

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
  String get lastTranscript => _lastTranscript;
  bool get lastIsReply => _lastIsReply;

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
    _lastIsReply = false;
    _lastBridgeVersion = DateTime.now().microsecondsSinceEpoch;
    _startStatePolling();

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
    _log.info('hangUp requested');
    // Always send the hang-up message even if _activeCharacterId is null
    // (the isolate side is idempotent and will clean up CallKit / notifications).
    // This covers the race where a CallKit broadcast already cleared the active
    // state but the UI hang-up button was just pressed — without this fallback,
    // the button would be a silent no-op and the overlay would never close.
    // Close the local UI before the three background delivery retries. The
    // old ordering made the red button look dead for about 4.5 seconds.
    final callback = onCallEnded;
    _status = 'ended';
    _clearActive();
    callback?.call(null);
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

  /// Queue a task message until the foreground-task isolate exists, then
  /// forward it.
  ///
  /// IMPORTANT: does NOT rely on the task_ready handshake message. That
  /// message travels task→main via IsolateNameServer, whose port map is
  /// per-isolate — the background isolate cannot resolve a port registered
  /// by the main isolate, so the handshake is unreliable. Instead we poll
  /// [FlutterForegroundTask.isRunningService] (Kotlin state, main→task
  /// direction works) and then send. The isolate-side handlers are idempotent
  /// (start/end/mute/speaker all no-op when already in that state), so the
  /// small re-send window is harmless insurance against a task engine that is
  /// still warming up.
  Future<void> _queueOrSend(Map<String, dynamic> data) async {
    if (!_taskReady) {
      // Wait until the service isolate is running (up to ~10s).
      for (var i = 0; i < 40; i++) {
        try {
          if (await FlutterForegroundTask.isRunningService) break;
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
    // Send repeatedly (idempotent on the isolate side) so a message cannot be
    // lost to a task engine that is still warming up.
    var sent = false;
    for (var i = 0; i < 3; i++) {
      try {
        if (await FlutterForegroundTask.isRunningService) {
          FlutterForegroundTask.sendDataToTask(data);
          sent = true;
          _log.fine('sent ${data['type']} to task isolate (try ${i + 1})');
        }
      } catch (e) {
        _log.warning('sendDataToTask failed: $e');
      }
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    if (!sent) {
      _log.warning('task not running within 10s; drop $data');
    }
  }

  void _clearActive() {
    _statePollTimer?.cancel();
    _statePollTimer = null;
    _activeCharacterId = null;
    _activeCharacterName = null;
    _activeCharacterAvatar = null;
  }

  void _startStatePolling() {
    _statePollTimer?.cancel();
    _statePollTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_pollCallState()),
    );
  }

  Future<void> _pollCallState() async {
    if (_statePollInProgress || _activeCharacterId == null) return;
    _statePollInProgress = true;
    try {
      final snapshot = await CallVoiceStateBridge.read();
      if (snapshot != null) _handleTaskData(snapshot);
    } catch (e) {
      _log.fine('poll call state failed: $e');
    } finally {
      _statePollInProgress = false;
    }
  }

  void _handleTaskData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'task_ready') {
      _taskReady = true;
      debugPrint('[CallVoiceRouter] task ready');
      return;
    }

    final version = data['version'] as int? ?? 0;
    if (version > 0) {
      if (version <= _lastBridgeVersion) return;
      _lastBridgeVersion = version;
    }

    switch (type) {
      case 'call_status':
        final status = data['status'] as String?;
        if (status == null) return;
        _status = status;
        final muted = data['muted'] as bool?;
        if (muted != null) _micMuted = muted;
        final speaker = data['speaker'] as bool?;
        if (speaker != null) _speakerOn = speaker;
        final transcript = data['transcript'] as String?;
        if (transcript != null && transcript.isNotEmpty) {
          _lastTranscript = transcript;
          _lastIsReply = data['reply'] == true;
        }
        onStatusChanged?.call(
          CallVoiceStatus(
            status: status,
            transcript: _lastTranscript,
            isReply: _lastIsReply,
            muted: _micMuted,
            speaker: _speakerOn,
          ),
        );
      case 'call_ended':
        _status = 'ended';
        final reason = data['reason'] as String?;
        final callback = onCallEnded;
        _clearActive();
        callback?.call(reason);
    }
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
