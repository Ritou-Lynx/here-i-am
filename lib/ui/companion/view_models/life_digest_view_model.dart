import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/agent/mcp/mcp_protocol.dart';
import 'package:memex/data/services/i_mcp_service.dart';
import 'package:memex/ui/companion/models/life_digest_models.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';

/// ViewModel for the Life Digest & Long-Term Profile viewer.
///
/// Strictly read-only: only calls the `life_digest` tool via [IMcpQueryService]
/// (the mobile app holds `i.read` scope only).
class LifeDigestViewModel extends ChangeNotifier {
  LifeDigestViewModel({
    IMcpQueryService? service,
    LifeDigestTab initialTab = LifeDigestTab.day,
    DateTime Function()? clock,
  })  : _service = service ?? IMcpService.instance,
        _clock = clock ?? DateTime.now,
        _currentTab = initialTab {
    final now = _today;
    _selectedDate = now;
    _selectedWeek = IsoWeek.fromDate(now);
    _selectedMonth = DateTime(now.year, now.month);
    load = Command0<void>(_loadCurrentTab);
    refresh = Command0<void>(_loadCurrentTab);
  }

  final IMcpQueryService _service;
  final DateTime Function() _clock;

  late final Command0<void> load;
  late final Command0<void> refresh;

  LifeDigestTab _currentTab;
  late DateTime _selectedDate;
  late IsoWeek _selectedWeek;
  late DateTime _selectedMonth;

  DayDigestData? _dayData;
  WeekDigestData? _weekData;
  MonthDigestData? _monthData;
  LifeDigestTodosData? _todosData;
  LongTermProfileData? _profileData;

  final Map<LifeDigestTab, LifeDigestFailure?> _failures = {};
  int _requestEpoch = 0;
  bool _pendingReload = false;
  bool _disposed = false;

  LifeDigestTab get currentTab => _currentTab;
  DateTime get selectedDate => _selectedDate;
  IsoWeek get selectedWeek => _selectedWeek;
  DateTime get selectedMonth => _selectedMonth;

  DayDigestData? get dayData => _dayData;
  WeekDigestData? get weekData => _weekData;
  MonthDigestData? get monthData => _monthData;
  LifeDigestTodosData? get todosData => _todosData;
  LongTermProfileData? get profileData => _profileData;

  LifeDigestFailure? get currentFailure => _failures[_currentTab];
  bool get isLoading => load.running || refresh.running;

  bool get hasCurrentTabData => switch (_currentTab) {
        LifeDigestTab.day => _dayData != null,
        LifeDigestTab.week => _weekData != null,
        LifeDigestTab.month => _monthData != null,
        LifeDigestTab.todos => _todosData != null,
        LifeDigestTab.profile => _profileData != null,
      };

  DateTime get _today {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  bool get canStepDateForward => _selectedDate.isBefore(_today);

  bool get canStepWeekForward =>
      _selectedWeek.compareTo(IsoWeek.fromDate(_today)) < 0;

  bool get canStepMonthForward {
    final today = _today;
    return _selectedMonth.year < today.year ||
        (_selectedMonth.year == today.year &&
            _selectedMonth.month < today.month);
  }

  void selectTab(LifeDigestTab tab) {
    if (_currentTab == tab) return;
    _currentTab = tab;
    _requestEpoch++;
    _safeNotify();
    _triggerLoad();
  }

  void stepDate(int deltaDays) {
    final candidate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day + deltaDays,
    );
    final today = _today;
    if (candidate.isAfter(today)) return;
    _selectedDate = candidate;
    _dayData = null;
    _failures.remove(LifeDigestTab.day);
    _requestEpoch++;
    _safeNotify();
    _triggerLoad();
  }

  void stepWeek(int deltaWeeks) {
    final candidate = _selectedWeek.step(deltaWeeks);
    final currentWeek = IsoWeek.fromDate(_today);
    if (candidate.compareTo(currentWeek) > 0) return;
    _selectedWeek = candidate;
    _weekData = null;
    _failures.remove(LifeDigestTab.week);
    _requestEpoch++;
    _safeNotify();
    _triggerLoad();
  }

