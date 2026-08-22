import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat message-layout A/B switch: 春雨昼眠 waterfall text (default) vs
/// traditional chat bubbles, persisted so the choice survives restarts.
///
/// Waterfall mode is the 春雨昼眠 design direction (无气泡连续对话轴).
/// Bubble mode restores the conventional IM layout — i on the left, the user
/// on the right — but keeps the same spring-rain palette (dark green surface,
/// warm ivory, moss/olive accents) and sentence-level splitting, so both
/// modes feel like the same room.
class ChatViewModeController extends ChangeNotifier {
  static const _prefsKey = 'chat_view_mode_bubbles';

  static const String flowId = 'flow';
  static const String bubblesId = 'bubbles';

  bool _isBubbleMode = false;
  bool _loaded = false;

  bool get isBubbleMode => _isBubbleMode;
  String get modeId => _isBubbleMode ? bubblesId : flowId;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isBubbleMode = prefs.getBool(_prefsKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(String id) async {
    final next = id == bubblesId;
    if (next == _isBubbleMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, next);
    _isBubbleMode = next;
    notifyListeners();
  }

  Future<void> toggle() => setMode(_isBubbleMode ? flowId : bubblesId);
}
