import 'dart:io';

import 'package:flutter/material.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/memory_v3/models/memory_card_view_data.dart';
import 'package:memex/data/memory_v3/services/life_insight_scheduler.dart';
import 'package:memex/data/memory_v3/services/memory_card_query_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/memory_v3/services/user_rhythm_service.dart';
import 'package:memex/data/services/coros_mcp_service.dart';
import 'package:memex/data/services/coros_sync_service.dart';
import 'package:memex/data/services/ble_heart_rate_gateway.dart';
import 'package:memex/data/services/mcp_token_storage.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/companion/widgets/insight_strip.dart';
import 'package:memex/ui/companion/widgets/live_heart_rate_card.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/memory/widgets/memory_card_detail_screen_v3.dart';
import 'package:memex/ui/memory/widgets/memory_summary_card_v3.dart';
import 'package:memex/ui/settings/widgets/coros_connect_page.dart';
import 'package:memex/ui/settings/widgets/heart_rate_device_settings_page.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

import 'health_stat_card.dart';

const _healthAccent = Color(0xFF737B46);
const _healthInk = Color(0xFF293025);
const _healthMuted = Color(0xFF667061);
const _healthOnRain = Color(0xFFF5EEE0);
const _healthSurface = Color(0xEDE7E8D1);
const _healthGreen = Color(0xFF5F7658);
const _healthWarm = Color(0xFF9A702E);
const _healthHeart = Color(0xFF9B5B52);
const _healthInfo = Color(0xFF526E72);

/// Health observation panel in Life Space.
///
/// Data sources (in priority order):
/// 1. COROS MCP live API — same as 林埃's `coros_query` tool
/// 2. Synced local files — fallback when API is unavailable
/// 3. Health-related Memory V3 cards
class CompanionHealthPanel extends StatefulWidget {
  const CompanionHealthPanel({super.key, this.heartRateGateway});

  final BleHeartRateGateway? heartRateGateway;

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

  // Menstrual cycle status
  String? _cyclePhase;
  String? _cyclePhaseDesc;
  DateTime? _cycleLatestStart;
  DateTime? _cyclePredictedNext;
  String? _cycleUpcomingAlert;
  int? _cycleCount;
  bool _recordingPeriod = false;

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
      await _loadCycleStatus();
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
      // NOTE: _fetchHrvLive disabled — COROS tool name TBD (server returned "Unknown tool")
      await Future.wait([
        _fetchDailyHealthLive(),
        _fetchSleepLive(),
        _fetchRecoveryLive(),
        _fetchRestingHrLive(),
        _fetchStressLive(),
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
      final rawText = result.text;
      // COROS MCP returns literal \n escape sequences — normalize to real newlines
      final text = rawText.replaceAll(r'\n', '\n');
      _logger.info('[COROS LIVE] $toolName → ${text.length} chars');
      _logger.info(
          '[COROS RAW] $toolName:\n${text.length > 2000 ? text.substring(0, 2000) : text}');
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
        if (file.existsSync()) {
          final rawText = await file.readAsString();
          final text = rawText.replaceAll(r'\n', '\n');
          _logger.info(
              '[COROS CACHE] $toolName ← $fallbackFileName → ${text.length} chars');
          _logger.info(
              '[CACHE RAW] $toolName:\n${text.length > 2000 ? text.substring(0, 2000) : text}');
          return text;
        }
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
    _logger.info(
        '[PARSE] daily_health sections: ${sections.keys.toList()..sort()}');
    if (sections.isEmpty) return;
    final newestDate = _pickNewestDate(sections.keys.toList());
    final section = sections[newestDate]!;
    _logger.info(
        '[PARSE] daily_health picked date: $newestDate, section preview: ${section.substring(0, section.length > 300 ? 300 : section.length)}');

    final steps = _parseInt(section, 'Steps:');
    final calories = _parseInt(section, 'Calories:') ??
        _parseInt(section, 'Active Calories:');
    final avgHrVal = _parseInt(section, 'Avg Heart Rate:');
    // Stress format: "Stress: Avg 45" — need to skip "Avg" prefix
    final stressVal = _parseIntAfterWord(section, 'Stress:', 'Avg') ??
        _parseInt(section, 'Avg Stress:');
    _logger.info(
        '[PARSE] daily_health values — steps=$steps, calories=$calories, avgHr=$avgHrVal, stress=$stressVal');

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

    // COROS MCP returns literal \n escape sequences in the text, NOT actual
    // newline characters. Normalize before parsing.
    final normalized = text.replaceAll(r'\n', '\n');
    final lines = normalized.split('\n');
    final dateIndices = <int, String>{}; // lineIndex → dateStr
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(line)) {
        dateIndices[i] = line;
      }
    }
    _logger.info(
        '[PARSE] sleep date lines found: ${dateIndices.length} — ${dateIndices.values.toList()}');

