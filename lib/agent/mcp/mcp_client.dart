import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/mcp/mcp_protocol.dart';

/// MCP client using Streamable HTTP transport (2024-11-05).
///
/// POSTs JSON-RPC requests directly to the MCP server. The server responds
/// with JSON and includes a session ID via the `Mcp-Session-Id` response
/// header. All subsequent requests include that session ID.
class McpClient {
  final Logger _logger = Logger('McpClient');

  final String serverUrl;
  String? Function()? _tokenProvider;

  final Dio _dio;
  int _nextRequestId = 0;
  bool _disposed = false;

  String? _sessionId;
  McpInitializeResult? _initResult;

  McpClient({
    required this.serverUrl,
    String? accessToken,
    String? Function()? tokenProvider,
  })  : _tokenProvider = (accessToken != null)
            ? (() => accessToken)
            : tokenProvider,
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  McpInitializeResult? get initResult => _initResult;
  bool get isConnected => _sessionId != null && !_disposed;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Initialize the MCP session: POSTs initialize, stores session ID,
  /// sends initialized notification.
  Future<McpInitializeResult> initialize() async {
    if (_disposed) throw StateError('McpClient already disposed');
    _logger.info('Initializing MCP session: $serverUrl');

    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': ++_nextRequestId,
      'method': 'initialize',
      'params': {
        'protocolVersion': mcpProtocolVersion,
        'capabilities': {},
        'clientInfo': {'name': 'Memex', 'version': '1.0.0'},
      },
    });

    final response = await _dio.post(
      serverUrl,
      data: requestBody,
      options: Options(
        contentType: 'application/json',
        headers: _authHeaders(),
      ),
    );

    if (response.statusCode != 200) {
      throw McpException(
          'Initialize failed: HTTP ${response.statusCode}\n${response.data}');
    }

    // Extract session ID from response headers
    _sessionId = response.headers.value('mcp-session-id');
    _logger.info('MCP session: $_sessionId');

    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data)
        : jsonDecode(response.data.toString()) as Map<String, dynamic>;
    final rpcResponse = JsonRpcResponse.fromJson(data);

    if (rpcResponse.isError) {
      throw McpException(
          'Initialize failed: ${rpcResponse.error}\n'
          'Server may require OAuth.');
    }

    _initResult = McpInitializeResult.fromJson(rpcResponse.result!);
    _logger.info('MCP initialized: ${_initResult!.serverInfo.name} '
        'v${_initResult!.serverInfo.version}');

    // Send initialized notification
    await _postJson(const JsonRpcNotification(method: 'notifications/initialized').toJson());

    return _initResult!;
  }

  /// Discover available tools from the server.
  Future<McpToolsListResult> listTools() async {
    final response = await _sendRequest('tools/list');
    if (response.isError) {
      throw McpException('tools/list failed: ${response.error}');
    }
    final result = McpToolsListResult.fromJson(response.result!);
    _logger.info('MCP tools: ${result.tools.map((t) => t.name).toList()}');
    return result;
  }

  /// Invoke a tool and return its result.
  Future<McpToolCallResult> callTool(String name,
      {Map<String, dynamic>? arguments}) async {
    final response = await _sendRequest('tools/call', {
      'name': name,
      if (arguments != null) 'arguments': arguments,
    });
    if (response.isError) {
      throw McpException('tools/call "$name" failed: ${response.error}');
    }
    return McpToolCallResult.fromJson(response.result!);
  }

  /// Release resources.
  Future<void> disconnect() async {
    _disposed = true;
    _sessionId = null;
    _dio.close();
  }

  /// Update the access token for subsequent requests.
  void updateToken(String token) {
    _tokenProvider = () => token;
    _sessionId = null;
  }

  // -----------------------------------------------------------------------
  // Internal
  // -----------------------------------------------------------------------

  String? _extractToken() => _tokenProvider?.call();

  Map<String, String> _authHeaders() {
    final token = _extractToken();
    final headers = <String, String>{
      'Accept': 'text/event-stream, application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<JsonRpcResponse> _sendRequest(
      String method, [Map<String, dynamic>? params]) async {
    final id = ++_nextRequestId;
    final request = JsonRpcRequest(id: id, method: method, params: params);
    final data = jsonEncode(request.toJson());

    final headers = _authHeaders();
    if (_sessionId != null) {
      headers['Mcp-Session-Id'] = _sessionId!;
    }

    _logger.fine('MCP request [$id]: $method');

    final response = await _dio.post(
      serverUrl,
      data: data,
      options: Options(
        contentType: 'application/json',
        headers: headers,
        responseType: ResponseType.plain,
      ),
    );

    if (response.statusCode != 200) {
      throw McpException(
          'MCP request failed: HTTP ${response.statusCode}\n${response.data}');
    }

    final Map<String, dynamic> body = _parseResponseBody(
        response.headers.value('content-type'), response.data.toString());
    return JsonRpcResponse.fromJson(body);
  }

  /// Parse response body as either JSON or SSE format.
  Map<String, dynamic> _parseResponseBody(String? contentType, String body) {
    if (contentType != null && contentType.contains('text/event-stream')) {
      return _parseSseBody(body);
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Extract JSON data from SSE-formatted response body.
  Map<String, dynamic> _parseSseBody(String sseBody) {
    for (final line in const LineSplitter().convert(sseBody)) {
      if (line.startsWith('data:')) {
        final data = line.substring(5).trim();
        if (data.isNotEmpty) {
          return jsonDecode(data) as Map<String, dynamic>;
        }
      }
    }
    throw McpException('No data field found in SSE response');
  }

  Future<void> _postJson(Map<String, dynamic> data) async {
    final headers = _authHeaders();
    if (_sessionId != null) {
      headers['Mcp-Session-Id'] = _sessionId!;
    }

    await _dio.post(
      serverUrl,
      data: jsonEncode(data),
      options: Options(
        contentType: 'application/json',
        headers: headers,
      ),
    );
  }
}

class McpException implements Exception {
  final String message;
  const McpException(this.message);
  @override
  String toString() => 'McpException: $message';
}
