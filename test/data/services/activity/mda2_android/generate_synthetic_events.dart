import 'dart:convert';
import 'dart:io';

// Direct Dart execution needs no application dependency resolution.
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_normalizer.dart';

/// Test-only stdin/stdout bridge. Input is stripped synthetic pairing metadata
/// from verify_wire.mjs; never credentials, a device query or a network call.
Future<void> main() async {
  final profiles =
      (jsonDecode(await stdin.transform(utf8.decoder).join()) as List)
          .cast<Map<String, dynamic>>();
  final events = <Map<String, Object?>>[];
  for (final profile in profiles) {
    var now = 2000000;
    final usage = profile['source'] == 'android_usage_events';
    final binding = SyntheticProbeBinding(
      deviceId: profile['device_id'] as String,
      probeId: profile['probe_id'] as String,
      serverIssuedPrefix: profile['event_id_prefix'] as String,
      source: usage
          ? AndroidActivitySource.usageEvents
          : AndroidActivitySource.screenState,
      reportIntervalMs: profile['expected_report_interval_ms'] as int,
      expirySloMs: profile['expiry_slo_ms'] as int,
      coverageMode: profile['coverage_mode'] as String,
      allowedKinds: (profile['allowed_kinds'] as List).cast<String>().toSet(),
      capabilities: (profile['capabilities'] as List).cast<String>().toSet(),
    );
    final outbox = MemoryActivityOutbox.forSyntheticPairing(binding);
    final collector = AndroidActivityNormalizer(
      outbox: outbox,
      clockMs: () => now,
      ttlMs: 300000,
    );
    void permission(String state) =>
        collector.acceptSynthetic({'type': 'usage_permission', 'state': state});
    void category(String value, {int? at}) => collector.acceptSynthetic({
      'type': 'usage_category',
      'category': value,
      'signal_at_ms': at ?? now,
    });
    void screen(String type, {int? at}) =>
        collector.acceptSynthetic({'type': type, 'signal_at_ms': at ?? now});
    if (usage) {
      permission('denied');
      category('chat'); // suppressed
      now += 10;
      permission('granted');
      for (final value in [
        'chat',
        'social',
        'video',
        'reading',
        'work',
        'other',
      ]) {
        now += 10;
        category(value);
      }
      now += 10;
      permission('revoked');
      category('work'); // suppressed
      now += 10;
      permission('granted');
      category('chat', at: now - 5); // gap history suppressed
      now += 10;
      category('reading');
    } else {
      screen('screen_interactive');
      now += 10;
      screen('user_present');
      now += 10;
      screen('screen_non_interactive');
    }
    now += 10;
    collector.markCollectionGap();
    now += 10;
    collector.heartbeat(); // does not recover collection
    if (usage) {
      category('work', at: now - 15); // gap history suppressed
      now += 10;
      category('work');
    } else {
      screen('user_present', at: now - 15); // gap history suppressed
      now += 10;
      screen('screen_interactive');
    }
    events.addAll(outbox.records.map((r) => r.event.toJson()));
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'synthetic_only': true,
      'origin':
          'existing ActivityControlPlane.pairProbe with deterministic test prefix factory; Dart normalizer output',
      'registrations': profiles,
      'events': events,
    }),
  );
}
