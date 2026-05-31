import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/companion/widgets/companion_first_shell.dart';
import 'package:memex/ui/companion/widgets/companion_life_space_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  test('last active enabled character wins over the fallback', () {
    expect(
      resolveCompanionFirstCharacterId(
        enabledCharacterIds: const ['luna', 'mira'],
        rememberedCharacterId: 'mira',
      ),
      'mira',
    );
  });

  test('disabled or missing remembered character falls back to first enabled',
      () {
    expect(
      resolveCompanionFirstCharacterId(
        enabledCharacterIds: const ['luna', 'mira'],
        rememberedCharacterId: 'disabled-character',
      ),
      'luna',
    );
    expect(
      resolveCompanionFirstCharacterId(
        enabledCharacterIds: const [],
        rememberedCharacterId: 'mira',
      ),
      isNull,
    );
  });

  test('last active companion is persisted per user', () async {
    await UserStorage.setLastActiveCompanionCharacterId('user-a', 'luna');
    await UserStorage.setLastActiveCompanionCharacterId('user-b', 'mira');

    expect(
      await UserStorage.getLastActiveCompanionCharacterId('user-a'),
      'luna',
    );
    expect(
      await UserStorage.getLastActiveCompanionCharacterId('user-b'),
      'mira',
    );
  });

  testWidgets('life space navigation exposes supporting destinations',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CompanionLifeSpaceNavigationBar(
            currentIndex: selected,
            onDestinationSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text(UserStorage.l10n.bottomNavTimeline), findsOneWidget);
    expect(find.text(UserStorage.l10n.schedule), findsOneWidget);
    expect(find.text(UserStorage.l10n.personalCenter), findsOneWidget);

    await tester.tap(find.text(UserStorage.l10n.schedule));
    expect(selected, 1);
  });
}
