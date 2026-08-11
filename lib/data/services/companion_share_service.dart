import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class CompanionShareService {
  CompanionShareService._();

  static final CompanionShareService instance = CompanionShareService._();

  static const MethodChannel _channel =
      MethodChannel('com.memexlab.memex/companion_share');

  bool get isSupported => Platform.isAndroid;

  void startListening(void Function(String? text, String? imagePath) onShare) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShareReceived') {
        final args = call.arguments as Map;
        final text = args['text'] as String?;
        final imagePath = args['imagePath'] as String?;
        onShare(text, imagePath);
      }
    });
  }

  Future<bool> isAccessibilityServiceEnabled() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled') ??
        false;
  }

  Future<bool> isServiceConnected() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('isServiceConnected') ?? false;
  }

  Future<void> openAccessibilitySettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<bool>('openAccessibilitySettings');
  }
}
