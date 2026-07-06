import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/services/coros_mcp_service.dart';
import 'package:memex/data/services/mcp_token_storage.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/memory/widgets/memory_summary_card_v3.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'health_stat_card.dart';

/// Health observation panel in Life Space.
///
/// Three data sources:
/// 1. COROS watch metrics (steps, sleep, heart rate) via MCP
/// 2. Sync button — attempts to open COROS app
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
      if (!AppDatabase.isInitialized) return;
      final queryService = MemoryCardQueryService(AppDatabase.instance);

      // Search with multiple health keywords
      final keywords = [
        '睡眠', '运动', '锻炼', '跑步', '健身',
        '步数', '身体', '健康', '生病', '不舒服',
        '体检', '医院', '感冒', '发烧', '头疼',
      ];

      final results = <MemoryCardViewData>[];
      final seenIds = <String>{};

      for (final kw in keywords) {
        final hits = await queryService.searchCardsResolved(kw, limit: 5);
        for (final card in hits) {
          if (seenIds.add(card.id)) {
            results.add(card);
          }
        }
        // Stop collecting after enough unique results.
        if (results.length >= 10) break;
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

  Future<void> _openCorosApp() async {
    try {
      // Common COROS Android package name.
      const packageName = 'com.coros.watch';
      final uri = Uri.parse('intent://#Intent;package=$packageName;end');
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开 COROS app，请手动打开同步数据')),
        );
      }
    } catch (_) {
      // Silently fail — user can open COROS manually.
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

    // No data at all
    if (_noData) {
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
          Icon(Icons.watch_outlined, size: 48, color: AppColors.primary.withValues(alpha: 0.4)),
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
    return GestureDetector(
      onTap: _openCorosApp,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync, size: 14, color: AppColors.primary),
            SizedBox(width: 4),
            Text(
              '同步',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
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

  void _openCardDetail(MemoryCardViewData card) {
    // Reuse the V3 detail screen pattern.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CardDetailView(card: card),
      ),
    );
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

/// Minimal card detail view for health panel navigation.
///
/// Shows the full retrieval text. Detailed card view V3 would be used when
/// the health panel gets its own detail screen.
class _CardDetailView extends StatelessWidget {
  const _CardDetailView({required this.card});

  final MemoryCardViewData card;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(card.title.isEmpty ? card.dropletLabel : card.title),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MemorySummaryCardV3(card: card),
      ),
    );
  }
}
