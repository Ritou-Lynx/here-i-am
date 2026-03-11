import 'package:path/path.dart' as path;
import 'package:memex/domain/models/calendar_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/file_system_service.dart';

final _logger = getLogger('GetCalendarDataEndpoint');

/// Get calendar data
/// Maps to backend GET /cards/calendar
Future<List<CalendarDay>> getCalendarData(
  int fromTimestamp,
  int toTimestamp,
) async {
  _logger.info(
      'getCalendarData called: fromTimestamp=$fromTimestamp, toTimestamp=$toTimestamp');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _logger.warning('No user ID found, returning empty calendar data');
      return [];
    }

    final fileSystemService = FileSystemService.instance;

    // Convert timestamps to dates
    final startDate =
        DateTime.fromMillisecondsSinceEpoch(fromTimestamp * 1000, isUtc: true);
    final endDate =
        DateTime.fromMillisecondsSinceEpoch(toTimestamp * 1000, isUtc: true);

    // Use FileSystemService to find files in range
    final cardFiles = await fileSystemService.getCardFilesInDateRange(
      userId,
      DateTime(startDate.year, startDate.month, startDate.day),
      DateTime(endDate.year, endDate.month, endDate.day),
    );

    // Group data by date
    final dailyData = <int, List<CalendarCard>>{};

    // Init container per day (ensure empty list even when no cards)
    var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final endDateTime = DateTime(endDate.year, endDate.month, endDate.day);
    while (currentDate.isBefore(endDateTime) ||
        currentDate.isAtSameMomentAs(endDateTime)) {
      // Day start timestamp (00:00:00)
      final dayStart =
          DateTime(currentDate.year, currentDate.month, currentDate.day);
      final ts = dayStart.millisecondsSinceEpoch ~/ 1000;
      dailyData[ts] = [];
      currentDate = currentDate.add(const Duration(days: 1));
    }

    // Process card files
    for (final cardFile in cardFiles) {
      try {
        // Parse fact_id from path
        // Path format: Cards/YYYY/MM/DD_ts_X.yaml
        final parts = path.split(cardFile);
        if (parts.length < 3) {
          continue;
        }
        final year = parts[parts.length - 3];
        final month = parts[parts.length - 2];
        final dayTsFile = parts[parts.length - 1];
        final dayTs = dayTsFile.replaceAll('.yaml', '');
        final dayTsParts = dayTs.split('_');
        if (dayTsParts.length < 2) {
          continue;
        }
        final day = dayTsParts[0];
        final tsPart = dayTsParts.sublist(1).join('_');
        final factId = '$year/$month/$day.md#$tsPart';

        // Read card data
        final cardData = await fileSystemService.readCardFile(userId, factId);
        if (cardData == null) {
          continue;
        }

        if (cardData.deleted == true) {
          continue;
        }

        var ts = cardData.userFixedTimestamp ?? cardData.timestamp;

        // Assign to day by ts
        final cardDt =
            DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
        final dayStartDt = DateTime(cardDt.year, cardDt.month, cardDt.day);
        final dayStartTs = dayStartDt.millisecondsSinceEpoch ~/ 1000;

        if (dailyData.containsKey(dayStartTs)) {
          final location = cardData.userFixedAddress ??
              cardData.userFixedLocation?.name ??
              cardData.address ??
              '';

          final calCard = CalendarCard(
            id: factId,
            timestamp: ts,
            title: cardData.title ?? 'Untitled',
            tags: List<String>.from(cardData.tags),
            location: location,
          );
          dailyData[dayStartTs]!.add(calCard);
        }
      } catch (e) {
        _logger.warning('Error processing card file $cardFile: $e');
        continue;
      }
    }

    // Build result list
    final result = <CalendarDay>[];

    // Sort by time
    final sortedDays = dailyData.keys.toList()..sort();

    for (final dayTs in sortedDays) {
      final cards = dailyData[dayTs]!;
      // Sort day's cards by time
      cards.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      result.add(CalendarDay(
        timestamp: dayTs,
        cards: cards,
        total: cards.length,
      ));
    }

    return result;
  } catch (e) {
    _logger.severe('Failed to get calendar data: $e');
    return [];
  }
}
