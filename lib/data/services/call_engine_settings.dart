import 'package:shared_preferences/shared_preferences.dart';

enum CallEngine {
  classic('classic'),
  gptLive('gpt_live');

  const CallEngine(this.id);
  final String id;

  static CallEngine parse(String? raw) => CallEngine.values.firstWhere(
    (engine) => engine.id == raw,
    orElse: () => CallEngine.gptLive,
  );
}

class CallEngineSettings {
  CallEngineSettings._();

  static const _key = 'call.engine';
  static const _legacySleepNudgeKey = 'sleep_nudge.engine';

  static Future<CallEngine> get() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_key);
    if (current != null) return CallEngine.parse(current);
    return CallEngine.parse(prefs.getString(_legacySleepNudgeKey));
  }

  static Future<void> set(CallEngine engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, engine.id);
  }
}
