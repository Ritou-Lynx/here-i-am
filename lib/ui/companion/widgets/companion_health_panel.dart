import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/services/coros_mcp_service.dart';
import 'package:memex/data/services/coros_sync_service.dart';
import 'package:memex/data/services/mcp_token_storage.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/memory/widgets/memory_card_detail_screen_v3.dart';
import 'package:memex/ui/memory/widgets/memory_summary_card_v3.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

import 'health_stat_card.dart';

/// Health observation panel in Life Space.
///
/// Three data sources:
/// 1. COROS watch metrics (steps, sleep, heart rate) via MCP
/// 2. Sync button — fetches COROS MCP data into the local data pool
/// 3. Health-related Memory V3 cards
class CompanionHealthPanel extends StatefulWidget {
  const CompanionHealthPanel({super.key});

  @override
  State<CompanionHealthPanel> createState() => _CompanionHealthPanelState();
}

class _CompanionHealthPanelState extends State<CompanionHealthPanel> {
  final _logger = getLogger('CompanionHealthPanel');
  final _scrollController = ScrollController();

  bool _loading = true;
  bool _syncing = false;
  String? _error;

  // COROS metrics
  bool _corosConnected = false;
  String? _steps;
  String? _sleepScore;
  String? _sleepBreakdown;
  String? _heartRate;
  String? _recovery;

  // Health memory cards
  List<MemoryCardViewData> _healthCards = const [];

  MemoryCardQueryService? get _query {
    if (!AppDatabase.isInitialized) return null;
    return MemoryCardQueryService(AppDatabase.instance);
  }

