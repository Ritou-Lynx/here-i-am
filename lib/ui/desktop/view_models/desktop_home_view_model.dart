/// Desktop workbench home — aggregates whiteboard-native data for desktop.
///
/// The desktop and phone products do not embed each other's page surfaces.
/// This projection only exposes the desktop whiteboard work loop: recent
/// boards and cards waiting to be organised on a board.
library;

import 'package:flutter/foundation.dart';

import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/source_content.dart';

/// One recently touched board in the desktop workbench.
class ContinueWorkItem {
  const ContinueWorkItem.board({
    required this.boardId,
    required this.title,
    required this.subtitle,
  });

  final String boardId;
  final String title;
  final String subtitle;
}

/// One honest aggregate point used by the compact desktop charts.
class DesktopCountPoint {
  const DesktopCountPoint({required this.label, required this.value});

  final String label;
  final int value;
}

/// Whiteboard-native statistics only. No health, ledger, task-room or mock
/// data is admitted into this projection.
class DesktopHomeStats {
  const DesktopHomeStats({
    this.dailyCardCreates = const [],
    this.cardKindCounts = const {},
    this.sourceMediaCounts = const {},
    this.totalCards = 0,
    this.placedCards = 0,
    this.boardGrowth = const [],
    this.boardsTouchedLast30Days = 0,
  });

  final List<DesktopCountPoint> dailyCardCreates;
  final Map<CardKind, int> cardKindCounts;
  final Map<SourceMediaType, int> sourceMediaCounts;
  final int totalCards;
  final int placedCards;
  final List<DesktopCountPoint> boardGrowth;
  final int boardsTouchedLast30Days;

  int get unplacedCards =>
      (totalCards - placedCards).clamp(0, totalCards).toInt();
  int get cardsCreatedLast30Days => dailyCardCreates.fold(
        0,
        (sum, point) => sum + point.value,
      );
}

/// Immutable data snapshot rendered by the module grid.
class DesktopHomeData {
  const DesktopHomeData({
    required this.boards,
    required this.continueWork,
    required this.pendingCards,
    this.stats = const DesktopHomeStats(),
  });

  /// 最近白板（最多 3 张）。
  final List<WhiteboardIndexEntry> boards;

  /// 「继续工作」条目：最近白板。
  final List<ContinueWorkItem> continueWork;

  /// 「待整理卡片」：未被任何白板引用的最近 note 卡。
  final List<MemoryCardViewData> pendingCards;

  /// Aggregates rendered by the four chart modules on the desktop home.
  final DesktopHomeStats stats;
}

/// Loads the workbench home data once and exposes load state.
class DesktopHomeViewModel extends ChangeNotifier {
  DesktopHomeViewModel({
    required this.db,
    UnifiedCardRepository? cardRepository,
    Future<DesktopHomeData> Function()? loader,
  })  : _cardRepository = cardRepository,
        _loader = loader;

  final AppDatabase db;
  final UnifiedCardRepository? _cardRepository;
  final Future<DesktopHomeData> Function()? _loader;

  bool _loading = true;
  Object? _error;
  DesktopHomeData? _data;

  bool get isLoading => _loading;
  Object? get error => _error;
  DesktopHomeData? get data => _data;

  static const int _boardLimit = 3;
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _data = await (_loader?.call() ?? _collect());
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
    final cardService = MemoryCardQueryService(db);

    final boards = await store.listBoards();
    final allCards = await unifiedCards.listCards();
    final placedCards = await unifiedCards.listCards(
      const CardLibraryQuery(placedOnBoard: true),
    );

    final continueWork = <ContinueWorkItem>[
      for (final board in boards.take(_boardLimit))
        ContinueWorkItem.board(
          boardId: board.boardId,
          title: board.name,
          subtitle: _relativeTime(board.updatedAt ?? board.createdAt),
        ),
    ];

    final pendingCards = await _loadPendingCards(cardService, unifiedCards);
    final stats = _buildStats(
      cards: allCards,
      placedCardCount: placedCards.length,
      boards: boards,
      now: DateTime.now(),
    );

    return DesktopHomeData(
      boards: boards.take(_boardLimit).toList(),
      continueWork: continueWork,
      pendingCards: pendingCards,
      stats: stats,
    );
  }

  DesktopHomeStats _buildStats({
    required List<UnifiedCardRecord> cards,
    required int placedCardCount,
    required List<WhiteboardIndexEntry> boards,
    required DateTime now,
  }) {
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final firstDay = today.subtract(const Duration(days: 29));
    final cardCounts = List<int>.filled(30, 0);
    final kindCounts = <CardKind, int>{};
    final mediaCounts = <SourceMediaType, int>{};

    for (final record in cards) {
      final card = record.card;
      kindCounts[card.cardKind] = (kindCounts[card.cardKind] ?? 0) + 1;
      final mediaType = record.source?.mediaType;
      if (mediaType != null) {
        mediaCounts[mediaType] = (mediaCounts[mediaType] ?? 0) + 1;
      }
      final created = card.createdAt.toLocal();
      final day = DateTime(created.year, created.month, created.day);
      final index = day.difference(firstDay).inDays;
      if (index >= 0 && index < cardCounts.length) cardCounts[index] += 1;
    }

    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final firstWeek = weekStart.subtract(const Duration(days: 35));
    final boardGrowth = <DesktopCountPoint>[];
    for (var index = 0; index < 6; index++) {
      final weekEnd = firstWeek.add(Duration(days: (index + 1) * 7));
      final cumulative = boards.where((board) {
        return board.createdAt.toLocal().isBefore(weekEnd);
      }).length;
      boardGrowth.add(
        DesktopCountPoint(
          label: '${weekEnd.month}/${weekEnd.day}',
          value: cumulative,
        ),
      );
    }

    final thirtyDaysAgo = localNow.subtract(const Duration(days: 30));
    final touched = boards.where((board) {
      return (board.updatedAt ?? board.createdAt)
          .toLocal()
          .isAfter(thirtyDaysAgo);
    }).length;

    return DesktopHomeStats(
      dailyCardCreates: [
        for (var index = 0; index < cardCounts.length; index++)
          DesktopCountPoint(
            label: '${firstDay.add(Duration(days: index)).month}/'
                '${firstDay.add(Duration(days: index)).day}',
            value: cardCounts[index],
          ),
      ],
      cardKindCounts: kindCounts,
      sourceMediaCounts: mediaCounts,
      totalCards: cards.length,
      placedCards: placedCardCount,
      boardGrowth: boardGrowth,
      boardsTouchedLast30Days: touched,
    );
  }

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
