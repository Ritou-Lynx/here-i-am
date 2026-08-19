/// Desktop workbench home — aggregates real data for the module grid.
///
/// Read-only projection over existing services (Task S · whiteboard parallel
/// charter §3): every value shown on the home grid comes from the same core
/// database the phone app uses. No writes, no new tables, no duplicated
/// entities. All queries go through the existing services:
///   - boards         → [WhiteboardDriftStore]
///   - task rooms     → [TaskRoomService]
///   - cards / memory → [MemoryCardQueryService]
library;

import 'package:flutter/foundation.dart';

import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';

/// One row of the "继续工作" module: a recently touched board or an active
/// task room. Both open real destinations from the frozen routes.
class ContinueWorkItem {
  const ContinueWorkItem.board({
    required this.boardId,
    required this.title,
    required this.subtitle,
  }) : isBoard = true;

  const ContinueWorkItem.task({
    required this.boardId,
    required this.title,
    required this.subtitle,
  }) : isBoard = false;

  final bool isBoard;
  final String boardId;
  final String title;
  final String subtitle;
}

/// Immutable data snapshot rendered by the module grid.
class DesktopHomeData {
  const DesktopHomeData({
    required this.boards,
    required this.continueWork,
    required this.activeTaskCount,
    required this.pendingCards,
    required this.scheduleCards,
    required this.scheduleOverview,
    required this.recentMemoryCards,
    required this.todayRecordCount,
    required this.followUpCount,
    required this.taskStatusCounts,
  });

  /// 最近白板（最多 3 张），用于「继续工作」与「林埃观察」计数。
  final List<WhiteboardIndexEntry> boards;

  /// 「继续工作」条目：最近白板 + 活跃任务房间。
  final List<ContinueWorkItem> continueWork;

  /// 活跃任务房间总数（pending / running / blocked / waiting_for_user）。
  final int activeTaskCount;

  /// 「待整理卡片」：未被任何白板引用的最近 note 卡。
  final List<MemoryCardViewData> pendingCards;

  /// 「日程与待办」：按到期时间排序的 active 任务 / 日程 / 计划卡。
  final List<MemoryCardViewData> scheduleCards;

  /// 日程概览 {overdue, today, upcoming, unscheduled}。
  final Map<String, int> scheduleOverview;

  /// 「记忆回顾」：最近新增的 Memory Card。
  final List<MemoryCardViewData> recentMemoryCards;

  /// 今日已记录条数（card createdAt ≥ 今天 0 点）。
  final int todayRecordCount;

  /// 待确认 follow-up 数量（今日总结的 User-truth 候选）。
  final int followUpCount;

  /// 后台任务按状态计数（running / waiting_for_user / failed / completed）。
  final Map<TaskStatus, int> taskStatusCounts;
}

/// Loads the workbench home data once and exposes load state.
class DesktopHomeViewModel extends ChangeNotifier {
  DesktopHomeViewModel({
    required this.db,
    UnifiedCardRepository? cardRepository,
  }) : _cardRepository = cardRepository;

  final AppDatabase db;
  final UnifiedCardRepository? _cardRepository;

  bool _loading = true;
  Object? _error;
  DesktopHomeData? _data;

  bool get isLoading => _loading;
  Object? get error => _error;
  DesktopHomeData? get data => _data;

