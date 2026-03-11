import 'package:logging/logging.dart';
import 'package:memex/data/services/auto_input/data_collector_interface.dart';
import 'package:memex/data/services/auto_input/collectors/photo_collector.dart';
import 'package:memex/data/repositories/memex_router.dart';

class AutoInputManager {
  static final Logger _logger = Logger('AutoInputManager');

  static final List<DataCollector> _collectors = [
    PhotoCollector(),
    // Add CalendarCollector, AudioCollector, NoteCollector here in the future
  ];

  static Future<int> checkUnprocessedCount() async {
    _logger.info('Checking for unprocessed AutoInput items...');
    final List<Map<String, dynamic>> allItems = [];

    for (final collector in _collectors) {
      try {
        final items = await collector.collect();
        allItems.addAll(items);
      } catch (e, stack) {
        _logger.severe(
            'Collector ${collector.sourceName} failed during check: $e',
            e,
            stack);
      }
    }

    if (allItems.isEmpty) return 0;

    final hashesToCheck = allItems
        .map((item) => item['client_hash'] as String?)
        .where((hash) => hash != null)
        .cast<String>()
        .toList();

    List<String> unprocessedHashes = [];
    if (hashesToCheck.isNotEmpty) {
      try {
        unprocessedHashes =
            await MemexRouter().checkProcessedHashes(hashesToCheck);
      } catch (e) {
        // Fallback: assume all are unprocessed
        unprocessedHashes = List.from(hashesToCheck);
      }
    }

    final unprocessedSet = unprocessedHashes.toSet();
    final count = allItems.where((item) {
      final hash = item['client_hash'] as String?;
      if (hash == null) return true;
      return unprocessedSet.contains(hash);
    }).length;

    _logger.info('Found $count unprocessed AutoInput items.');
    return count;
  }

  static Future<void> collectAndSubmitAll() async {
    _logger.info('Starting AutoInput collection cycle...');

    final List<Map<String, dynamic>> allItems = [];

    // 1. Collect from all sources
    for (final collector in _collectors) {
      try {
        final items = await collector.collect();
        _logger.info(
            'Collector ${collector.sourceName} yielded ${items.length} items.');
        allItems.addAll(items);
      } catch (e, stack) {
        _logger.severe(
            'Collector ${collector.sourceName} failed: $e', e, stack);
      }
    }

    if (allItems.isEmpty) {
      _logger.info('No new items collected from any source.');
      return;
    }

    // 2. Filter out already processed hashes
    final hashesToCheck = allItems
        .map((item) => item['client_hash'] as String?)
        .where((hash) => hash != null)
        .cast<String>()
        .toList();

    _logger.info(
        'Checking ${hashesToCheck.length} hashes against processed history...');

    List<String> unprocessedHashes = [];
    if (hashesToCheck.isNotEmpty) {
      try {
        unprocessedHashes =
            await MemexRouter().checkProcessedHashes(hashesToCheck);
      } catch (e) {
        _logger.warning(
            'Failed to check processed hashes, assuming all are unprocessed. Error: $e');
        unprocessedHashes = List.from(hashesToCheck);
      }
    }

    final unprocessedSet = unprocessedHashes.toSet();

    // 3. Keep only unprocessed items
    final finalItemsToSubmit = allItems.where((item) {
      final hash = item['client_hash'] as String?;
      if (hash == null) {
        return true; // Items without hash are always submitted (though we enforce hashes above)
      }
      return unprocessedSet.contains(hash);
    }).toList();

    if (finalItemsToSubmit.isEmpty) {
      _logger.info(
          'All collected items were already processed previously. Skipping submission.');
      return;
    }

    _logger.info(
        'Preparing to submit ${finalItemsToSubmit.length} new unprocessed items to auto_input.');
  }
}
