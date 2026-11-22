import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/services/i_mcp_service.dart';
import 'package:memex/ui/companion/models/life_digest_models.dart';
import 'package:memex/ui/companion/view_models/life_digest_view_model.dart';
import 'package:memex/ui/settings/widgets/i_mcp_connect_page.dart';
import 'package:provider/provider.dart';

/// Read-only Life Digest & Long-Term Profile panel for embedding inside
/// [CompanionLifeSpaceScreen] or [LifeDigestScreen].
///
/// Follows the 春雨昼眠 · 生活空间外壳 visual language: high-opacity frosted
/// light-mist cards directly on the crisp rain-glass background, with warm
/// ivory headers over the glass and olive/warm-amber accents inside cards.
class CompanionLifeDigestPanel extends StatelessWidget {
  const CompanionLifeDigestPanel({super.key});

  static const _ink = Color(0xFF293025);
  static const _muted = Color(0xFF667061);
  static const _accent = Color(0xFF737B46);
  static const _surface = Color(0xE8F7F5EE);
  static const _cardBorder = Color(0xB8FFFFFF);
  static const _onRain = Color(0xFFF5EEE0);
  static const _warnAccent = Color(0xFFC5821C);
  static const _warnSurface = Color(0xF0FAF2DE);
  static const _warnBorder = Color(0x88D09B31);

