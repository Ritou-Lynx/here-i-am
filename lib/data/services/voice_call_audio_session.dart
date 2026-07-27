import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:memex/utils/logger.dart';

/// Manages the Android/iOS audio session for the companion voice-call mode.
///
/// Configures the system audio path as a **VoIP call** so that the microphone
/// and the TTS speaker can be active simultaneously without one stealing focus
/// from the other, and so that the OS-level acoustic echo cancellation (AEC)
/// cancels the speaker output from the mic signal fed to ASR.
///
/// Lifecycle:
///   [enter]  — call once when voice mode starts (before mic + TTS come up)
///   [exit]   — call when voice mode ends (restores the previous audio session)
///
/// On Android this maps to `MODE_IN_COMMUNICATION` + `USAGE_VOICE_COMMUNICATION`
/// for both the recorder and the player, routing both through
/// `STREAM_VOICE_CALL` where the platform AEC applies. On iOS this maps to the
/// `playAndRecord` AVAudioSession category with default-to-speaker options,
/// which likewise enables hardware AEC.
class VoiceCallAudioSession {
  VoiceCallAudioSession._();
  static final VoiceCallAudioSession instance = VoiceCallAudioSession._();

  static final Logger _logger = getLogger('VoiceCallAudioSession');

  AudioSession? _session;
  AudioSessionConfiguration? _previousConfiguration;
  bool _active = false;

  /// Whether a VoIP call audio session is currently active.
  bool get isActive => _active;

  /// Enter VoIP call audio mode. Configures the shared audio session for
  /// bidirectional voice communication with system echo cancellation.
  Future<void> enter() async {
    if (_active) return;
    if (kIsWeb) return; // no-op on web
    try {
      _session = await AudioSession.instance;
      _previousConfiguration = _session!.configuration;
      await _session!.configure(_callConfiguration);
      await _session!.setActive(true);
      _active = true;
      _logger.info('VoIP call audio session entered');
    } catch (e) {
      _logger.severe('Failed to enter VoIP call audio session: $e');
    }
  }

  /// Exit VoIP call audio mode. Deactivates the call session and restores the
  /// previous configuration (so normal media playback works again).
  Future<void> exit() async {
    if (!_active) return;
    _active = false;
    final session = _session;
    if (session == null) return;
    try {
      await session.setActive(false);
      final prev = _previousConfiguration;
      if (prev != null) {
        await session.configure(prev);
      }
      _logger.info('VoIP call audio session exited');
    } catch (e) {
      _logger.warning('Failed to exit VoIP call audio session: $e');
    } finally {
      _previousConfiguration = null;
    }
  }

  /// The audio session configuration used during a voice call.
  ///
  /// Android: `voiceCommunication` usage + `speech` content, transient focus
  /// so it doesn't permanently claim media focus.
  /// iOS: `playAndRecord` category with speaker + Bluetooth + AEC options.
  static const AudioSessionConfiguration _callConfiguration =
      AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
    // allowBluetooth(0x4) | allowBluetoothA2dp(0x20) | defaultToSpeaker(0x8)
    avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions(0x2C),
    avAudioSessionMode: AVAudioSessionMode.voiceChat,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.voiceCommunication,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
  );
}