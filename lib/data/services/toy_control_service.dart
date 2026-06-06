import 'package:memex/data/services/buttplug_toy_controller.dart';
import 'package:memex/data/services/lovense_toy_controller.dart';
import 'package:memex/data/services/toy_controller.dart';

export 'package:memex/data/services/toy_controller.dart'
    show ToyController, ToyConfig, ToyProtocol, ToyPattern;

/// Factory: builds the right [ToyController] from persisted config.
class ToyControlService {
  ToyControlService._();

  static Future<ToyController?> fromPrefs() async {
    final config = await ToyConfig.load();
    if (config == null) return null;
    if (!config.autoConnect) return null;
    return switch (config.protocol) {
      ToyProtocol.buttplug => ButtplugToyController(wsUrl: config.url),
      ToyProtocol.lovense => LovenseToyController(apiUrl: config.url),
      ToyProtocol.magicMotion => null,
    };
  }
}
