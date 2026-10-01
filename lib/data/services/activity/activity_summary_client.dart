import 'package:dio/dio.dart';
import 'package:memex/utils/result.dart';

const _maxSafeInteger = 9007199254740991;
const _maxActivityDurationMs = 86400000;

/// Ephemeral connection details for the activity summary reader.
///
/// This object is intentionally not serializable and redacts itself when
/// rendered. Callers must obtain and retain it only in memory.
final class ActivitySummaryCredentials {
  const ActivitySummaryCredentials({
    required this.baseUrl,
    required this.readerToken,
  });

  final String baseUrl;
  final String readerToken;

  @override
  String toString() => 'ActivitySummaryCredentials(<redacted>)';
}

/// Read-only client for the MDA-1 minimal per-device activity summary.
final class ActivitySummaryClient {
  ActivitySummaryClient({
    required ActivitySummaryCredentials credentials,
    Dio? dio,
  })  : _credentials = credentials,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
            ));

  final ActivitySummaryCredentials _credentials;
  final Dio _dio;

  Future<Result<ActivitySummary>> fetchSummary() => runResult(() async {
        try {
          if (!_readerToken.hasMatch(_credentials.readerToken)) {
            throw const ActivitySummaryClientException(
                'invalid_summary_credentials');
          }
          final response = await _dio.getUri<dynamic>(
            _summaryUri(_credentials.baseUrl),
            options: Options(
              responseType: ResponseType.json,
              followRedirects: false,
              maxRedirects: 0,
              headers: <String, String>{
                'Authorization': 'Bearer ${_credentials.readerToken}',
                'X-Core-Protocol': '0.1',
                'Accept': 'application/json',
              },
            ),
          );
          if (response.statusCode != 200 || response.data is! Map) {
            throw const ActivitySummaryClientException(
                'invalid_summary_response');
          }
          return ActivitySummary.fromJson(
            Map<String, dynamic>.from(response.data as Map),
          );
        } on ActivitySummaryClientException {
          rethrow;
        } on DioException {
          // Do not retain Dio's request details: they include the Bearer token.
          throw const ActivitySummaryClientException('summary_request_failed');
        } catch (_) {
          throw const ActivitySummaryClientException(
              'invalid_summary_response');
        }
      });

  static Uri _summaryUri(String baseUrl) {
    if (!_baseUrlForm.hasMatch(baseUrl)) {
      throw const ActivitySummaryClientException('invalid_summary_base_url');
    }
    final base = Uri.parse(baseUrl);
    if (!base.isAbsolute ||
        (base.scheme != 'http' && base.scheme != 'https') ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/')) {
      throw const ActivitySummaryClientException('invalid_summary_base_url');
    }
    return base.replace(path: '/v1/core/activity/summary');
  }
}

final RegExp _readerToken = RegExp(r'^[A-Za-z0-9_-]{1,512}$');
final RegExp _baseUrlForm =
    RegExp(r'^https?://[^/?#]+/?$', caseSensitive: false);
final RegExp _opaqueIdForm = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');

const _knownSources = <String>{
  'windows_wts',
  'windows_last_input',
  'windows_probe',
  'android_usage_events',
  'android_screen_state',
  'android_tasker',
  'iphone_shortcuts',
  'android_ble_hrs_quality',
};

final class ActivitySummaryClientException implements Exception {
  const ActivitySummaryClientException(this.code);
  final String code;
  @override
  String toString() => 'ActivitySummaryClientException($code)';
}

enum ActivitySummaryState { active, locked, networkOnly, unknown }

enum ActivityCredentialState { active, revoked, unknown }

enum ActivityStatusReason {
  unobserved,
  coreRestartGap,
  futureSkew,
  clockRegression,
  coverageGap,
  coverageStale,
  coverageMissing,
  coverageInvalid,
  probeError,
  permissionUnavailable,
  reachabilityOnly,
  insufficientHumanEvidence,
  freshSignal,
  credentialRevoked,
  ttlExpired,
  retentionExpired,
  unknown,
}

