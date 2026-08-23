import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';

void main() {
  test('warm-up discovers capabilities without creating a session or turn',
      () async {
    final adapter = _RuntimeAdapter(provider: 'fake-runtime');
    final dio = Dio()..httpClientAdapter = adapter;
    final client = WorkbenchRuntimeClient(dio: dio);

    final operation = client.warmUp();
    await operation.completed;

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, endsWith('/capabilities'));
    expect(adapter.requests.single.data, isNull);
  });

  test('warm-up is bounded and cancels its local readiness wait', () async {
    final adapter = _RuntimeAdapter(
      provider: 'fake-runtime',
      capabilityDelay: const Duration(milliseconds: 50),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final client = WorkbenchRuntimeClient(
      dio: dio,
      warmUpTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      client.warmUp().completed,
      throwsA(
        isA<WorkbenchRuntimeException>().having(
          (error) => error.code,
          'code',
          'runtime_warmup_timeout',
        ),
      ),
    );
  });

  test('start and resume send the same tools and resume provider guard',
      () async {
    final adapter = _RuntimeAdapter(provider: 'fake-runtime');
    final dio = Dio()..httpClientAdapter = adapter;
    final client = WorkbenchRuntimeClient(dio: dio);
    const tools = [
      {'name': 'search_workbench_content'},
    ];

    await client.startSession(dynamicTools: tools);
    await client.resumeSession(
      provider: 'fake-runtime',
      providerSessionId: 'provider-thread-1',
      dynamicTools: tools,
    );

    final started = adapter.requests[0].data as Map<String, dynamic>;
    final resumed = adapter.requests[1].data as Map<String, dynamic>;
    expect((started['config'] as Map)['dynamic_tools'], tools);
    expect(resumed['provider'], 'fake-runtime');
    expect((resumed['config'] as Map)['dynamic_tools'], tools);
  });

  test('resume rejects a provider mismatch from the Runtime response',
      () async {
    final adapter = _RuntimeAdapter(provider: 'other-runtime');
    final dio = Dio()..httpClientAdapter = adapter;
    final client = WorkbenchRuntimeClient(dio: dio);

    await expectLater(
      client.resumeSession(
        provider: 'fake-runtime',
        providerSessionId: 'provider-thread-1',
        dynamicTools: const [],
      ),
      throwsA(
        isA<WorkbenchRuntimeException>().having(
          (error) => error.code,
          'code',
          'runtime_provider_mismatch',
        ),
      ),
    );
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.path, endsWith('/sessions/local-1'));
  });
}

class _RuntimeAdapter implements HttpClientAdapter {
  _RuntimeAdapter({
    required this.provider,
    this.capabilityDelay = Duration.zero,
  });

  final String provider;
  final Duration capabilityDelay;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/capabilities')) {
      if (capabilityDelay > Duration.zero) {
        await Future<void>.delayed(capabilityDelay);
      }
      return ResponseBody.fromString(
        jsonEncode({
          'capabilities': ['session_start', 'turn_start'],
          'provider_metadata': {
            'provider': provider,
            'models': [
              {'id': 'fake-model'},
            ],
          },
        }),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'session_id': 'local-${requests.length}',
        'provider_metadata': {
          'provider': provider,
          'provider_session_id': 'provider-thread-1',
        },
      }),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
