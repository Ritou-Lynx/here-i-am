import 'dart:async';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/built_in_tools/i_mcp_query_tool.dart';
import 'package:memex/agent/mcp/mcp_protocol.dart';
import 'package:memex/data/services/i_mcp_service.dart';

void main() {
  test('uses object parameterMode so agents pass decoded args map directly', () {
    final tool = buildIMcpQueryTool(service: _FakeIMcpQueryService(connected: false));
    expect(tool.parameterMode, ToolParameterMode.object);
    expect(iMcpReadTools.length, 10);
    expect(
      tool.description,
      contains('life_digest：生活摘要与长期档案；参数 period（day/week/month/profile，默认 day）、date、week、month、section、category。'),
    );
  });

  test('redirect URI exactly matches the registered app callback', () {
    expect(
      iMcpRedirectUri,
      'http://127.0.0.1:47859/hereiam/i-mcp/callback',
    );
  });

  test('rejects a tool outside the read-only allowlist', () async {
    final fake = _FakeIMcpQueryService(connected: true);
    final output = await buildIMcpQueryTool(service: fake).executable!({
      'tool': 'i_remember',
      'arguments': {'text': 'must not be sent'},
    });

    expect(output, contains('不允许'));
    expect(fake.calls, isEmpty);
  });

  test('forwards arguments unchanged to the injected service', () async {
    final fake = _FakeIMcpQueryService(connected: true);
    final arguments = <String, dynamic>{
      'days': 3,
      'date': '2026-11-10',
      'folder': 'synthetic',
    };

    final output = await buildIMcpQueryTool(service: fake).executable!({
      'tool': 'notes_recent',
      'arguments': arguments,
    });

    expect(output, 'ok');
    expect(fake.calls, ['notes_recent']);
    expect(fake.lastArguments, arguments);
  });

  test('returns the settings guidance when no connection is available',
      () async {
    final fake = _FakeIMcpQueryService(connected: false);
    final output = await buildIMcpQueryTool(service: fake).executable!({
      'tool': 'life_digest',
    });

    expect(output, '还没连接 i MCP，请到设置里连接');
    expect(fake.calls, isEmpty);
  });

  test('truncates results over 20000 characters and labels the truncation',
      () async {
    final fake = _FakeIMcpQueryService(
      connected: true,
      resultText: 'x' * 20001,
    );
    final output = await buildIMcpQueryTool(service: fake).executable!({
      'tool': 'notes_read',
      'arguments': {'token': 'synthetic-token'},
    }) as String;

    expect(output.startsWith('x' * 20000), isTrue);
    expect(output, endsWith('[结果超过 20000 字，已截断]'));
  });

  test('turns service errors into result text', () async {
    final fake = _FakeIMcpQueryService(
      connected: true,
      error: StateError('synthetic failure'),
    );
    final output = await buildIMcpQueryTool(service: fake).executable!({
      'tool': 'food_day',
      'arguments': {'date': '2026-11-10'},
    });

    expect(output, contains('i MCP 查询失败'));
    expect(output, contains('synthetic failure'));
  });

  group('shouldClearIMcpAuthorizationAfterRefreshError', () {
    DioException dioStatus(int statusCode, {Object? data}) {
      final req = RequestOptions(path: 'https://example.test/token');
      return DioException(
        requestOptions: req,
        response: Response(
          requestOptions: req,
          statusCode: statusCode,
          data: data,
        ),
        type: DioExceptionType.badResponse,
      );
    }

    test('clears authorization on explicit OAuth rejection (400/401/invalid_grant/invalid_client)', () {
      expect(shouldClearIMcpAuthorizationAfterRefreshError(dioStatus(400)), isTrue);
      expect(shouldClearIMcpAuthorizationAfterRefreshError(dioStatus(401)), isTrue);
      expect(
        shouldClearIMcpAuthorizationAfterRefreshError(
          dioStatus(403, data: {'error': 'invalid_grant'}),
        ),
        isTrue,
      );
      expect(
        shouldClearIMcpAuthorizationAfterRefreshError(
          Exception('OAuth refresh failed: invalid_client'),
        ),
        isTrue,
      );
    });

    test('preserves authorization on transient failures (timeout/socket/5xx)', () {
      expect(
        shouldClearIMcpAuthorizationAfterRefreshError(
          TimeoutException('refresh timed out'),
        ),
        isFalse,
      );
      expect(
        shouldClearIMcpAuthorizationAfterRefreshError(
          const SocketException('Failed host lookup'),
        ),
        isFalse,
      );
      expect(shouldClearIMcpAuthorizationAfterRefreshError(dioStatus(500)), isFalse);
      expect(shouldClearIMcpAuthorizationAfterRefreshError(dioStatus(502)), isFalse);
    });
  });
}

class _FakeIMcpQueryService implements IMcpQueryService {
  _FakeIMcpQueryService({
    required bool connected,
    this.resultText = 'ok',
    this.error,
  }) : _connected = connected;

  final bool _connected;
  final String resultText;
  final Object? error;
  final List<String> calls = [];
  Map<String, dynamic>? lastArguments;

  @override
  bool get isConnected => _connected;

  @override
  String? get lastError => null;

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<McpToolCallResult> callTool(
    String name, {
    Map<String, dynamic>? arguments,
  }) async {
    calls.add(name);
    lastArguments = arguments;
    if (error != null) throw error!;
    return McpToolCallResult(
      content: [McpContentItem(type: 'text', text: resultText)],
    );
  }
}
