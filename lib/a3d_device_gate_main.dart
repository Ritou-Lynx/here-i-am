import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/services/activity/mda2_android/activity_integrity_key_repository.dart';
import 'data/services/activity/mda2_android/android_activity_signal_platform.dart';
import 'ui/a3d_device_gate/a3d_device_gate_controller.dart';
import 'ui/a3d_device_gate/a3d_device_gate_screen.dart';
import 'ui/a3d_device_gate/a3d_timing_probe.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'hereIAmV3') {
    runApp(const A3dDeviceGateUnavailableApp());
    return;
  }

  final timing = A3dTimingProbe();
  final platform = A3dTimingSignalPlatform(
    MethodChannelAndroidActivitySignalPlatform(),
    timing,
  );
  final controller = A3dDeviceGateController(
    keyRepository: ActivityIntegrityKeyRepository(
      storage: FlutterSecureActivityIntegrityStorage(),
    ),
    platform: platform,
    timingProbe: timing,
    clockMs: () => DateTime.now().millisecondsSinceEpoch,
    // The product application id is used only for the native in-memory
    // package-to-coarse-category lookup. It is never shown or exported.
    categoryMapping: const {'com.memexlab.hereiam.v3': 'other'},
  );
  // Read-only and registered only after the Debug + flavor guard. Arming,
  // recording and native actions remain explicit UI actions.
  developer.registerExtension('ext.a3d.readTimingTrace',
      (_, parameters) => readTimingTraceExtension(controller, parameters));
  runApp(A3dDeviceGateApp(controller: controller));
}

/// Read-only transport handler; registration remains inside the guarded entry.
Future<developer.ServiceExtensionResponse> readTimingTraceExtension(
  A3dDeviceGateController controller,
  Map<String, String> parameters,
) async {
  // isolateId is VM routing metadata, never an action or trace field.
  if (parameters.keys.any((key) => key != 'isolateId')) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.invalidParams,
      jsonEncode(const {'code': 'no_action_parameters'}),
    );
  }
  return developer.ServiceExtensionResponse.result(
    jsonEncode(controller.readTimingTrace()),
  );
}
