/// Desktop home dashboard — the workbench landing page shown inside
/// [DesktopShell] on desktop platforms. Mirrors the web MVP home page
/// (`desktop/whiteboard_mvp/src/app.mjs` `renderHome`): a dense module grid
/// with real User-truth data where available and honest placeholders where
/// the underlying service is not yet wired or not available on desktop.
///
/// Data sources (all desktop-safe, no Android platform channels):
/// - 日程待办 / 记忆回顾 → [SharedLifeMemoryService] (Drift)
/// - 本月账本 → [AiFinanceService] (Drift)
/// - 后台任务 → [AgentActivityService] (local Dart singleton)
/// - 继续工作 → [WhiteboardDriftStore] (Drift)
/// - 待整理卡片 → [RichTextSearchIndex] (local files)
///
/// Placeholder modules (no desktop-ready service yet):
/// - 林埃观察 / 继续阅读 / 睡眠区间 — shown with an explicit "待接入" hint
///   rather than fake numbers, per the honest-state contract.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/agent_activity_service.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/rich_text_search.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard/card_library_screen.dart';
import 'package:memex/ui/whiteboard/desktop/desktop_buttons.dart';
import 'package:memex/ui/whiteboard/desktop/desktop_page_head.dart';
import 'package:memex/ui/whiteboard/desktop/desktop_shell.dart';
import 'package:memex/ui/whiteboard/desktop/desktop_shell_tokens.dart';

/// The desktop home dashboard. Shown at `/desktop-home` on desktop platforms.
class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  _DashboardData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _DashboardData.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DesktopShell(
      activeRoute: AppRoutes.home,
      child: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(54, 26, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopPageHead(
                title: '工作台',
                kicker: _dateKicker(),
                actions: [
                  DesktopPrimaryButton(
                    label: '新建白板',
                    icon: Icons.add_rounded,
                    onPressed: () => context.go(AppRoutes.whiteboard),
                  ),
                ],
              ),
              _buildGrid(),
            ],
          ),
        ),
      ),
    );
  }

  String _dateKicker() {
    final now = DateTime.now();
    return '${DateFormat('yyyy.MM.dd').format(now)} · 故我在 V3 · 桌面端';
  }

  Widget _buildGrid() {
    if (_error != null) {
      return _ErrorPane(message: '$_error', onRetry: _load);
    }
    if (_data == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: DesktopShellTokens.green,
            ),
          ),
        ),
      );
    }
    final d = _data!;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ModuleCard(
          width: _Span.large,
          label: '日程与待办',
          stat: '${d.todaySchedule.length} 项今天',
          child: _ScheduleList(items: d.todaySchedule),
        ),
        _ModuleCard(
          width: _Span.large,
          label: '记忆回顾',
          stat: '${d.recentMemories.length} 条',
          child: _MemoryList(items: d.recentMemories),
        ),
        _ModuleCard(
          width: _Span.small,
          label: '继续工作',
          link: '打开白板',
          onLink: () => context.go(AppRoutes.whiteboard),
          child: _BoardList(items: d.boards),
        ),
        _ModuleCard(
          width: _Span.small,
          label: '本月账本',
          stat: _monthLabel(),
          child: _LedgerBlock(summary: d.financeSummary),
        ),
        _ModuleCard(
          width: _Span.small,
          label: '后台任务',
          stat: '${d.agentActivities.length} 项',
          child: _AgentActivityList(items: d.agentActivities),
        ),
        _ModuleCard(
          width: _Span.small,
          label: '待整理卡片',
          link: '查看卡片库',
          onLink: () => context.go(AppRoutes.cardLibrary),
          child: _CardLibrarySummary(totalCards: d.cardCount),
        ),
        _ModuleCard(
          width: _Span.small,
          label: '林埃观察',
          stat: '待接入',
          child: _PlaceholderBlock(
            hint: '需要 Insights Agent 聚合本月字数、阅读时长与完成率。',
          ),
        ),
        _ModuleCard(
          width: _Span.small,
          label: '继续阅读',
          stat: '待接入',
          child: _PlaceholderBlock(hint: '阅读进度服务尚未在桌面端接线。'),
        ),
        _ModuleCard(
          width: _Span.small,
          label: '睡眠区间',
          stat: '待接入',
          child: _PlaceholderBlock(hint: 'Health Service 依赖 Android 平台通道。'),
        ),
      ],
    );
  }

  String _monthLabel() {
    final now = DateTime.now();
    return '${now.month} 月';
  }
}

/// Aggregate data loaded once for the dashboard.
class _DashboardData {
  final List<_ScheduleItem> todaySchedule;
  final List<_MemoryItem> recentMemories;
  final List<WhiteboardIndexEntry> boards;
  final Map<String, dynamic> financeSummary;
  final List<_AgentActivityItem> agentActivities;
  final int cardCount;

