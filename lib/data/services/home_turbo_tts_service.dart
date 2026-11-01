import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/logger.dart';

/// 林埃英文声音：家里电脑上常驻的 Chatterbox-Turbo 服务（tools/linai_tts）。
///
/// 手机经 Tailscale 访问 `https://<电脑>:8445`；`tailscale serve` 会带上手机的
/// Tailscale 身份，服务端按名单放行，所以 App 不需要 token。
///
/// 含中文的句子不送过去（Turbo 只会英文），直接由 MiniMax 念。
/// 任何失败都返回 null，由 [TtsService] 换成 MiniMax 念这一句；连续失败
/// [HomeTurboBreaker.maxConsecutiveFailures] 次后熔断一段时间，免得每句都先等超时。
class HomeTurboTtsService {
  HomeTurboTtsService._();

  static final _log = getLogger('HomeTurboTts');

  /// 用户手动填的服务地址（KvStore）。没填就从漫画服务地址推出来。
  static const kvUrlKey = 'linai_tts.url';
  static const comicUrlKey = 'comic.hermes_url';
  static const defaultPort = 8445;

  /// 服务端单段上限（与 tools/linai_tts 的 max_chars 一致），超出直接走回退。
  static const maxChars = 400;

  static const _cacheVersion = 'turbo-v1';

  /// 测试注入点。
  static http.Client Function() clientFactory = http.Client.new;
  static Future<String?> Function(String key) kvRead = _defaultKvRead;
  static Future<void> Function(String key, String value) kvWrite =
      _defaultKvWrite;

  static final breaker = HomeTurboBreaker();

  /// 一句话的等待上限：基础 4 秒，再按字数放宽（RTF≈0.35，长句要多给时间）。
  static Duration timeoutFor(String text) =>
      Duration(milliseconds: 4000 + 25 * text.length);

  // ── 地址 ────────────────────────────────────────────────────────────────

