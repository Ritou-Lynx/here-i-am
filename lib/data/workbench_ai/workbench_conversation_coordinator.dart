library;

import 'dart:async';

import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_session_binding.dart';

typedef WorkbenchReplyWriter = Future<int> Function(
  String characterId,
  String content,
);
typedef WorkbenchReplyDelta = void Function(String accumulatedText);

enum WorkbenchConversationOutcome { completed, failed, interrupted }

class WorkbenchConversationResult {
  const WorkbenchConversationResult({
    required this.outcome,
    required this.message,
    this.errorCode,
  });

  final WorkbenchConversationOutcome outcome;
  final String message;
  final String? errorCode;
}

/// Product-owned continuity for ordinary desktop workbench conversation.
///
/// Bindings intentionally live in this process for P1. A product conversation
/// can reuse its local runtime session while the app stays open, and can resume
/// the opaque provider thread after the Bridge loses local session state. No
/// provider identifier is promoted to chat identity or persisted as memory.
class WorkbenchConversationCoordinator {
  WorkbenchConversationCoordinator({
    required WorkbenchConversationRuntimeGateway runtime,
    required WorkbenchReplyWriter addReply,
    DateTime Function()? clock,
    Duration pollInterval = const Duration(milliseconds: 120),
    Duration turnTimeout = const Duration(minutes: 3),
  })  : _runtime = runtime,
        _addReply = addReply,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _pollInterval = pollInterval,
        _turnTimeout = turnTimeout;

  static final instance = WorkbenchConversationCoordinator(
    runtime: WorkbenchRuntimeClient(),
    addReply: (characterId, content) =>
        PersonaChatService.instance.addCharacterMessage(
      characterId,
      content,
      isRead: true,
    ),
  );

  static const _terminalStatuses = {
    'completed',
    'failed',
    'interrupted',
    'closed',
    'unavailable',
  };

  final WorkbenchConversationRuntimeGateway _runtime;
  final WorkbenchReplyWriter _addReply;
  final DateTime Function() _clock;
  final Duration _pollInterval;
  final Duration _turnTimeout;
  final Map<String, _ConversationRuntime> _bindings = {};
  final Map<String, _ActiveConversationTurn> _activeTurns = {};
  int _bindingSerial = 0;

  bool isRunning(String conversationId) =>
      _activeTurns.containsKey(conversationId);

  RuntimeSessionBinding? bindingFor(String conversationId) =>
      _bindings[conversationId]?.binding;

  Future<WorkbenchConversationResult> send({
    required String conversationId,
    required String characterId,
    required String userText,
    WorkbenchReplyDelta? onDelta,
  }) async {
    final text = userText.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(userText, 'userText', 'must not be blank');
    }
    if (_activeTurns.containsKey(conversationId)) {
      const busy = WorkbenchConversationResult(
        outcome: WorkbenchConversationOutcome.failed,
        message: '上一条电脑回复还在进行，请先停止或等待完成。',
        errorCode: 'conversation_busy',
      );
      try {
        await _addReply(characterId, busy.message);
      } catch (_) {
        // The original active turn remains authoritative. A failed secondary
        // notice must neither interrupt it nor invoke a mobile fallback.
      }
      return busy;
    }

    final activeTurn = _ActiveConversationTurn.pending();
    _activeTurns[conversationId] = activeTurn;
    _ConversationRuntime? runtime;
    String? turnId;
    _DrivenConversationTurn? driven;
    late WorkbenchConversationResult result;
    try {
      runtime = await _ensureRuntime(conversationId);
      WorkbenchRuntimeTurn turn;
      try {
        turn = await _runtime.startTurn(
          runtime.localSessionId,
          _turnInput(text),
        );
      } on WorkbenchRuntimeException catch (error) {
        if (!_shouldResume(error.code)) rethrow;
        runtime = await _resumeRuntime(conversationId, runtime);
        turn = await _runtime.startTurn(
          runtime.localSessionId,
          _turnInput(text),
        );
      }
      activeTurn.markStarted(
        sessionId: runtime.localSessionId,
        turnId: turn.turnId,
      );
      turnId = turn.turnId;
      _markActive(conversationId);
      if (activeTurn.stopRequested) {
        await _runtime.interruptTurn(
          sessionId: runtime.localSessionId,
          turnId: turn.turnId,
        );
      }
      driven = await _driveTurn(
        runtime: runtime,
        turnId: turn.turnId,
        onDelta: onDelta,
      );
      result = driven.result;
    } on WorkbenchRuntimeException catch (error) {
      result = WorkbenchConversationResult(
        outcome: WorkbenchConversationOutcome.failed,
        message: _runtimeFailureMessage(error.code),
        errorCode: _portableErrorCode(error.code),
      );
    } catch (_) {
      result = const WorkbenchConversationResult(
        outcome: WorkbenchConversationOutcome.failed,
        message: '这次电脑回复没有完成。你可以稍后重试。',
        errorCode: 'workbench_conversation_failed',
      );
    }

