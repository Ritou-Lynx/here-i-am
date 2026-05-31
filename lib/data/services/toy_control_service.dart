import 'package:memex/data/services/buttplug_toy_controller.dart';
import 'package:memex/data/services/lovense_toy_controller.dart';
import 'package:memex/data/services/toy_controller.dart';

export 'package:memex/data/services/toy_controller.dart'
    show ToyController, ToyConfig, ToyProtocol, ToyPattern;

/// Factory that builds the right [ToyController] from persisted config.
class ToyControlService {
  ToyControlService._();

  /// Load config from SharedPreferences and return the appropriate controller.
  /// Returns null if no URL has been configured yet.
  static Future<ToyController?> fromPrefs() async {
    final config = await ToyConfig.load();
    if (config == null) return null;
    return _build(config);
  }

  static ToyController _build(ToyConfig config) {
    switch (config.protocol) {
      case ToyProtocol.buttplug:
        return ButtplugToyController(wsUrl: config.url);
      case ToyProtocol.lovense:
        return LovenseToyController(apiUrl: config.url);
    }
  }
}
