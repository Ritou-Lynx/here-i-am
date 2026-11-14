import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:memex/agent/mcp/mcp_oauth.dart';
import 'package:memex/data/services/i_mcp_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Connects the app to the read-only i MCP OAuth frontend.
class IMcpConnectPage extends StatefulWidget {
  const IMcpConnectPage({super.key});

  @override
  State<IMcpConnectPage> createState() => _IMcpConnectPageState();
}

class _IMcpConnectPageState extends State<IMcpConnectPage> {
  final _serverController = TextEditingController();
  final _service = IMcpService.instance;

  WebViewController? _webViewController;
  bool _loading = true;
  bool _connected = false;
  String _status = '正在读取连接状态…';
  String? _error;
  int? _toolCount;
  String? _oauthState;

  @override
  void initState() {
    super.initState();
    _loadExistingConnection();
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingConnection() async {
    final serverUrl = await _service.storedServerUrl();
    if (serverUrl != null) _serverController.text = serverUrl;
    if (await _service.hasStoredToken()) {
      await _service.ensureConnected();
    }
    if (!mounted) return;
    setState(() {
      _connected = _service.isConnected;
      _status = _connected ? '已连接' : '粘贴 i MCP 地址以开始连接';
      _error = _connected ? null : _service.lastError;
      _loading = false;
    });
    if (_connected) await _loadToolCount();
  }

  Future<void> _startAuthorization() async {
    String serverUrl;
    try {
      serverUrl = IMcpService.normalizeServerUrl(_serverController.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = '正在发现授权服务…';
      _webViewController = null;
    });

    try {
      final oauth = McpOAuth(serverUrl: serverUrl);
      final metadata = await oauth.discoverMetadata();
      if (!mounted) return;
      setState(() => _status = '正在注册 App…');
      final clientId = await oauth.registerClient(
        metadata,
        clientName: 'Here I Am App',
        redirectUri: iMcpRedirectUri,
      );
      final pkce = oauth.buildPkceAuthParams();
      final state = _newState();
      _oauthState = state;
      final authUrl = oauth.buildAuthUrl(
        metadata: metadata,
        codeChallenge: pkce.codeChallenge,
        clientId: clientId,
        redirectUri: iMcpRedirectUri,
        state: state,
        scope: 'i.read',
      );

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (_isRedirect(request.url)) {
                _handleRedirect(
                  request.url,
                  serverUrl: serverUrl,
                  oauth: oauth,
                  metadata: metadata,
                  codeVerifier: pkce.codeVerifier,
                  clientId: clientId,
                );
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame == true && mounted) {
                setState(() => _error = '授权页面加载失败：${error.description}');
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(authUrl));
      if (!mounted) return;
      setState(() {
        _webViewController = controller;
        _status = '请在授权页输入口令';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '连接准备失败：$error';
      });
    }
  }

  Future<void> _handleRedirect(
    String url, {
    required String serverUrl,
    required McpOAuth oauth,
    required McpOAuthMetadata metadata,
    required String codeVerifier,
    required String clientId,
  }) async {
    final uri = Uri.parse(url);
    final state = uri.queryParameters['state'];
    if (state == null || state != _oauthState) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '授权状态校验失败，请重新连接';
          _webViewController = null;
        });
      }
      return;
    }
    final oauthError = uri.queryParameters['error'];
    final code = uri.queryParameters['code'];
    if (oauthError != null || code == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = oauthError == null ? '授权回调缺少 code' : '授权未完成：$oauthError';
          _webViewController = null;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _status = '正在交换令牌并验证连接…';
      _webViewController = null;
    });
    try {
      final token = await oauth.exchangeCode(
        metadata: metadata,
        code: code,
        codeVerifier: codeVerifier,
        clientId: clientId,
        redirectUri: iMcpRedirectUri,
      );
      await _service.saveAuthorization(
        serverUrl: serverUrl,
        token: token,
        clientId: clientId,
        tokenEndpoint: metadata.tokenEndpoint,
      );
      await _service.ensureConnected();
      if (!_service.isConnected) {
        throw IMcpException(_service.lastError ?? '无法建立 MCP 会话');
      }
      final tools = await _service.listTools();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _loading = false;
        _toolCount = tools.tools.length;
        _status = '已连接，可用工具 ${tools.tools.length} 个';
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '连接验证失败：$error';
      });
    }
  }

  Future<void> _loadToolCount() async {
    try {
      final tools = await _service.listTools();
      if (!mounted) return;
      setState(() {
        _toolCount = tools.tools.length;
        _status = '已连接，可用工具 ${tools.tools.length} 个';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '读取工具列表失败：$error');
    }
  }

  Future<void> _disconnect() async {
    setState(() => _loading = true);
    await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _loading = false;
      _toolCount = null;
      _status = '已断开';
      _error = null;
      _serverController.clear();
    });
  }

  bool _isRedirect(String value) {
    final actual = Uri.tryParse(value);
    final expected = Uri.parse(iMcpRedirectUri);
    return actual != null &&
        actual.scheme == expected.scheme &&
        actual.host == expected.host &&
        actual.port == expected.port &&
        actual.path == expected.path;
  }

  String _newState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('林埃数据（i MCP）')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: Theme.of(context).textTheme.titleMedium),
              if (_toolCount != null) ...[
                const SizedBox(height: 4),
                Text('当前只读工具数：$_toolCount'),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              if (_connected)
                FilledButton.tonal(
                  onPressed: _loading ? null : _disconnect,
                  child: const Text('断开'),
                )
              else ...[
                TextField(
                  controller: _serverController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'i MCP 地址',
                    hintText: 'https://…/mcp',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loading ? null : _startAuthorization,
                  child: const Text('连接'),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_webViewController != null) ...[
                const SizedBox(height: 16),
                Expanded(child: WebViewWidget(controller: _webViewController!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
