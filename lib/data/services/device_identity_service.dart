import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Installation-scoped identity used as sync provenance.
///
/// This value must not be copied through backup/restore: a restored app is a
/// different sync client. [BackupService] therefore excludes this key prefix.
class DeviceIdentityService {
  DeviceIdentityService._();

  static const preferenceKey = 'here_i_am_installation_id';
  static const _uuid = Uuid();

  static String? _cached;
  static Future<String>? _pending;

  static Future<String> getOrCreate() {
    final cached = _cached;
    if (cached != null && cached.isNotEmpty) return Future.value(cached);
    return _pending ??= _loadOrCreate().whenComplete(() => _pending = null);
  }

  static Future<String> _loadOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(preferenceKey)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return _cached = existing;
    }

    final created = _uuid.v4();
    await prefs.setString(preferenceKey, created);
    return _cached = created;
  }

  static void resetForTesting() {
    _cached = null;
    _pending = null;
  }
}
