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
/// Two colors of the same olive/moss hue family (H≈65–68°): the deep olive
/// #6E7541 for everyday use (the original look the user prefers; ~2.7:1 on the
/// dark surface — a knowingly accepted trade-off, see ADR-16) and moss green
/// #A3A866 (~5:1) as a more legible alternative. Only the user message text
/// consumes [userColor]; nothing else changes.
class SpringRainChatColorController extends ChangeNotifier {
  static const _prefsKey = 'spring_rain_user_color_id';

  static const List<SpringRainUserColorOption> options = [
    SpringRainUserColorOption(
      id: 'deep',
      label: '橄榄 · 深',
      color: Color(0xFF6E7541),
    ),
    SpringRainUserColorOption(
      id: 'moss',
      label: '苔绿 · 浅',
      color: Color(0xFFA3A866),
    ),
  ];

  Color _userColor = SpringRainChatTokens.springRainDaydream.userColor;
  String _selectedId = 'deep';

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