    var persisted = false;
    try {
      await _addReply(characterId, result.message);
      persisted = true;
    } catch (_) {
      if (result.outcome == WorkbenchConversationOutcome.completed) {
        result = const WorkbenchConversationResult(
          outcome: WorkbenchConversationOutcome.failed,
          message: '电脑回复已经结束，但没有成功保存到对话。',
          errorCode: 'chat_persistence_failed',
        );
      }
    }

    final safeTerminal = persisted &&
        (result.outcome == WorkbenchConversationOutcome.completed ||
            result.outcome == WorkbenchConversationOutcome.interrupted) &&
        driven?.providerSettled == true;
    if (runtime != null && turnId != null && !safeTerminal) {
      await _cleanupAbandonedTurn(
        conversationId: conversationId,
        runtime: runtime,
        turnId: turnId,
      );
    } else if (safeTerminal) {
      if (result.outcome == WorkbenchConversationOutcome.completed) {
        _markIdle(conversationId);
      } else {
        _markInterrupted(conversationId);
      }
    }
    _activeTurns.remove(conversationId);
    return result;
  }

  Future<bool> stop(String conversationId) async {
    final active = _activeTurns[conversationId];
    if (active == null) return false;
    if (!active.hasStarted) {
      active.stopRequested = true;
      return true;
    }
    try {
      await _runtime.interruptTurn(
        sessionId: active.sessionId!,
        turnId: active.turnId!,
      );
      return true;
    } on WorkbenchRuntimeException {
      _markUnavailable(conversationId);
      return false;
    }
  }

  Future<_ConversationRuntime> _ensureRuntime(String conversationId) async {
    final existing = _bindings[conversationId];
    if (existing != null &&
        existing.binding.status != RuntimeSessionStatus.closed &&
        existing.binding.status != RuntimeSessionStatus.unavailable) {
      return existing;
    }
    if (existing != null) {
      return _resumeRuntime(conversationId, existing);
    }
    final session = await _runtime.startSession(
      dynamicTools: const [],
      contextManifest: {
        'conversation_id': conversationId,
        'profile': RuntimeProfile.workbench.wireName,
        'scope': 'desktop_chat',
      },
    );
    final now = _clock().toUtc();
    final created = _ConversationRuntime(
      localSessionId: session.sessionId,
      binding: RuntimeSessionBinding(
        id: 'runtime-binding-${now.microsecondsSinceEpoch}-${++_bindingSerial}',
        conversationId: conversationId,
        provider: 'codex',
        providerSessionId: session.providerSessionId,
        profile: RuntimeProfile.workbench,
        scopeType: RuntimeScopeType.surface,
        scopeId: 'desktop_chat',
        status: RuntimeSessionStatus.idle,
        createdAt: now,
        lastActiveAt: now,
      ),
    );
    _bindings[conversationId] = created;
    return created;
  }

  Future<_ConversationRuntime> _resumeRuntime(
    String conversationId,
    _ConversationRuntime previous,
  ) async {
    final session = await _runtime.resumeSession(
      providerSessionId: previous.binding.providerSessionId,
    );
    final now = _clock().toUtc();
    final resumed = _ConversationRuntime(
      localSessionId: session.sessionId,
      binding: RuntimeSessionBinding(
        id: previous.binding.id,
        conversationId: previous.binding.conversationId,
        provider: previous.binding.provider,
        providerSessionId: session.providerSessionId,
        profile: previous.binding.profile,
        scopeType: previous.binding.scopeType,
        scopeId: previous.binding.scopeId,
        status: RuntimeSessionStatus.idle,
        providerMetadata: previous.binding.providerMetadata,
        createdAt: previous.binding.createdAt,
        lastActiveAt: now,
      ),
    );
    _bindings[conversationId] = resumed;
    return resumed;
  }

  Future<_DrivenConversationTurn> _driveTurn({
    required _ConversationRuntime runtime,
    required String turnId,
    WorkbenchReplyDelta? onDelta,
  }) async {
    var cursor = 0;
    var reply = '';
    String? providerErrorCode;
    final deadline = _clock().toUtc().add(_turnTimeout);
    while (_clock().toUtc().isBefore(deadline)) {
      final batch = await _runtime.readEvents(
        runtime.localSessionId,
        afterSequence: cursor,
      );
      cursor = batch.nextSequence;
      for (final event in batch.events) {
        if (event['turn_id'] != turnId) continue;
        final data = _asMap(event['data']);
        if (event['kind'] == 'message_delta') {
          final delta = data['text'];
          if (delta is String && delta.isNotEmpty) {
            reply += delta;
            onDelta?.call(reply);
          }
        } else if (event['kind'] == 'error') {
          providerErrorCode = data['code']?.toString();
        }
        final status = event['status'];
        if (event['kind'] != 'turn_status' ||
            !_terminalStatuses.contains(status)) {
          continue;
        }
        if (status == 'completed' && reply.trim().isNotEmpty) {
          return _DrivenConversationTurn(
            providerSettled: true,
            result: WorkbenchConversationResult(
              outcome: WorkbenchConversationOutcome.completed,
              message: reply.trim(),
            ),
          );
        }
        if (status == 'interrupted') {
          return const _DrivenConversationTurn(
            providerSettled: true,
            result: WorkbenchConversationResult(
              outcome: WorkbenchConversationOutcome.interrupted,
              message: '已停止这次电脑回复。',
              errorCode: 'runtime_interrupted',
            ),
          );
        }
        return _DrivenConversationTurn(
          providerSettled: false,
          result: WorkbenchConversationResult(
            outcome: WorkbenchConversationOutcome.failed,
            message: '这次电脑回复没有正常完成。你可以稍后重试。',
            errorCode: _portableErrorCode(
              providerErrorCode ?? 'runtime_${status ?? 'failed'}',
            ),
          ),
        );
      }
      await Future<void>.delayed(_pollInterval);
    }
    return const _DrivenConversationTurn(
      providerSettled: false,
      result: WorkbenchConversationResult(
        outcome: WorkbenchConversationOutcome.failed,
        message: '电脑回复等待超时。你可以稍后重试。',
        errorCode: 'runtime_timeout',
      ),
    );
  }

  Future<void> _cleanupAbandonedTurn({
    required String conversationId,
    required _ConversationRuntime runtime,
    required String turnId,
  }) async {
    _markUnavailable(conversationId);
    try {
      await _runtime.interruptTurn(
        sessionId: runtime.localSessionId,
        turnId: turnId,
      );
    } catch (_) {
      // Preserve the original product error. Closing the session is still
      // attempted so a rejected interrupt cannot leave a reusable local turn.
    }
    try {
      await _runtime.closeSession(runtime.localSessionId);
    } catch (_) {
      // The binding remains unavailable and must resume through the opaque
      // provider id on a later user turn.
    }
  }

  void _markIdle(String conversationId) =>
      _transition(conversationId, RuntimeSessionStatus.idle);

  void _markActive(String conversationId) =>
      _transition(conversationId, RuntimeSessionStatus.active);

  void _markInterrupted(String conversationId) =>
      _transition(conversationId, RuntimeSessionStatus.interrupted);

  void _markUnavailable(String conversationId) =>
      _transition(conversationId, RuntimeSessionStatus.unavailable);

  void _transition(String conversationId, RuntimeSessionStatus status) {
    final current = _bindings[conversationId];
    if (current == null || !current.binding.canTransitionTo(status)) return;
    _bindings[conversationId] = _ConversationRuntime(
      localSessionId: current.localSessionId,
      binding: current.binding.transitionTo(status, at: _clock().toUtc()),
    );
  }

  static String _turnInput(String userText) =>
      '你是 Here I am 桌面工作台中的林埃。请直接自然回复，不要声称完成了未实际执行的操作。\n\n$userText';
}

