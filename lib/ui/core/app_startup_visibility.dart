import 'package:flutter/foundation.dart';

/// Coordinates chrome that must stay hidden until the primary app surface is
/// genuinely interactive.
///
/// The floating record ball lives above the Navigator, so route-local loading
/// widgets cannot hide it on their own. The companion shell flips this signal
/// only after its first usable frame has rendered.
class AppStartupVisibilityController {
  AppStartupVisibilityController._();

  static final ValueNotifier<bool> isAppInteractive =
      ValueNotifier<bool>(false);

  static void markLoading() {
    if (isAppInteractive.value) {
      isAppInteractive.value = false;
    }
  }

  static void markInteractive() {
    if (!isAppInteractive.value) {
      isAppInteractive.value = true;
    }
  }
}
