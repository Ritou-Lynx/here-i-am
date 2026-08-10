import 'dart:io';

import 'package:flutter/services.dart';

class CompanionShareService {
  CompanionShareService._();

  static final CompanionShareService instance = CompanionShareService._();

  static const MethodChannel _channel =
      MethodChannel('com.memexlab.memex/companion_share');

  bool get isSupported => Platform.isAndroid;

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
