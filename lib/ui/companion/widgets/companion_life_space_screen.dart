import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/companion/view_models/ledger_view_model.dart';
import 'package:memex/ui/companion/view_models/schedule_view_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

import 'companion_health_panel.dart';
import 'companion_ledger_panel.dart';
import 'companion_review_screen.dart';
import 'companion_schedule_panel.dart';
import 'topic_thread_browser_screen.dart';

/// Secondary life space. Chat remains the app home; this screen is opened only
/// when the user explicitly wants to browse organized information.
///
/// Tab switching lives in the top bar alongside a persistent back arrow so the
/// user can return to chat from any tab with one tap.
class CompanionLifeSpaceScreen extends StatefulWidget {
  const CompanionLifeSpaceScreen({
    super.key,
    this.timelineViewModel,
    this.financeService,
  });

  /// No longer used — kept for caller compatibility during transition.
  final dynamic timelineViewModel;

  /// Optional injection point for tests; production uses the app database.
  final AiFinanceService? financeService;

  @override
  State<CompanionLifeSpaceScreen> createState() =>
      _CompanionLifeSpaceScreenState();
}

class _CompanionLifeSpaceScreenState extends State<CompanionLifeSpaceScreen> {
  static const _backgroundAsset = 'assets/images/雨玻璃.jpg';

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
      '日程',
      'Ledger',
      'Health',
      '话题线索',
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF252A22),
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _backgroundAsset,
              key: const ValueKey('life_space_rain_glass_background'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _LifeSpaceTopBar(
                    currentIndex: _currentIndex,
                    labels: labels,
                    onBack: () => Navigator.pop(context),
                    onTabSelected: _selectTab,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _LifeSpaceContentArea(
                      child: SafeArea(
                        top: false,
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
                    ),
                  ),
                ],
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
      1 => ChangeNotifierProvider(
          create: (_) => ScheduleViewModel(
            queryService: MemoryCardQueryService(AppDatabase.instance),
          )..load.execute(),
          child: const CompanionSchedulePanel(),
        ),
      2 => ChangeNotifierProvider(
          create: (_) => LedgerViewModel(
            service: widget.financeService ??
                AiFinanceService(db: AppDatabase.instance),
          )..load.execute(),
          child: const CompanionLedgerPanel(),
        ),
      3 => const CompanionHealthPanel(),
      _ => const TopicThreadBrowserScreen(),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _FrostedControl(
            borderRadius: BorderRadius.circular(999),
            child: IconButton(
              key: const ValueKey('life_space_back_button'),
              onPressed: onBack,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              color: const Color(0xFFF5EEE0),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 44,
                height: 44,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FrostedControl(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 44,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: List.generate(labels.length, (i) {
                      final selected = i == currentIndex;
                      return Semantics(
                        selected: selected,
                        button: true,
                        child: InkWell(
                          key: ValueKey('life_space_tab_$i'),
                          onTap: () => onTabSelected(i),
                          borderRadius: BorderRadius.circular(999),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xE8EEE9DB)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.10,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: selected
                                    ? const Color(0xFF293025)
                                    : const Color(0xE6F5EEE0),
                                shadows: selected
                                    ? null
                                    : const [
                                        Shadow(
                                          color: Color(0x66000000),
                                          blurRadius: 5,
                                        ),
                                      ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedControl extends StatelessWidget {
  const _FrostedControl({
    required this.child,
    required this.borderRadius,
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x4DFFFFFF),
          borderRadius: borderRadius,
          border: Border.all(color: const Color(0x66FFFFFF), width: 0.8),
        ),
        child: child,
      ),
    );
  }
}

class _LifeSpaceContentArea extends StatelessWidget {
  const _LifeSpaceContentArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('life_space_content_surface'),
      child: child,
    );
  }
}
