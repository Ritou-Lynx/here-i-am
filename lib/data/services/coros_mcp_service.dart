import 'package:logging/logging.dart';
import 'package:memex/agent/mcp/mcp_client.dart';
import 'package:memex/agent/mcp/mcp_oauth.dart';
import 'package:memex/agent/mcp/mcp_protocol.dart';
import 'package:memex/data/services/mcp_token_storage.dart';
import 'package:memex/utils/user_storage.dart';

/// Service layer for COROS MCP — manages session lifecycle and exposes typed
/// query methods for health/fitness data.
class CorosMcpService {
  static final _logger = Logger('CorosMcpService');
  static CorosMcpService? _instance;

  McpClient? _client;
  bool _initializing = false;
  String? _lastError;

  String? get lastError => _lastError;

  CorosMcpService._();

  static CorosMcpService get instance => _instance ??= CorosMcpService._();

  bool get isConnected => _client?.isConnected ?? false;

  /// Ensure the MCP session is established. Safe to call repeatedly — will
  /// skip if already connected or if no token is available.
  ///
  /// If [userId] is provided, uses it directly. Otherwise reads from storage.
  Future<void> ensureConnected({String? userId}) async {
    if (_client?.isConnected == true) return;
    if (_initializing) return;

    _initializing = true;
    _lastError = null;
    try {
      userId ??= await UserStorage.getUserId();
      if (userId == null) {
        _lastError = 'COROS MCP: No user ID';
        return;
      }

      final storage = McpTokenStorage(userId: userId);
      final token = await storage.load();
      if (token == null) {
        _lastError = 'COROS 尚未连接，请先在设置中授权';
        return;
      }

      var accessToken = token.accessToken;

      if (token.isExpired) {
        _logger.info('COROS token expired — attempting refresh');
        final meta = await storage.loadRefreshMeta();
        if (meta != null && token.refreshToken != null) {
          try {
            final oauth = McpOAuth(
                serverUrl: 'https://mcpcn.coros.com/mcp');
            final newToken = await oauth.refreshToken(
              metadata: McpOAuthMetadata(tokenEndpoint: meta.tokenEndpoint),
              refreshToken: token.refreshToken!,
              clientId: meta.clientId,
            );
            await storage.save(
              newToken,
              clientId: meta.clientId,
              tokenEndpoint: meta.tokenEndpoint,
            );
            accessToken = newToken.accessToken;
            _logger.info('COROS token refreshed successfully');
          } catch (e) {
            _lastError = 'COROS token 刷新失败: $e';
            return;
          }
        } else {
          _lastError = 'COROS 授权已过期，请重新连接（缺少刷新凭据）';
          return;
        }
      }

      _client = McpClient(
        serverUrl: 'https://mcpcn.coros.com/mcp',
        accessToken: accessToken,
      );

      await _client!.initialize();
      _logger.info('COROS MCP connected');
    } catch (e) {
      _lastError = 'COROS MCP: $e';
      _logger.warning(_lastError!);
      _client?.disconnect();
      _client = null;
    } finally {
      _initializing = false;
    }
  }

  /// Call any COROS MCP tool by name with optional arguments.
  Future<McpToolCallResult> callTool(String name,
      {Map<String, dynamic>? arguments}) async {
    await ensureConnected();
    if (_client == null || !_client!.isConnected) {
      throw CorosMcpException('COROS MCP not connected');
    }
    return _client!.callTool(name, arguments: arguments);
  }

  /// Shorthand queries -------------------------------------------------------

  Future<McpToolCallResult> queryUserInfo() => callTool('queryUserInfo');

  Future<McpToolCallResult> queryDailyHealthData(
          {int days = 7, String timezone = 'Asia/Shanghai'}) =>
      callTool('queryDailyHealthData',
          arguments: {'days': days, 'timezone': timezone});

  Future<McpToolCallResult> querySleepData({
    String? startDate,
    String? endDate,
    int days = 7,
    String timezone = 'Asia/Shanghai',
  }) {
    final args = <String, dynamic>{
      'days': days,
      'timezone': timezone,
    };
    if (startDate != null) args['startDate'] = startDate;
    if (endDate != null) args['endDate'] = endDate;
    return callTool('querySleepData', arguments: args);
  }

  Future<McpToolCallResult> querySportRecords({
    String? startDate,
    String? endDate,
    List<int>? sportTypeCodes,
    int limit = 20,
    String timezone = 'Asia/Shanghai',
  }) {
    final args = <String, dynamic>{
      'limit': limit,
      'timezone': timezone,
    };
    if (startDate != null) args['startDate'] = startDate;
    if (endDate != null) args['endDate'] = endDate;
    if (sportTypeCodes != null) args['sportTypeCodes'] = sportTypeCodes;
    return callTool('querySportRecords', arguments: args);
  }

  Future<McpToolCallResult> queryFitnessAssessmentOverview() =>
      callTool('queryFitnessAssessmentOverview');

  Future<McpToolCallResult> queryRecoveryStatus() =>
      callTool('queryRecoveryStatus');

  Future<McpToolCallResult> queryAvgHeartRate(
          {int days = 7, String timezone = 'Asia/Shanghai'}) =>
      callTool('queryAvgHeartRate',
          arguments: {'days': days, 'timezone': timezone});

  Future<McpToolCallResult> queryRestingHeartRate(
          {int days = 7, String timezone = 'Asia/Shanghai'}) =>
      callTool('queryRestingHeartRate',
          arguments: {'days': days, 'timezone': timezone});

  Future<McpToolCallResult> queryStressLevel(
          {int days = 7, String timezone = 'Asia/Shanghai'}) =>
      callTool('queryStressLevel',
          arguments: {'days': days, 'timezone': timezone});

  Future<McpToolCallResult> queryHrvAssessment(
          {int days = 7, String timezone = 'Asia/Shanghai'}) =>
      callTool('queryHrvAssessment',
          arguments: {'days': days, 'timezone': timezone});

  Future<McpToolCallResult> queryTrainingLoadAssessment({int days = 7}) =>
      callTool('queryTrainingLoadAssessment', arguments: {'days': days});

  Future<McpToolCallResult> queryTrainingSchedule({
    String? startDate,
    String? endDate,
    String timezone = 'Asia/Shanghai',
  }) {
    final args = <String, dynamic>{'timezone': timezone};
    if (startDate != null) args['startDate'] = startDate;
    if (endDate != null) args['endDate'] = endDate;
    return callTool('queryTrainingSchedule', arguments: args);
  }

  Future<McpToolCallResult> queryDevices() => callTool('queryDevices');

  Future<McpToolCallResult> getActivityDetail(
          {required String labelId, required int sportType}) =>
      callTool('getActivityDetail',
          arguments: {'labelId': labelId, 'sportType': sportType});

  Future<McpToolCallResult> analyzeActivityDetail({
    required String labelId,
    required int sportType,
    String? focus,
  }) {
    final args = <String, dynamic>{
      'labelId': labelId,
      'sportType': sportType,
    };
    if (focus != null) args['focus'] = focus;
    return callTool('analyzeActivityDetail', arguments: args);
  }

  /// Disconnect and release resources.
  Future<void> disconnect() async {
    await _client?.disconnect();
    _client = null;
  }
}

class CorosMcpException implements Exception {
  final String message;
  const CorosMcpException(this.message);
  @override
  String toString() => 'CorosMcpException: $message';
}
