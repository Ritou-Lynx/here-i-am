import 'package:memex/data/services/system_action_service.dart';
import 'package:memex/data/services/clarification_request_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/table_change_notifier.dart';
import 'package:memex/ui/card_attachments/card_attachment_data.dart';

/// Attachment type constants.
class CardAttachmentType {
  static const systemAction = 'system_action';
  static const clarificationRequest = 'clarification_request';
}

/// Aggregates all attachment data sources for a given factId into a single
/// sorted list.
///
/// Data flow:
/// 1. Initial load: called during timeline card list fetch.
/// 2. Incremental updates: [init] registers table-change watchers that emit
///    [AttachmentsChangedMessage] via EventBus. ViewModel listens and
///    re-fetches only the affected cards.
class CardAttachmentService {
  CardAttachmentService._();
  static final instance = CardAttachmentService._();

  /// Register table-change watchers. Call once after [TableChangeNotifier.init].
  void init() {
    final notifier = TableChangeNotifier.instance;
    notifier.watch('system_actions', (_) => _emitChanged());
    notifier.watch('clarification_requests', (_) => _emitChanged());
  }

  void _emitChanged() {
    EventBusService.instance.emitEvent(AttachmentsChangedMessage());
  }

  /// Fetches all pending attachments (for the action center / notification badge).
  Future<List<CardAttachmentData>> getPendingAttachments() async {
    final results = await Future.wait([
      _getPendingSystemActions(),
      _getPendingClarificationRequests(),
    ]);
    final merged = results.expand((e) => e).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return merged;
  }

  /// Fetches all attachments for a single [factId], sorted by [sortKey].
  Future<List<CardAttachmentData>> getAttachments(String factId) async {
    final results = await Future.wait([
      _getSystemActions(factId),
      _getClarificationRequests(factId),
    ]);
    final merged = results.expand((e) => e).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return merged;
  }

  /// Fetches attachments for multiple factIds in one call.
  /// Returns a map of factId → sorted attachment list.
  Future<Map<String, List<CardAttachmentData>>> getAttachmentsForFacts(
    List<String> factIds,
  ) async {
    final map = <String, List<CardAttachmentData>>{};
    final futures = factIds.map((id) async {
      map[id] = await getAttachments(id);
    });
    await Future.wait(futures);
    return map;
  }

  // ---------------------------------------------------------------------------
  // Data sources — add new attachment types here
  // ---------------------------------------------------------------------------

  Future<List<CardAttachmentData>> _getSystemActions(String factId) async {
    final actions =
        await SystemActionService.instance.getVisibleForFact(factId);
    return actions
        .map((a) => CardAttachmentData(
              id: 'system_action_${a.id}',
              type: CardAttachmentType.systemAction,
              data: {'action': a},
              sortKey: 100,
            ))
        .toList();
  }

  Future<List<CardAttachmentData>> _getClarificationRequests(
      String factId) async {
    final requests =
        await ClarificationRequestService.instance.getVisibleForFact(factId);
    return requests
        .map((r) => CardAttachmentData(
              id: 'clarification_${r.id}',
              type: CardAttachmentType.clarificationRequest,
              data: {'request': r},
              sortKey: 50,
            ))
        .toList();
  }

  Future<List<CardAttachmentData>> _getPendingSystemActions() async {
    final actions = await SystemActionService.instance.getPending();
    return actions
        .map((a) => CardAttachmentData(
              id: 'system_action_${a.id}',
              type: CardAttachmentType.systemAction,
              data: {'action': a},
              sortKey: 100,
            ))
        .toList();
  }

  Future<List<CardAttachmentData>> _getPendingClarificationRequests() async {
    final requests = await ClarificationRequestService.instance.getPending();
    return requests
        .map((r) => CardAttachmentData(
              id: 'clarification_${r.id}',
              type: CardAttachmentType.clarificationRequest,
              data: {'request': r},
              sortKey: 50,
            ))
        .toList();
  }
}
