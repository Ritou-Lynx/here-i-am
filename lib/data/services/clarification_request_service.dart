import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/global_event_bus.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:uuid/uuid.dart';

class ClarificationRequestStatus {
  static const pending = 'pending';
  static const answered = 'answered';
  static const completed = 'completed';
  static const dismissed = 'dismissed';
  static const failed = 'failed';
  static const expired = 'expired';
}

class ClarificationResponseType {
  static const confirm = 'confirm';
  static const singleChoice = 'single_choice';
  static const multiChoice = 'multi_choice';
  static const shortText = 'short_text';
}

class ClarificationRequestService {
  static final ClarificationRequestService instance =
      ClarificationRequestService._internal();
  ClarificationRequestService._internal();

  final _logger = Logger('ClarificationRequestService');
  AppDatabase get _db => AppDatabase.instance;

  Future<String> createRequest({
    String? id,
    required String question,
    required String responseType,
    List<Map<String, dynamic>>? options,
    String? entityType,
    String? entityLabel,
    List<String>? evidenceFactIds,
    String? reason,
    String? impact,
    double? confidence,
    String? proposedMemory,
    String? resolutionTarget,
    String? sourceAgent,
    String? dedupeKey,
    String? factId,
    int? expiresAt,
  }) async {
    final trimmedDedupeKey = dedupeKey?.trim();
    if (trimmedDedupeKey != null && trimmedDedupeKey.isNotEmpty) {
      final existing = await (_db.select(_db.clarificationRequests)
            ..where((t) =>
                t.dedupeKey.equals(trimmedDedupeKey) &
                t.status.isIn([
                  ClarificationRequestStatus.pending,
                  ClarificationRequestStatus.answered,
                ]))
            ..limit(1))
          .getSingleOrNull();

      if (existing != null) {
        _logger.info(
            'Reusing active clarification request ${existing.id} for $trimmedDedupeKey');
        return existing.id;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final requestId = id ?? const Uuid().v4();

    await _db.into(_db.clarificationRequests).insert(
          ClarificationRequestsCompanion.insert(
            id: requestId,
            question: question,
            responseType: responseType,
            options: Value(options == null ? null : jsonEncode(options)),
            status: ClarificationRequestStatus.pending,
            answerData: const Value(null),
            entityType: Value(entityType),
            entityLabel: Value(entityLabel),
            evidenceFactIds: Value(
              evidenceFactIds == null ? null : jsonEncode(evidenceFactIds),
            ),
            reason: Value(reason),
            impact: Value(impact),
            confidence: Value(confidence),
            proposedMemory: Value(proposedMemory),
            resolutionTarget: Value(resolutionTarget ?? 'auto'),
            sourceAgent: Value(sourceAgent),
            dedupeKey: Value(trimmedDedupeKey),
            factId: Value(factId),
            error: const Value(null),
            createdAt: Value(now),
            updatedAt: Value(now),
            answeredAt: const Value(null),
            expiresAt: Value(expiresAt),
          ),
        );

    _logger.info('Created clarification request $requestId');
    return requestId;
  }

  Stream<List<ClarificationRequest>> watchPending() {
    final query = _db.select(_db.clarificationRequests)
      ..where((t) => t.status.equals(ClarificationRequestStatus.pending))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Stream<List<ClarificationRequest>> watchPendingForFact(String factId) {
    final query = _db.select(_db.clarificationRequests)
      ..where((t) =>
          t.status.equals(ClarificationRequestStatus.pending) &
          t.factId.equals(factId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Stream<List<ClarificationRequest>> watchVisibleForFact(String factId) {
    final query = _db.select(_db.clarificationRequests)
      ..where((t) =>
          t.status.isIn([
            ClarificationRequestStatus.pending,
            ClarificationRequestStatus.answered,
            ClarificationRequestStatus.completed,
            ClarificationRequestStatus.failed,
          ]) &
          t.factId.equals(factId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Stream<List<ClarificationRequest>> watchVisibleGlobal() {
    final query = _db.select(_db.clarificationRequests)
      ..where((t) =>
          t.status.isIn([
            ClarificationRequestStatus.pending,
            ClarificationRequestStatus.answered,
            ClarificationRequestStatus.completed,
            ClarificationRequestStatus.failed,
          ]) &
          (t.factId.isNull() | t.factId.equals('')))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Future<ClarificationRequest?> getRequest(String requestId) {
    return (_db.select(_db.clarificationRequests)
          ..where((t) => t.id.equals(requestId)))
        .getSingleOrNull();
  }

  Future<List<ClarificationRequest>> getRecentRequests({int limit = 20}) {
    final safeLimit = limit.clamp(1, 50).toInt();
    final query = _db.select(_db.clarificationRequests)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(safeLimit);
    return query.get();
  }

  Future<bool> answerRequest(
    String requestId,
    Map<String, dynamic> answerData,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final count = await (_db.update(_db.clarificationRequests)
          ..where((t) => t.id.equals(requestId)))
        .write(
      ClarificationRequestsCompanion(
        status: const Value(ClarificationRequestStatus.answered),
        answerData: Value(jsonEncode(answerData)),
        answeredAt: Value(now),
        updatedAt: Value(now),
        error: const Value(null),
      ),
    );

    if (count == 0) return false;

    final userId = await UserStorage.getUserId();
    if (userId != null) {
      await GlobalEventBus.instance.publish(
        userId: userId,
        event: SystemEvent(
          type: SystemEventTypes.clarificationAnswered,
          source: 'clarification_request_service.answerRequest',
          payload: ClarificationAnsweredPayload(requestId: requestId),
        ),
      );
    }
    return true;
  }

  Future<bool> dismissRequest(String requestId) async {
    return updateStatus(requestId, ClarificationRequestStatus.dismissed);
  }

  Future<bool> updateStatus(
    String requestId,
    String status, {
    String? error,
  }) async {
    final count = await (_db.update(_db.clarificationRequests)
          ..where((t) => t.id.equals(requestId)))
        .write(
      ClarificationRequestsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        error: Value(error),
      ),
    );
    return count > 0;
  }

  List<Map<String, dynamic>> decodeOptions(ClarificationRequest request) {
    if (request.options == null || request.options!.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(request.options!) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      _logger.warning('Failed to decode clarification options: $e');
      return const [];
    }
  }

  Map<String, dynamic> decodeAnswerData(ClarificationRequest request) {
    if (request.answerData == null || request.answerData!.isEmpty) {
      return const {};
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(request.answerData!));
    } catch (e) {
      _logger.warning('Failed to decode clarification answer: $e');
      return const {};
    }
  }

  List<String> decodeEvidenceFactIds(ClarificationRequest request) {
    if (request.evidenceFactIds == null || request.evidenceFactIds!.isEmpty) {
      return const [];
    }
    try {
      return (jsonDecode(request.evidenceFactIds!) as List<dynamic>)
          .map((e) => e.toString())
          .toList();
    } catch (e) {
      _logger.warning('Failed to decode clarification evidence: $e');
      return const [];
    }
  }
}
