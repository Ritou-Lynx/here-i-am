import 'package:memex/data/services/buttplug_toy_controller.dart';
import 'package:memex/data/services/lovense_toy_controller.dart';
import 'package:memex/data/services/magic_motion_flamingo_controller.dart';
import 'package:memex/data/services/svakom_toy_controller.dart';
import 'package:memex/data/services/toy_controller.dart';

export 'package:memex/data/services/toy_controller.dart'
    show ToyController, ToyConfig, ToyProtocol, ToyPattern;

/// Factory: builds the right [ToyController] from persisted config.
///
/// Priority order:
///   1. Svakom direct BLE (if device saved)
///   2. Magic Motion Flamingo Max direct BLE (if device saved)
///   3. Buttplug/Lovense URL-based (if config saved and autoConnect=true)
class ToyControlService {
  ToyControlService._();

  static Future<ToyController?> fromPrefs() async {
    // 1. Svakom direct BLE
    final svakomDevice = await loadSvakomDevice();
    if (svakomDevice != null) {
      return SvakomToyController(
        deviceId: svakomDevice.id,
        deviceName: svakomDevice.name,
      );
    }

    // 2. Magic Motion Flamingo Max direct BLE
    final flamingoDevice = await loadFlamingoDevice();
    if (flamingoDevice != null) {
      return MagicMotionFlamingoController(
        deviceId: flamingoDevice.id,
        deviceName: flamingoDevice.name,
      );
    }

    // 3. URL-based (Buttplug / Lovense)
    final config = await ToyConfig.load();
    if (config == null) return null;
    if (!config.autoConnect) return null;
    return switch (config.protocol) {
      ToyProtocol.buttplug    => ButtplugToyController(wsUrl: config.url),
      ToyProtocol.lovense     => LovenseToyController(apiUrl: config.url),
      ToyProtocol.magicMotion => null,
      ToyProtocol.svakom      => null,
    };
  }
}
