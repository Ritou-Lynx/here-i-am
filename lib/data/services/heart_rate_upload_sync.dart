import 'package:memex/data/services/ble_heart_rate_gateway.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';

/// HR1: tell the native heart-rate service where the home computer is.
/// The address is derived from the Core sync address (same computer, port
/// 8447); with no HTTPS Core address the derived value is cleared. Never
/// throws: syncing heart rate is optional.
Future<void> syncHeartRateUploadTarget({
  BleHeartRateGateway? gateway,
  Future<String?> Function()? readCoreBaseUrl,
}) async {
  try {
    final coreBase = readCoreBaseUrl != null
        ? await readCoreBaseUrl()
        : (await CoreSyncConnectionStore.instance.read())?.baseUrl;
    await (gateway ?? BleHeartRateGateway.instance).configureUpload(
      derivedUrl: heartRateUploadBaseFromCore(coreBase) ?? '',
    );
  } catch (_) {
    // Heart-rate sync stays on its last known address.
  }
}
