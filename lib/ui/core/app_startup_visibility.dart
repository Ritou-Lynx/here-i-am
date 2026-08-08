import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Coordinates chrome that must stay hidden until the primary app surface is
/// genuinely interactive.
///
/// The floating record ball lives above the Navigator, so route-local loading
/// widgets cannot hide it on their own. The companion shell flips this signal
/// only after its first usable frame has rendered.
class AppStartupVisibilityController {
  AppStartupVisibilityController._();

  static const _nativeSplashChannel =
      MethodChannel('com.memexlab.memex/opening_splash');
  static bool _nativeSplashDismissed = false;

  static final ValueNotifier<bool> isAppInteractive =
      ValueNotifier<bool>(false);

  static void markLoading() {
    if (isAppInteractive.value) {
      isAppInteractive.value = false;
    }
  }

  static void dismissNativeSplash() {
    if (_nativeSplashDismissed) return;
    _nativeSplashDismissed = true;
    unawaited(_dismissNativeSplash());
  }

  static Future<void> _dismissNativeSplash() async {
    try {
      await _nativeSplashChannel.invokeMethod<void>('dismiss');
    } on MissingPluginException {
      // Non-Android platforms and widget tests do not install this channel.
    } on PlatformException catch (error) {
      debugPrint('Unable to dismiss native opening splash: $error');
    }
  }

  static void markInteractive() {
    if (!isAppInteractive.value) {
      isAppInteractive.value = true;
    }
    dismissNativeSplash();
  }
}
