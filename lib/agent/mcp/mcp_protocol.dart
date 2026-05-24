/// MCP protocol version.
const mcpProtocolVersion = '2024-11-05';

// ---------------------------------------------------------------------------
// JSON-RPC 2.0 base types
// ---------------------------------------------------------------------------

class JsonRpcRequest {
  final int id;
  final String method;
  final Map<String, dynamic>? params;

  const JsonRpcRequest({
    required this.id,
    required this.method,
    this.params,
  });

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      };
}

class JsonRpcNotification {
  final String method;
  final Map<String, dynamic>? params;

  const JsonRpcNotification({required this.method, this.params});

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'method': method,
        if (params != null) 'params': params,
      };
}

class JsonRpcResponse {
  final int? id;
  final Map<String, dynamic>? result;
  final JsonRpcError? error;

  const JsonRpcResponse({this.id, this.result, this.error});

  factory JsonRpcResponse.fromJson(Map<String, dynamic> json) {
    final errorJson = json['error'];
    return JsonRpcResponse(
      id: json['id'] as int?,
      result: json['result'] as Map<String, dynamic>?,
      error: errorJson != null
          ? JsonRpcError.fromJson(errorJson as Map<String, dynamic>)
          : null,
    );
  }

  bool get isError => error != null;
}

class JsonRpcError {
  final int code;
  final String message;
  final dynamic data;

  const JsonRpcError({required this.code, required this.message, this.data});

  factory JsonRpcError.fromJson(Map<String, dynamic> json) => JsonRpcError(
        code: json['code'] as int? ?? -1,
        message: json['message'] as String? ?? 'Unknown error',
        data: json['data'],
      );

  @override
  String toString() => 'JsonRpcError($code): $message';
}

// ---------------------------------------------------------------------------
// MCP-specific types
// ---------------------------------------------------------------------------

class McpServerInfo {
  final String name;
  final String version;

  const McpServerInfo({required this.name, required this.version});

  factory McpServerInfo.fromJson(Map<String, dynamic> json) => McpServerInfo(
        name: json['name'] as String? ?? '',
        version: json['version'] as String? ?? '',
      );
}

class McpInitializeResult {
  final String protocolVersion;
  final Map<String, dynamic> capabilities;
  final McpServerInfo serverInfo;
  final String? instructions;

  const McpInitializeResult({
    required this.protocolVersion,
    required this.capabilities,
    required this.serverInfo,
    this.instructions,
  });

  factory McpInitializeResult.fromJson(Map<String, dynamic> json) =>
      McpInitializeResult(
        protocolVersion: json['protocolVersion'] as String? ?? '',
        capabilities: json['capabilities'] as Map<String, dynamic>? ?? {},
        serverInfo:
            McpServerInfo.fromJson(json['serverInfo'] as Map<String, dynamic>? ?? {}),
        instructions: json['instructions'] as String?,
      );
}

class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) => McpTool(
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        inputSchema: json['inputSchema'] as Map<String, dynamic>? ?? {},
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}

class McpToolsListResult {
  final List<McpTool> tools;

  const McpToolsListResult({required this.tools});

  factory McpToolsListResult.fromJson(Map<String, dynamic> json) {
    final rawTools = json['tools'] as List<dynamic>? ?? [];
    return McpToolsListResult(
      tools: rawTools
          .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

class McpContentItem {
  final String type;
  final String? text;

  const McpContentItem({required this.type, this.text});

  factory McpContentItem.fromJson(Map<String, dynamic> json) => McpContentItem(
        type: json['type'] as String? ?? 'text',
        text: json['text'] as String?,
      );
}

class McpToolCallResult {
  final List<McpContentItem> content;
  final bool isError;

  const McpToolCallResult({required this.content, this.isError = false});

  factory McpToolCallResult.fromJson(Map<String, dynamic> json) =>
      McpToolCallResult(
        content: (json['content'] as List<dynamic>?)
                ?.map(
                    (c) => McpContentItem.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        isError: json['isError'] as bool? ?? false,
      );

  String get text =>
      content.map((c) => c.text ?? '').join('\n');
}
