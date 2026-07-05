import 'package:geolocator/geolocator.dart';
import 'package:memex/data/services/geocoding_service.dart';
import 'package:memex/domain/models/location_context_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

class LocationContextService {
  static final LocationContextService instance =
      LocationContextService._internal();
  LocationContextService._internal();

  static const Duration _maxLastKnownPositionAge = Duration(minutes: 2);
  static const Duration _maxDiagnosticLastKnownPositionAge = Duration(hours: 6);

  final _logger = getLogger('LocationContextService');
  CurrentLocationContext? _cachedContext;
  String? _cachedConfigSignature;

  /// Device GPS is the only source for current location.
  /// IP-based fallback is intentionally not used because proxy/VPN/network
  /// routing can make it misleading for agent context.
  Future<CurrentLocationContext> getCurrentContext({
    bool forceRefresh = false,
    bool ignoreEnabled = false,
  }) async {
    final config = await UserStorage.getLocationContextConfig();
    final now = DateTime.now();
    final configSignature = _configSignature(
      config,
      ignoreEnabled: ignoreEnabled,
    );

    if (!config.enabled && !ignoreEnabled) {
      return CurrentLocationContext(
        status: 'disabled',
        source: 'device_gps',
        updatedAt: now,
        granularity: config.granularity,
        reason: 'location context is disabled in settings',
      );
    }

    final ttl = Duration(minutes: config.ttlMinutes.clamp(1, 1440));
    final cached = _cachedContext;
    if (!forceRefresh &&
        cached != null &&
        _cachedConfigSignature == configSignature &&
        now.difference(cached.updatedAt) <= _cacheWindow(cached, ttl)) {
      return cached;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _unavailable(
          config,
          configSignature,
          'location service is disabled',
          status: 'unavailable',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return _unavailable(
          config,
          configSignature,
          'location permission denied',
          status: 'unavailable',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        return _unavailable(
          config,
          configSignature,
          'location permission permanently denied',
          status: 'unavailable',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: ignoreEnabled
              ? const Duration(seconds: 20)
              : const Duration(seconds: 8),
        ),
      );

      final geocodeResult =
          await GeocodingService.instance.reverseGeocodeWithStatus(
        position.latitude,
        position.longitude,
        config: config,
        timeout: const Duration(seconds: 4),
      );
      final address = geocodeResult.address;

      final context = CurrentLocationContext(
        status: 'fresh',
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        source: address == null ? 'device_gps' : 'device_gps + reverse_geocode',
        updatedAt: now,
        address: address,
        granularity: config.granularity,
        reason: address == null
            ? 'reverse geocode unavailable (${geocodeResult.provider.name}): ${geocodeResult.reason ?? geocodeResult.status}'
            : geocodeResult.reason,
      );
      _remember(context, configSignature);
      return context;
    } catch (e) {
      _logger.warning('Failed to build current location context: $e');
      final failureReason = 'failed to get current device location: $e';
      final lastKnown = await _tryLastKnownPosition(
        config,
        configSignature,
        maxAge: ignoreEnabled
            ? _maxDiagnosticLastKnownPositionAge
            : _maxLastKnownPositionAge,
        currentLookupFailureReason: failureReason,
      );
      if (lastKnown != null) {
        return lastKnown;
      }
      return _unavailable(
        config,
        configSignature,
        failureReason,
        status: 'unavailable',
      );
    }
  }

  Future<CurrentLocationContext?> _tryLastKnownPosition(
    LocationContextConfig config,
    String configSignature, {
    Duration maxAge = _maxLastKnownPositionAge,
    String? currentLookupFailureReason,
  }) async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      final now = DateTime.now();
      final age = now.difference(position.timestamp);
      if (age > maxAge) {
        _logger.info(
          'Skipping stale last known location from ${position.timestamp.toIso8601String()}',
        );
        return null;
      }
      final isFreshEnough = age <= _maxLastKnownPositionAge;
      final geocodeResult =
          await GeocodingService.instance.reverseGeocodeWithStatus(
        position.latitude,
        position.longitude,
        config: config,
        timeout: const Duration(seconds: 4),
      );
      final address = geocodeResult.address;
      final context = CurrentLocationContext(
        status: isFreshEnough ? 'fresh' : 'stale',
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        source: address == null
            ? 'last_known_device_gps'
            : 'last_known_device_gps + reverse_geocode',
        updatedAt: now,
        address: address,
        granularity: config.granularity,
        reason: [
          if (isFreshEnough)
            'using recent last known device location after current lookup failed'
          else
            'using stale last known device location for diagnostics; age: ${age.inMinutes} minutes',
          if (currentLookupFailureReason != null) currentLookupFailureReason,
          if (address == null)
            'reverse geocode unavailable (${geocodeResult.provider.name}): ${geocodeResult.reason ?? geocodeResult.status}',
          if (address != null && geocodeResult.reason != null)
            geocodeResult.reason!,
        ].join('; '),
      );
      _remember(context, configSignature);
      return context;
    } catch (e) {
      _logger.warning('Failed to use last known location: $e');
      return null;
    }
  }

  CurrentLocationContext _unavailable(
    LocationContextConfig config,
    String configSignature,
    String reason, {
    required String status,
  }) {
    final context = CurrentLocationContext(
      status: status,
      source: 'device_gps',
      updatedAt: DateTime.now(),
      granularity: config.granularity,
      reason: reason,
    );
    _remember(context, configSignature);
    return context;
  }

  Duration _cacheWindow(CurrentLocationContext context, Duration freshTtl) {
    if (context.isFresh && context.address == null) {
      return const Duration(minutes: 2);
    }
    if (context.isFresh) return freshTtl;
    return const Duration(minutes: 2);
  }

  String _configSignature(
    LocationContextConfig config, {
    required bool ignoreEnabled,
  }) {
    return [
      config.enabled,
      ignoreEnabled,
      config.provider.name,
      config.amapApiKey.hashCode,
      config.granularity.name,
      config.ttlMinutes,
    ].join('|');
  }

  void _remember(CurrentLocationContext context, String configSignature) {
    _cachedContext = context;
    _cachedConfigSignature = configSignature;
  }
}
