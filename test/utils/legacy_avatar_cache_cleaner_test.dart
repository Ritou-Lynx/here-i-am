import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/utils/legacy_avatar_cache_cleaner.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('removes only legacy generated avatar SVG files', () async {
    final directory = await Directory.systemTemp.createTemp('avatar_cache_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    await File(p.join(directory.path, 'avatar_abc.svg')).writeAsString('a');
    await File(p.join(directory.path, 'avatar_def.svg')).writeAsString('b');
    await File(p.join(directory.path, 'other.svg')).writeAsString('c');

    await clearLegacyAvatarCache(directory);

    expect(
      await File(p.join(directory.path, 'avatar_abc.svg')).exists(),
      false,
    );
    expect(
      await File(p.join(directory.path, 'avatar_def.svg')).exists(),
      false,
    );
    expect(await File(p.join(directory.path, 'other.svg')).exists(), true);
  });

  test('one-time cleanup records completion and skips later scans', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('avatar_once_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final first = File(p.join(directory.path, 'avatar_first.svg'));
    await first.writeAsString('first');
    await clearLegacyAvatarCacheOnce(directory: directory);
    expect(await first.exists(), false);

    final later = File(p.join(directory.path, 'avatar_later.svg'));
    await later.writeAsString('later');
    await clearLegacyAvatarCacheOnce(directory: directory);

    expect(await later.exists(), true);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(legacyAvatarCacheClearedKey), true);
  });
}