  static const _onRainShadow = <Shadow>[
    Shadow(color: Color(0x66000000), blurRadius: 5),
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.read<LifeDigestViewModel>();
    return ListenableBuilder(
      listenable: Listenable.merge([vm, vm.load, vm.refresh]),
      builder: (context, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: _SubTabBar(
                currentTab: vm.currentTab,
                onSelected: vm.selectTab,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: _accent,
                backgroundColor: const Color(0xFFF7F5EE),
                onRefresh: () => vm.refresh.execute(),
                child: _buildBody(context, vm),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, LifeDigestViewModel vm) {
    final headerWidgets = <Widget>[
      if (vm.currentTab == LifeDigestTab.day) ...[
        _PeriodSelectorBar(
          label: formatIsoDate(vm.selectedDate),
          badge: vm.dayData?.displayStageLabel,
          canStepForward: vm.canStepDateForward,
          onPrevious: () => vm.stepDate(-1),
          onNext: () => vm.stepDate(1),
        ),
        const SizedBox(height: 12),
      ] else if (vm.currentTab == LifeDigestTab.week) ...[
        _PeriodSelectorBar(
          label: vm.selectedWeek.formatted,
          subtitle:
              vm.weekData?.dateRange ?? vm.selectedWeek.fallbackDateRange,
          canStepForward: vm.canStepWeekForward,
          onPrevious: () => vm.stepWeek(-1),
          onNext: () => vm.stepWeek(1),
        ),
        const SizedBox(height: 12),
      ] else if (vm.currentTab == LifeDigestTab.month) ...[
        _PeriodSelectorBar(
          label: formatIsoMonth(vm.selectedMonth),
          subtitle: vm.monthData?.dateRange,
          canStepForward: vm.canStepMonthForward,
          onPrevious: () => vm.stepMonth(-1),
          onNext: () => vm.stepMonth(1),
        ),
        const SizedBox(height: 12),
      ],
    ];

    final failure = vm.currentFailure;
    if (vm.isLoading && !vm.hasCurrentTabData && failure == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          ...headerWidgets,
          const SizedBox(height: 64),
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: _onRain,
                strokeWidth: 2.2,
              ),
            ),
          ),
        ],
      );
    }

    if (failure != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          ...headerWidgets,
          _FailureCard(
            failure: failure,
            onOpenConnect: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IMcpConnectPage()),
              );
              if (context.mounted) {
                await vm.refresh.execute();
              }
            },
            onRetry: () => vm.refresh.execute(),
          ),
        ],
      );
    }

    final contentWidgets = switch (vm.currentTab) {
      LifeDigestTab.day => _buildDayContent(vm.dayData),
      LifeDigestTab.week => _buildWeekContent(vm.weekData),
      LifeDigestTab.month => _buildMonthContent(vm.monthData),
      LifeDigestTab.todos => _buildTodosContent(vm.todosData),
      LifeDigestTab.profile => _buildProfileContent(vm.profileData),
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 32),
      children: [
        ...headerWidgets,
        ...contentWidgets,
      ],
    );
  }

  List<Widget> _buildDayContent(DayDigestData? data) {
    if (data == null || !data.available || data.failed || !data.hasBodyContent) {
      return [
        _EmptyCard(
          message: data?.note ?? '这一天还没有生成生活摘要',
        ),
      ];
    }

    return [
      if (data.morning != null && !data.morning!.isEmpty) ...[
        _MorningCard(morning: data.morning!),
        const SizedBox(height: 12),
      ],
      if (data.headline != null && data.headline!.isNotEmpty) ...[
        _HeadlineCard(headline: data.headline!),
        const SizedBox(height: 14),
      ],
      if (data.yourDay.isNotEmpty) ...[
        const _RainSectionTitle('你的一天'),
        const SizedBox(height: 8),
        _BulletListCard(items: data.yourDay),
        const SizedBox(height: 14),
      ],
      if (data.us.isNotEmpty) ...[
        const _RainSectionTitle('我们之间'),
        const SizedBox(height: 8),
        _BulletListCard(items: data.us),
        const SizedBox(height: 14),
      ],
      if (data.anomalies.isNotEmpty) ...[
        const _RainSectionTitle('异常提醒'),
        const SizedBox(height: 8),
        _AnomalyListCard(items: data.anomalies),
        const SizedBox(height: 14),
      ],
      if (data.note != null && data.note!.isNotEmpty)
        _FooterNote(text: data.note!),
    ];
  }

  List<Widget> _buildWeekContent(WeekDigestData? data) {
    if (data == null || !data.available || data.failed || !data.hasBodyContent) {
      return [
        _EmptyCard(
          message: data?.note ?? '这一周还没有生成周摘要',
        ),
      ];
    }

    return [
      if (data.headline != null && data.headline!.isNotEmpty) ...[
        _HeadlineCard(headline: data.headline!),
        const SizedBox(height: 14),
      ],
      if (data.highlights.isNotEmpty) ...[
        const _RainSectionTitle('本周重点'),
        const SizedBox(height: 8),
        _BulletListCard(items: data.highlights),
        const SizedBox(height: 14),
      ],
      if (data.us.isNotEmpty) ...[
        const _RainSectionTitle('我们之间'),
        const SizedBox(height: 8),
        _BulletListCard(items: data.us),
        const SizedBox(height: 14),
      ],
      if (data.moodRhythm != null && data.moodRhythm!.isNotEmpty) ...[
        const _RainSectionTitle('情绪与节奏'),
        const SizedBox(height: 8),
        _ProseCard(text: data.moodRhythm!),
        const SizedBox(height: 14),
      ],
      if (data.todosSummary != null && data.todosSummary!.isNotEmpty) ...[
        const _RainSectionTitle('待办推进'),
        const SizedBox(height: 8),
        _ProseCard(text: data.todosSummary!),
        const SizedBox(height: 14),
      ],
      if (data.note != null && data.note!.isNotEmpty)
        _FooterNote(text: data.note!),
    ];
  }

  List<Widget> _buildMonthContent(MonthDigestData? data) {
    if (data == null || !data.available || data.failed || !data.hasBodyContent) {
      return [
        _EmptyCard(
          message: data?.note ?? '这个月还没有生成月摘要',
        ),
      ];
    }

    return [
      if (data.headline != null && data.headline!.isNotEmpty) ...[
        _HeadlineCard(headline: data.headline!),
        const SizedBox(height: 14),
      ],
      if (data.themes.isNotEmpty) ...[
        const _RainSectionTitle('本月主题'),
        const SizedBox(height: 8),
        _BulletListCard(items: data.themes),
        const SizedBox(height: 14),
      ],
      if (data.us.isNotEmpty) ...[
        const _RainSectionTitle('我们之间'),
        const SizedBox(height: 8),
        _BulletListCard(items: data.us),
        const SizedBox(height: 14),
      ],
      if (data.shifts.isNotEmpty) ...[
        const _RainSectionTitle('状态与变化'),
        const SizedBox(height: 8),
        _BulletListCard(items: data.shifts),
        const SizedBox(height: 14),
      ],
      if (data.milestones.isNotEmpty) ...[
        const _RainSectionTitle('里程碑'),
        const SizedBox(height: 8),
        _BulletListCard(items: data.milestones),
        const SizedBox(height: 14),
      ],
      if (data.note != null && data.note!.isNotEmpty)
        _FooterNote(text: data.note!),
    ];
  }

  List<Widget> _buildTodosContent(LifeDigestTodosData? data) {
    final todos = data?.todos ?? const <LifeDigestTodoItem>[];
    if (todos.isEmpty) {
      return [
        _EmptyCard(
          message: data?.note ?? '当前没有未完成的待办',
        ),
        const SizedBox(height: 14),
        const _FooterNote(text: '在和林埃聊天时说一声即可划掉或放弃待办'),
      ];
    }

    return [
      for (final todo in todos) ...[
        _TodoCard(todo: todo),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
      const _FooterNote(text: '在和林埃聊天时说一声即可划掉或放弃待办'),
    ];
  }

  List<Widget> _buildProfileContent(LongTermProfileData? data) {
    final grouped = data?.orderedNonEmptyCategories ?? const [];
    if (data == null || !data.available || data.failed || grouped.isEmpty) {
      return [
        _EmptyCard(
          message: data?.note ?? '长期档案尚未整理出内容',
        ),
        const SizedBox(height: 14),
        const _FooterNote(text: '如需修改或删除条目，直接告诉林埃即可'),
      ];
    }

    return [
      for (final entry in grouped) ...[
        _RainSectionTitle(profileCategoryLabel(entry.key)),
        const SizedBox(height: 8),
        _ProfileCategoryCard(items: entry.value),
        const SizedBox(height: 14),
      ],
      const _FooterNote(text: '如需修改或删除条目，直接告诉林埃即可'),
    ];
  }
}