  const _DashboardData({
    required this.todaySchedule,
    required this.recentMemories,
    required this.boards,
    required this.financeSummary,
    required this.agentActivities,
    required this.cardCount,
  });

  static Future<_DashboardData> load() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    // SharedLifeMemoryService — desktop-safe (Drift only).
    List<_ScheduleItem> schedule = const [];
    List<_MemoryItem> memories = const [];
    if (SharedLifeMemoryService.isInitialized) {
      final svc = SharedLifeMemoryService.instance;
      final scheduleEntities = await svc.queryRelevantEntities(
        '',
        entityType: 'schedule',
        limit: 12,
      );
      final taskEntities = await svc.queryRelevantEntities(
        '',
        entityType: 'task',
        limit: 12,
      );
      final combined = [...scheduleEntities, ...taskEntities];
      schedule = combined
          .where((e) {
            final occ = e.occurredAt;
            if (occ == null) return true;
            final dt = DateTime.fromMillisecondsSinceEpoch(occ, isUtc: true);
            return !dt.isBefore(todayStart) && dt.isBefore(todayEnd);
          })
          .take(8)
          .map((e) => _ScheduleItem(
                title: e.title,
                type: e.entityType,
                status: e.status,
                time: e.occurredAt,
              ))
          .toList();

      final allEntities = await svc.listEntities(limit: 12);
      memories = allEntities
          .map((e) => _MemoryItem(
                type: e.entityType,
                title: e.title,
                domain: e.primaryDomain,
                updatedAt: e.updatedAt,
              ))
          .toList();
    }

    // WhiteboardDriftStore — desktop-safe.
    final store = WhiteboardDriftStore(AppDatabase.instance);
    final boards = await store.listBoards();

    // AiFinanceService — desktop-safe (Drift only).
    final finance = AiFinanceService(db: AppDatabase.instance);
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final financeSummary = await finance.getSummary(month: month);

    // AgentActivityService — desktop-safe (local Dart).
    List<_AgentActivityItem> activities = const [];
    if (AgentActivityService.isInitialized) {
      final history = await AgentActivityService.instance.getHistory(limit: 8);
      activities = history
          .map((m) => _AgentActivityItem(
                title: m.title,
                agentName: m.agentName,
                timestamp: m.timestamp,
              ))
          .toList();
    }

    // Card library count — desktop-safe (local files).
    int cardCount = 0;
    try {
      final index = await CardLibraryScreen.resolveIndex();
      cardCount = index.allCardIds().length;
    } catch (_) {}

    return _DashboardData(
      todaySchedule: schedule,
      recentMemories: memories,
      boards: boards,
      financeSummary: financeSummary,
      agentActivities: activities,
      cardCount: cardCount,
    );
  }
}

class _ScheduleItem {
  final String title;
  final String type;
  final String status;
  final int? time;
  const _ScheduleItem({
    required this.title,
    required this.type,
    required this.status,
    required this.time,
  });
}

class _MemoryItem {
  final String type;
  final String title;
  final String domain;
  final int updatedAt;
  const _MemoryItem({
    required this.type,
    required this.title,
    required this.domain,
    required this.updatedAt,
  });
}

class _AgentActivityItem {
  final String title;
  final String agentName;
  final DateTime timestamp;
  const _AgentActivityItem({
    required this.title,
    required this.agentName,
    required this.timestamp,
  });
}

enum _Span { small, large }

extension _SpanWidth on _Span {
  double get width {
    switch (this) {
      case _Span.small:
        return 320;
      case _Span.large:
        return 480;
    }
  }
}

