import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/mcp/mcp_oauth.dart';
import 'package:memex/data/services/coros_mcp_service.dart';
import 'package:memex/data/services/mcp_token_storage.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Full-screen OAuth page that connects to COROS MCP.
///
/// Opens a WebView for the user to log in and authorize Memex.
/// Intercepts the OAuth redirect to extract the authorization code,
/// exchanges it for an access token, and persists the token.
class CorosConnectPage extends StatefulWidget {
  const CorosConnectPage({super.key, this.initiallyConnected = false});

  final bool initiallyConnected;

  @override
  State<CorosConnectPage> createState() => _CorosConnectPageState();
}

class _CorosConnectPageState extends State<CorosConnectPage> {
  static const _serverUrl = 'https://mcpcn.coros.com/mcp';
  static const _redirectUri = 'http://localhost:8080/callback';
  static final _logger = Logger('CorosConnectPage');

  bool _loading = true;
  bool _connected = false;
  String? _error;
  String _statusText = 'Preparing...';
  WebViewController? _webViewCtrl;

  final _oauth = McpOAuth(serverUrl: _serverUrl);

  @override
  void initState() {
    super.initState();
    _loading = true;
    _checkExistingToken();
  }

  Future<void> _checkExistingToken() async {
    final userId = await UserStorage.getUserId();
    final token = userId != null
        ? await McpTokenStorage(userId: userId).load()
        : null;
    final hasValidToken = token != null && !token.isExpired;

    if (!mounted) return;

    setState(() {
      _connected = hasValidToken;
      _loading = false;
    });

    if (hasValidToken) {
      _logger.info('[COROS OAUTH] Existing valid token found, skipping auth');
    } else if (token != null && token.isExpired) {
      _logger.info('[COROS OAUTH] Token expired, starting auth');
      _startAuth();
    } else {
      _logger.info('[COROS OAUTH] No token found, starting auth');
      _startAuth();
    }
  }

  void _restartAuth() {
    setState(() {
      _connected = false;
      _error = null;
      _loading = true;
      _statusText = 'Preparing...';
      _webViewCtrl = null;
    });
    _startAuth();
  }

