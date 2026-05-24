import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/character/widgets/character_config_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
  });

  testWidgets('blank persona does not block character save validation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CharacterEditPage(),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).first,
      'Test character',
    );
    await tester.tap(find.text(UserStorage.l10n.save));
    await tester.pump();

    expect(
        find.text(UserStorage.l10n.pleaseEnterCharacterPersona), findsNothing);
  });
}
