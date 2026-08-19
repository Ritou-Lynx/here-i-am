import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Durable fallback for task-isolate -> main-isolate call UI updates.
///
/// flutter_foreground_task's direct data callback is best-effort across
/// engine lifecycle changes. This single JSON snapshot lets the main isolate
/// recover subtitles, reply text, and call-ended state even when a callback
/// is missed.
abstract final class CallVoiceStateBridge {
  static const _snapshotKey = 'call_voice_state_snapshot_v1';

  static Future<void> write(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(state));
  }

  static Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
