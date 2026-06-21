import 'package:flutter/foundation.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HereIamThemeController extends ChangeNotifier {
  static const _prefsKey = 'here_iam_visual_theme_id';

  HereIamThemeTokens _tokens = HereIamThemeTokens.current;
  bool _loaded = false;

  HereIamThemeTokens get tokens => _tokens;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);
    _setTokens(
      savedId == null
          ? HereIamThemeTokens.current
          : HereIamThemeTokens.byId(savedId),
      notify: false,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> selectTheme(String id) async {
    final next = HereIamThemeTokens.byId(id);
    if (next.id == _tokens.id) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next.id);
    _setTokens(next);
  }

  void _setTokens(HereIamThemeTokens tokens, {bool notify = true}) {
    _tokens = tokens;
    HereIamThemeRuntime.current = tokens;
    if (notify) notifyListeners();
  }
}
