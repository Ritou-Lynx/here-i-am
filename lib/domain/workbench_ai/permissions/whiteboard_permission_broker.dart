library;

import 'package:memex/domain/whiteboard/whiteboard_ids.dart';

typedef WhiteboardPermissionClock = DateTime Function();
typedef WhiteboardAuthorizationIdFactory = String Function();

enum WhiteboardWriteCapability {
  createCard('create_card'),
  placeExistingCard('place_existing_card'),
  editCardTitle('edit_card_title'),
  editCardBody('edit_card_body'),
  setCardLabels('set_card_labels'),
  movePlacement('move_placement'),
  resizePlacement('resize_placement'),
  removePlacement('remove_placement'),
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
    required this.selectedCardIds,
    required this.capabilities,
    required this.maxOperationCount,
    required this.maxOperationCountByCapability,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String authorizationId;
  final String runtimeTurnId;
  final String userAuthorizationMessageId;
  final String boardId;
  final Set<String> selectedItemIds;
  final Set<String> selectedCardIds;
  final Set<WhiteboardWriteCapability> capabilities;
  final int maxOperationCount;
  final Map<WhiteboardWriteCapability, int> maxOperationCountByCapability;
  final DateTime issuedAt;
  final DateTime expiresAt;

  Map<String, dynamic> toAuditJson() => {
        'authorization_id': authorizationId,
        'runtime_turn_id': runtimeTurnId,
        'user_authorization_message_id': userAuthorizationMessageId,
        'board_id': boardId,
        'selected_item_ids': selectedItemIds.toList()..sort(),
        'selected_card_ids': selectedCardIds.toList()..sort(),
        'capabilities': capabilities.map((value) => value.wireName).toList()
          ..sort(),
        'max_operation_count': maxOperationCount,
        'max_operation_count_by_capability': {
          for (final entry in maxOperationCountByCapability.entries)
            entry.key.wireName: entry.value,
        },
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
    Set<String> selectedCardIds = const {},
    required Set<WhiteboardWriteCapability> capabilities,
    int maxOperationCount = 64,
    Map<WhiteboardWriteCapability, int>? maxOperationCountByCapability,
  }) {
    _requireId(runtimeTurnId, 'runtimeTurnId');
    _requireId(userAuthorizationMessageId, 'userAuthorizationMessageId');
    _requireId(boardId, 'boardId');
    if (selectedItemIds.length > hardMaxSelectedItems ||
        selectedCardIds.length > hardMaxSelectedItems ||
        (selectedItemIds.isEmpty &&
            selectedCardIds.isEmpty &&
            !capabilities.contains(WhiteboardWriteCapability.createCard))) {
      throw ArgumentError(
        'authorization scope is empty or exceeds $hardMaxSelectedItems ids',
      );
    }
    for (final itemId in selectedItemIds) {
      _requireId(itemId, 'selectedItemIds[]');
    }
    for (final cardId in selectedCardIds) {
      _requireId(cardId, 'selectedCardIds[]');
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
    final perCapability = maxOperationCountByCapability ??
        {for (final capability in capabilities) capability: maxOperationCount};
    if (perCapability.keys.any((key) => !capabilities.contains(key)) ||
        capabilities.any((key) => !perCapability.containsKey(key)) ||
        perCapability.values.any(
          (value) => value <= 0 || value > maxOperationCount,
        )) {
      throw ArgumentError(
        'per-capability limits must cover only granted capabilities and fit '
        'the total operation limit',
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
      selectedCardIds: Set.unmodifiable(selectedCardIds),
      capabilities: Set.unmodifiable(capabilities),
      maxOperationCount: maxOperationCount,
      maxOperationCountByCapability: Map.unmodifiable(perCapability),
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
    Set<String> targetCardIds = const {},
    required Set<WhiteboardWriteCapability> requiredCapabilities,
    required int operationCount,
    Map<WhiteboardWriteCapability, int>? operationCountByCapability,
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
    if (!state.grant.selectedCardIds.containsAll(targetCardIds)) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.targetOutsideSelection,
      );
    }
    if (operationCount <= 0 || operationCount > state.grant.maxOperationCount) {
      return const WhiteboardPermissionDecision.denied(
        WhiteboardPermissionDecisionCode.operationLimitExceeded,
      );
    }
    final perCapability = operationCountByCapability ??
        {for (final capability in requiredCapabilities) capability: 1};
    for (final entry in perCapability.entries) {
      final allowed = state.grant.maxOperationCountByCapability[entry.key];
      if (allowed == null || entry.value <= 0 || entry.value > allowed) {
        return const WhiteboardPermissionDecision.denied(
          WhiteboardPermissionDecisionCode.operationLimitExceeded,
        );
      }
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

  /// Reverts an in-memory permission commit when the enclosing durable
  /// transaction rolls back after [commit] succeeded.
  void rollbackCommit({
    required String authorizationId,
    required String operationBatchId,
  }) {
    final state = _grants[authorizationId];
    if (state?.committedBatchId == operationBatchId) {
      state!
        ..committedBatchId = null
        ..reservedBatchId = null;
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