class _ConversationRuntime {
  const _ConversationRuntime({
    required this.localSessionId,
    required this.binding,
  });

  final String localSessionId;
  final RuntimeSessionBinding binding;
}

class _DrivenConversationTurn {
  const _DrivenConversationTurn({
    required this.result,
    required this.providerSettled,
  });

  final WorkbenchConversationResult result;
  final bool providerSettled;
}

class _ActiveConversationTurn {
  _ActiveConversationTurn.pending();

  String? sessionId;
  String? turnId;
  bool stopRequested = false;
  bool get hasStarted => sessionId != null && turnId != null;

  void markStarted({
    required String sessionId,
    required String turnId,
  }) {
    this.sessionId = sessionId;
    this.turnId = turnId;
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _runtimeFailureMessage(String code) => switch (code) {
      'experimental_runtime_disabled' => '电脑 Codex 能力尚未开启，这次消息没有发送到手机模型。',
      'authentication_required' => '电脑 Codex 尚未登录，这次消息没有发送到手机模型。',
      _ => '电脑 Codex 当前不可用，这次消息没有发送到手机模型。',
    };

bool _shouldResume(String code) =>
    code == 'session_not_found' || code == 'runtime_unavailable';

String _portableErrorCode(String value) {
  final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9._:-]'), '_');
  if (normalized.isEmpty) return 'runtime_error';
  return normalized.substring(
      0, normalized.length > 120 ? 120 : normalized.length);
}
