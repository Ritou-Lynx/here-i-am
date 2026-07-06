import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/utils/user_storage.dart';

import 'companion_health_panel.dart';
import 'companion_review_screen.dart';

/// Secondary life space. Chat remains the app home; this screen is opened only
/// when the user explicitly wants to browse organized information.
///
/// Tab switching lives in the top bar alongside a persistent back arrow so the
/// user can return to chat from any tab with one tap.
class CompanionLifeSpaceScreen extends StatefulWidget {
  const CompanionLifeSpaceScreen({
    super.key,
    this.timelineViewModel,
  });

  /// No longer used — kept for caller compatibility during transition.
  final dynamic timelineViewModel;

  @override
  State<CompanionLifeSpaceScreen> createState() =>
      _CompanionLifeSpaceScreenState();
}

class _CompanionLifeSpaceScreenState extends State<CompanionLifeSpaceScreen> {
  int _currentIndex = 0;
  final Set<int> _visitedIndexes = {0};

  void _selectTab(int index) {
    setState(() {
      _currentIndex = index;
      _visitedIndexes.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      UserStorage.l10n.bottomNavTimeline,
      UserStorage.l10n.healthPanel,
      UserStorage.l10n.personalCenter,
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _LifeSpaceTopBar(
              currentIndex: _currentIndex,
              labels: labels,
              onBack: () => Navigator.pop(context),
              onTabSelected: _selectTab,
            ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: List.generate(
                  labels.length,
                  (index) => _visitedIndexes.contains(index)
                      ? _buildTab(index)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    return switch (index) {
      0 => const CompanionReviewScreen(),
      1 => const CompanionHealthPanel(),
      _ => const PersonalCenterScreen(),
    };
  }
}

class _LifeSpaceTopBar extends StatelessWidget {
  const _LifeSpaceTopBar({
    required this.currentIndex,
    required this.labels,
    required this.onBack,
    required this.onTabSelected,
  });

  final int currentIndex;
  final List<String> labels;
  final VoidCallback onBack;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: AppColors.primary,
            padding: const EdgeInsets.all(10),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(labels.length, (i) {
                  final selected = i == currentIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => onTabSelected(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
