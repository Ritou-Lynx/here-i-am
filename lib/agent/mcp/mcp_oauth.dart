import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

/// OAuth 2.0 metadata discovered from the MCP server.
class McpOAuthMetadata {
  final String issuer;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String? registrationEndpoint;
  final List<String> scopesSupported;
  final List<String> responseTypesSupported;

  const McpOAuthMetadata({
    this.issuer = '',
    this.authorizationEndpoint = '',
    required this.tokenEndpoint,
    this.registrationEndpoint,
    this.scopesSupported = const [],
    this.responseTypesSupported = const ['code'],
  });

  factory McpOAuthMetadata.fromJson(Map<String, dynamic> json) {
    return McpOAuthMetadata(
      issuer: json['issuer'] as String? ?? '',
      authorizationEndpoint: json['authorization_endpoint'] as String? ?? '',
      tokenEndpoint: json['token_endpoint'] as String? ?? '',
      registrationEndpoint: json['registration_endpoint'] as String?,
      scopesSupported: (json['scopes_supported'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      responseTypesSupported: (json['response_types_supported'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['code'],
    );
  }
}

/// Result of a successful token exchange.
class McpOAuthToken {
  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final DateTime? obtainedAt;

  const McpOAuthToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.obtainedAt,
  });

  bool get isExpired {
    if (expiresIn == null || obtainedAt == null) return false;
    return DateTime.now().difference(obtainedAt!).inSeconds > (expiresIn! - 60);
  }

  factory McpOAuthToken.fromJson(Map<String, dynamic> json) {
    return McpOAuthToken(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expiresIn: json['expires_in'] as int?,
      obtainedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (expiresIn != null) 'expires_in': expiresIn,
        if (obtainedAt != null) 'obtained_at': obtainedAt!.toIso8601String(),
      };

  factory McpOAuthToken.fromStoredJson(Map<String, dynamic> json) {
    final obtainedStr = json['obtained_at'] as String?;
    return McpOAuthToken(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expiresIn: json['expires_in'] as int?,
      obtainedAt:
          obtainedStr != null ? DateTime.tryParse(obtainedStr) : null,
    );
  }
}

class _PkceParams {
  final String verifier;
  final String challenge;
  const _PkceParams({required this.verifier, required this.challenge});
}

/// Handles MCP OAuth 2.0 / PKCE flow.
///
/// Usage:
/// ```dart
/// final oauth = McpOAuth(serverUrl: 'https://mcpcn.coros.com/mcp');
/// final metadata = await oauth.discoverMetadata();
/// final pkce = oauth.generatePkce();
/// // Open authorization URL in browser: oauth.buildAuthUrl(metadata, pkce, ...)
/// // After redirect, exchange the code:
/// final token = await oauth.exchangeCode(metadata, pkce, code, redirectUri, clientId);
/// // Store token for later use.
/// ```
class McpOAuth {
  final Logger _logger = Logger('McpOAuth');
  final String serverUrl;
  final Dio _dio;

  McpOAuth({required this.serverUrl}) : _dio = Dio();

  // -----------------------------------------------------------------------
  // OAuth metadata discovery
  // -----------------------------------------------------------------------

  /// Fetch OAuth 2.0 server metadata from the MCP server's well-known URL.
  Future<McpOAuthMetadata> discoverMetadata() async {
    final origin = _origin(serverUrl);
    final wellKnownUrl = '$origin/.well-known/oauth-authorization-server';

    _logger.info('Discovering OAuth metadata: $wellKnownUrl');
    final response = await _dio.get(wellKnownUrl);

    if (response.statusCode != 200) {
      throw McpOAuthException(
          'Failed to discover OAuth metadata: HTTP ${response.statusCode}');
    }

    final metadata = McpOAuthMetadata.fromJson(
        (response.data is Map ? Map<String, dynamic>.from(response.data) : <String, dynamic>{}));
    _logger.info('OAuth issuer: ${metadata.issuer}');
    return metadata;
  }

  // -----------------------------------------------------------------------
  // Dynamic Client Registration (DCR)
  // -----------------------------------------------------------------------

  /// Register a dynamic OAuth client. Returns the assigned client_id.
  Future<String> registerClient(
    McpOAuthMetadata metadata, {
    String clientName = 'Memex',
    String redirectUri = 'http://localhost:8080/callback',
  }) async {
    if (metadata.registrationEndpoint == null) {
      throw McpOAuthException('Server does not support DCR');
    }

    _logger.info('Registering OAuth client: $clientName');
    final response = await _dio.post(
      metadata.registrationEndpoint!,
      data: {
        'client_name': clientName,
        'redirect_uris': [redirectUri],
      },
      options: Options(
        validateStatus: (_) => true,
      ),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw McpOAuthException(
          'DCR failed: HTTP ${response.statusCode}: ${response.data}');
    }

    final data = (response.data is Map
        ? Map<String, dynamic>.from(response.data)
        : <String, dynamic>{});
    _logger.info('DCR response: $data');
    final clientId = data['client_id'] as String?;
    if (clientId == null) throw McpOAuthException('DCR response missing client_id');
    _logger.info('DCR client_id: $clientId');
    return clientId;
  }

  // -----------------------------------------------------------------------
  // PKCE
  // -----------------------------------------------------------------------

  /// Generate PKCE code verifier and challenge pair.
  _PkceParams _generatePkce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final verifier = base64Url.encode(bytes).replaceAll('=', '');
    final challengeBytes = sha256.convert(utf8.encode(verifier)).bytes;
    final challenge = base64Url.encode(challengeBytes).replaceAll('=', '');
    return _PkceParams(verifier: verifier, challenge: challenge);
  }

  /// Get a PKCE code verifier string.
  String generateCodeVerifier() => _generatePkce().verifier;

  /// Build PKCE params needed for the authorization flow.
  PkceAuthParams buildPkceAuthParams() {
    final pkce = _generatePkce();
    return PkceAuthParams(
      codeVerifier: pkce.verifier,
      codeChallenge: pkce.challenge,
    );
  }

  // -----------------------------------------------------------------------
  // Authorization URL
  // -----------------------------------------------------------------------

  /// Build the authorization URL to open in a browser/WebView.
  String buildAuthUrl({
    required McpOAuthMetadata metadata,
    required String codeChallenge,
    required String clientId,
    String redirectUri = 'http://localhost:8080/callback',
    String? state,
    String scope = '',
  }) {
    final stateVal = state ?? _randomState();
    final params = {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': stateVal,
      if (scope.isNotEmpty) 'scope': scope,
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '${metadata.authorizationEndpoint}?$query';
  }

  // -----------------------------------------------------------------------
  // Token exchange
  // -----------------------------------------------------------------------

  /// Exchange an authorization code for an access token.
  Future<McpOAuthToken> exchangeCode({
    required McpOAuthMetadata metadata,
    required String code,
    required String codeVerifier,
    required String clientId,
    String redirectUri = 'http://localhost:8080/callback',
  }) async {
    _logger.info('Exchanging authorization code for token');
    final response = await _dio.post(
      metadata.tokenEndpoint,
      data: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
        'client_id': clientId,
      },
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
      ),
    );

    if (response.statusCode != 200) {
      throw McpOAuthException(
          'Token exchange failed: HTTP ${response.statusCode}: ${response.data}');
    }

    final raw = response.data;
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return McpOAuthToken.fromJson(data);
  }

  /// Refresh an expired access token.
  Future<McpOAuthToken> refreshToken({
    required McpOAuthMetadata metadata,
    required String refreshToken,
    required String clientId,
  }) async {
    _logger.info('Refreshing access token');
    final response = await _dio.post(
      metadata.tokenEndpoint,
      data: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
      },
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
      ),
    );

    if (response.statusCode != 200) {
      throw McpOAuthException(
          'Token refresh failed: HTTP ${response.statusCode}: ${response.data}');
    }

    final data =
        (response.data is Map ? Map<String, dynamic>.from(response.data) : <String, dynamic>{});
    return McpOAuthToken.fromJson(data);
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  String _origin(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Auth params needed for the full OAuth flow.
class PkceAuthParams {
  final String codeVerifier;
  final String codeChallenge;

  const PkceAuthParams({
    required this.codeVerifier,
    required this.codeChallenge,
  });
}

class McpOAuthException implements Exception {
  final String message;
  const McpOAuthException(this.message);
  @override
  String toString() => 'McpOAuthException: $message';
}
