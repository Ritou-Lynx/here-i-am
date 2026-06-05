import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/companion/widgets/companion_first_shell.dart';
import 'package:memex/ui/companion/widgets/companion_life_space_screen.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';
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

  testWidgets('life space top bar shows all tab labels',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanionLifeSpaceScreen(
          timelineViewModel: _FakeTimelineViewModel(),
        ),
      ),
    );

    expect(find.text(UserStorage.l10n.bottomNavTimeline), findsOneWidget);
    expect(find.text(UserStorage.l10n.schedule), findsOneWidget);
    expect(find.text(UserStorage.l10n.personalCenter), findsOneWidget);

    // Back arrow is always visible.
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    // Tapping a tab switches content.
    await tester.tap(find.text(UserStorage.l10n.schedule));
    await tester.pump();
    // The schedule tab pill should now be highlighted (no simple finder for
    // selected style; verifying it doesn't crash is the main signal).
  });

  testWidgets('life space route passes the existing timeline view model',
      (tester) async {
    final timelineViewModel = _FakeTimelineViewModel();
    late CompanionLifeSpaceScreen destination;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final route = companionLifeSpaceRoute(
              timelineViewModel: timelineViewModel,
            ) as MaterialPageRoute<void>;
            destination = route.builder(context) as CompanionLifeSpaceScreen;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(destination.timelineViewModel, same(timelineViewModel));
  });
}

class _FakeTimelineViewModel extends ChangeNotifier
    implements TimelineViewModel {
  @override
  final Command0<void> load = Command0<void>(() async => const Ok.v());

  @override
  List<TimelineCardModel> cards = [];

  @override
  bool isLoading = false;

  @override
  String? errorMessage;

  @override
  bool hasMore = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