enum ActivityCoverageMode {
  continuous,
  discreteBestEffort,
  heartbeatOnly,
  none,
  unknown
}

enum ActivityCoverageStatus { covered, gap, missing, invalid, unknown }

enum ActivityClockHealth { healthy, futureSkew, clockRegression, unknown }

final class ActivitySummary {
  const ActivitySummary({
    required this.generatedAtMs,
    required this.authority,
    required this.devices,
  });

  final int generatedAtMs;
  final ActivitySummaryAuthority authority;
  final List<ActivitySummaryDevice> devices;

  factory ActivitySummary.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const [
      'contract',
      'schema_version',
      'generated_at_ms',
      'authority',
      'devices',
      'semantics',
    ]);
    if (_string(json, 'contract') != 'device.activity.v1' ||
        _integer(json, 'schema_version') != 1) {
      throw const ActivitySummaryClientException(
          'unsupported_summary_contract');
    }
    final semantics = _object(json, 'semantics');
    _exactKeys(semantics, const ['silence_is_unknown', 'sleep_inference']);
    if (_bool(semantics, 'silence_is_unknown') != true ||
        _string(semantics, 'sleep_inference') != 'not_supported') {
      throw const ActivitySummaryClientException(
          'unsupported_summary_semantics');
    }
    final generatedAtMs = _nonNegative(json, 'generated_at_ms');
    final devices = _array(json, 'devices')
        .map((value) => ActivitySummaryDevice.fromJson(_map(value)))
        .toList(growable: false);
    final deviceIds = devices.map((device) => device.deviceId).toSet();
    final allSources = devices.expand((device) => device.sources).toList();
    final probeIds = allSources.map((source) => source.probeId).toSet();
    if (deviceIds.length != devices.length ||
        probeIds.length != allSources.length) {
      _bad();
    }
    if (devices.any((device) => device.sources
        .any((source) => source.freshness.serverTimeMs != generatedAtMs))) {
      _bad();
    }
    return ActivitySummary(
      generatedAtMs: generatedAtMs,
      authority: ActivitySummaryAuthority.fromJson(_object(json, 'authority')),
      devices: devices,
    );
  }
}

final class ActivitySummaryAuthority {
  const ActivitySummaryAuthority({required this.nodeId, required this.epoch});
  final String nodeId;
  final int epoch;
  factory ActivitySummaryAuthority.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const ['node_id', 'epoch']);
    return ActivitySummaryAuthority(
        nodeId: _opaqueId(json, 'node_id'), epoch: _positive(json, 'epoch'));
  }
}

final class ActivitySummaryDevice {
  const ActivitySummaryDevice(
      {required this.deviceId, required this.state, required this.sources});
  final String deviceId;
  final ActivitySummaryState state;
  final List<ActivitySummarySource> sources;
  factory ActivitySummaryDevice.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const ['device_id', 'state', 'sources']);
    final deviceId = _opaqueId(json, 'device_id');
    final sources = _array(json, 'sources')
        .map((value) => ActivitySummarySource.fromJson(_map(value)))
        .toList(growable: false);
    if (sources.isEmpty ||
        sources.any((source) => source.deviceId != deviceId)) {
      _bad();
    }
    final reportedState = _state(_string(json, 'state'));
    return ActivitySummaryDevice(
      deviceId: deviceId,
      state: _deviceState(reportedState, sources),
      sources: sources,
    );
  }
}