  RecordOrganizerServiceV3? get _organizer =>
      RecordOrganizerServiceV3.isInitialized
          ? RecordOrganizerServiceV3.instance
          : null;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _checkCorosConnection();
      if (_corosConnected) {
        await Future.wait([
          _fetchDailyHealth(),
          _fetchSleep(),
          _fetchRecovery(),
        ]);
      }
      await _fetchHealthCards();
    } catch (e) {
      _logger.warning('Health panel load failed: $e');
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ── COROS connection ────────────────────────────────────────────────────

  Future<void> _checkCorosConnection() async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final storage = McpTokenStorage(userId: userId);
      final token = await storage.load();
      if (mounted) {
        setState(() => _corosConnected = token != null && !token.isExpired);
      }
    } catch (_) {
      if (mounted) setState(() => _corosConnected = false);
    }
  }

  // ── COROS data via MCP ──────────────────────────────────────────────────

  Future<void> _fetchDailyHealth() async {
    try {
      final svc = CorosMcpService.instance;
      await svc.ensureConnected();
      if (!svc.isConnected) return;

      final result = await svc.queryDailyHealthData(days: 1);
      if (result.isError || result.text.isEmpty) return;

      // COROS returns JSON in the content text.
      final data = jsonDecode(result.text) as Map<String, dynamic>;
      final healthList = data['dailyHealthList'] as List<dynamic>?;
      if (healthList == null || healthList.isEmpty) return;

      final today = healthList.first as Map<String, dynamic>;
      final steps = today['totalSteps'] as int?;
      final avgHr = today['avgHeartRate'] as int?;

      if (mounted) {
        setState(() {
          if (steps != null) _steps = _formatNumber(steps);
          if (avgHr != null && avgHr > 0) _heartRate = '$avgHr';
        });
      }
    } catch (e) {
      _logger.warning('Failed to fetch daily health: $e');
    }
  }

  Future<void> _fetchSleep() async {
    try {
      final svc = CorosMcpService.instance;
      await svc.ensureConnected();
      if (!svc.isConnected) return;

      final result = await svc.querySleepData(days: 1);
      if (result.isError || result.text.isEmpty) return;

      final data = jsonDecode(result.text) as Map<String, dynamic>;
      final sleepList = data['sleepList'] as List<dynamic>?;
      if (sleepList == null || sleepList.isEmpty) return;

      final today = sleepList.first as Map<String, dynamic>;
      final score = today['sleepScore'] as int?;
      final totalMin = today['totalSleepMinutes'] as int?;
      final deepMin = today['deepSleepMinutes'] as int?;
      final remMin = today['remSleepMinutes'] as int?;
      final lightMin = today['lightSleepMinutes'] as int?;

      if (mounted) {
        setState(() {
          if (score != null) _sleepScore = '$score';
          if (totalMin != null && totalMin > 0) {
            final hours = totalMin ~/ 60;
            final mins = totalMin % 60;
            final parts = <String>[];
            if (deepMin != null && deepMin > 0) {
              parts.add('深睡 ${_fmtMin(deepMin)}');
            }
            if (remMin != null && remMin > 0) {
              parts.add('REM ${_fmtMin(remMin)}');
            }
            if (lightMin != null && lightMin > 0) {
              parts.add('浅睡 ${_fmtMin(lightMin)}');
            }
            _sleepBreakdown =
                '${hours > 0 ? '$hours 小时 ' : ''}${mins > 0 ? '$mins 分钟' : ''}';
            if (parts.isNotEmpty) {
              _sleepBreakdown = '$_sleepBreakdown · ${parts.join(' · ')}';
            }
          }
        });
      }
    } catch (e) {
      _logger.warning('Failed to fetch sleep: $e');
    }
  }

  Future<void> _fetchRecovery() async {
    try {
      final svc = CorosMcpService.instance;
      await svc.ensureConnected();
      if (!svc.isConnected) return;

      final result = await svc.queryRecoveryStatus();
      if (result.isError || result.text.isEmpty) return;

      final data = jsonDecode(result.text) as Map<String, dynamic>;
      final recovery = data['recoveryPercent'] as int?;

      if (mounted && recovery != null) {
        setState(() => _recovery = '$recovery');
      }
    } catch (e) {
      _logger.warning('Failed to fetch recovery: $e');
    }
  }

  // ── Health memory cards ─────────────────────────────────────────────────

  Future<void> _fetchHealthCards() async {
    try {
      final queryService = _query;
      if (queryService == null) return;
      final results = <MemoryCardViewData>[];
      final seenIds = <String>{};

      final structuredHits = await queryService.listCardsByStructuredFieldTypes(
        const {
          'sleep_record',
          'workout_record',
          'health_observation',
        },
        limit: 20,
      );
      for (final card in structuredHits) {
        if (seenIds.add(card.id)) results.add(card);
      }

      // Sort by recency descending.
      results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (mounted) {
        setState(() => _healthCards = results);
      }
    } catch (e) {
      _logger.warning('Failed to fetch health memory cards: $e');
    }
  }

  // ── Sync ────────────────────────────────────────────────────────────────

  Future<void> _syncCorosData() async {
    if (_syncing) return;
    final userId = await UserStorage.getUserId();
    if (userId == null) return;

    if (mounted) setState(() => _syncing = true);

    try {
      final result = await CorosSyncService.syncDetailed(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      await _loadData();
    } catch (e) {
      _logger.warning('Failed to sync COROS MCP data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('COROS MCP 同步失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Loading
    if (_loading && _noData) {
      return const Center(child: AgentLogoLoading());
    }

    // Error with no data
    if (_error != null && _noData) {
      return ListView(
        controller: _scrollController,
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                '加载失败\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textTertiary),
              ),
            ),
          ),
        ],
      );
    }

    // No data and no connected health source.
    if (_noData && !_corosConnected) {
      return ListView(
        controller: _scrollController,
        children: [
          const SizedBox(height: 80),
          _buildConnectPrompt(),
        ],
      );
    }

    // Data available
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _itemCount,
      itemBuilder: _buildItem,
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final items = _buildCardList();
    if (index >= items.length) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: items[index],
    );
  }

  int get _itemCount => _buildCardList().length;

  bool get _noData =>
      _steps == null &&
      _sleepScore == null &&
      _heartRate == null &&
      _recovery == null &&
      _healthCards.isEmpty;

  List<Widget> _buildCardList() {
    final items = <Widget>[];

    // ── Section: COROS metrics ──

    if (_corosConnected) {
      items.add(
        Row(
          children: [
            _sectionHeader('手表数据'),
            const Spacer(),
            _syncButton(),
          ],
        ),
      );

      if (_steps != null) {
        items.add(HealthStatCard(
          icon: Icons.directions_walk,
          label: '今日步数',
          value: _steps!,
          unit: '步',
          color: const Color(0xFF10B981),
        ));
      }

      if (_sleepScore != null) {
        items.add(HealthStatCard(
          icon: Icons.bedtime_outlined,
          label: '睡眠评分',
          value: _sleepScore!,
          subtitle: _sleepBreakdown,
          color: const Color(0xFF6366F1),
        ));
      }

      if (_heartRate != null) {
        items.add(HealthStatCard(
          icon: Icons.favorite_outline,
          label: '静息心率',
          value: _heartRate!,
          unit: 'bpm',
          color: const Color(0xFFF43F5E),
        ));
      }

      if (_recovery != null) {
        items.add(HealthStatCard(
          icon: Icons.auto_awesome,
          label: '身体恢复',
          value: '$_recovery%',
          color: const Color(0xFFF59E0B),
        ));
      }

      if (_steps == null &&
          _sleepScore == null &&
          _heartRate == null &&
          _recovery == null) {
        items.add(_emptyHint('暂无手表数据，点同步更新'));
      }

      items.add(const SizedBox(height: 8));
    } else {
      items.add(_buildConnectPrompt());
      items.add(const SizedBox(height: 16));
    }

    // ── Section: Health memory cards ──

    if (_healthCards.isNotEmpty) {
      items.add(_sectionHeader('健康记忆'));
      for (final card in _healthCards) {
        items.add(
          MemorySummaryCardV3(
            card: card,
            onTap: () => _openCardDetail(card),
          ),
        );
      }
    }

    return items;
  }

  Widget _buildConnectPrompt() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.watch_outlined,
              size: 48, color: AppColors.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            '连接 COROS 获取手表数据',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '在设置中连接 COROS 后，这里将展示步数、睡眠、心率等健康数据。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              // Navigate to settings — the caller (Life Space) handles navigation.
              // For now, show a minimal action: go to settings.
              Navigator.pop(context);
            },
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
  }

  Widget _syncButton() {
    return TextButton.icon(
      onPressed: _syncing ? null : _syncCorosData,
      icon: _syncing
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync, size: 16),
      label: Text(_syncing ? '同步中' : '同步'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
        disabledForegroundColor: AppColors.textTertiary,
        disabledBackgroundColor: AppColors.textTertiary.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(72, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Future<void> _openCardDetail(MemoryCardViewData card) async {
    final queryService = _query;
    if (queryService == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryCardDetailScreenV3(
          cardId: card.id,
          queryService: queryService,
          organizerService: _organizer,
        ),
      ),
    );
    await _fetchHealthCards();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _formatNumber(int n) {
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(1)} 万';
    }
    return n.toString();
  }

  static String _fmtMin(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '$h 小时 $m 分钟' : '$h 小时';
  }
}
