import 'dart:io';

import 'package:memex/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const legacyAvatarCacheClearedKey =
    'legacy_dice'
    'bear_cache_cleared';

final _logger = getLogger('LegacyAvatarCacheCleaner');

/// Deletes legacy generated avatar files from [directory].
Future<void> clearLegacyAvatarCache(Directory directory) async {
  if (!await directory.exists()) return;

  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name.startsWith('avatar_') && name.endsWith('.svg')) {
      await entity.delete();
    }
  }
}

/// Clears the legacy cache once without delaying or failing app startup.
Future<void> clearLegacyAvatarCacheOnce({Directory? directory}) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(legacyAvatarCacheClearedKey) == true) return;

    final supportDirectory =
        directory ?? await getApplicationSupportDirectory();
    await clearLegacyAvatarCache(supportDirectory);
    await preferences.setBool(legacyAvatarCacheClearedKey, true);
  } catch (error, stackTrace) {
    _logger.warning('Failed to clear legacy avatar cache', error, stackTrace);
  }
}