  void stepMonth(int deltaMonths) {
    final candidate = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + deltaMonths,
    );
    final today = _today;
    final currentMonth = DateTime(today.year, today.month);
    if (candidate.isAfter(currentMonth)) return;
    _selectedMonth = candidate;
    _monthData = null;
    _failures.remove(LifeDigestTab.month);
    _requestEpoch++;
    _safeNotify();
    _triggerLoad();
  }

  void _triggerLoad() {
    if (load.running) {
      _pendingReload = true;
      return;
    }
    unawaited(load.execute());
  }

  Future<Result<void>> _loadCurrentTab() async {
    final tab = _currentTab;
    final epoch = _requestEpoch;
    final arguments = _argumentsForTab(tab);

    final result = await runResultVoid(() async {
      await _service.ensureConnected();
      if (!_service.isConnected) {
        final failure = _classifyDisconnected(_service.lastError);
        if (epoch == _requestEpoch) {
          _failures[tab] = failure;
          _safeNotify();
        }
        return;
      }

      final toolResult = await _service.callTool(
        'life_digest',
        arguments: arguments,
      );

      if (epoch != _requestEpoch || _disposed) return;

      if (toolResult.isError) {
        _failures[tab] = _classifyErrorMessage(
          toolResult.text,
          tab: tab,
        );
        _safeNotify();
        return;
      }

      final decoded = _decodeJsonMap(toolResult);
      if (decoded == null) {
        _failures[tab] = _classifyErrorMessage(
          toolResult.text,
          tab: tab,
          fallbackMessage: '返回的数据格式暂时无法解析，请稍后重试',
        );
        _safeNotify();
        return;
      }

      final payloadError = decoded['error']?.toString();
      if (payloadError != null && payloadError.isNotEmpty) {
        _failures[tab] = _classifyErrorMessage(
          '$payloadError ${decoded['message'] ?? ''}',
          tab: tab,
        );
        _safeNotify();
        return;
      }

      _failures[tab] = null;
      switch (tab) {
        case LifeDigestTab.day:
          _dayData = DayDigestData.fromJson(
            decoded,
            fallbackDate: formatIsoDate(_selectedDate),
          );
        case LifeDigestTab.week:
          _weekData = WeekDigestData.fromJson(
            decoded,
            fallbackWeek: _selectedWeek.formatted,
          );
        case LifeDigestTab.month:
          _monthData = MonthDigestData.fromJson(
            decoded,
            fallbackMonth: formatIsoMonth(_selectedMonth),
          );
        case LifeDigestTab.todos:
          _todosData = LifeDigestTodosData.fromJson(decoded);
        case LifeDigestTab.profile:
          _profileData = LongTermProfileData.fromJson(decoded);
      }
      _safeNotify();
    });

    if (result case Error(:final error)) {
      if (epoch == _requestEpoch && !_disposed) {
        _failures[tab] = _classifyException(error, tab: tab);
        _safeNotify();
      }
    }

    if (_pendingReload && !_disposed) {
      _pendingReload = false;
      scheduleMicrotask(() {
        if (!_disposed) unawaited(load.execute());
      });
    }

    return result;
  }

  Map<String, dynamic> _argumentsForTab(LifeDigestTab tab) {
    return switch (tab) {
      // Omit `period` for day so older M1 servers stay compatible.
      LifeDigestTab.day => <String, dynamic>{
          'date': formatIsoDate(_selectedDate),
        },
      LifeDigestTab.week => <String, dynamic>{
          'period': 'week',
          'week': _selectedWeek.formatted,
        },
      LifeDigestTab.month => <String, dynamic>{
          'period': 'month',
          'month': formatIsoMonth(_selectedMonth),
        },
      LifeDigestTab.todos => <String, dynamic>{
          'section': 'todos',
        },
      LifeDigestTab.profile => <String, dynamic>{
          'period': 'profile',
        },
    };
  }

  Map<String, dynamic>? _decodeJsonMap(McpToolCallResult result) {
    final text = result.text.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  LifeDigestFailure _classifyDisconnected(String? lastError) {
    final raw = lastError?.trim() ?? '';
    if (raw.isNotEmpty && _looksOffline(raw)) {
      return const LifeDigestFailure(
        kind: LifeDigestFailureKind.offline,
        message: '暂时连不上家里电脑，请确认电脑在线后再试',
      );
    }
    return LifeDigestFailure(
      kind: LifeDigestFailureKind.notConnected,
      message: raw.isNotEmpty ? raw : '还没连接 i MCP，请先完成连接',
    );
  }

  LifeDigestFailure _classifyException(
    Object error, {
    required LifeDigestTab tab,
  }) {
    if (error is IMcpException) {
      final msg = error.message;
      if (_looksNotConnected(msg)) {
        return LifeDigestFailure(
          kind: LifeDigestFailureKind.notConnected,
          message: msg,
        );
      }
      if (_looksOffline(msg)) {
        return const LifeDigestFailure(
          kind: LifeDigestFailureKind.offline,
          message: '暂时连不上家里电脑，请确认电脑在线后再试',
        );
      }
      return _classifyErrorMessage(msg, tab: tab);
    }

    if (error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException ||
        error is DioException) {
      return const LifeDigestFailure(
        kind: LifeDigestFailureKind.offline,
        message: '暂时连不上家里电脑，请确认电脑在线后再试',
      );
    }

    return _classifyErrorMessage(error.toString(), tab: tab);
  }

  LifeDigestFailure _classifyErrorMessage(
    String raw, {
    required LifeDigestTab tab,
    String? fallbackMessage,
  }) {
    if (_looksNotConnected(raw)) {
      return LifeDigestFailure(
        kind: LifeDigestFailureKind.notConnected,
        message: raw.trim().isNotEmpty ? raw.trim() : '还没连接 i MCP，请先完成连接',
      );
    }
    if (_isExtendedPeriodTab(tab) && _looksUnsupportedPeriod(raw)) {
      return const LifeDigestFailure(
        kind: LifeDigestFailureKind.unsupportedPeriod,
        message: '家里电脑尚未更新到此版本，部署后即可查看',
      );
    }
    if (_looksOffline(raw)) {
      return const LifeDigestFailure(
        kind: LifeDigestFailureKind.offline,
        message: '暂时连不上家里电脑，请确认电脑在线后再试',
      );
    }
    return LifeDigestFailure(
      kind: LifeDigestFailureKind.error,
      message: fallbackMessage ??
          (raw.trim().isNotEmpty ? raw.trim() : '加载失败，请稍后重试'),
    );
  }

  bool _isExtendedPeriodTab(LifeDigestTab tab) =>
      tab == LifeDigestTab.week ||
      tab == LifeDigestTab.month ||
      tab == LifeDigestTab.profile;

  bool _looksNotConnected(String text) {
    final lower = text.toLowerCase();
    return text.contains('还没连接') ||
        text.contains('授权已失效') ||
        text.contains('请到设置里') ||
        text.contains('没有可用的用户') ||
        lower.contains('not connected');
  }

  bool _looksUnsupportedPeriod(String text) {
    final lower = text.toLowerCase();
    return lower.contains('invalid_life_digest_period') ||
        lower.contains('invalid_request') ||
        lower.contains('unknown period') ||
        lower.contains('unsupported period') ||
        lower.contains('invalid period') ||
        lower.contains('unexpected keyword argument') ||
        lower.contains('extra inputs are not permitted') ||
        lower.contains('unknown argument');
  }

  bool _looksOffline(String text) {
    final lower = text.toLowerCase();
    return text.contains('离线') ||
        text.contains('连不上') ||
        text.contains('连接失败') ||
        text.contains('超时') ||
        lower.contains('socketexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('timed out') ||
        lower.contains('network is unreachable');
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    load.dispose();
    refresh.dispose();
    super.dispose();
  }
}
