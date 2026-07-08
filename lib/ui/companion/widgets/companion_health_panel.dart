import 'dart:io';

import 'package:flutter/material.dart';
import 'package:memex/data/services/file_system_service.dart';
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
/// Data sources (in priority order):
/// 1. COROS MCP live API — same as 林埃's `coros_query` tool
/// 2. Synced local files — fallback when API is unavailable
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

  // COROS connection
  bool _corosConnected = false;
  bool _usingLiveApi = false;

  // COROS metrics
  String? _steps;
  String? _calories;
  String? _restingHr;
  String? _avgHr;
  String? _sleepScore;
  String? _sleepBreakdown;
  String? _recovery;
  String? _stress;
  String? _hrv;
  String? _vo2max;
  String? _fitnessLevel;
  List<Map<String, dynamic>> _recentWorkouts = const [];

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
        final apiOk = await _tryLiveApi();
        if (!apiOk) {
          await _loadFromCache();
        }
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

  // ── Live COROS MCP API ──────────────────────────────────────────────────

  /// Try fetching all metrics from the live COROS MCP API.
  /// Returns true if at least some data was retrieved.
  Future<bool> _tryLiveApi() async {
    try {
      await CorosMcpService.instance.ensureConnected();
      if (!CorosMcpService.instance.isConnected) {
        _logger.info('COROS MCP not connected, falling back to cache');
        return false;
      }

      // Fire all queries in parallel (matching what 林埃 can access)
      await Future.wait([
        _fetchDailyHealthLive(),
        _fetchSleepLive(),
        _fetchRecoveryLive(),
        _fetchRestingHrLive(),
        _fetchStressLive(),
        _fetchHrvLive(),
        _fetchFitnessLive(),
        _fetchRecentWorkoutsLive(),
      ], eagerError: false);

      final anyData = _steps != null ||
          _sleepScore != null ||
          _recovery != null ||
          _restingHr != null;
      if (mounted) {
        setState(() => _usingLiveApi = anyData);
      }
      _logger.info('Live API fetch: ${anyData ? "success" : "no data"}');
      return anyData;
    } catch (e) {
      _logger.warning('Live API fetch failed, falling back to cache: $e');
      return false;
    }
  }

  /// Call a COROS MCP tool and return its text, with file fallback on failure.
  Future<String?> _callCoros(
    String toolName, {
    Map<String, dynamic>? arguments,
    String? fallbackFileName,
  }) async {
    try {
      final result = await CorosMcpService.instance.callTool(
        toolName,
        arguments: arguments,
      );
      final text = result.text;
      if (text.isNotEmpty) return text;
    } catch (e) {
      _logger.info('Live $toolName failed, trying file fallback: $e');
    }

    // Fallback: read from synced file
    if (fallbackFileName != null) {
      try {
        final dir = await _getCorosDir();
        if (dir.isEmpty) return null;
        final file = File('$dir/$fallbackFileName');
        if (file.existsSync()) return file.readAsString();
      } catch (e) {
        _logger.warning('File fallback for $toolName failed: $e');
      }
    }
    return null;
  }

  // ── Individual live fetchers ────────────────────────────────────────────

  Future<void> _fetchDailyHealthLive() async {
    final text = await _callCoros(
      'queryDailyHealthData',
      arguments: {'days': 2, 'timezone': 'Asia/Shanghai'},
      fallbackFileName: 'daily_health.json',
    );
    if (text == null) return;

    final sections = _splitDatedSections(text);
    if (sections.isEmpty) return;
    final newestDate = _pickNewestDate(sections.keys.toList());
    final section = sections[newestDate]!;

    final steps = _parseInt(section, 'Steps:');
    final calories = _parseInt(section, 'Calories:') ??
        _parseInt(section, 'Active Calories:');
    final avgHrVal = _parseInt(section, 'Avg Heart Rate:');
    final stressVal =
        _parseInt(section, 'Stress:') ?? _parseInt(section, 'Avg Stress:');

    if (mounted) {
      setState(() {
        if (steps != null) _steps = _formatNumber(steps);
        if (calories != null && calories > 0) {
          _calories = _formatNumber(calories);
        }
        if (avgHrVal != null && avgHrVal > 0) _avgHr = '$avgHrVal';
        if (stressVal != null && stressVal > 0) _stress = '$stressVal';
      });
    }
  }

  Future<void> _fetchSleepLive() async {
    final text = await _callCoros(
      'querySleepData',
      arguments: {'days': 2, 'timezone': 'Asia/Shanghai'},
      fallbackFileName: 'sleep_data.json',
    );
    if (text == null) return;

    final sections = _splitDatedSections(text);
    // Keep only sections with actual sleep scores
    final sleepSections = <String, String>{};
    for (final e in sections.entries) {
      if (e.value.contains('Sleep Score:')) {
        sleepSections[e.key] = e.value;
      }
    }
    if (sleepSections.isEmpty) return;

    // FIX: pick newest date by date comparison, NOT by iteration order
    final newestDate = _pickNewestDate(sleepSections.keys.toList());
    _applySleepSection(sleepSections[newestDate]!);
  }

  void _applySleepSection(String section) {
    final score = _parseInt(section, 'Sleep Score:');
    final totalMin = _parseDurationMin(section, 'Main Sleep:');
    final deepPct = _parseInt(section, 'Deep Sleep Ratio:');
    final remPct = _parseInt(section, 'REM Ratio:');
    final lightPct = _parseInt(section, 'Light Sleep Ratio:');

    if (mounted) {
      setState(() {
        if (score != null) _sleepScore = '$score';
        if (totalMin != null && totalMin > 0) {
          final hours = totalMin ~/ 60;
          final mins = totalMin % 60;
          final parts = <String>[];
          if (deepPct != null && deepPct > 0) parts.add('深睡 $deepPct%');
          if (remPct != null && remPct > 0) parts.add('REM $remPct%');
          if (lightPct != null && lightPct > 0) parts.add('浅睡 $lightPct%');
          _sleepBreakdown =
              '${hours > 0 ? '$hours 小时 ' : ''}${mins > 0 ? '$mins 分钟' : ''}';
          if (parts.isNotEmpty) {
            _sleepBreakdown = '$_sleepBreakdown · ${parts.join(' · ')}';
          }
        }
      });
    }
  }

  Future<void> _fetchRecoveryLive() async {
    final text = await _callCoros(
      'queryRecoveryStatus',
      fallbackFileName: 'recovery_status.txt',
    );
    if (text == null) return;
    final recovery = _parseInt(text, 'Recovery:');
    if (mounted && recovery != null) {
      setState(() => _recovery = '$recovery');
    }
  }

  Future<void> _fetchRestingHrLive() async {
    // Use the dedicated resting HR endpoint — same as what 林埃 would use
    final text = await _callCoros(
      'queryRestingHeartRate',
      arguments: {'days': 2, 'timezone': 'Asia/Shanghai'},
      fallbackFileName: 'daily_health.json',
    );
    if (text == null) return;

    final sections = _splitDatedSections(text);
    String section;
    if (sections.isNotEmpty) {
      final newestDate = _pickNewestDate(sections.keys.toList());
      section = sections[newestDate]!;
    } else {
      section = text;
    }

    final restingHr = _parseInt(section, 'Resting Heart Rate:') ??
        _parseInt(section, 'Resting HR:') ??
        _parseInt(section, 'Average Resting HR:');

    if (mounted && restingHr != null && restingHr > 0) {
      setState(() => _restingHr = '$restingHr');
    }
  }

  Future<void> _fetchStressLive() async {
    final text = await _callCoros(
      'queryStressLevel',
      arguments: {'days': 2, 'timezone': 'Asia/Shanghai'},
    );
    if (text == null) return;

    final sections = _splitDatedSections(text);
    String section;
    if (sections.isNotEmpty) {
      final newestDate = _pickNewestDate(sections.keys.toList());
      section = sections[newestDate]!;
    } else {
      section = text;
    }

    final stressVal = _parseInt(section, 'Avg Stress:') ??
        _parseInt(section, 'Stress:') ??
        _parseInt(section, 'Average Stress Level:');

    if (mounted && stressVal != null && stressVal > 0) {
      setState(() => _stress = '$stressVal');
    }
  }

  Future<void> _fetchHrvLive() async {
    final text = await _callCoros(
      'queryHrvAssessment',
      arguments: {'days': 2, 'timezone': 'Asia/Shanghai'},
    );
    if (text == null) return;

    final sections = _splitDatedSections(text);
    String section;
    if (sections.isNotEmpty) {
      final newestDate = _pickNewestDate(sections.keys.toList());
      section = sections[newestDate]!;
    } else {
      section = text;
    }

    final hrvVal = _parseInt(section, 'HRV:') ??
        _parseInt(section, 'Avg HRV:') ??
        _parseInt(section, 'Average HRV:') ??
        _parseInt(section, 'Rmssd:');

    if (mounted && hrvVal != null && hrvVal > 0) {
      setState(() => _hrv = '$hrvVal');
    }
  }

  Future<void> _fetchFitnessLive() async {
    final text = await _callCoros(
      'queryFitnessAssessmentOverview',
      fallbackFileName: 'fitness_assessment.txt',
    );
    if (text == null) return;

    final vo2 = _parseFloat(text, 'VO2max:') ??
        _parseFloat(text, 'VO2 Max:') ??
        _parseFloat(text, 'Vo2max:');
    final fitnessLevelStr = _extractLine(text, 'Running Level:') ??
        _extractLine(text, 'Running Performance:') ??
        _extractLine(text, 'Fitness Level:');

    if (mounted) {
      setState(() {
        if (vo2 != null && vo2 > 0) _vo2max = vo2.toStringAsFixed(1);
        if (fitnessLevelStr != null && fitnessLevelStr.isNotEmpty) {
          _fitnessLevel = fitnessLevelStr;
        }
      });
    }
  }

  Future<void> _fetchRecentWorkoutsLive() async {
    final text = await _callCoros(
      'querySportRecords',
      arguments: {'limit': 3, 'timezone': 'Asia/Shanghai'},
      fallbackFileName: 'recent_sport_records.json',
    );
    if (text == null) return;

    final workouts = <Map<String, dynamic>>[];
    final sections = text.split('\n\n');
    for (final s in sections) {
      if (!s.contains('Type:') &&
          !s.contains('Sport:') &&
          !s.contains('Workout:')) {
        continue;
      }
      final type = _extractLine(s, 'Type:') ??
          _extractLine(s, 'Sport:') ??
          _extractLine(s, 'Workout:') ??
          '';
      final date = _extractLine(s, 'Date:') ??
          _extractLine(s, 'Start Time:') ??
          '';
      final duration = _extractLine(s, 'Duration:') ??
          _extractLine(s, 'Total Time:') ??
          '';
      final distance = _extractLine(s, 'Distance:') ?? '';
      final kcal = _parseInt(s, 'Calories:') ?? _parseInt(s, 'Energy:');

      if (type.isNotEmpty) {
        workouts.add({
          'type': type.trim(),
          'date': date.trim(),
          'duration': duration.trim(),
          'distance': distance.trim(),
          'calories': kcal,
        });
      }
      if (workouts.length >= 3) break;
    }

    if (mounted && workouts.isNotEmpty) {
      setState(() => _recentWorkouts = workouts);
    }
  }

  // ── Cache fallback (when live API is unreachable) ───────────────────────

  Future<void> _loadFromCache() async {
    await Future.wait([
      _fetchDailyHealthCached(),
      _fetchSleepCached(),
      _fetchRecoveryCached(),
    ]);
    if (mounted) setState(() => _usingLiveApi = false);
  }

  Future<String> _getCorosDir() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return '';
    return '${FileSystemService.instance.getUserSettingsPath(userId)}/external_data/coros';
  }

  Future<void> _fetchDailyHealthCached() async {
    try {
      final dir = await _getCorosDir();
      if (dir.isEmpty) return;
      final file = File('$dir/daily_health.json');
      if (!file.existsSync()) return;
      final text = await file.readAsString();

      final sections = _splitDatedSections(text);
      if (sections.isEmpty) return;
      final newestDate = _pickNewestDate(sections.keys.toList());
      final section = sections[newestDate]!;

      final steps = _parseInt(section, 'Steps:');
      final calories = _parseInt(section, 'Calories:') ??
          _parseInt(section, 'Active Calories:');
      final restingHr = _parseInt(section, 'Resting HR:') ??
          _parseInt(section, 'Resting Heart Rate:');
      final avgHrVal = _parseInt(section, 'Avg Heart Rate:');
      final stressVal =
          _parseInt(section, 'Stress:') ?? _parseInt(section, 'Avg Stress:');

      if (mounted) {
        setState(() {
          if (steps != null) _steps = _formatNumber(steps);
          if (calories != null && calories > 0) {
            _calories = _formatNumber(calories);
          }
          if (restingHr != null && restingHr > 0) {
            _restingHr = '$restingHr';
          } else if (avgHrVal != null && avgHrVal > 0) {
            _avgHr = '$avgHrVal';
          }
          if (stressVal != null && stressVal > 0) _stress = '$stressVal';
        });
      }
    } catch (e) {
      _logger.warning('Failed to read cached daily health: $e');
    }
  }

  Future<void> _fetchSleepCached() async {
    try {
      final dir = await _getCorosDir();
      if (dir.isEmpty) return;
      final file = File('$dir/sleep_data.json');
      if (!file.existsSync()) return;
      final text = await file.readAsString();

      final sections = _splitDatedSections(text);
      final sleepSections = <String, String>{};
      for (final e in sections.entries) {
        if (e.value.contains('Sleep Score:')) {
          sleepSections[e.key] = e.value;
        }
      }
      if (sleepSections.isEmpty) return;
      final newestDate = _pickNewestDate(sleepSections.keys.toList());
      _applySleepSection(sleepSections[newestDate]!);
    } catch (e) {
      _logger.warning('Failed to read cached sleep: $e');
    }
  }

  Future<void> _fetchRecoveryCached() async {
    try {
      final dir = await _getCorosDir();
      if (dir.isEmpty) return;
      final file = File('$dir/recovery_status.txt');
      if (!file.existsSync()) return;
      final text = await file.readAsString();
      final recovery = _parseInt(text, 'Recovery:');
      if (mounted && recovery != null) {
        setState(() => _recovery = '$recovery');
      }
    } catch (e) {
      _logger.warning('Failed to read cached recovery: $e');
    }
  }

  // ── Section parsing (date-aware, fixes ordering bug) ────────────────────

  /// Split COROS MCP text response into a map of normalized-date → section.
  ///
  /// Handles:
  ///   --- 20260708 ---
  ///   key: value
  ///   --- 20260707 ---
  ///
  /// And:
  ///   Date: 2026-07-08
  ///   key: value
  ///   Date: 2026-07-07
  Map<String, String> _splitDatedSections(String text) {
    final result = <String, String>{};

    // COROS-style date markers: "--- YYYYMMDD ---"
    final corosMarker = RegExp(r'^---\s*(\d{8})\s*---\s*$', multiLine: true);
    final matches = corosMarker.allMatches(text).toList();

    if (matches.isNotEmpty) {
      for (int i = 0; i < matches.length; i++) {
        final dateStr = matches[i].group(1)!;
        final normalized =
            '${dateStr.substring(0, 4)}-${dateStr.substring(4, 6)}-${dateStr.substring(6, 8)}';
        final start = matches[i].end;
        final end =
            (i + 1 < matches.length) ? matches[i + 1].start : text.length;
        result[normalized] = text.substring(start, end).trim();
      }
      return result;
    }

    // "Date: YYYY-MM-DD" or "Date: YYYYMMDD" style
    final dateLine = RegExp(
      r'(?:^|\n)Date:\s*(\d{4}-\d{2}-\d{2}|\d{8})\s*$',
      multiLine: true,
    );
    final dateMatches = dateLine.allMatches(text).toList();
    if (dateMatches.length > 1) {
      for (int i = 0; i < dateMatches.length; i++) {
        var dateStr = dateMatches[i].group(1)!;
        if (dateStr.length == 8) {
          dateStr =
              '${dateStr.substring(0, 4)}-${dateStr.substring(4, 6)}-${dateStr.substring(6, 8)}';
        }
        final start = dateMatches[i].start;
        final end = (i + 1 < dateMatches.length)
            ? dateMatches[i + 1].start
            : text.length;
        result[dateStr] = text.substring(start, end).trim();
      }
      return result;
    }

    // Fallback: return whole text (for non-dated responses)
    if (text.trim().isNotEmpty) {
      result[''] = text.trim();
    }
    return result;
  }

  /// Pick the most recent date from a list of yyyy-MM-dd strings.
  String _pickNewestDate(List<String> dates) {
    if (dates.isEmpty) return '';
    dates.sort((a, b) => b.compareTo(a)); // newest first
    for (final d in dates) {
      if (d.isNotEmpty) return d;
    }
    return dates.first;
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
    if (_loading && _noData) {
      return const Center(child: AgentLogoLoading());
    }

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

    if (_noData && _corosConnected) {
      return ListView(
        controller: _scrollController,
        children: [
          const SizedBox(height: 80),
          _buildNoDataPrompt(),
        ],
      );
    }

    if (_noData && !_corosConnected) {
      return ListView(
        controller: _scrollController,
        children: [
          const SizedBox(height: 80),
          _buildConnectPrompt(),
        ],
      );
    }

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
      _calories == null &&
      _sleepScore == null &&
      _restingHr == null &&
      _avgHr == null &&
      _recovery == null &&
      _stress == null &&
      _hrv == null &&
      _vo2max == null &&
      _fitnessLevel == null &&
      _recentWorkouts.isEmpty &&
      _healthCards.isEmpty;

  List<Widget> _buildCardList() {
    final items = <Widget>[];

    // ── Section: COROS watch metrics ──

    if (_corosConnected) {
      items.add(
        Row(
          children: [
            _sectionHeader('手表数据'),
            if (!_usingLiveApi) ...[
              const SizedBox(width: 8),
              _cachedIndicator(),
            ],
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

      if (_calories != null) {
        items.add(HealthStatCard(
          icon: Icons.local_fire_department,
          label: '活动卡路里',
          value: _calories!,
          unit: 'kcal',
          color: const Color(0xFFF97316),
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

      // Resting HR — properly labeled, from dedicated endpoint
      if (_restingHr != null) {
        items.add(HealthStatCard(
          icon: Icons.favorite_outline,
          label: '静息心率',
          value: _restingHr!,
          unit: 'bpm',
          color: const Color(0xFFF43F5E),
        ));
      } else if (_avgHr != null) {
        // Fallback: shown as "平均心率" (not "静息心率") because it's avg, not resting
        items.add(HealthStatCard(
          icon: Icons.favorite_outline,
          label: '平均心率',
          value: _avgHr!,
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

      if (_stress != null) {
        items.add(HealthStatCard(
          icon: Icons.psychology_outlined,
          label: '压力指数',
          value: _stress!,
          color: const Color(0xFF8B5CF6),
        ));
      }

      if (_hrv != null) {
        items.add(HealthStatCard(
          icon: Icons.monitor_heart_outlined,
          label: 'HRV',
          value: _hrv!,
          unit: 'ms',
          color: const Color(0xFF06B6D4),
        ));
      }

      if (_vo2max != null || _fitnessLevel != null) {
        items.add(HealthStatCard(
          icon: Icons.fitness_center,
          label: '体能评估',
          value: _vo2max ?? _fitnessLevel ?? '',
          unit: _vo2max != null ? 'ml/kg/min' : null,
          subtitle: _vo2max != null ? _fitnessLevel : null,
          color: const Color(0xFF22C55E),
        ));
      }

      // Recent workouts
      for (final w in _recentWorkouts) {
        final type = w['type'] as String? ?? '';
        final date = w['date'] as String? ?? '';
        final duration = w['duration'] as String? ?? '';
        final distance = w['distance'] as String? ?? '';
        final calories = w['calories'];

        final subtitleParts = <String>[];
        if (duration.isNotEmpty) subtitleParts.add(duration);
        if (distance.isNotEmpty) subtitleParts.add(distance);
        if (calories != null && calories > 0) {
          subtitleParts.add('$calories kcal');
        }

        items.add(HealthStatCard(
          icon: Icons.directions_run,
          label: type.isNotEmpty ? type : '训练记录',
          value: date,
          subtitle: subtitleParts.join(' · '),
          color: const Color(0xFF3B82F6),
        ));
      }

      if (_steps == null &&
          _calories == null &&
          _sleepScore == null &&
          _restingHr == null &&
          _avgHr == null &&
          _recovery == null &&
          _stress == null &&
          _hrv == null &&
          _vo2max == null &&
          _fitnessLevel == null &&
          _recentWorkouts.isEmpty) {
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

  Widget _cachedIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textTertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '离线缓存',
        style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildNoDataPrompt() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.watch_outlined,
              size: 48, color: AppColors.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            'COROS 已连接，暂无手表数据',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            '请确认手表已同步至 COROS App，再点击同步。',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _syncButton(),
        ],
      ),
    );
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
            '在设置中连接 COROS 后，这里将展示步数、睡眠、心率、压力、HRV、体能等数据。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
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

  // ── Text parsing helpers ────────────────────────────────────────────────

  /// Parse an integer from text after a prefix, e.g. "Steps: 12,345" → 12345.
  int? _parseInt(String text, String prefix) {
    final match = RegExp('$prefix\\s*([0-9,]+)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  /// Parse a float from text after a prefix, e.g. "VO2max: 48.5" → 48.5.
  double? _parseFloat(String text, String prefix) {
    final match =
        RegExp('$prefix\\s*([0-9]+(?:\\.[0-9]+)?)').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  /// Extract the text on the rest of a line after a prefix.
  String? _extractLine(String text, String prefix) {
    final match =
        RegExp('$prefix\\s*(.+?)\\s*\$', multiLine: true).firstMatch(text);
    if (match == null) return null;
    return match.group(1)?.trim();
  }

  /// Parse duration like "7h 18min" or "7h" or "18min" → total minutes.
  int? _parseDurationMin(String text, String prefix) {
    final idx = text.indexOf(prefix);
    if (idx < 0) return null;
    final remainder = text.substring(idx + prefix.length).trim();
    var hours = 0;
    var mins = 0;
    final hMatch = RegExp(r'(\d+)\s*h').firstMatch(remainder);
    if (hMatch != null) hours = int.parse(hMatch.group(1)!);
    final mMin = RegExp(r'(\d+)\s*min').firstMatch(remainder);
    if (mMin != null) mins = int.parse(mMin.group(1)!);
    if (hours == 0 && mins == 0) return null;
    return hours * 60 + mins;
  }

  // ── Formatting ──────────────────────────────────────────────────────────

  static String _formatNumber(int n) {
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(1)} 万';
    }
    return n.toString();
  }
}
