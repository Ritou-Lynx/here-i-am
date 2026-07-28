import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/spring_rain_chat_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One selectable user-text color candidate for the 春雨昼眠 chat skin.
@immutable
class SpringRainUserColorOption {
  const SpringRainUserColorOption({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final Color color;
}

/// Runtime switch for the chat user-message color.
///
/// Two lightness steps of the same moss/olive hue (H≈68°): moss green #A3A866
/// for everyday use (the §22.5 / ADR-13 final — ~5:1 contrast on the dark
/// surface) and a brighter moss #AEB873 that stays legible in a dark room.
/// Only the user message text consumes [userColor]; nothing else changes.
class SpringRainChatColorController extends ChangeNotifier {
  static const _prefsKey = 'spring_rain_user_color_id';

  static const List<SpringRainUserColorOption> options = [
    SpringRainUserColorOption(
      id: 'moss',
      label: '苔绿 · 日常',
      color: Color(0xFFA3A866),
    ),
    SpringRainUserColorOption(
      id: 'bright',
      label: '苔绿 · 暗室',
      color: Color(0xFFAEB873),
    ),
  ];

  Color _userColor = SpringRainChatTokens.springRainDaydream.userColor;
  String _selectedId = 'moss';

  Color get userColor => _userColor;
  String get selectedId => _selectedId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);
    final match = options.where((o) => o.id == savedId);
    if (match.isNotEmpty) {
      _userColor = match.first.color;
      _selectedId = match.first.id;
    }
    notifyListeners();
  }

  Future<void> select(String id) async {
    final match = options.where((o) => o.id == id);
    if (match.isEmpty || match.first.id == _selectedId) return;
    _userColor = match.first.color;
    _selectedId = match.first.id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
  }
}
