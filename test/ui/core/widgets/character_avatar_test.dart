import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';

void main() {
  Future<void> pumpAvatar(
    WidgetTester tester, {
    required String? avatar,
    required String name,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CharacterAvatar(avatar: avatar, name: name),
        ),
      ),
    );
  }

  testWidgets('null avatar shows an uppercase name initial', (tester) async {
    await pumpAvatar(tester, avatar: null, name: 'lin');

    expect(find.byType(AvatarInitialPlaceholder), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('legacy non-image values show the name initial', (tester) async {
    for (final avatar in ['Felix', 'i']) {
      await pumpAvatar(tester, avatar: avatar, name: '林埃');

      expect(find.byType(AvatarInitialPlaceholder), findsOneWidget);
      expect(find.text('林'), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    }
  });

  testWidgets('empty name shows the person icon', (tester) async {
    await pumpAvatar(tester, avatar: null, name: '');

    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
