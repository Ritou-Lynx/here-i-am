import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:memex/data/services/toy_controller.dart';
import 'package:memex/utils/logger.dart';

/// Lovense Connect Local API (same-device HTTP).
///
/// Lovense app must be running with Local API enabled.
/// Settings → About → Local API → copy the base URL (e.g. http://127.0.0.1:20010).
class LovenseToyController implements ToyController {
  final _log = getLogger('LovenseToyController');
  final String apiUrl;
  final Dio _dio;

  Timer? _patternTimer;

  LovenseToyController({required this.apiUrl})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ));

  @override
  bool get isReady => apiUrl.isNotEmpty;

  @override
  Future<bool> ensureReady({
    Duration timeout = const Duration(seconds: 8),
  }) async =>
      isReady;

  Future<bool> _send(String action, {int timeSec = 0}) async {
    try {
      final resp = await _dio.post(
        '$apiUrl/v2/SendLocalCommand',
        data: jsonEncode({
          'command': 'Function',
          'action': action,
          'timeSec': timeSec,
          'toy': '',
          'apiVer': 1,
        }),
        options: Options(contentType: 'application/json'),
      );
      final code = (resp.data is Map) ? resp.data['code'] : 200;
      return code == 200;
    } catch (e) {
      _log.warning('Lovense send failed: $e');
      return false;
    }
  }

  @override
  Future<bool> vibrate(int intensity, {int durationSeconds = 0}) {
    _cancelPattern();
    return _send('Vibrate:${intensity.clamp(0, 20)}', timeSec: durationSeconds);
  }

  @override
  Future<bool> stop() {
    _cancelPattern();
    return _send('Vibrate:0');
  }

  @override
  Future<String> playPattern(ToyPattern pattern, int peakIntensity) async {
    _cancelPattern();
    final peak = peakIntensity.clamp(1, 20);
    switch (pattern) {
      case ToyPattern.steady:
        await vibrate(peak);
        return 'steady vibration at intensity $peak';
      case ToyPattern.wave:
        return _startWave(peak);
      case ToyPattern.pulse:
        return _startPulse(peak);
      case ToyPattern.escalate:
        return _startEscalate(peak);
      case ToyPattern.tease:
        return _startTease(peak);
    }
  }

  String _startWave(int peak) {
    int step = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 300), (_) async {
      final t = (step % 20) / 20.0;
      final level =
          (peak * (0.5 - 0.5 * (2 * t - 1).abs() + 0.5)).round().clamp(0, 20);
      await _send('Vibrate:$level');
      step++;
    });
    return 'gentle wave pattern peaking at intensity $peak';
  }

  String _startPulse(int peak) {
    bool on = false;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) async {
      on = !on;
      await _send(on ? 'Vibrate:$peak' : 'Vibrate:0');
    });
    return 'rhythmic pulse at intensity $peak';
  }

  String _startEscalate(int peak) {
    int current = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      current = (current + 1).clamp(0, peak);
      await _send('Vibrate:$current');
      if (current >= peak) _cancelPattern();
    });
    return 'slow escalation up to intensity $peak';
  }

  String _startTease(int peak) {
    int tick = 0;
    _patternTimer =
        Timer.periodic(const Duration(milliseconds: 350), (_) async {
      await _send((tick % 5) < 2 ? 'Vibrate:$peak' : 'Vibrate:0');
      tick++;
    });
    return 'teasing bursts at intensity $peak';
  }

  void _cancelPattern() {
    _patternTimer?.cancel();
    _patternTimer = null;
  }

  @override
  void dispose() {
    _cancelPattern();
    _dio.close();
  }
}
