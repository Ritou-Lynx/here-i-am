import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which persona chat is visibly open in the foreground.
///
/// This is intentionally lightweight and timestamped because notification
/// decisions can happen from another isolate. Readers reload preferences and
/// ignore stale values instead of trusting a long-lived in-memory flag.
class ActivePersonaChatService {
  ActivePersonaChatService._();
  static final ActivePersonaChatService instance = ActivePersonaChatService._();

  static const _keyCharacterId = 'active_persona_chat_character_id';
  static const _keyUpdatedAtMs = 'active_persona_chat_updated_at_ms';
  static const _freshWindow = Duration(minutes: 2);

  Future<void> markActive(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCharacterId, characterId);
    await prefs.setInt(_keyUpdatedAtMs, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> clear({String? characterId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (characterId != null &&
        prefs.getString(_keyCharacterId) != characterId) {
      return;
    }
    await prefs.remove(_keyCharacterId);
    await prefs.remove(_keyUpdatedAtMs);
  }

  Future<bool> isActive(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getString(_keyCharacterId) != characterId) {
      return false;
    }
    final updatedAtMs = prefs.getInt(_keyUpdatedAtMs);
    if (updatedAtMs == null) return false;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
    return !age.isNegative && age <= _freshWindow;
  }

  /// Returns the most-recently active character ID if it is still inside the
  /// freshness window, or null otherwise. Used by features (e.g. Reading
  /// Capture from share intent) that need to route content to "whichever
  /// companion the user was just talking to".
  Future<String?> getActiveCharacterId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final id = prefs.getString(_keyCharacterId);
    if (id == null || id.isEmpty) return null;
    final updatedAtMs = prefs.getInt(_keyUpdatedAtMs);
    if (updatedAtMs == null) return null;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
    if (age.isNegative || age > _freshWindow) return null;
    return id;
  }
}