/// Standalone full-screen wrapper for opening the Life Digest & Long-Term
/// Profile viewer from [AboutIScreen].
class LifeDigestScreen extends StatelessWidget {
  const LifeDigestScreen({
    super.key,
    this.initialTab = LifeDigestTab.day,
    this.iMcpService,
  });

  final LifeDigestTab initialTab;

  /// Optional injection point for tests; production defaults to [IMcpService.instance].
  final IMcpQueryService? iMcpService;

  static const _backgroundAsset = 'assets/images/雨玻璃.jpg';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LifeDigestViewModel(
        service: iMcpService,
        initialTab: initialTab,
      )..load.execute(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                key: const ValueKey('life_digest_rain_glass_background'),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0x4DFFFFFF),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0x66FFFFFF),
                                  width: 0.8,
                                ),
                              ),
                              child: IconButton(
                                key: const ValueKey('life_digest_back_button'),
                                onPressed: () => Navigator.pop(context),
                                tooltip: MaterialLocalizations.of(context)
                                    .backButtonTooltip,
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 18,
                                ),
                                color: CompanionLifeDigestPanel._onRain,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 44,
                                ),
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Text(
                              '林埃眼中的你',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: CompanionLifeDigestPanel._onRain,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                shadows: CompanionLifeDigestPanel._onRainShadow,
                              ),
                            ),
                          ),
                          const SizedBox(width: 44),
                        ],
                      ),
                    ),
                    const Expanded(
                      child: SafeArea(
                        top: false,
                        child: CompanionLifeDigestPanel(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SubTabBar extends StatelessWidget {
  const _SubTabBar({
    required this.currentTab,
    required this.onSelected,
  });

  final LifeDigestTab currentTab;
  final ValueChanged<LifeDigestTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x52FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x6BFFFFFF), width: 0.8),
      ),
      child: Row(
        children: [
          for (final tab in LifeDigestTab.values)
            Expanded(
              child: Semantics(
                selected: tab == currentTab,
                button: true,
                child: InkWell(
                  key: ValueKey('life_digest_subtab_${tab.name}'),
                  onTap: () => onSelected(tab),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tab == currentTab
                          ? const Color(0xECFAF7EE)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.1,
                        fontWeight: tab == currentTab
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: tab == currentTab
                            ? CompanionLifeDigestPanel._ink
                            : CompanionLifeDigestPanel._onRain,
                        shadows: tab == currentTab
                            ? null
                            : CompanionLifeDigestPanel._onRainShadow,
                      ),
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

class _PeriodSelectorBar extends StatelessWidget {
  const _PeriodSelectorBar({
    required this.label,
    required this.canStepForward,
    required this.onPrevious,
    required this.onNext,
    this.subtitle,
    this.badge,
  });

  final String label;
  final String? subtitle;
  final String? badge;
  final bool canStepForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _MistCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      borderRadius: 16,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('life_digest_period_prev'),
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            color: CompanionLifeDigestPanel._ink,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CompanionLifeDigestPanel._ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (badge != null && badge!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _PillBadge(
                        label: badge!,
                        background:
                            CompanionLifeDigestPanel._accent.withValues(alpha: 0.14),
                        foreground: CompanionLifeDigestPanel._accent,
                      ),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CompanionLifeDigestPanel._muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('life_digest_period_next'),
            onPressed: canStepForward ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
            color: CompanionLifeDigestPanel._ink,
            disabledColor:
                CompanionLifeDigestPanel._muted.withValues(alpha: 0.35),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _MorningCard extends StatelessWidget {
  const _MorningCard({required this.morning});

  final DigestMorningBroadcast morning;

  @override
  Widget build(BuildContext context) {
    return _MistCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.wb_twilight_rounded,
                size: 16,
                color: CompanionLifeDigestPanel._accent,
              ),
              const SizedBox(width: 6),
              const Text(
                '晨间播报',
                style: TextStyle(
                  color: CompanionLifeDigestPanel._accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (morning.weather != null && morning.weather!.isNotEmpty) ...[
                const Spacer(),
                _PillBadge(
                  label: morning.weather!,
                  background:
                      CompanionLifeDigestPanel._accent.withValues(alpha: 0.12),
                  foreground: CompanionLifeDigestPanel._muted,
                ),
              ],
            ],
          ),
          if (morning.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              morning.text,
              style: const TextStyle(
                color: CompanionLifeDigestPanel._ink,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.headline});

  final String headline;

  @override
  Widget build(BuildContext context) {
    return _MistCard(
      child: Text(
        headline,
        style: const TextStyle(
          color: CompanionLifeDigestPanel._ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
    );
  }
}

class _ProseCard extends StatelessWidget {
  const _ProseCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _MistCard(
      child: Text(
        text,
        style: const TextStyle(
          color: CompanionLifeDigestPanel._ink,
          fontSize: 14,
          height: 1.55,
        ),
      ),
    );
  }
}

class _BulletListCard extends StatelessWidget {
  const _BulletListCard({required this.items});

  final List<DigestBulletItem> items;

  @override
  Widget build(BuildContext context) {
    return _MistCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  color: CompanionLifeDigestPanel._ink.withValues(alpha: 0.08),
                ),
              ),
            _BulletRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.item});

  final DigestBulletItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: CompanionLifeDigestPanel._accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.text,
                style: const TextStyle(
                  color: CompanionLifeDigestPanel._ink,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (item.sources.isNotEmpty) ...[
                const SizedBox(height: 6),
                _SourceTags(sources: item.sources),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AnomalyListCard extends StatelessWidget {
  const _AnomalyListCard({required this.items});

  final List<DigestBulletItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _AnomalyCard(item: items[i]),
        ],
      ],
    );
  }
}

class _AnomalyCard extends StatelessWidget {
  const _AnomalyCard({required this.item});

  final DigestBulletItem item;

  @override
  Widget build(BuildContext context) {
    final isWarn = item.isWarn;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isWarn
            ? CompanionLifeDigestPanel._warnSurface
            : CompanionLifeDigestPanel._surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWarn
              ? CompanionLifeDigestPanel._warnBorder
              : CompanionLifeDigestPanel._cardBorder,
          width: isWarn ? 1.0 : 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              isWarn
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline_rounded,
              size: 18,
              color: isWarn
                  ? CompanionLifeDigestPanel._warnAccent
                  : CompanionLifeDigestPanel._accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.text,
                  style: const TextStyle(
                    color: CompanionLifeDigestPanel._ink,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (item.sources.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _SourceTags(sources: item.sources),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.todo});

  final LifeDigestTodoItem todo;

  @override
  Widget build(BuildContext context) {
    final overdue = todo.isOverdue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: overdue
            ? CompanionLifeDigestPanel._warnSurface
            : CompanionLifeDigestPanel._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: overdue
              ? CompanionLifeDigestPanel._warnBorder
              : CompanionLifeDigestPanel._cardBorder,
          width: overdue ? 1.0 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  todo.text,
                  style: const TextStyle(
                    color: CompanionLifeDigestPanel._ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PillBadge(
                label: '已拖 ${todo.daysOpen} 天',
                background: overdue
                    ? CompanionLifeDigestPanel._warnAccent.withValues(alpha: 0.18)
                    : CompanionLifeDigestPanel._accent.withValues(alpha: 0.12),
                foreground: overdue
                    ? CompanionLifeDigestPanel._warnAccent
                    : CompanionLifeDigestPanel._accent,
              ),
            ],
          ),
          if (todo.quote != null && todo.quote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color:
                        CompanionLifeDigestPanel._accent.withValues(alpha: 0.45),
                    width: 2.5,
                  ),
                ),
              ),
              child: Text(
                todo.quote!,
                style: const TextStyle(
                  color: CompanionLifeDigestPanel._muted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ],
          if (todo.firstSeen != null && todo.firstSeen!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '首次提及：${todo.firstSeen}',
              style: const TextStyle(
                color: CompanionLifeDigestPanel._muted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCategoryCard extends StatelessWidget {
  const _ProfileCategoryCard({required this.items});

  final List<ProfileItem> items;

  @override
  Widget build(BuildContext context) {
    return _MistCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Divider(
                  height: 1,
                  color: CompanionLifeDigestPanel._ink.withValues(alpha: 0.08),
                ),
              ),
            _ProfileItemRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _ProfileItemRow extends StatelessWidget {
  const _ProfileItemRow({required this.item});

  final ProfileItem item;

  @override
  Widget build(BuildContext context) {
    final pinned = item.isPinned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.text,
                style: const TextStyle(
                  color: CompanionLifeDigestPanel._ink,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PillBadge(
              label: pinned ? '已确认' : '自动整理',
              background: pinned
                  ? CompanionLifeDigestPanel._accent.withValues(alpha: 0.16)
                  : CompanionLifeDigestPanel._muted.withValues(alpha: 0.12),
              foreground: pinned
                  ? CompanionLifeDigestPanel._accent
                  : CompanionLifeDigestPanel._muted,
            ),
          ],
        ),
        if (item.sources.isNotEmpty) ...[
          const SizedBox(height: 6),
          _SourceTags(sources: item.sources),
        ],
      ],
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({
    required this.failure,
    required this.onOpenConnect,
    required this.onRetry,
  });

  final LifeDigestFailure failure;
  final VoidCallback onOpenConnect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title, String description, bool showConnect) =
        switch (failure.kind) {
      LifeDigestFailureKind.notConnected => (
          Icons.link_off_rounded,
          '尚未连接 i MCP',
          '连接家里的 i MCP 后，即可查看日/周/月摘要、待办与长期档案。',
          true,
        ),
      LifeDigestFailureKind.offline => (
          Icons.cloud_off_rounded,
          '家里电脑暂时离线',
          failure.message,
          false,
        ),
      LifeDigestFailureKind.unsupportedPeriod => (
          Icons.system_update_alt_rounded,
          '等待家里电脑更新',
          failure.message,
          false,
        ),
      LifeDigestFailureKind.error => (
          Icons.error_outline_rounded,
          '暂时无法读取',
          failure.message,
          false,
        ),
    };

    return _MistCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 30,
            color: CompanionLifeDigestPanel._accent,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CompanionLifeDigestPanel._ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CompanionLifeDigestPanel._muted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (showConnect)
            FilledButton.icon(
              key: const ValueKey('life_digest_connect_button'),
              onPressed: onOpenConnect,
              style: FilledButton.styleFrom(
                backgroundColor: CompanionLifeDigestPanel._accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.link_rounded, size: 16),
              label: const Text('去连接 i MCP'),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('life_digest_retry_button'),
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: CompanionLifeDigestPanel._accent,
                side: const BorderSide(
                  color: CompanionLifeDigestPanel._accent,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _MistCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: CompanionLifeDigestPanel._muted,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }
}

class _MistCard extends StatelessWidget {
  const _MistCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: CompanionLifeDigestPanel._surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: CompanionLifeDigestPanel._cardBorder,
          width: 0.8,
        ),
      ),
      child: child,
    );
  }
}

class _RainSectionTitle extends StatelessWidget {
  const _RainSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: CompanionLifeDigestPanel._onRain,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          shadows: CompanionLifeDigestPanel._onRainShadow,
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: CompanionLifeDigestPanel._onRain,
          fontSize: 12,
          height: 1.4,
          shadows: CompanionLifeDigestPanel._onRainShadow,
        ),
      ),
    );
  }
}

class _SourceTags extends StatelessWidget {
  const _SourceTags({required this.sources});

  final List<String> sources;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final source in sources)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: CompanionLifeDigestPanel._ink.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              source,
              style: const TextStyle(
                color: CompanionLifeDigestPanel._muted,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
