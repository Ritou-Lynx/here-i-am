import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/companion/widgets/companion_media_tray.dart';
import 'package:memex/utils/user_storage.dart';

void main() {
  setUp(() async {
    await UserStorage.initL10n();
  });

  testWidgets('open media tray keeps album and camera actions visible',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanionMediaTray(
            isOpen: true,
            loadSuggestions: () async => [],
            onSubmit: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(UserStorage.l10n.photos), findsOneWidget);
    expect(find.text(UserStorage.l10n.camera), findsOneWidget);
  });

  testWidgets('closed media tray stays out of the conversation',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanionMediaTray(
            isOpen: false,
            loadSuggestions: () async => [],
            onSubmit: (_) async => true,
          ),
        ),
      ),
    );

    expect(find.text(UserStorage.l10n.photos), findsNothing);
    expect(find.text(UserStorage.l10n.camera), findsNothing);
  });
}