final class ActivitySummarySource {
  const ActivitySummarySource({
    required this.deviceId,
    required this.probeId,
    required this.source,
    required this.state,
    required this.credentialState,
    required this.statusReason,
    required this.occurredAtMs,
    required this.receivedAtMs,
    required this.ttlMs,
    required this.freshness,
    required this.coverage,
    required this.registeredCoverage,
    required this.coverageStatus,
    required this.clockHealth,
  });
  final String deviceId;
  final String probeId;
  final String source;
  final ActivitySummaryState state;
  final ActivityCredentialState credentialState;
  final ActivityStatusReason statusReason;
  final int? occurredAtMs;
  final int? receivedAtMs;
  final int? ttlMs;
  final ActivityFreshness freshness;
  final ActivityCoverage? coverage;
  final ActivityRegisteredCoverage registeredCoverage;
  final ActivityCoverageStatus coverageStatus;
  final ActivityClockHealth clockHealth;
  factory ActivitySummarySource.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const [
      'device_id',
      'probe_id',
      'source',
      'state',
      'credential_state',
      'status_reason',
      'occurred_at_ms',
      'received_at_ms',
      'ttl_ms',
      'freshness',
      'coverage',
      'registered_coverage',
      'coverage_status',
      'clock_health',
    ]);
    final credentialState = _credential(_string(json, 'credential_state'));
    final statusReason = _reason(_string(json, 'status_reason'));
    final occurredAtMs = _nullableNonNegative(json, 'occurred_at_ms');
    final receivedAtMs = _nullableNonNegative(json, 'received_at_ms');
    final ttlMs = _nullableNonNegative(json, 'ttl_ms');
    final freshness = ActivityFreshness.fromJson(_object(json, 'freshness'));
    final coverage = _coverageOrNull(json);
    final coverageStatus = _coverageStatus(_string(json, 'coverage_status'));
    final clockHealth = _clock(_string(json, 'clock_health'));
    final reportedState = _state(_string(json, 'state'));
    final source = _summarySource(_string(json, 'source'));
    final registeredCoverage = ActivityRegisteredCoverage.fromJson(
        _object(json, 'registered_coverage'));
    if (ttlMs != null && ttlMs > _maxActivityDurationMs) _bad();
    if (coverage == null &&
        (reportedState != ActivitySummaryState.unknown ||
            occurredAtMs != null ||
            receivedAtMs != null ||
            ttlMs != null ||
            freshness.fresh ||
            freshness.expiresAtMs != null ||
            coverageStatus == ActivityCoverageStatus.covered ||
            clockHealth == ActivityClockHealth.healthy)) {
      _bad();
    }
    return ActivitySummarySource(
      deviceId: _opaqueId(json, 'device_id'),
      probeId: _opaqueId(json, 'probe_id'),
      source: source,
      state: source == 'unknown'
          ? ActivitySummaryState.unknown
          : _safeSourceState(
              reportedState: reportedState,
              credentialState: credentialState,
              statusReason: statusReason,
              freshness: freshness,
              coverage: coverage,
              registeredCoverage: registeredCoverage,
              coverageStatus: coverageStatus,
              clockHealth: clockHealth,
              occurredAtMs: occurredAtMs,
              receivedAtMs: receivedAtMs,
              ttlMs: ttlMs,
            ),
      credentialState: credentialState,
      statusReason: statusReason,
      occurredAtMs: occurredAtMs,
      receivedAtMs: receivedAtMs,
      ttlMs: ttlMs,
      freshness: freshness,
      coverage: coverage,
      registeredCoverage: registeredCoverage,
      coverageStatus: coverageStatus,
      clockHealth: clockHealth,
    );
  }
}

final class ActivityFreshness {
  const ActivityFreshness(
      {required this.fresh,
      required this.expiresAtMs,
      required this.serverTimeMs});
  final bool fresh;
  final int? expiresAtMs;
  final int serverTimeMs;
  factory ActivityFreshness.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const ['fresh', 'expires_at_ms', 'server_time_ms']);
    return ActivityFreshness(
        fresh: _bool(json, 'fresh'),
        expiresAtMs: _nullableNonNegative(json, 'expires_at_ms'),
        serverTimeMs: _nonNegative(json, 'server_time_ms'));
  }
}