  Future<void> _startAuth() async {
    try {
      // 1. Discover OAuth metadata
      setState(() => _statusText = 'Connecting to COROS...');
      final metadata = await _oauth.discoverMetadata();

      // 2. Register client (DCR)
      setState(() => _statusText = 'Registering...');
      String clientId;
      try {
        clientId = await _oauth.registerClient(metadata);
      } catch (e) {
        setState(() {
          _loading = false;
          _error = 'DCR failed: $e';
        });
        return;
      }

      // 3. Generate PKCE
      final pkce = _oauth.buildPkceAuthParams();

      // 4. Build authorization URL
      final authUrl = _oauth.buildAuthUrl(
        metadata: metadata,
        codeChallenge: pkce.codeChallenge,
        clientId: clientId,
        redirectUri: _redirectUri,
        scope: 'openid mcp.tools offline_access',
      );

      // 5. Create WebView and navigate
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              _logger.fine('[COROS OAUTH] Navigation: ${request.url}');
              if (request.url.startsWith(_redirectUri)) {
                _handleRedirect(
                    request.url, metadata, pkce.codeVerifier, clientId);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onWebResourceError: (error) {
              _logger.warning(
                  '[COROS OAUTH] WebView error: ${error.errorCode} ${error.description} url=${error.url}');
            },
            onPageFinished: (url) {
              _logger.fine('[COROS OAUTH] Page finished: $url');
              if (_loading) setState(() => _loading = false);
            },
          ),
        )
        ..loadRequest(Uri.parse(authUrl));

      _webViewCtrl = controller;
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _handleRedirect(
    String url,
    McpOAuthMetadata metadata,
    String codeVerifier,
    String clientId,
  ) async {
    _logger.info('[COROS OAUTH] Redirect intercepted: $url');
    try {
      setState(() {
        _loading = true;
        _statusText = 'Exchanging authorization code...';
      });

      final uri = Uri.parse(url);
      _logger.info('[COROS OAUTH] Parsed query params: ${uri.queryParameters.keys.toList()}');
      final error = uri.queryParameters['error'];
      if (error != null) {
        _logger.warning('[COROS OAUTH] OAuth error in redirect: $error');
        setState(() {
          _loading = false;
          _error = 'Authorization denied: $error';
        });
        return;
      }

      final code = uri.queryParameters['code'];
      if (code == null) {
        _logger.warning('[COROS OAUTH] No code in redirect URL: $uri');
        setState(() {
          _loading = false;
          _error = 'No authorization code received';
        });
        return;
      }

      _logger.info('[COROS OAUTH] Got code, exchanging for token...');
      // 6. Exchange code for token
      setState(() => _statusText = 'Getting access token...');
      final token = await _oauth.exchangeCode(
        metadata: metadata,
        code: code,
        codeVerifier: codeVerifier,
        clientId: clientId,
        redirectUri: _redirectUri,
      );
      _logger.info('[COROS OAUTH] Token exchange OK, access token len=${token.accessToken.length}');

      // 7. Save token (with refresh metadata)
      final userId = await UserStorage.getUserId();
      if (userId != null) {
        await McpTokenStorage(userId: userId).save(
          token,
          clientId: clientId,
          tokenEndpoint: metadata.tokenEndpoint,
        );
        _logger.info('[COROS OAUTH] Token saved for user=$userId');
      } else {
        _logger.warning('[COROS OAUTH] No userId, token not persisted');
      }

      // 8. Verify the token actually works by calling the MCP server.
      setState(() => _statusText = 'Verifying connection...');
      try {
        final verifyClient = CorosMcpService.instance;
        await verifyClient.disconnect();
        await verifyClient.ensureConnected(userId: userId);
        if (!verifyClient.isConnected) {
          final detail = verifyClient.lastError ?? 'unknown error';
          _logger.warning('[COROS OAUTH] Verification failed: $detail');
          setState(() {
            _loading = false;
            _error = '连接验证失败：$detail\n\n'
                '（token 已保存但无法建立 MCP 会话，可能已被 COROS 服务器撤销）';
          });
          return;
        }
        _logger.info('[COROS OAUTH] MCP verification OK');
      } catch (e) {
        _logger.warning('[COROS OAUTH] Verification exception: $e');
        setState(() {
          _loading = false;
          _error = '连接验证异常：$e';
        });
        return;
      }

      if (mounted) {
        setState(() {
          _connected = true;
          _loading = false;
        });
        // Pop after a brief delay so the user can see the "已连接" state.
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.pop(context, true);
          }
        });
      }
    } catch (e, stack) {
      _logger.warning('[COROS OAUTH] Fatal error in _handleRedirect: $e\n$stack');
      setState(() {
        _loading = false;
        _error = 'Token exchange failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect COROS'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_connected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                size: 56,
                color: SpringRainUiTokens.daylightSuccess,
              ),
              const SizedBox(height: 16),
              const Text(
                '已连接',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: SpringRainUiTokens.daylightTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Memex 已经可以读取 COROS 高驰授权的数据。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: SpringRainUiTokens.daylightTextSecondary),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _restartAuth,
                icon: const Icon(Icons.refresh),
                label: const Text('重新连接'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: SpringRainUiTokens.daylightError),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: SpringRainUiTokens.daylightError)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _loading = true;
                  });
                  _startAuth();
                },
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading && _webViewCtrl == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_statusText),
          ],
        ),
      );
    }

    if (_webViewCtrl != null) {
      return Stack(
        children: [
          WebViewWidget(controller: _webViewCtrl!),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    return const Center(child: CircularProgressIndicator());
  }
}
