import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

/// A/B switch for the 春雨昼眠 Chat user-text color (olive vs moss), persisted
/// so both options can be compared on-device back to back.
///
/// Design source: docs/design/春雨昼眠主题UI设计原型.md §22.5 / ADR-2 / ADR-13.
/// Olive #6E7541 measures ~2.7:1 on the dark-green background; moss #A3A866
/// keeps the same hue family and lifts contrast to ~5:1. The link quote-bar
/// pin color is always moss (links need clarity, no A/B per product call).
class SpringRainChatStyleController extends ChangeNotifier {
  static const _prefsKey = 'spring_rain_chat_user_color_id';

  static const String oliveId = 'olive';
  static const String mossId = 'moss';

  static const Color oliveUserColor = Color(0xFF6E7541);
  static const Color mossUserColor = Color(0xFFA3A866);

  String _userColorId = mossId;
  bool _loaded = false;

  String get userColorId => _userColorId;
  bool get loaded => _loaded;

  /// User message text color, switchable for the on-device A/B.
  Color get userColor =>
      _userColorId == oliveId ? oliveUserColor : mossUserColor;

  /// Link quote-bar pin + title color: fixed moss, not part of the A/B.
  Color get linkColor => mossUserColor;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);
    if (savedId == oliveId || savedId == mossId) {
      _userColorId = savedId!;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> selectUserColor(String id) async {
    if (id != oliveId && id != mossId) return;
    if (id == _userColorId) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
    _userColorId = id;
    notifyListeners();
  }
}