final class ActivityCoverage {
  const ActivityCoverage(
      {required this.mode,
      required this.windowStartMs,
      required this.windowEndMs,
      required this.expectedReportIntervalMs});
  final ActivityCoverageMode mode;
  final int? windowStartMs;
  final int? windowEndMs;
  final int? expectedReportIntervalMs;
  factory ActivityCoverage.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const [
      'mode',
      'window_start_ms',
      'window_end_ms',
      'expected_report_interval_ms'
    ]);
    final windowStartMs = _nullableNonNegative(json, 'window_start_ms');
    final windowEndMs = _nullableNonNegative(json, 'window_end_ms');
    final expectedReportIntervalMs =
        _nullableNonNegative(json, 'expected_report_interval_ms');
    final mode = _coverageMode(_string(json, 'mode'));
    if (windowStartMs == null ||
        windowEndMs == null ||
        windowStartMs > windowEndMs ||
        (expectedReportIntervalMs != null && expectedReportIntervalMs <= 0) ||
        (expectedReportIntervalMs != null &&
            expectedReportIntervalMs > _maxActivityDurationMs) ||
        (mode == ActivityCoverageMode.continuous &&
            expectedReportIntervalMs == null)) {
      _bad();
    }
    return ActivityCoverage(
        mode: mode,
        windowStartMs: windowStartMs,
        windowEndMs: windowEndMs,
        expectedReportIntervalMs: expectedReportIntervalMs);
  }
}

final class ActivityRegisteredCoverage {
  const ActivityRegisteredCoverage(
      {required this.mode,
      required this.expectedReportIntervalMs,
      required this.expirySloMs});
  final ActivityCoverageMode mode;
  final int? expectedReportIntervalMs;
  final int? expirySloMs;
  factory ActivityRegisteredCoverage.fromJson(Map<String, dynamic> json) {
    _exactKeys(
        json, const ['mode', 'expected_report_interval_ms', 'expiry_slo_ms']);
    final expectedReportIntervalMs =
        _nullableNonNegative(json, 'expected_report_interval_ms');
    final expirySloMs = _nullableNonNegative(json, 'expiry_slo_ms');
    if (expectedReportIntervalMs == null ||
        expectedReportIntervalMs <= 0 ||
        expectedReportIntervalMs > _maxActivityDurationMs ||
        expirySloMs == null ||
        expirySloMs <= 0 ||
        expirySloMs > _maxActivityDurationMs) {
      _bad();
    }
    return ActivityRegisteredCoverage(
        mode: _coverageMode(_string(json, 'mode')),
        expectedReportIntervalMs: expectedReportIntervalMs,
        expirySloMs: expirySloMs);
  }
}

Never _bad() => throw const ActivitySummaryClientException('malformed_summary');
void _exactKeys(Map<String, dynamic> value, List<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    _bad();
  }
}

Map<String, dynamic> _object(Map<String, dynamic> value, String key) =>
    _map(value[key]);
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : _bad();
List<dynamic> _array(Map<String, dynamic> value, String key) =>
    value[key] is List ? List<dynamic>.from(value[key] as List) : _bad();
String _string(Map<String, dynamic> value, String key) =>
    value[key] is String ? value[key] as String : _bad();
String _opaqueId(Map<String, dynamic> value, String key) {
  final result = _string(value, key);
  final lower = result.toLowerCase();
  if (!_opaqueIdForm.hasMatch(result) ||
      lower.contains('bearer') ||
      lower.contains('token') ||
      lower.contains('secret') ||
      lower.contains('password') ||
      lower.contains('jwt') ||
      lower.contains('http') ||
      lower.contains('url') ||
      lower.contains('stack')) {
    _bad();
  }
  return result;
}

String _summarySource(String value) =>
    _knownSources.contains(value) ? value : 'unknown';

bool _bool(Map<String, dynamic> value, String key) =>
    value[key] is bool ? value[key] as bool : _bad();
