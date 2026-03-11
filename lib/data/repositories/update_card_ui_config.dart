import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/data/services/file_system_service.dart';

final _logger = getLogger('UpdateCardUiConfigEndpoint');
final _fileSystemService = FileSystemService.instance;

/// Update card UI config data
///
/// Args:
///   cardId: card ID (fact_id)
///   configIndex: index in ui_configs list
///   updates: map to merge
///
/// Returns:
///   bool: success
Future<bool> updateCardUiConfigEndpoint(
    String cardId, int configIndex, Map<String, dynamic> updates) async {
  _logger.info(
      'updateCardUiConfig called: cardId=$cardId, index=$configIndex, updates=$updates');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      throw Exception('User not logged in, cannot update card config');
    }

    // Use updateCardFile for ui_configs, concurrency-safe
    final updatedCardData = await _fileSystemService.updateCardFile(
      userId,
      cardId,
      (card) {
        if (card.uiConfigs.isEmpty) {
          throw Exception('No ui_configs found in card $cardId');
        }
        if (configIndex < 0 || configIndex >= card.uiConfigs.length) {
          throw Exception('Config index out of bounds: $configIndex');
        }
        final target = card.uiConfigs[configIndex];
        final newData = {...target.data, ...updates};
        final updatedList = card.uiConfigs.toList();
        updatedList[configIndex] =
            UiConfig(templateId: target.templateId, data: newData);
        return card.copyWith(uiConfigs: updatedList);
      },
    );

    if (updatedCardData == null) {
      _logger.warning('Card not found: $cardId');
      return false;
    }

    _logger.info('Updated ui_config at index $configIndex for $cardId');
    return true;
  } catch (e) {
    _logger.severe('Failed to update card ui config for $cardId: $e');
    return false;
  }
}