  static const int _boardLimit = 3;
  static const int _taskRoomLimit = 50;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _data = await _collect();
      _loading = false;
      notifyListeners();
    } catch (e, stackTrace) {
      _error = e;
      _loading = false;
      notifyListeners();
      debugPrint('DesktopHomeViewModel.load failed: $e\n$stackTrace');
    }
  }

  Future<DesktopHomeData> _collect() async {
    final store = WhiteboardDriftStore(db);
    final unifiedCards =
        _cardRepository ?? await WhiteboardDataBootstrap.productionRepository();
    final taskService = TaskRoomService(db: db);
    final cardService = MemoryCardQueryService(db);

    final boards = await store.listBoards();

    final taskRooms = await taskService.listTaskRooms(limit: _taskRoomLimit);
    final activeTasks = taskRooms
        .where((t) => !_isTerminal(t.status))
        .take(_boardLimit)
        .toList();

    final continueWork = <ContinueWorkItem>[
      for (final board in boards.take(_boardLimit))
        ContinueWorkItem.board(
          boardId: board.boardId,
          title: board.name,
          subtitle: _relativeTime(board.updatedAt ?? board.createdAt),
        ),
      for (final task in activeTasks)
        ContinueWorkItem.task(
          boardId: task.boardId ?? '',
          title: task.title,
          subtitle: _taskStatusLabel(task.status),
        ),
    ];

    final scheduleCards = await cardService.listScheduleCards(limit: 20);
    final scheduleOverview = await cardService.getScheduleOverview();

    final pendingCards = await _loadPendingCards(cardService, unifiedCards);
    final recentMemoryCards = (await cardService.listRecentCards(limit: 6))
        .take(_boardLimit)
        .toList();

    final todayCount = await _countTodayRecords(cardService);
    final followUpCount =
        (await cardService.getFollowUpCards(limit: 50)).length;

    final statusCounts = <TaskStatus, int>{};
    for (final room in taskRooms) {
      final status = TaskStatus.fromString(room.status);
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }

    return DesktopHomeData(
      boards: boards.take(_boardLimit).toList(),
      continueWork: continueWork,
      activeTaskCount: activeTasks.length,
      pendingCards: pendingCards,
      scheduleCards: scheduleCards.take(4).toList(),
      scheduleOverview: scheduleOverview,
      recentMemoryCards: recentMemoryCards,
      todayRecordCount: todayCount,
      followUpCount: followUpCount,
      taskStatusCounts: statusCounts,
    );
  }

  bool _isTerminal(String status) =>
      status == TaskStatus.completed.value ||
      status == TaskStatus.failed.value ||
      status == TaskStatus.cancelled.value ||
      status == TaskStatus.archived.value;

  /// 「待整理卡片」= 白板 note 卡里尚未被任何白板引用的最近卡片。
  ///
  /// 身份复用 MemoryCards（memoryScope='user_truth'、type='note'，W6 契约）；
  /// “已上板”判定 = 该 cardId 出现在 WhiteboardBoardItems。这与 W6 的
  /// “删除 BoardItem 不删除 Card”语义一致：没有 BoardItem 的卡仍在等待
  /// 分类 / 放入白板。
  Future<List<MemoryCardViewData>> _loadPendingCards(
    MemoryCardQueryService cardService,
    UnifiedCardRepository repository,
  ) async {
    final candidates = await repository.listCards(
      const CardLibraryQuery(
        kinds: {CardKind.note},
        placedOnBoard: false,
        limit: _boardLimit,
      ),
    );
    final ids = candidates.map((record) => record.card.cardId).toList();
    if (ids.isEmpty) return const [];
    return cardService.getCardsByIds(ids);
  }

  Future<int> _countTodayRecords(MemoryCardQueryService cardService) async {
    final todayStart = DateTime.now();
    final startMs = DateTime(todayStart.year, todayStart.month, todayStart.day)
        .millisecondsSinceEpoch;
    final recent = await cardService.listRecentCards(limit: 150);
    return recent.where((c) => c.createdAt >= startMs).length;
  }
}

/// 简洁相对时间（首页元信息专用，避免引入全量 intl 本地化依赖）。
String _relativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time.toLocal());
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays == 1) return '昨天';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final local = time.toLocal();
  return '${local.month} 月 ${local.day} 日';
}

String _taskStatusLabel(String status) {
  switch (status) {
    case 'running':
      return '运行中';
    case 'blocked':
      return '受阻';
    case 'waiting_for_user':
      return '等待决定';
    case 'pending':
      return '待开始';
    case 'completed':
      return '已完成';
    case 'failed':
      return '失败';
    case 'cancelled':
      return '已取消';
    case 'archived':
      return '已归档';
    default:
      return status;
  }
}

/// 后台任务模块展示用的状态标签与计数顺序。
const List<TaskStatus> backgroundTaskStatusOrder = [
  TaskStatus.running,
  TaskStatus.waitingForUser,
  TaskStatus.failed,
  TaskStatus.completed,
];

String backgroundTaskStatusLabel(TaskStatus status) {
  switch (status) {
    case TaskStatus.running:
      return '运行中';
    case TaskStatus.waitingForUser:
      return '等待决定';
    case TaskStatus.failed:
      return '失败';
    case TaskStatus.completed:
      return '已完成';
    case TaskStatus.blocked:
      return '受阻';
    case TaskStatus.pending:
      return '待开始';
    case TaskStatus.cancelled:
      return '已取消';
    case TaskStatus.archived:
      return '已归档';
  }
}