int _integer(Map<String, dynamic> value, String key) {
  final number = value[key];
  return number is int && number >= 0 && number <= _maxSafeInteger
      ? number
      : _bad();
}

int _nonNegative(Map<String, dynamic> value, String key) =>
    _integer(value, key);
int _positive(Map<String, dynamic> value, String key) {
  final result = _integer(value, key);
  return result > 0 ? result : _bad();
}

int? _nullableNonNegative(Map<String, dynamic> value, String key) =>
    value[key] == null ? null : _integer(value, key);

ActivityCoverage? _coverageOrNull(Map<String, dynamic> value) {
  final raw = value['coverage'];
  if (raw is! Map) _bad();
  if (raw.isEmpty) return null;
  return ActivityCoverage.fromJson(Map<String, dynamic>.from(raw));
}

ActivitySummaryState _safeSourceState({
  required ActivitySummaryState reportedState,
  required ActivityCredentialState credentialState,
  required ActivityStatusReason statusReason,
  required ActivityFreshness freshness,
  required ActivityCoverage? coverage,
  required ActivityRegisteredCoverage registeredCoverage,
  required ActivityCoverageStatus coverageStatus,
  required ActivityClockHealth clockHealth,
  required int? occurredAtMs,
  required int? receivedAtMs,
  required int? ttlMs,
}) {
  if (reportedState == ActivitySummaryState.unknown ||
      credentialState != ActivityCredentialState.active ||
      !freshness.fresh ||
      coverage == null ||
      coverageStatus != ActivityCoverageStatus.covered ||
      clockHealth != ActivityClockHealth.healthy ||
      occurredAtMs == null ||
      receivedAtMs == null ||
      ttlMs == null ||
      freshness.expiresAtMs == null) {
    return ActivitySummaryState.unknown;
  }
  if (ttlMs <= 0 ||
      ttlMs > registeredCoverage.expirySloMs! ||
      freshness.expiresAtMs! < freshness.serverTimeMs ||
      receivedAtMs > freshness.serverTimeMs ||
      occurredAtMs > _maxSafeInteger - ttlMs ||
      freshness.expiresAtMs != occurredAtMs + ttlMs ||
      coverage.windowStartMs! > occurredAtMs ||
      coverage.windowEndMs! < occurredAtMs ||
      !_isConcreteCoverageMode(coverage.mode) ||
      !_isConcreteCoverageMode(registeredCoverage.mode) ||
      coverage.mode != registeredCoverage.mode ||
      (coverage.expectedReportIntervalMs != null &&
          coverage.expectedReportIntervalMs !=
              registeredCoverage.expectedReportIntervalMs)) {
    return ActivitySummaryState.unknown;
  }
  final reasonIsSafe = switch (reportedState) {
    ActivitySummaryState.active ||
    ActivitySummaryState.locked =>
      statusReason == ActivityStatusReason.freshSignal,
    ActivitySummaryState.networkOnly =>
      statusReason == ActivityStatusReason.reachabilityOnly,
    ActivitySummaryState.unknown => false,
  };
  return reasonIsSafe ? reportedState : ActivitySummaryState.unknown;
}

bool _isConcreteCoverageMode(ActivityCoverageMode mode) =>
    mode == ActivityCoverageMode.continuous ||
    mode == ActivityCoverageMode.discreteBestEffort ||
    mode == ActivityCoverageMode.heartbeatOnly;

ActivitySummaryState _deviceState(
  ActivitySummaryState reportedState,
  List<ActivitySummarySource> sources,
) {
  final ranked =
      sources.map((source) => (source, _deviceRank(source))).toList();
  final highestRank =
      ranked.map((entry) => entry.$2).reduce((a, b) => a > b ? a : b);
  if (highestRank == 0) return ActivitySummaryState.unknown;
  final rankedWinners = ranked.where((entry) => entry.$2 == highestRank);
  final latestOccurredAt = rankedWinners
      .map((entry) => entry.$1.occurredAtMs ?? -1)
      .reduce((a, b) => a > b ? a : b);
  final candidates = rankedWinners
      .where((entry) => (entry.$1.occurredAtMs ?? -1) == latestOccurredAt)
      .map((entry) => entry.$1.state)
      .toSet();
  if (candidates.length != 1) return ActivitySummaryState.unknown;
  final winner = candidates.single;
  return winner == reportedState && winner != ActivitySummaryState.unknown
      ? winner
      : ActivitySummaryState.unknown;
}