    if (dateIndices.isEmpty) return;

    final dateList = dateIndices.entries.toList();
    final sleepSections = <String, String>{};
    for (int j = 0; j < dateList.length; j++) {
      final dateStr = dateList[j].value;
      // Content starts at the line after the date line
      final contentStartLine = dateList[j].key + 1;
      final contentEndLine =
          (j + 1 < dateList.length) ? dateList[j + 1].key : lines.length;
      final sectionLines = lines.sublist(contentStartLine, contentEndLine);
      final section = sectionLines.join('\n').trim();
      _logger.info(
          '[PARSE] sleep section $dateStr: ${sectionLines.length} lines, hasScore=${section.contains("Sleep Score:")}');
      if (section.contains('Sleep Score:')) {
        sleepSections[dateStr] = section;
      }
    }

    _logger.info(
        '[PARSE] sleep sections with scores: ${sleepSections.keys.toList()..sort()}');
    if (sleepSections.isEmpty) return;

    final newestDate = _pickNewestDate(sleepSections.keys.toList());
    _logger.info('[PARSE] sleep picked date: $newestDate');
    _applySleepSection(sleepSections[newestDate]!);
  }

  void _applySleepSection(String section) {
    final score = _parseInt(section, 'Sleep Score:');
    final totalMin = _parseDurationMin(section, 'Main Sleep:');
    final deepPct = _parseInt(section, 'Deep Sleep Ratio:');
    final remPct = _parseInt(section, 'REM Ratio:');
    final lightPct = _parseInt(section, 'Light Sleep Ratio:');
    _logger.info(
        '[PARSE] sleep values — score=$score, totalMin=$totalMin, deep=$deepPct%, rem=$remPct%, light=$lightPct%');

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
    // Use the dedicated resting HR endpoint.
    // Format: "2026-07-08: 62 bpm\n2026-07-07: 61 bpm"
    final text = await _callCoros(
      'queryRestingHeartRate',
      arguments: {'days': 2, 'timezone': 'Asia/Shanghai'},
      fallbackFileName: 'daily_health.json',
    );
    if (text == null) return;

    final sections = _splitDatedSections(text);
    // sections map: date → "62 bpm" (value after colon, per pattern 3a)
    final hrByDate = <String, int>{};
    for (final e in sections.entries) {
      if (e.key.isEmpty) continue;
      // value is e.g. "62 bpm" — extract just the number
      final hr = _parseInt(e.value, ''); // empty prefix: match first number
      if (hr != null && hr > 0) hrByDate[e.key] = hr;
    }

    if (hrByDate.isEmpty) return;
    final newestDate = _pickNewestDate(hrByDate.keys.toList());
    final restingHr = hrByDate[newestDate];

    if (mounted && restingHr != null && restingHr > 0) {
      setState(() => _restingHr = '$restingHr');
    }
  }

  Future<void> _fetchStressLive() async {
    // Format: "2026-07-08:\nAverage Stress: 44 (Low)\n..."
    // _splitDatedSections pattern 3b splits into date→multi-line section
    final text = await _callCoros(
      'queryStressLevel',
      arguments: {'days': 2, 'timezone': 'Asia/Shanghai'},
    );
    if (text == null) return;

    final sections = _splitDatedSections(text);
    final stressByDate = <String, int>{};
    for (final e in sections.entries) {
      if (e.key.isEmpty) continue;
      // section content: "Average Stress: 44 (Low)\nRelaxed: ..."
      final val = _parseInt(e.value, 'Average Stress:') ??
          _parseInt(e.value, 'Stress:') ??
          _parseInt(e.value, 'Avg Stress:');
      if (val != null && val > 0) stressByDate[e.key] = val;
    }

    if (stressByDate.isEmpty) return;
    final newestDate = _pickNewestDate(stressByDate.keys.toList());

    if (mounted) {
      setState(() => _stress = '${stressByDate[newestDate]}');
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
      final date =
          _extractLine(s, 'Date:') ?? _extractLine(s, 'Start Time:') ?? '';
      final duration =
          _extractLine(s, 'Duration:') ?? _extractLine(s, 'Total Time:') ?? '';
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
      final avgHrVal = _parseInt(section, 'Avg Heart Rate:');
      final stressVal = _parseIntAfterWord(section, 'Stress:', 'Avg') ??
          _parseInt(section, 'Avg Stress:');

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

      // Same dedicated sleep parser as live version
      final datePattern = RegExp(r'\n(\d{4}-\d{2}-\d{2})\n');
      final matches = datePattern.allMatches(text).toList();
      if (matches.isEmpty) return;

      final sleepSections = <String, String>{};
      for (int i = 0; i < matches.length; i++) {
        final dateStr = matches[i].group(1)!;
        final contentStart = matches[i].end;
        final contentEnd =
            (i + 1 < matches.length) ? matches[i + 1].start : text.length;
        final section = text.substring(contentStart, contentEnd).trim();
        if (section.contains('Sleep Score:')) {
          sleepSections[dateStr] = section;
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
  /// Handles actual COROS response formats:
  ///   --- 20260708 ---        (daily_health)
  ///   2026-07-07              (sleep_data — bare date on own line)
  ///   2026-07-08:             (stress, resting HR — date: value on same line)
  Map<String, String> _splitDatedSections(String text) {
    final result = <String, String>{};

    // Pattern 1: "--- YYYYMMDD ---"  (daily_health)
    // Don't use ^/$ anchors — they fail on some line-ending combinations.
    final m1 = RegExp(r'---\s*(\d{8})\s*---');
    final m1Matches = m1.allMatches(text).toList();
    if (m1Matches.length >= 1) {
      for (int i = 0; i < m1Matches.length; i++) {
        final ds = m1Matches[i].group(1)!;
        final normalized =
            '${ds.substring(0, 4)}-${ds.substring(4, 6)}-${ds.substring(6, 8)}';
        final start = m1Matches[i].end;
        final end =
            (i + 1 < m1Matches.length) ? m1Matches[i + 1].start : text.length;
        final section = text.substring(start, end).trim();
        if (section.isNotEmpty) result[normalized] = section;
      }
      if (result.isNotEmpty) return result;
    }

    // Pattern 2: bare "YYYY-MM-DD" on its own line  (sleep_data)
    // NOTE: use [ \t]* not \s* — \s* would greedily eat the \n we need to match
    final m2 = RegExp(r'(?:^|\n)(\d{4}-\d{2}-\d{2})[ \t]*\r?\n');
    final m2Matches = m2.allMatches(text).toList();
    if (m2Matches.length >= 1) {
      for (int i = 0; i < m2Matches.length; i++) {
        final dateStr = m2Matches[i].group(1)!;
        // start after the date line; end at next date line or EOF
        final contentStart = m2Matches[i].end;
        final contentEnd =
            (i + 1 < m2Matches.length) ? m2Matches[i + 1].start : text.length;
        final section = text.substring(contentStart, contentEnd).trim();
        if (section.isNotEmpty) result[dateStr] = section;
      }
      if (result.isNotEmpty) return result;
    }

    // Pattern 3: "YYYY-MM-DD:" — two sub-cases:
    //  3a: "YYYY-MM-DD: value" all on one line  (resting HR)
    //  3b: "YYYY-MM-DD:\nKey: value\n..." multi-line section  (stress)
    final m3 =
        RegExp(r'(?:^|\n)(\d{4}-\d{2}-\d{2}):[ \t]*(\S.*)?$', multiLine: true);
    final m3Matches = m3.allMatches(text).toList();
    if (m3Matches.length >= 1) {
      for (int i = 0; i < m3Matches.length; i++) {
        final dateStr = m3Matches[i].group(1)!;
        final inlineValue = m3Matches[i].group(2);
        if (inlineValue != null && inlineValue.isNotEmpty) {
          // Case 3a: value on same line  e.g. "2026-07-08: 62 bpm"
          result[dateStr] = inlineValue.trim();
        } else {
          // Case 3b: value on following lines until next date marker or EOF
          final contentStart = m3Matches[i].end;
          final contentEnd =
              (i + 1 < m3Matches.length) ? m3Matches[i + 1].start : text.length;
          final section = text.substring(contentStart, contentEnd).trim();
          if (section.isNotEmpty) result[dateStr] = section;
        }
      }
      if (result.isNotEmpty) return result;
    }

    // Fallback: return whole text as a single (undated) section
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

  Future<void> _loadCycleStatus() async {
    try {
      if (!UserRhythmService.isInitialized) return;
      final status =
          await UserRhythmService.instance.getMenstrualCycleStatus();
      if (mounted) {
        setState(() {
          _cyclePhase = status?.phase;
          _cyclePhaseDesc = status?.phaseDescription;
          _cycleLatestStart = status?.latestStart;
          _cyclePredictedNext = status?.predictedNextStart;
          _cycleUpcomingAlert = status?.upcomingAlert;
          _cycleCount = status?.cycleCount;
        });
      }
    } catch (e) {
      _logger.warning('Failed to load cycle status: $e');
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
        SnackBar(
          content: Text(
            result.detail != null && result.detail!.isNotEmpty
                ? '${result.message}\n${result.detail}'
                : result.message,
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      if (result.synced) await _loadData();
    } catch (e) {
      _logger.warning('Failed to sync COROS MCP data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('COROS 同步异常：$e'),
            duration: const Duration(seconds: 5),
          ),
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
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildLiveHeartRateCard(),
          const SizedBox(height: 48),
          const Center(
            child: CircularProgressIndicator(
              color: _healthAccent,
              strokeWidth: 2,
            ),
          ),
        ],
      );
    }

    if (_error != null && _noData) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildLiveHeartRateCard(),
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                '加载失败\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _healthOnRain,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_noData && _corosConnected) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildLiveHeartRateCard(),
          const SizedBox(height: 80),
          _buildNoDataPrompt(),
        ],
      );
    }

    if (_noData && !_corosConnected) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildLiveHeartRateCard(),
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

    // Native BLE HRS is independent from COROS cloud metrics and is always
    // the first Health surface, including unconfigured/error states.
    items.add(_buildLiveHeartRateCard());

    // ── Insight strip (Life Insights for health domain) ──
    items.add(InsightStrip(
      domain: 'health',
      onRefresh: () => LifeInsightScheduler(db: AppDatabase.instance)
          .forceRunWeeklyAnalysis(),
    ));

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
          color: _healthGreen,
        ));
      }

      if (_calories != null) {
        items.add(HealthStatCard(
          icon: Icons.local_fire_department,
          label: '活动卡路里',
          value: _calories!,
          unit: 'kcal',
          color: _healthWarm,
        ));
      }

      if (_sleepScore != null) {
        items.add(HealthStatCard(
          icon: Icons.bedtime_outlined,
          label: '睡眠评分',
          value: _sleepScore!,
          subtitle: _sleepBreakdown,
          color: _healthAccent,
        ));
      }

      // Resting HR — properly labeled, from dedicated endpoint
      if (_restingHr != null) {
        items.add(HealthStatCard(
          icon: Icons.favorite_outline,
          label: '静息心率',
          value: _restingHr!,
          unit: 'bpm',
          color: _healthHeart,
        ));
      } else if (_avgHr != null) {
        // Fallback: shown as "平均心率" (not "静息心率") because it's avg, not resting
        items.add(HealthStatCard(
          icon: Icons.favorite_outline,
          label: '平均心率',
          value: _avgHr!,
          unit: 'bpm',
          color: _healthHeart,
        ));
      }

      if (_recovery != null) {
        items.add(HealthStatCard(
          icon: Icons.auto_awesome,
          label: '身体恢复',
          value: '$_recovery%',
          color: _healthWarm,
        ));
      }

      if (_stress != null) {
        items.add(HealthStatCard(
          icon: Icons.psychology_outlined,
          label: '压力指数',
          value: _stress!,
          color: _healthAccent,
        ));
      }

      if (_hrv != null) {
        items.add(HealthStatCard(
          icon: Icons.monitor_heart_outlined,
          label: 'HRV',
          value: _hrv!,
          unit: 'ms',
          color: _healthInfo,
        ));
      }

      if (_vo2max != null || _fitnessLevel != null) {
        items.add(HealthStatCard(
          icon: Icons.fitness_center,
          label: '体能评估',
          value: _vo2max ?? _fitnessLevel ?? '',
          unit: _vo2max != null ? 'ml/kg/min' : null,
          subtitle: _vo2max != null ? _fitnessLevel : null,
          color: _healthGreen,
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
          color: _healthInfo,
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

    // ── Section: Menstrual cycle ──

    // Always show the menstrual section: either the cycle status card
    // (when data exists) or an empty-state prompt with a record button.
    items.add(_sectionHeader('经期'));
    if (_cyclePhase != null) {
      items.add(_buildCycleCard());
    } else {
      items.add(_buildCycleEmptyPrompt());
    }
    items.add(_buildCycleRecordButton());
    items.add(const SizedBox(height: 8));

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

  Widget _buildLiveHeartRateCard() {
    return LiveHeartRateCard(
      gateway: widget.heartRateGateway,
      onTap: _openHeartRateSettings,
    );
  }

  Future<void> _openHeartRateSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SpringRainUiScope(
          child: HeartRateDeviceSettingsPage(
            gateway: widget.heartRateGateway,
          ),
        ),
      ),
    );
  }

  Widget _cachedIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _healthSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '离线缓存',
        style: TextStyle(fontSize: 10, color: _healthMuted),
      ),
    );
  }

  Widget _buildNoDataPrompt() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _healthSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xA8FFFFFF), width: .8),
      ),
      child: Column(
        children: [
          const Icon(Icons.watch_outlined, size: 48, color: _healthAccent),
          const SizedBox(height: 12),
          const Text(
            'COROS 已连接，暂无手表数据',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            '请确认手表已同步至 COROS App，再点击同步。',
            style: TextStyle(fontSize: 13, color: _healthMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _syncButton(),
        ],
      ),
    );
  }

  Widget _buildCycleCard() {
    final phaseColor = _cyclePhase == 'menstrual'
        ? const Color(0xFFE91E63)
        : _cyclePhase == 'late'
            ? const Color(0xFFFF9800)
            : const Color(0xFFAB47BC);

    final lines = <String>[];
    if (_cyclePhaseDesc != null) lines.add(_cyclePhaseDesc!);
    if (_cycleLatestStart != null) {
      lines.add('上次开始：${_cycleLatestStart!.month}/${_cycleLatestStart!.day}');
    }
    if (_cyclePredictedNext != null) {
      lines.add('预测下次：${_cyclePredictedNext!.month}/${_cyclePredictedNext!.day}');
    }
    if (_cycleUpcomingAlert != null) {
      lines.add('⚠️ ${_cycleUpcomingAlert}');
    }
    if (_cycleCount != null && _cycleCount! > 0) {
      lines.add('已记录 $_cycleCount 个周期');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: phaseColor.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.spa_outlined, size: 20, color: phaseColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines
                  .map((l) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          l,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: l.startsWith('⚠️')
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF333333),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleEmptyPrompt() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _healthSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _healthAccent.withValues(alpha: 0.2),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.spa_outlined, size: 20, color: _healthAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '尚无经期记录。来月经时点下方按钮记录，林埃会学习你的周期。',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: _healthMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleRecordButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _recordingPeriod ? null : _recordMenstrualPeriod,
          icon: _recordingPeriod
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_circle_outline, size: 16),
          label: Text(_recordingPeriod ? '记录中…' : '记录经期'),
          style: TextButton.styleFrom(
            foregroundColor: _healthAccent,
            backgroundColor: _healthSurface,
            disabledForegroundColor: _healthMuted,
            disabledBackgroundColor: _healthSurface.withValues(alpha: 0.72),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(72, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  /// Record a menstrual period via the Record Organizer natural-language
  /// path. Opens a date picker for the start date, then feeds a natural
  /// sentence into organizeAndPersist so the LLM extracts a structured
  /// menstrual_record card. The card->rhythm bridge then syncs the cycle
  /// projection automatically.
  Future<void> _recordMenstrualPeriod() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now,
      helpText: '选择经期开始日期',
    );
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _recordingPeriod = true);
    try {
      final dateStr =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      final rawInput = '大姨妈 $dateStr 来了';

      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final result =
          await RecordOrganizerServiceV3.instance.organizeAndPersist(
        client: resources.client,
        modelConfig: resources.modelConfig,
        source: RecordSource(sourceKind: 'fab', rawInput: rawInput),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isEmpty ? '未能生成经期记录，请重试' : '已记录经期'),
          duration: const Duration(seconds: 2),
        ),
      );
      await _loadCycleStatus();
    } catch (e) {
      _logger.warning('Failed to record menstrual period: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记录失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _recordingPeriod = false);
    }
  }

  Widget _buildConnectPrompt() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _healthSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xA8FFFFFF), width: .8),
      ),
      child: Column(
        children: [
          const Icon(Icons.watch_outlined, size: 48, color: _healthAccent),
          const SizedBox(height: 12),
          const Text(
            '连接 COROS 获取手表数据',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _healthInk,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '在设置中连接 COROS 后，这里将展示步数、睡眠、心率、压力、HRV、体能等数据。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _healthMuted),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _openCorosConnectPage,
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCorosConnectPage() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CorosConnectPage(
          initiallyConnected: _corosConnected,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
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
        foregroundColor: _healthAccent,
        backgroundColor: _healthSurface,
        disabledForegroundColor: _healthMuted,
        disabledBackgroundColor: _healthSurface.withValues(alpha: 0.72),
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
          color: _healthOnRain,
          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
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
          color: _healthOnRain,
          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
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

  /// Parse integer after a prefix followed by a word to skip.
  /// E.g. "Stress: Avg 45" → parseIntAfterWord(text, 'Stress:', 'Avg') → 45.
  int? _parseIntAfterWord(String text, String prefix, String word) {
    final match = RegExp('$prefix\\s*$word\\s*([0-9,]+)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  /// Parse a float from text after a prefix, e.g. "VO2max: 48.5" → 48.5.
  double? _parseFloat(String text, String prefix) {
    final match = RegExp('$prefix\\s*([0-9]+(?:\\.[0-9]+)?)').firstMatch(text);
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