/// A module card — mirrors `.hia-module`.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.label,
    required this.child,
    this.stat,
    this.link,
    this.onLink,
    required this.width,
  });

  final String label;
  final Widget child;
  final String? stat;
  final String? link;
  final VoidCallback? onLink;
  final _Span width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width.width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesktopShellTokens.surface,
        border: Border.all(color: const Color(0x1234332F)),
        borderRadius: BorderRadius.circular(DesktopShellTokens.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: DesktopShellTokens.moduleTitle,
                  fontWeight: FontWeight.w600,
                  color: DesktopShellTokens.textPrimary,
                ),
              ),
              const Spacer(),
              if (stat != null)
                Text(
                  stat!,
                  style: const TextStyle(
                    fontSize: DesktopShellTokens.meta,
                    color: DesktopShellTokens.textMuted,
                  ),
                ),
              if (link != null && onLink != null) ...[
                const SizedBox(width: 12),
                InkWell(
                  onTap: onLink,
                  child: Text(
                    link!,
                    style: const TextStyle(
                      fontSize: DesktopShellTokens.meta,
                      color: DesktopShellTokens.green,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ScheduleList extends StatelessWidget {
  const _ScheduleList({required this.items});
  final List<_ScheduleItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyHint(text: '今天没有日程或待办。');
    }
    return Column(
      children: items.map((item) {
        final done = item.status == 'completed' || item.status == 'done';
        final timeStr = item.time != null
            ? DateFormat('HH:mm').format(
                DateTime.fromMillisecondsSinceEpoch(item.time!, isUtc: true))
            : null;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Checkbox(done: done),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesktopShellTokens.content,
                        fontWeight: FontWeight.w500,
                        color: done
                            ? DesktopShellTokens.textMuted
                            : DesktopShellTokens.textPrimary,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (timeStr != null)
                      Text(
                        '$timeStr · ${item.type == "schedule" ? "日程" : "待办"}',
                        style: const TextStyle(
                          fontSize: DesktopShellTokens.meta,
                          color: DesktopShellTokens.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.done});
  final bool done;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 15,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: DesktopShellTokens.textFaint),
        color: done ? DesktopShellTokens.green : Colors.transparent,
      ),
      child: done
          ? const Icon(Icons.check, size: 11, color: DesktopShellTokens.canvas)
          : null,
    );
  }
}

class _MemoryList extends StatelessWidget {
  const _MemoryList({required this.items});
  final List<_MemoryItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyHint(text: '还没有记忆。在聊天里点「记录」或用悬浮球保存。');
    }
    return Column(
      children: items.map((item) {
        final typeLabel = const {
          'event': '事件',
          'task': '任务',
          'plan': '计划',
          'schedule': '日程',
          'fact': '事实',
        }[item.type] ??
            item.type;
        final updated = DateTime.fromMillisecondsSinceEpoch(item.updatedAt,
            isUtc: true);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeLabel,
                style: const TextStyle(
                  fontSize: DesktopShellTokens.status,
                  color: DesktopShellTokens.textMuted,
                ),
              ),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: DesktopShellTokens.content,
                  fontWeight: FontWeight.w500,
                  color: DesktopShellTokens.textPrimary,
                ),
              ),
              Text(
                '${item.domain} · ${DateFormat('MM-dd').format(updated)}',
                style: const TextStyle(
                  fontSize: DesktopShellTokens.status,
                  color: DesktopShellTokens.textFaint,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _BoardList extends StatelessWidget {
  const _BoardList({required this.items});
  final List<WhiteboardIndexEntry> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyHint(text: '还没有白板。');
    }
    return Column(
      children: items.take(3).map((board) {
        return InkWell(
          onTap: () =>
              context.go(AppRoutes.whiteboardCanvasPath(board.boardId)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.space_dashboard_outlined,
                  size: 16,
                  color: DesktopShellTokens.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    board.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: DesktopShellTokens.content,
                      color: DesktopShellTokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _LedgerBlock extends StatelessWidget {
  const _LedgerBlock({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final expense = (summary['expense'] as num?)?.toDouble() ?? 0;
    final periodNet = (summary['period_net'] as num?)?.toDouble() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¥${expense.toStringAsFixed(0)}',
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: DesktopShellTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '本月支出 · 净额 ¥${periodNet.toStringAsFixed(0)}',
          style: const TextStyle(
            fontSize: DesktopShellTokens.meta,
            color: DesktopShellTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _AgentActivityList extends StatelessWidget {
  const _AgentActivityList({required this.items});
  final List<_AgentActivityItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyHint(text: '没有最近的后台任务。');
    }
    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: DesktopShellTokens.greenMid,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: DesktopShellTokens.content,
                    color: DesktopShellTokens.textPrimary,
                  ),
                ),
              ),
              Text(
                DateFormat('HH:mm').format(item.timestamp),
                style: const TextStyle(
                  fontSize: DesktopShellTokens.status,
                  color: DesktopShellTokens.textFaint,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _CardLibrarySummary extends StatelessWidget {
  const _CardLibrarySummary({required this.totalCards});
  final int totalCards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$totalCards',
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: DesktopShellTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '张卡片 · 通过内容搜索',
          style: TextStyle(
            fontSize: DesktopShellTokens.meta,
            color: DesktopShellTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _PlaceholderBlock extends StatelessWidget {
  const _PlaceholderBlock({required this.hint});
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hint,
            style: const TextStyle(
              fontSize: DesktopShellTokens.meta,
              color: DesktopShellTokens.textFaint,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: DesktopShellTokens.meta,
          color: DesktopShellTokens.textFaint,
          height: 1.6,
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '加载失败：$message',
              style: const TextStyle(
                fontSize: DesktopShellTokens.content,
                color: DesktopShellTokens.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            DesktopQuietButton(label: '重试', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}