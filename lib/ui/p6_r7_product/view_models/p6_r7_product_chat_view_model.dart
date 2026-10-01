import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:memex/data/workbench_ai/product/workbench_product_chat_store.dart';
import 'package:memex/data/workbench_ai/workbench_conversation_coordinator.dart';
import 'package:memex/data/workbench_ai/workbench_desktop_conversation_entry.dart';
import 'package:memex/db/app_database.dart';

/// UI state for one explicitly composed product-chat conversation.
///
/// It owns neither the database nor runtime closure.  The product gateway must
/// fence admissions and perform the strict close after [quiesce] completes.
class P6R7ProductChatViewModel extends ChangeNotifier {
  P6R7ProductChatViewModel({
    required this.store,
    required this.coordinator,
    required this.conversationId,
  }) {
    if (conversationId != store.conversationId) {
      throw ArgumentError.value(
          conversationId, 'conversationId', 'must match store');
    }
    _messagesSubscription = store.watchMessages().listen(
      (rows) {
        _messages = rows;
        _loading = false;
        _notify();
      },
      onError: (_) {
        _loading = false;
        _notify();
      },
    );
  }

  final WorkbenchProductChatStore store;
  final WorkbenchConversationCoordinator coordinator;
  final String conversationId;

  StreamSubscription<List<PersonaChatMessage>>? _messagesSubscription;
  List<PersonaChatMessage> _messages = const [];
  Future<P6R7ProductChatSubmission>? _activeSend;
  bool _loading = true;
  bool _disposed = false;
  bool _fenced = false;
  String _streamingText = '';

  List<PersonaChatMessage> get messagesNewestFirst => _messages;
  bool get loading => _loading;
  bool get isStreaming => _activeSend != null;
  String get streamingText => _streamingText;
  bool get acceptsNewTurns => !_disposed && !_fenced && _activeSend == null;

  Future<WorkbenchConversationResult> send(String userText) =>
      sendWithAdmission(userText).then((submission) => submission.result);

  /// [persisted] distinguishes a rejected draft from a user message already
  /// committed to the isolated candidate store.
  Future<P6R7ProductChatSubmission> sendWithAdmission(String userText) {
    if (!acceptsNewTurns) {
      return Future.value(P6R7ProductChatSubmission.rejected(_busyResult()));
    }
    final send = _send(userText);
    _activeSend = send;
    return send;
  }

  Future<P6R7ProductChatSubmission> _send(String userText) async {
    var persisted = false;
    try {
      final result = await sendPersonaDesktopConversationEntry(
        chatService: store,
        coordinator: coordinator,
        conversationId: conversationId,
        characterId: store.characterId,
        userText: userText,
        afterPersist: (_) async {
          persisted = true;
          if (_disposed || _fenced) return;
          _streamingText = '';
          _notify();
        },
        connector: ({
          required coordinator,
          required conversationId,
          required characterId,
          required userText,
          required userMessageId,
          onDelta,
        }) {
          if (_disposed || _fenced) {
            return Future.value(_closingAfterPersistResult());
          }
          return connectPersonaDesktopConversation(
            coordinator: coordinator,
            conversationId: conversationId,
            characterId: characterId,
            userText: userText,
            userMessageId: userMessageId,
            onDelta: onDelta,
          );
        },
        onDelta: (text) {
          if (_disposed || _fenced) return;
          _streamingText = text;
          _notify();
        },
      );
      return P6R7ProductChatSubmission(result, persisted: persisted);
    } on Object {
      return P6R7ProductChatSubmission(
        persisted ? _closingAfterPersistResult() : _inputRejectedResult(),
        persisted: persisted,
      );
    } finally {
      _streamingText = '';
      _activeSend = null;
      _notify();
    }
  }

  Future<bool> stop() => coordinator.stop(conversationId);

  /// Synchronically prevents a new send and joins the one real coordinator
  /// turn.  A stop acknowledgement remains only an acknowledgement; terminal
  /// proof is still supplied by the injected product close gateway.
  Future<void> quiesce() async {
    _fenced = true;
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    final active = _activeSend;
    if (active != null) await active;
  }

  WorkbenchConversationResult _busyResult() =>
      const WorkbenchConversationResult(
        outcome: WorkbenchConversationOutcome.failed,
        message: '上一条电脑回复还在进行，请先停止或等待完成。',
        errorCode: 'conversation_busy',
      );

  WorkbenchConversationResult _inputRejectedResult() =>
      const WorkbenchConversationResult(
        outcome: WorkbenchConversationOutcome.failed,
        message: '这条消息暂时无法发送，请检查内容后重试。',
        errorCode: 'product_chat_input_rejected',
      );

  WorkbenchConversationResult _closingAfterPersistResult() =>
      const WorkbenchConversationResult(
        outcome: WorkbenchConversationOutcome.failed,
        message: '这条消息已保存，但对话正在关闭，未启动新的电脑回复。',
        errorCode: 'conversation_closing_after_persist',
      );

  @override
  void dispose() {
    _disposed = true;
    _fenced = true;
    // Widget disposal cannot await, but this immediately fences updates and
    // keeps the real send joined until it settles.
    unawaited(quiesce().catchError((Object _) {}));
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

class P6R7ProductChatSubmission {
  const P6R7ProductChatSubmission(this.result, {required this.persisted});

  const P6R7ProductChatSubmission.rejected(this.result) : persisted = false;

  final WorkbenchConversationResult result;
  final bool persisted;
}
