import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/data/services/ble_heart_rate_gateway.dart';

const _freshSampleWindow = Duration(seconds: 15);

Tool buildLiveHeartRateSnapshotTool({
  required String userId,
  BleHeartRateGateway? gateway,
  DateTime Function()? now,
}) {
  final heartRateGateway = gateway ?? BleHeartRateGateway.instance;
  final clock = now ?? DateTime.now;
  return Tool(
    name: 'LiveHeartRateSnapshot',
    description: '''Read the user's latest local BLE heart-rate snapshot.
Use once when current heart rate or live sensor availability matters. Only a
successful response contains a fresh BPM. Never infer sleep, wakefulness,
anxiety, diagnosis, or a need to call from one heart-rate sample.''',
    parameters: const {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> args) async {
      if (userId.trim().isEmpty) {
        return jsonEncode({
          'success': false,
          'status': 'unavailable',
          'reason': 'user_required',
        });
      }

      try {
        final snapshot = await heartRateGateway.getSnapshot(userId);
        final sample = snapshot.lastSample;
        final currentTime = clock();
        final age =
            sample == null ? null : currentTime.difference(sample.timestamp);
        final fresh = snapshot.configured &&
            snapshot.enabled &&
            snapshot.status == BleHeartRateStatus.live &&
            sample != null &&
            sample.bpm > 0 &&
            age != null &&
            !age.isNegative &&
            age <= _freshSampleWindow;

        if (!fresh) {
          return jsonEncode({
            'success': false,
            'status': snapshot.status == BleHeartRateStatus.live
                ? BleHeartRateStatus.stale.name
                : snapshot.status.name,
            'reason': _unavailableReason(snapshot, sample, age),
            'configured': snapshot.configured,
            'enabled': snapshot.enabled,
            if (snapshot.deviceName != null) 'device_name': snapshot.deviceName,
          });
        }

        return jsonEncode({
          'success': true,
          'status': 'live',
          'source': 'local_ble_heart_rate',
          'device_name': snapshot.deviceName,
          'bpm': sample.bpm,
          'timestamp': sample.timestamp.toIso8601String(),
          'age_ms': age.inMilliseconds,
          'rr_present': sample.rrIntervalsSeconds.isNotEmpty,
          if (sample.rrIntervalsSeconds.isNotEmpty)
            'rr_intervals_seconds': sample.rrIntervalsSeconds,
          'contact': {
            'supported': sample.contactSupported,
            if (sample.contactSupported) 'detected': sample.contactDetected,
          },
          'interpretation': 'raw_sensor_sample_only',
          'sleep_inference': 'not_supported_from_single_sample',
        });
      } catch (_) {
        return jsonEncode({
          'success': false,
          'status': 'unavailable',
          'reason': 'query_failed',
        });
      }
    },
  );
}

String _unavailableReason(
  BleHeartRateSnapshot snapshot,
  BleHeartRateSample? sample,
  Duration? age,
) {
  if (!snapshot.configured) return 'not_configured';
  if (!snapshot.enabled) return 'not_enabled';
  if (snapshot.status != BleHeartRateStatus.live) {
    return snapshot.reason ?? 'no_fresh_live_sample';
  }
  if (sample == null || sample.bpm <= 0) return 'sample_unavailable';
  if (age == null || age.isNegative) return 'invalid_sample_time';
  return 'sample_stale';
}
