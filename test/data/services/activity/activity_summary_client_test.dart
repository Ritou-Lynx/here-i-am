import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/activity/activity_summary_client.dart';
import 'package:memex/utils/result.dart';

void main() {
  test('uses the exact read-only summary request surface', () async {
    final adapter = _SummaryAdapter([_Response.json(_summary())]);
    final result = await _client(adapter).fetchSummary();

    expect(result, isA<Ok<ActivitySummary>>());
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/v1/core/activity/summary');
    expect(request.uri.hasQuery, isFalse);
    expect(request.data, isNull);
    expect(request.headers['Authorization'],
        'Bearer reader-secret-should-not-leak');
    expect(request.headers['X-Core-Protocol'], '0.1');
    expect(request.headers['Accept'], 'application/json');
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(
      request.headers.keys.map((key) => key.toLowerCase()),
      unorderedEquals(['authorization', 'x-core-protocol', 'accept']),
    );
  });

  test('parses multiple devices and sources, including empty devices',
      () async {
    final body = _summary();
    body['devices'] = [
      body['devices'][0],
      {
        'device_id': 'device-b',
        'state': 'locked',
        'sources': [
          _source(deviceId: 'device-b', probeId: 'probe-b', state: 'locked')
        ],
      },
    ];
    final result =
        await _client(_SummaryAdapter([_Response.json(body)])).fetchSummary();
    final summary = (result as Ok<ActivitySummary>).value;
    expect(summary.devices, hasLength(2));
    expect(summary.devices[0].sources, hasLength(2));
    expect(summary.devices[1].state, ActivitySummaryState.locked);

    final empty = _summary()..['devices'] = [];
    final emptyResult =
        await _client(_SummaryAdapter([_Response.json(empty)])).fetchSummary();
    expect((emptyResult as Ok<ActivitySummary>).value.devices, isEmpty);
  });

  test('maps unknown state-like values conservatively to unknown', () async {
    final body = _summary();
    final source =
        (body['devices'] as List).first['sources'][0] as Map<String, dynamic>;
    body['devices'][0]['state'] = 'future_active';
    source['state'] = 'future_active';
    source['credential_state'] = 'future_active';
    source['status_reason'] = 'future_active';
    source['coverage_status'] = 'future_active';
    source['clock_health'] = 'future_active';
    source['coverage']['mode'] = 'future_active';
    source['registered_coverage']['mode'] = 'future_active';
    final summary = ((await _client(_SummaryAdapter([_Response.json(body)]))
            .fetchSummary()) as Ok<ActivitySummary>)
        .value;
    final parsed = summary.devices.single.sources.first;
    expect(summary.devices.single.state, ActivitySummaryState.unknown);
    expect(parsed.state, ActivitySummaryState.unknown);
    expect(parsed.credentialState, ActivityCredentialState.unknown);
    expect(parsed.statusReason, ActivityStatusReason.unknown);
    expect(parsed.coverageStatus, ActivityCoverageStatus.unknown);
    expect(parsed.clockHealth, ActivityClockHealth.unknown);
    expect(parsed.coverage!.mode, ActivityCoverageMode.unknown);
    expect(parsed.registeredCoverage.mode, ActivityCoverageMode.unknown);
  });

  test('accepts the Core just-paired empty coverage encoding as unknown',
      () async {
    final body = _singleSourceSummary();
    final source =
        (body['devices'] as List).first['sources'][0] as Map<String, dynamic>;
    body['devices'][0]['state'] = 'unknown';
    source
      ..['state'] = 'unknown'
      ..['credential_state'] = 'active'
      ..['status_reason'] = 'ttl_expired'
      ..['occurred_at_ms'] = null
      ..['received_at_ms'] = null
      ..['ttl_ms'] = null
      ..['freshness'] = <String, dynamic>{
        'fresh': false,
        'expires_at_ms': null,
        'server_time_ms': 1000000,
      }
      ..['coverage'] = {}
      ..['coverage_status'] = 'missing'
      ..['clock_health'] = 'unknown';
    final result =
        await _client(_SummaryAdapter([_Response.json(body)])).fetchSummary();
    final parsed =
        (result as Ok<ActivitySummary>).value.devices.single.sources.first;
    expect(parsed.coverage, isNull);
    expect(parsed.state, ActivitySummaryState.unknown);
  });

  test('never exposes concrete state without complete matching evidence',
      () async {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (source) => source['credential_state'] = 'revoked',
      (source) => source['freshness']['fresh'] = false,
      (source) => source['coverage_status'] = 'gap',
      (source) => source['clock_health'] = 'future_skew',
      (source) => source['state'] = 'unrecognized_future_state',
      (source) => source['status_reason'] = 'reachability_only',
      (source) => source['coverage']['mode'] = 'future_mode',
      (source) => source['registered_coverage']['mode'] = 'future_mode',
      (source) {
        source['coverage']['mode'] = 'future_mode';
        source['registered_coverage']['mode'] = 'future_mode';
      },
      (source) => source['coverage']['mode'] = 'none',
      (source) => source['registered_coverage']['mode'] = 'none',
      (source) {
        source['coverage']['mode'] = 'none';
        source['registered_coverage']['mode'] = 'none';
      },
      (source) => source['received_at_ms'] = 1000001,
      (source) => source['ttl_ms'] = 1,
    ]) {
      final body = _singleSourceSummary();
      final source = (body['devices'] as List).single['sources'].single
          as Map<String, dynamic>;
      mutation(source);
      final summary = ((await _client(_SummaryAdapter([_Response.json(body)]))
              .fetchSummary()) as Ok<ActivitySummary>)
          .value;
      expect(summary.devices.single.sources.single.state,
          ActivitySummaryState.unknown);
      expect(summary.devices.single.state, ActivitySummaryState.unknown);
    }
    final emptySources = _singleSourceSummary();
    emptySources['devices'][0]['sources'] = [];
    expect(
        await _client(_SummaryAdapter([_Response.json(emptySources)]))
            .fetchSummary(),
        isA<Error<ActivitySummary>>());
    final mismatchedDevice = _singleSourceSummary();
    mismatchedDevice['devices'][0]['state'] = 'locked';
    final mismatch =
        ((await _client(_SummaryAdapter([_Response.json(mismatchedDevice)]))
                .fetchSummary()) as Ok<ActivitySummary>)
            .value;
    expect(mismatch.devices.single.state, ActivitySummaryState.unknown);
  });

  test('rejects contradictory coverage, registration and summary clocks',
      () async {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (source) => source['coverage']['window_start_ms'] = 1000001,
      (source) => source['coverage']['expected_report_interval_ms'] = 0,
      (source) =>
          source['registered_coverage']['expected_report_interval_ms'] = null,
      (source) => source['registered_coverage']['expiry_slo_ms'] = 0,
      (source) => source['freshness']['server_time_ms'] = 999999,
    ]) {
      final body = _singleSourceSummary();
      mutation((body['devices'] as List).single['sources'].single
          as Map<String, dynamic>);
      expect(
          await _client(_SummaryAdapter([_Response.json(body)])).fetchSummary(),
          isA<Error<ActivitySummary>>());
    }
  });

  test('uses only an unambiguous observable device winner', () async {
    final newerLock = _singleSourceSummary();
    final oldActive = _source(probeId: 'probe-old');
    oldActive['occurred_at_ms'] = 999999;
    oldActive['received_at_ms'] = 999999;
    oldActive['ttl_ms'] = 300000;
    oldActive['freshness'] = <String, dynamic>{
      'fresh': true,
      'expires_at_ms': 1299999,
      'server_time_ms': 1000000,
    };
    oldActive['coverage'] = <String, dynamic>{
      'mode': 'continuous',
      'window_start_ms': 970000,
      'window_end_ms': 999999,
      'expected_report_interval_ms': 30000,
    };
    newerLock['devices'][0]['sources'] = [
      oldActive,
      _source(probeId: 'probe-new', state: 'locked'),
    ];
    newerLock['devices'][0]['state'] = 'active';
    expect(
        ((await _client(_SummaryAdapter([_Response.json(newerLock)]))
                .fetchSummary()) as Ok<ActivitySummary>)
            .value
            .devices
            .single
            .state,
        ActivitySummaryState.unknown);

    final rankFirst = _singleSourceSummary();
    final network = _source(probeId: 'probe-network', state: 'network_only')
      ..['status_reason'] = 'reachability_only';
    rankFirst['devices'][0]['sources'] = [oldActive, network];
    rankFirst['devices'][0]['state'] = 'active';
    expect(
        ((await _client(_SummaryAdapter([_Response.json(rankFirst)]))
                .fetchSummary()) as Ok<ActivitySummary>)
            .value
            .devices
            .single
            .state,
        ActivitySummaryState.active);

    final tied = _singleSourceSummary();
    tied['devices'][0]['sources'] = [
      _source(probeId: 'probe-active'),
      _source(probeId: 'probe-locked', state: 'locked'),
    ];
    expect(
        ((await _client(_SummaryAdapter([_Response.json(tied)])).fetchSummary())
                as Ok<ActivitySummary>)
            .value
            .devices
            .single
            .state,
        ActivitySummaryState.unknown);

    final humanBlocksNetwork = _singleSourceSummary();
    final humanEvidence = _source(probeId: 'probe-human', state: 'unknown')
      ..['status_reason'] = 'insufficient_human_evidence';
    humanBlocksNetwork['devices'][0]['sources'] = [humanEvidence, network];
    humanBlocksNetwork['devices'][0]['state'] = 'network_only';
    expect(
        ((await _client(_SummaryAdapter([_Response.json(humanBlocksNetwork)]))
                .fetchSummary()) as Ok<ActivitySummary>)
            .value
            .devices
            .single
            .state,
        ActivitySummaryState.unknown);
  });

  test('enforces the current 24-hour limits and concrete ttl SLO', () async {
    final overTtl = _singleSourceSummary();
    overTtl['devices'][0]['sources'][0]['ttl_ms'] = 86400001;
    expect(
        await _client(_SummaryAdapter([_Response.json(overTtl)]))
            .fetchSummary(),
        isA<Error<ActivitySummary>>());
    final overRegistration = _singleSourceSummary();
    overRegistration['devices'][0]['sources'][0]['registered_coverage']
        ['expiry_slo_ms'] = 86400001;
    expect(
        await _client(_SummaryAdapter([_Response.json(overRegistration)]))
            .fetchSummary(),
        isA<Error<ActivitySummary>>());
    final overRegisteredInterval = _singleSourceSummary();
    overRegisteredInterval['devices'][0]['sources'][0]['registered_coverage']
        ['expected_report_interval_ms'] = 86400001;
    expect(
        await _client(_SummaryAdapter([_Response.json(overRegisteredInterval)]))
            .fetchSummary(),
        isA<Error<ActivitySummary>>());
    final overCoverageInterval = _singleSourceSummary();
    overCoverageInterval['devices'][0]['sources'][0]['coverage']
        ['expected_report_interval_ms'] = 86400001;
    expect(
        await _client(_SummaryAdapter([_Response.json(overCoverageInterval)]))
            .fetchSummary(),
        isA<Error<ActivitySummary>>());
    final exceedsSlo = _singleSourceSummary();
    exceedsSlo['devices'][0]['sources'][0]['registered_coverage']
        ['expiry_slo_ms'] = 299999;
    final parsed =
        ((await _client(_SummaryAdapter([_Response.json(exceedsSlo)]))
                .fetchSummary()) as Ok<ActivitySummary>)
            .value;
    expect(parsed.devices.single.sources.single.state,
        ActivitySummaryState.unknown);
    expect(parsed.devices.single.state, ActivitySummaryState.unknown);
  });

  test('returns Error for every HTTP failure, timeout and non-JSON response',
      () async {
    for (final code in [401, 403, 426, 500, 502, 503]) {
      final result = await _client(_SummaryAdapter([
        _Response.json({'error': 'nope'}, status: code)
      ])).fetchSummary();
      expect(result, isA<Error<ActivitySummary>>(), reason: 'HTTP $code');
    }
    final timeout =
        await _client(_SummaryAdapter(const [], throwsTimeout: true))
            .fetchSummary();
    expect(timeout, isA<Error<ActivitySummary>>());
    final nonJson = await _client(
            _SummaryAdapter([const _Response('not json', 200, 'text/plain')]))
        .fetchSummary();
    expect(nonJson, isA<Error<ActivitySummary>>());
    final redirectAdapter = _SummaryAdapter([
      _Response.json({'location': 'https://other.example'}, status: 302)
    ]);
    final redirect = await _client(redirectAdapter).fetchSummary();
    expect(redirect, isA<Error<ActivitySummary>>());
    expect(redirectAdapter.requests, hasLength(1));
  });

  test('returns Error for missing fields, wrong types and malformed shape',
      () async {
    final missing = _summary()..remove('authority');
    final wrongType = _summary()..['generated_at_ms'] = '1000000';
    final malformed = _summary()..['devices'] = {'not': 'an array'};
    final extra = _summary()..['unexpected'] = true;
    final unsafeInteger = _summary()..['generated_at_ms'] = 9007199254740992;
    final partialCoverage = _singleSourceSummary();
    partialCoverage['devices'][0]['sources'][0]
        ['coverage'] = {'mode': 'continuous'};
    final nullCoverage = _singleSourceSummary();
    nullCoverage['devices'][0]['sources'][0]['coverage'] = null;
    final impossibleEmptyCoverage = _singleSourceSummary();
    impossibleEmptyCoverage['devices'][0]['sources'][0]['coverage'] = {};
    for (final body in [
      missing,
      wrongType,
      malformed,
      extra,
      unsafeInteger,
      partialCoverage,
      nullCoverage,
      impossibleEmptyCoverage,
    ]) {
      final result =
          await _client(_SummaryAdapter([_Response.json(body)])).fetchSummary();
      expect(result, isA<Error<ActivitySummary>>());
    }
  });

  test('does not expose the reader token through errors, models, or strings',
      () async {
    const token = 'reader-secret-should-not-leak';
    const credentials = ActivitySummaryCredentials(
        baseUrl: 'https://core.example', readerToken: token);
    final client = ActivitySummaryClient(
      credentials: credentials,
      dio: Dio()
        ..httpClientAdapter = _SummaryAdapter([
          _Response.json({'bad': true}, status: 500)
        ]),
    );
    final result = await client.fetchSummary();
    final failure = result as Error<ActivitySummary>;
    final material =
        '$credentials|$client|${failure.error}|${failure.stackTrace}';
    expect(material, isNot(contains(token)));
  });

  test('allows a trailing slash and rejects ambiguous credentials before I/O',
      () async {
    final validAdapter = _SummaryAdapter([_Response.json(_summary())]);
    expect(
        await _client(validAdapter).fetchSummary(), isA<Ok<ActivitySummary>>());
    for (final entry in <({String baseUrl, String token})>[
      (baseUrl: 'ftp://core.example', token: 'reader'),
      (baseUrl: 'https:///no-host', token: 'reader'),
      (baseUrl: 'https://reader@core.example', token: 'reader'),
      (baseUrl: 'https://core.example?cursor=1', token: 'reader'),
      (baseUrl: 'https://core.example#fragment', token: 'reader'),
      (baseUrl: 'https://core.example', token: ''),
      (baseUrl: 'https://core.example', token: 'has space'),
      (baseUrl: 'https://core.example', token: 'has\r\nnewline'),
      (baseUrl: 'https://core.example', token: List.filled(513, 'a').join()),
      (baseUrl: 'https://core.example/a-prefix', token: 'reader'),
      (baseUrl: 'https://core.example/.', token: 'reader'),
      (baseUrl: 'https://core.example/%2e', token: 'reader'),
    ]) {
      final adapter = _SummaryAdapter([_Response.json(_summary())]);
      final result = await ActivitySummaryClient(
        credentials: ActivitySummaryCredentials(
          baseUrl: entry.baseUrl,
          readerToken: entry.token,
        ),
        dio: Dio()..httpClientAdapter = adapter,
      ).fetchSummary();
      expect(result, isA<Error<ActivitySummary>>(), reason: entry.baseUrl);
      expect(adapter.requests, isEmpty);
    }
  });

  test('does not cache a success after a later failed fetch', () async {
    final adapter = _SummaryAdapter([
      _Response.json(_summary()),
      _Response.json({'error': 'unavailable'}, status: 503),
    ]);
    final client = _client(adapter);
    expect(await client.fetchSummary(), isA<Ok<ActivitySummary>>());
    expect(await client.fetchSummary(), isA<Error<ActivitySummary>>());
    expect(adapter.requests, hasLength(2));
  });

  test('rejects duplicate identities and keeps unknown sources inert',
      () async {
    final duplicateDevice = _singleSourceSummary();
    duplicateDevice['devices'] = [
      duplicateDevice['devices'][0],
      {
        'device_id': 'device-a',
        'state': 'active',
        'sources': [_source(deviceId: 'device-a', probeId: 'probe-b')],
      },
    ];
    expect(
        await _client(_SummaryAdapter([_Response.json(duplicateDevice)]))
            .fetchSummary(),
        isA<Error<ActivitySummary>>());
    final duplicateProbe = _singleSourceSummary();
    duplicateProbe['devices'] = [
      duplicateProbe['devices'][0],
      {
        'device_id': 'device-b',
        'state': 'active',
        'sources': [_source(deviceId: 'device-b', probeId: 'probe-a')],
      },
    ];
    expect(
        await _client(_SummaryAdapter([_Response.json(duplicateProbe)]))
            .fetchSummary(),
        isA<Error<ActivitySummary>>());
    final duplicateProbeSameDevice = _singleSourceSummary();
    duplicateProbeSameDevice['devices'][0]['sources'] = [
      _source(probeId: 'probe-a'),
      _source(probeId: 'probe-a'),
    ];
    expect(
        await _client(
                _SummaryAdapter([_Response.json(duplicateProbeSameDevice)]))
            .fetchSummary(),
        isA<Error<ActivitySummary>>());
    final unknown = _singleSourceSummary();
    unknown['devices'][0]['sources'][0]['source'] = 'future_private_probe';
    final parsed = ((await _client(_SummaryAdapter([_Response.json(unknown)]))
            .fetchSummary()) as Ok<ActivitySummary>)
        .value;
    expect(parsed.devices.single.sources.single.source, 'unknown');
    expect(parsed.devices.single.sources.single.state,
        ActivitySummaryState.unknown);
    expect(parsed.devices.single.state, ActivitySummaryState.unknown);
  });

  test('rejects unsafe opaque identifiers', () async {
    for (final field in ['node_id', 'device_id', 'probe_id']) {
      final body = _singleSourceSummary();
      if (field == 'node_id') {
        body['authority']['node_id'] = 'Bearer_secret';
      } else if (field == 'device_id') {
        body['devices'][0]['device_id'] = 'token-value';
        body['devices'][0]['sources'][0]['device_id'] = 'token-value';
      } else {
        body['devices'][0]['sources'][0]['probe_id'] = 'token-value';
      }
      expect(
          await _client(_SummaryAdapter([_Response.json(body)])).fetchSummary(),
          isA<Error<ActivitySummary>>());
    }
  });
}

