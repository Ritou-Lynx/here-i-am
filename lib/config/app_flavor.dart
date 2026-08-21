/// App flavor configuration.
///
/// Flavor is determined by the `--flavor` flag passed to `flutter run` / `flutter build`.
/// On Android, the flavor name comes from Gradle productFlavors.
/// On iOS, it comes from the Xcode scheme name.
///
/// Usage:
///   flutter run --flavor global
///   flutter run --flavor cn
///   flutter run --flavor globalEarly
///   flutter run --flavor cnEarly
///   flutter run --flavor globalDev
///   flutter run --flavor cnDev
///   flutter run --flavor hereIAmDev
///   flutter run --flavor hereIAmV3
enum AppFlavorType { global, cn }

enum AppChannelType { stable, early, dev }

class AppFlavor {
  AppFlavor._();

  static AppFlavorType _current = AppFlavorType.global;
  static AppChannelType _channel = AppChannelType.stable;
  static bool _isHereIAm = false;

  static AppFlavorType get current => _current;
  static AppChannelType get channel => _channel;

  static bool get isGlobal => _current == AppFlavorType.global;
  static bool get isCN => _current == AppFlavorType.cn;
  static bool get isStable => _channel == AppChannelType.stable;
  static bool get isEarly => _channel == AppChannelType.early;
  static bool get isDev => _channel == AppChannelType.dev;
  static bool get isHereIAm => _isHereIAm;
  static String get name => switch ((_current, _channel)) {
        (AppFlavorType.cn, AppChannelType.dev) => 'cnDev',
        (AppFlavorType.global, AppChannelType.dev) => 'globalDev',
        (AppFlavorType.cn, AppChannelType.early) => 'cnEarly',
        (AppFlavorType.global, AppChannelType.early) => 'globalEarly',
        (AppFlavorType.cn, AppChannelType.stable) => 'cn',
        _ => 'global',
      };

  /// Call once at app startup with the flavor string from `appFlavor`.
  ///
  /// Flutter desktop builds do not expose a native flavor unless one is
  /// supplied as a Dart define. Here I am owns the desktop application, so
  /// its startup path may opt into the V3 identity when that value is absent.
  /// Explicit flavors always win.
  static void init(String? flavor, {bool defaultToHereIAm = false}) {
    final effectiveFlavor =
        flavor ?? (defaultToHereIAm ? 'hereIAmV3' : '');
    final normalized = effectiveFlavor.toLowerCase();
    _isHereIAm = normalized == 'hereiamdev' || normalized == 'hereiamv3';
    if (normalized.startsWith('cn')) {
      _current = AppFlavorType.cn;
    } else {
      _current = AppFlavorType.global;
    }

    if (normalized.contains('dev') || normalized == 'hereiamv3') {
      _channel = AppChannelType.dev;
    } else if (normalized.contains('early')) {
      _channel = AppChannelType.early;
    } else {
      _channel = AppChannelType.stable;
    }
  }
}
