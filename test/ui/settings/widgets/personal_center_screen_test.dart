import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.initL10n();
  });

  testWidgets('personal center renders profile tile and settings in a single scrollable list',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PersonalCenterScreen(),
        ),
      ),
    );

    // The entire body should be a single ListView (not a Column with an
    // Expanded ListView inside it).
    final listViews = find.byType(ListView);
    expect(listViews, findsOneWidget);

    // The profile section is gone — no more centered avatar column.
    expect(
      find.byKey(const ValueKey('personal_center_profile')),
      findsNothing,
    );

    // The old search header is gone.
    expect(
      find.byKey(const ValueKey('personal_center_header')),
      findsNothing,
    );
  });
}