ActivitySummaryClient _client(_SummaryAdapter adapter) => ActivitySummaryClient(
      credentials: const ActivitySummaryCredentials(
        baseUrl: 'https://core.example/',
        readerToken: 'reader-secret-should-not-leak',
      ),
      dio: Dio()..httpClientAdapter = adapter,
    );

Map<String, dynamic> _summary() => {
      'contract': 'device.activity.v1',
      'schema_version': 1,
      'generated_at_ms': 1000000,
      'authority': {'node_id': 'node-a', 'epoch': 1},
      'devices': [
        {
          'device_id': 'device-a',
          'state': 'active',
          'sources': [
            _source(probeId: 'probe-a'),
            _source(probeId: 'probe-a2', state: 'network_only')
          ],
        },
      ],
      'semantics': {
        'silence_is_unknown': true,
        'sleep_inference': 'not_supported'
      },
    };

Map<String, dynamic> _singleSourceSummary() {
  final body = _summary();
  body['devices'][0]['sources'] = [_source(probeId: 'probe-a')];
  return body;
}

Map<String, dynamic> _source(
        {String deviceId = 'device-a',
        required String probeId,
        String state = 'active'}) =>
    {
      'device_id': deviceId,
      'probe_id': probeId,
      'source': 'windows_wts',
      'state': state,
      'credential_state': 'active',
      'status_reason': 'fresh_signal',
      'occurred_at_ms': 1000000,
      'received_at_ms': 1000000,
      'ttl_ms': 300000,
      'freshness': <String, dynamic>{
        'fresh': true,
        'expires_at_ms': 1300000,
        'server_time_ms': 1000000
      },
      'coverage': <String, dynamic>{
        'mode': 'continuous',
        'window_start_ms': 970000,
        'window_end_ms': 1000000,
        'expected_report_interval_ms': 30000
      },
      'registered_coverage': <String, dynamic>{
        'mode': 'continuous',
        'expected_report_interval_ms': 30000,
        'expiry_slo_ms': 300000
      },
      'coverage_status': 'covered',
      'clock_health': 'healthy',
    };

class _SummaryAdapter implements HttpClientAdapter {
  _SummaryAdapter(this.responses, {this.throwsTimeout = false});
  final List<_Response> responses;
  final bool throwsTimeout;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<dynamic>? cancelFuture) async {
    requests.add(options);
    if (throwsTimeout) {
      throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1), requestOptions: options);
    }
    final response = responses.removeAt(0);
    return ResponseBody.fromString(response.body, response.status, headers: {
      'content-type': [response.contentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Response {
  const _Response(this.body, this.status, this.contentType);
  factory _Response.json(Object body, {int status = 200}) =>
      _Response(jsonEncode(body), status, 'application/json');
  final String body;
  final int status;
  final String contentType;
}