  /// 从漫画服务地址推出语音服务地址：同一台电脑，换成 https 和 8445 端口。
  static String? deriveFromComicUrl(String? comicUrl) {
    if (comicUrl == null || comicUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(comicUrl.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return Uri(scheme: 'https', host: uri.host, port: defaultPort).toString();
  }

  static String normalizeUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// 用户填的地址；为空时返回从漫画服务推出的默认地址。
  static Future<String?> resolveBaseUrl() async {
    final own = await kvRead(kvUrlKey);
    if (own != null && own.trim().isNotEmpty) return normalizeUrl(own);
    return deriveFromComicUrl(await kvRead(comicUrlKey));
  }

  static Future<String> getSavedUrl() async => (await kvRead(kvUrlKey)) ?? '';

  static Future<String?> getDerivedUrl() async =>
      deriveFromComicUrl(await kvRead(comicUrlKey));

  static Future<void> saveUrl(String url) =>
      kvWrite(kvUrlKey, normalizeUrl(url));

  // ── 健康检查 ────────────────────────────────────────────────────────────

  static Future<HomeTurboHealth> checkHealth({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final base = await resolveBaseUrl();
    if (base == null) return const HomeTurboHealth.unreachable('no_url');
    final client = clientFactory();
    try {
      final resp =
          await client.get(Uri.parse('$base/v1/tts/health')).timeout(timeout);
      if (resp.statusCode != 200) {
        return HomeTurboHealth.unreachable('http_${resp.statusCode}');
      }
      final body = jsonDecode(resp.body);
      if (body is! Map) return const HomeTurboHealth.unreachable('bad_json');
      return HomeTurboHealth(
        reachable: true,
        modelLoaded: body['model_loaded'] == true,
        callerAuthorized: body['caller_authorized'] == true,
        gpuName: body['gpu_name'] as String?,
        lastError: body['last_error'] as String?,
      );
    } on TimeoutException {
      return const HomeTurboHealth.unreachable('timeout');
    } catch (e) {
      return HomeTurboHealth.unreachable(e.runtimeType.toString());
    } finally {
      client.close();
    }
  }

  /// 通话/语音会话开始时调用：服务能用就重置熔断，不能用就整段会话先不试。
  static Future<HomeTurboHealth> prepareForSession() async {
    final health = await checkHealth();
    if (health.usable) {
      breaker.reset();
    } else {
      breaker.trip();
    }
    _log.info('prepareForSession: ${health.summary}');
    return health;
  }

  // ── 合成 ────────────────────────────────────────────────────────────────

  /// 合成一段英文，返回 WAV 字节；失败、超时或熔断中返回 null。
  static Future<Uint8List?> trySynthesize(String text) async {
    final trimmed = text.trim();
    // Turbo 只会英文：含中日韩字符的句子直接交给 MiniMax，不算失败。
    if (trimmed.isEmpty || trimmed.length > maxChars || hasCjk(trimmed)) {
      return null;
    }
    if (breaker.isOpen) return null;
    final result = await synthesize(trimmed);
    if (result.audio != null) {
      breaker.recordSuccess();
    } else {
      breaker.recordFailure();
      _log.warning('synthesize failed: ${result.error}');
    }
    return result.audio;
  }

  /// 不经过熔断的一次请求，设置页的“测试连接”也用它。
  static Future<HomeTurboResult> synthesize(String text,
      {Duration? timeout}) async {
    final base = await resolveBaseUrl();
    if (base == null) return const HomeTurboResult.failed('no_url');
    final client = clientFactory();
    final sw = Stopwatch()..start();
    try {
      final resp = await client
          .post(
            Uri.parse('$base/v1/tts/speak'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(timeout ?? timeoutFor(text));
      if (resp.statusCode != 200) {
        String code = 'http_${resp.statusCode}';
        try {
          final body = jsonDecode(resp.body);
          if (body is Map && body['error'] is String) {
            code = '$code:${body['error']}';
          }
        } catch (_) {}
        return HomeTurboResult.failed(code);
      }
      final bytes = resp.bodyBytes;
      if (!isWav(bytes)) return const HomeTurboResult.failed('not_wav');
      return HomeTurboResult(
        audio: bytes,
        totalMs: sw.elapsedMilliseconds,
        genMs: int.tryParse(resp.headers['x-gen-ms'] ?? ''),
        audioMs: int.tryParse(resp.headers['x-audio-ms'] ?? ''),
      );
    } on TimeoutException {
      return const HomeTurboResult.failed('timeout');
    } catch (e) {
      return HomeTurboResult.failed(e.runtimeType.toString());
    } finally {
      client.close();
    }
  }

  /// 非流式入口（手动播放、语音提示）：合成成功写入缓存并返回路径，失败返回 null。
  static Future<String?> trySynthesizeToFile(String text) async {
    final key =
        sha256.convert(utf8.encode('$_cacheVersion:${text.trim()}')).toString();
    final path = '${await _cacheDir()}/$key.wav';
    if (await File(path).exists()) return path;
    final audio = await trySynthesize(text);
    if (audio == null) return null;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(audio, flush: true);
    return path;
  }

  static Future<String> _cacheDir() async {
    final dir = await FileSystemService.getAppSupportDir();
    return '${dir.path}/tts_cache_turbo';
  }

  static Future<void> clearCache() async {
    final dir = Directory(await _cacheDir());
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static final _cjk =
      RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]');

  static bool hasCjk(String text) => _cjk.hasMatch(text);

  static bool isWav(List<int> bytes) =>
      bytes.length > 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46; // F

  static Future<String?> _defaultKvRead(String key) async {
    final db = AppDatabase.instance;
    final row = await (db.select(db.kvStore)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  static Future<void> _defaultKvWrite(String key, String value) async {
    final db = AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.into(db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: key,
            value: Value(value),
            updatedAt: Value(now),
          ),
        );
  }
}

/// 连续失败 [maxConsecutiveFailures] 次后熔断 [openFor]，期间直接走回退。
class HomeTurboBreaker {
  HomeTurboBreaker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const maxConsecutiveFailures = 3;
  static const openFor = Duration(minutes: 10);

  final DateTime Function() _now;
  int _failures = 0;
  DateTime? _openUntil;

  int get consecutiveFailures => _failures;

  bool get isOpen {
    final until = _openUntil;
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _openUntil = null;
    _failures = 0;
    return false;
  }

  void recordSuccess() => _failures = 0;

  void recordFailure() {
    _failures++;
    if (_failures >= maxConsecutiveFailures) trip();
  }

  void trip() => _openUntil = _now().add(openFor);

  void reset() {
    _failures = 0;
    _openUntil = null;
  }
}

class HomeTurboHealth {
  const HomeTurboHealth({
    required this.reachable,
    required this.modelLoaded,
    required this.callerAuthorized,
    this.gpuName,
    this.lastError,
    this.error,
  });

  const HomeTurboHealth.unreachable(String this.error)
      : reachable = false,
        modelLoaded = false,
        callerAuthorized = false,
        gpuName = null,
        lastError = null;

  final bool reachable;
  final bool modelLoaded;
  final bool callerAuthorized;
  final String? gpuName;
  final String? lastError;
  final String? error;

  bool get usable => reachable && modelLoaded && callerAuthorized;

  String get summary {
    if (!reachable) return '连不上（${error ?? 'unknown'}）';
    if (!callerAuthorized) return '已连上，但这台手机的 Tailscale 账号不在放行名单里';
    if (!modelLoaded) {
      return lastError != null ? '模型加载失败（$lastError）' : '模型还在加载';
    }
    return '可用${gpuName != null ? '（$gpuName）' : ''}';
  }
}

class HomeTurboResult {
  const HomeTurboResult({
    required Uint8List this.audio,
    required this.totalMs,
    this.genMs,
    this.audioMs,
  }) : error = null;

  const HomeTurboResult.failed(String this.error)
      : audio = null,
        totalMs = null,
        genMs = null,
        audioMs = null;

  final Uint8List? audio;
  final int? totalMs;
  final int? genMs;
  final int? audioMs;
  final String? error;
}
