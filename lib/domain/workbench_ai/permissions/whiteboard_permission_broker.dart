library;

import 'package:memex/domain/whiteboard/whiteboard_ids.dart';

typedef WhiteboardPermissionClock = DateTime Function();
typedef WhiteboardAuthorizationIdFactory = String Function();

enum WhiteboardWriteCapability {
  groupSelection('group_selection'),
  connectSelection('connect_selection');

  const WhiteboardWriteCapability(this.wireName);
  final String wireName;
}

enum WhiteboardPermissionDecisionCode {
  allowed,
  authorizationNotFound,
  authorizationExpired,
  authorizationConsumed,
  authorizationBusy,
  runtimeTurnMismatch,
  boardMismatch,
  capabilityDenied,
  targetOutsideSelection,
  operationLimitExceeded,
}

class WhiteboardAuthorizationGrant {
  const WhiteboardAuthorizationGrant._({
    required this.authorizationId,
    required this.runtimeTurnId,
    required this.userAuthorizationMessageId,
    required this.boardId,
    required this.selectedItemIds,
    required this.capabilities,
    required this.maxOperationCount,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String authorizationId;
  final String runtimeTurnId;
  final String userAuthorizationMessageId;
  final String boardId;
  final Set<String> selectedItemIds;
  final Set<WhiteboardWriteCapability> capabilities;
  final int maxOperationCount;
  final DateTime issuedAt;
  final DateTime expiresAt;

  Map<String, dynamic> toAuditJson() => {
        'authorization_id': authorizationId,
        'runtime_turn_id': runtimeTurnId,
        'user_authorization_message_id': userAuthorizationMessageId,
        'board_id': boardId,
        'selected_item_ids': selectedItemIds.toList()..sort(),
        'capabilities': capabilities.map((value) => value.wireName).toList()
          ..sort(),
        'max_operation_count': maxOperationCount,
        'issued_at': issuedAt.toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
      };
}

class WhiteboardPermissionDecision {
  const WhiteboardPermissionDecision._({
    required this.allowed,
    required this.code,
    this.grant,
  });

  const WhiteboardPermissionDecision.allowed(WhiteboardAuthorizationGrant grant)
      : this._(
          allowed: true,
          code: WhiteboardPermissionDecisionCode.allowed,
          grant: grant,
        );

  const WhiteboardPermissionDecision.denied(
    WhiteboardPermissionDecisionCode code,
  ) : this._(allowed: false, code: code);

  final bool allowed;
  final WhiteboardPermissionDecisionCode code;
  final WhiteboardAuthorizationGrant? grant;
}

class WhiteboardPermissionBroker {
  WhiteboardPermissionBroker({
    WhiteboardPermissionClock? clock,
    WhiteboardAuthorizationIdFactory? authorizationIdFactory,
    this.authorizationTtl = const Duration(minutes: 15),
    this.hardMaxSelectedItems = 64,
    this.hardMaxOperationCount = 128,
  })  : _clock = clock ?? (() => DateTime.now().toUtc()),
        _authorizationIdFactory =
            authorizationIdFactory ?? _defaultAuthorizationId;

  final WhiteboardPermissionClock _clock;
  final WhiteboardAuthorizationIdFactory _authorizationIdFactory;
  final Duration authorizationTtl;
  final int hardMaxSelectedItems;
  final int hardMaxOperationCount;

  final Map<String, _GrantState> _grants = {};

  WhiteboardAuthorizationGrant issueSelectionAuthorization({
    required String runtimeTurnId,
    required String userAuthorizationMessageId,
    required String boardId,
    required Set<String> selectedItemIds,
    required Set<WhiteboardWriteCapability> capabilities,
    int maxOperationCount = 64,
  }) {
    _requireId(runtimeTurnId, 'runtimeTurnId');
    _requireId(userAuthorizationMessageId, 'userAuthorizationMessageId');
    _requireId(boardId, 'boardId');
    if (selectedItemIds.isEmpty ||
        selectedItemIds.length > hardMaxSelectedItems) {
      throw ArgumentError(
        'selectedItemIds must contain 1..$hardMaxSelectedItems stable ids',
      );
    }
    for (final itemId in selectedItemIds) {
      _requireId(itemId, 'selectedItemIds[]');
    }
    if (capabilities.isEmpty) {
      throw ArgumentError('at least one write capability is required');
    }
    if (maxOperationCount <= 0 || maxOperationCount > hardMaxOperationCount) {
      throw RangeError.range(
        maxOperationCount,
        1,
        hardMaxOperationCount,
        'maxOperationCount',
      );
    }
    if (authorizationTtl <= Duration.zero) {
      throw StateError('authorizationTtl must be positive');
    }

    final authorizationId = _authorizationIdFactory();
    _requireId(authorizationId, 'authorizationId');
    if (_grants.containsKey(authorizationId)) {
      throw StateError('authorizationIdFactory returned a duplicate id');
    }
    final issuedAt = _clock().toUtc();
    final grant = WhiteboardAuthorizationGrant._(
      authorizationId: authorizationId,
      runtimeTurnId: runtimeTurnId,
      userAuthorizationMessageId: userAuthorizationMessageId,
      boardId: boardId,
      selectedItemIds: Set.unmodifiable(selectedItemIds),
      capabilities: Set.unmodifiable(capabilities),
      maxOperationCount: maxOperationCount,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(authorizationTtl),
    );
    _grants[authorizationId] = _GrantState(grant);
    return grant;
  }

  WhiteboardPermissionDecision reserve({
    required String authorizationId,
    required String operationBatchId,
    required String runtimeTurnId,
    required String boardId,
    required Set<String> targetItemIds,
    required Set<WhiteboardWriteCapability> requiredCapabilities,
    required int operationCount,
  }) {
    final state = _grants[authorizationId];
    if (state == null) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.authorizationNotFound,
      );
    }
    final now = _clock().toUtc();
    if (!now.isBefore(state.grant.expiresAt)) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.authorizationExpired,
      );
    }
    if (state.committedBatchId != null) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.authorizationConsumed,
      );
    }
    if (state.reservedBatchId != null &&
        state.reservedBatchId != operationBatchId) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.authorizationBusy,
      );
    }
    if (state.grant.runtimeTurnId != runtimeTurnId) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.runtimeTurnMismatch,
      );
    }
    if (state.grant.boardId != boardId) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.boardMismatch,
      );
    }
    if (!state.grant.capabilities.containsAll(requiredCapabilities)) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.capabilityDenied,
      );
    }
    if (!state.grant.selectedItemIds.containsAll(targetItemIds)) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.targetOutsideSelection,
      );
    }
    if (operationCount <= 0 || operationCount > state.grant.maxOperationCount) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.operationLimitExceeded,
      );
    }
    state.reservedBatchId = operationBatchId;
    return WhiteboardPermissionDecision.allowed(state.grant);
  }

  bool commit({
    required String authorizationId,
    required String operationBatchId,
  }) {
    final state = _grants[authorizationId];
    if (state == null || state.reservedBatchId != operationBatchId) {
      return false;
    }
    state
      ..reservedBatchId = null
      ..committedBatchId = operationBatchId;
    return true;
  }

  void release({
    required String authorizationId,
    required String operationBatchId,
  }) {
    final state = _grants[authorizationId];
    if (state?.reservedBatchId == operationBatchId) {
      state!.reservedBatchId = null;
    }
  }

  static String _defaultAuthorizationId() => StableId.generate('auth').value;
}

class _GrantState {
  _GrantState(this.grant);

  final WhiteboardAuthorizationGrant grant;
  String? reservedBatchId;
  String? committedBatchId;
}

void _requireId(String value, String field) {
  if (value.isEmpty ||
      value.length > 256 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value)) {
    throw ArgumentError('$field must be a portable stable id');
  }
}
