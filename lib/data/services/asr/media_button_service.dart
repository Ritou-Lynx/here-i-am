import 'dart:async';

import 'package:flutter/services.dart';

/// Bridges Android MediaSession button events into the voice input controller.
class MediaButtonService {
  MediaButtonService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static final MediaButtonService instance = MediaButtonService._();

  static const MethodChannel _channel =
      MethodChannel('com.memexlab.memex/media_buttons');

  VoidCallback? _onToggle;
  VoidCallback? _onCancel;

  void setOnToggle(VoidCallback cb) {
    _onToggle = cb;
  }

  void setOnCancel(VoidCallback cb) {
    _onCancel = cb;
  }

  void clearCallbacks() {
    _onToggle = null;
    _onCancel = null;
  }

  Future<void> activate() async {
    await _channel.invokeMethod<void>('activate');
  }

  Future<void> deactivate() async {
    await _channel.invokeMethod<void>('deactivate');
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'voiceToggle':
        _onToggle?.call();
        break;
      case 'voiceCancel':
        _onCancel?.call();
        break;
      default:
        throw PlatformException(
          code: 'unimplemented',
          message: 'Unknown media button method: ${call.method}',
        );
    }
  }
}
