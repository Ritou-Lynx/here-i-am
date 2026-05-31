import 'package:flutter/material.dart';
import 'package:memex/ui/schedule/widgets/schedule_aggregator_screen.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

import 'companion_review_screen.dart';

/// Secondary life space. Chat remains the app home; this screen is opened only
/// when the user explicitly wants to browse organized information.
class CompanionLifeSpaceScreen extends StatefulWidget {
  const CompanionLifeSpaceScreen({super.key});

  @override
  State<CompanionLifeSpaceScreen> createState() =>
      _CompanionLifeSpaceScreenState();
}

class _CompanionLifeSpaceScreenState extends State<CompanionLifeSpaceScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CompanionReviewScreen(
            viewModel: context.watch<TimelineViewModel>(),
          ),
          const ScheduleAggregatorScreen(),
          const PersonalCenterScreen(),
        ],
      ),
      bottomNavigationBar: CompanionLifeSpaceNavigationBar(
        currentIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
      ),
    );
  }
}

@visibleForTesting
class CompanionLifeSpaceNavigationBar extends StatelessWidget {
  const CompanionLifeSpaceNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.auto_stories_outlined),
          selectedIcon: const Icon(Icons.auto_stories_rounded),
          label: UserStorage.l10n.bottomNavTimeline,
        ),
        NavigationDestination(
          icon: const Icon(Icons.calendar_today_outlined),
          selectedIcon: const Icon(Icons.calendar_today_rounded),
          label: UserStorage.l10n.schedule,
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline_rounded),
          selectedIcon: const Icon(Icons.person_rounded),
          label: UserStorage.l10n.personalCenter,
        ),
      ],
    );
  }
}
