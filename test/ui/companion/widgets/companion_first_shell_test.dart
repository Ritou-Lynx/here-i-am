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

  testWidgets('life space top bar shows all tab labels', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CompanionLifeSpaceScreen()),
    );

    expect(
      find.byKey(const ValueKey('life_space_rain_glass_background')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('life_space_content_surface')),
      findsOneWidget,
    );
    expect(find.text(UserStorage.l10n.bottomNavTimeline), findsOneWidget);
    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('话题线索'), findsOneWidget);
    expect(find.text(UserStorage.l10n.personalCenter), findsNothing);

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    await tester.tap(find.text('Health'));
    await tester.pump();
  });

  testWidgets('life space route builds the secondary screen', (tester) async {
    late CompanionLifeSpaceScreen destination;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final route = companionLifeSpaceRoute() as MaterialPageRoute<void>;
            destination = route.builder(context) as CompanionLifeSpaceScreen;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(destination, isA<CompanionLifeSpaceScreen>());
  });
}