int _deviceRank(ActivitySummarySource source) {
  if (source.state == ActivitySummaryState.active ||
      source.state == ActivitySummaryState.locked) {
    return 3;
  }
  final healthyUnknown =
      source.credentialState == ActivityCredentialState.active &&
          source.freshness.fresh &&
          source.coverage != null &&
          source.coverageStatus == ActivityCoverageStatus.covered &&
          source.clockHealth == ActivityClockHealth.healthy &&
          source.statusReason == ActivityStatusReason.insufficientHumanEvidence;
  if (healthyUnknown) return 2;
  return source.state == ActivitySummaryState.networkOnly ? 1 : 0;
}

ActivitySummaryState _state(String value) => switch (value) {
      'active' => ActivitySummaryState.active,
      'locked' => ActivitySummaryState.locked,
      'network_only' => ActivitySummaryState.networkOnly,
      _ => ActivitySummaryState.unknown
    };
ActivityCredentialState _credential(String value) => switch (value) {
      'active' => ActivityCredentialState.active,
      'revoked' => ActivityCredentialState.revoked,
      _ => ActivityCredentialState.unknown
    };
ActivityStatusReason _reason(String value) => switch (value) {
      'unobserved' => ActivityStatusReason.unobserved,
      'core_restart_gap' => ActivityStatusReason.coreRestartGap,
      'future_skew' => ActivityStatusReason.futureSkew,
      'clock_regression' => ActivityStatusReason.clockRegression,
      'coverage_gap' => ActivityStatusReason.coverageGap,
      'coverage_stale' => ActivityStatusReason.coverageStale,
      'coverage_missing' => ActivityStatusReason.coverageMissing,
      'coverage_invalid' => ActivityStatusReason.coverageInvalid,
      'probe_error' => ActivityStatusReason.probeError,
      'permission_unavailable' => ActivityStatusReason.permissionUnavailable,
      'reachability_only' => ActivityStatusReason.reachabilityOnly,
      'insufficient_human_evidence' =>
        ActivityStatusReason.insufficientHumanEvidence,
      'fresh_signal' => ActivityStatusReason.freshSignal,
      'credential_revoked' => ActivityStatusReason.credentialRevoked,
      'ttl_expired' => ActivityStatusReason.ttlExpired,
      'retention_expired' => ActivityStatusReason.retentionExpired,
      _ => ActivityStatusReason.unknown
    };
ActivityCoverageMode _coverageMode(String value) => switch (value) {
      'continuous' => ActivityCoverageMode.continuous,
      'discrete_best_effort' => ActivityCoverageMode.discreteBestEffort,
      'heartbeat_only' => ActivityCoverageMode.heartbeatOnly,
      'none' => ActivityCoverageMode.none,
      _ => ActivityCoverageMode.unknown
    };
ActivityCoverageStatus _coverageStatus(String value) => switch (value) {
      'covered' => ActivityCoverageStatus.covered,
      'gap' => ActivityCoverageStatus.gap,
      'missing' => ActivityCoverageStatus.missing,
      'invalid' => ActivityCoverageStatus.invalid,
      _ => ActivityCoverageStatus.unknown
    };
ActivityClockHealth _clock(String value) => switch (value) {
      'healthy' => ActivityClockHealth.healthy,
      'future_skew' => ActivityClockHealth.futureSkew,
      'clock_regression' => ActivityClockHealth.clockRegression,
      _ => ActivityClockHealth.unknown
    };
