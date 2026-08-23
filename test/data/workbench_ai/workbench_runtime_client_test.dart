import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';

void main() {
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
  _RuntimeAdapter({required this.provider});

  final String provider;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    requests.add(options);
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
