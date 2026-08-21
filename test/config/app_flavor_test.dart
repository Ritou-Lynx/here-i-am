import 'package:flutter_test/flutter_test.dart';
import 'package:memex/config/app_flavor.dart';

void main() {
  tearDown(() => AppFlavor.init('global'));

  test('desktop fallback uses Here I am V3 when platform flavor is absent', () {
    AppFlavor.init(null, defaultToHereIAm: true);

    expect(AppFlavor.isHereIAm, isTrue);
    expect(AppFlavor.isDev, isTrue);
  });

  test('explicit platform flavor wins over the desktop fallback', () {
    AppFlavor.init('cnEarly', defaultToHereIAm: true);

    expect(AppFlavor.isHereIAm, isFalse);
    expect(AppFlavor.isCN, isTrue);
    expect(AppFlavor.isEarly, isTrue);
  });

  test('non-desktop startup keeps the existing global default', () {
    AppFlavor.init(null);

    expect(AppFlavor.isHereIAm, isFalse);
    expect(AppFlavor.isGlobal, isTrue);
    expect(AppFlavor.isStable, isTrue);
  });
}
