import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/data/services/asr/media_button_service.dart';
import 'package:memex/data/services/companion_foreground_task.dart';

/// Main-isolate media-button router for the background voice session.
///
/// The chat screen registers its own owner with [MediaButtonService] and wins
/// the owner stack while it is open (foreground chat + media keys work exactly
/// as before). Once the chat screen releases the media buttons — app
/// backgrounded, or no chat open — this router's owner is promoted, and each
/// toggle/cancel is forwarded to the foreground-service isolate via
/// [FlutterForegroundTask.sendDataToTask], where [BackgroundVoiceSession]
/// runs the half-duplex voice conversation.
class VoiceSessionRouter {
  VoiceSessionRouter._() {
    FlutterForegroundTask.addTaskDataCallback((data) {
      debugPrint('[VoiceSessionRouter] data from task: $data');
    });
  }

  static final VoiceSessionRouter instance = VoiceSessionRouter._();

  static final Object _owner = Object();
  bool _activated = false;

  /// Wire up the router at app startup. Reads the media-key toggle from
  /// settings; also call [syncFromSettings] whenever the toggle changes.
  Future<void> init() async {
    await syncFromSettings();
  }

  /// Re-reads the media-key setting and activates/deactivates accordingly.
  /// Call after the user changes the switch in ASR settings.
  Future<void> syncFromSettings() async {
    final enabled = await AsrConfig.getUseMediaKeys();
    if (enabled) {
      await activate();
    } else {
      await deactivate();
    }
  }

  Future<void> activate() async {
    if (_activated) return;
    _activated = true;
    final mediaButtons = MediaButtonService.instance;
    mediaButtons.setOnToggle(
      () => unawaited(_routeToggle()),
      owner: _owner,
    );
    mediaButtons.setOnCancel(
      () => unawaited(_routeCancel()),
      owner: _owner,
    );
    try {
      await mediaButtons.activate(owner: _owner);
    } catch (e) {
      debugPrint('[VoiceSessionRouter] activate failed: $e');
      mediaButtons.clearCallbacks(owner: _owner);
      _activated = false;
    }
  }

  Future<void> deactivate() async {
    if (!_activated) return;
    _activated = false;
    final mediaButtons = MediaButtonService.instance;
    mediaButtons.clearCallbacks(owner: _owner);
    try {
      await mediaButtons.deactivate(owner: _owner);
    } catch (e) {
      debugPrint('[VoiceSessionRouter] deactivate failed: $e');
    }
  }

  Future<void> _routeToggle() async {
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) {
        // Very early cold start: the persistent service may not be up yet.
        // Start it — events sent before its isolate is ready are dropped.
        await CompanionForegroundService.startPersistent();
      }
      FlutterForegroundTask.sendDataToTask({'type': 'voice_toggle'});
    } catch (e) {
      debugPrint('[VoiceSessionRouter] toggle route failed: $e');
    }
  }

  Future<void> _routeCancel() async {
    try {
      FlutterForegroundTask.sendDataToTask({'type': 'voice_cancel'});
    } catch (e) {
      debugPrint('[VoiceSessionRouter] cancel route failed: $e');
    }
  }
}
