import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/desktop/desktop_exit_gate.dart';

void main() {
  test('fences synchronously and closes conversation before queue', () async {
    final steps = <String>[];
    final conversation = _Conversation(steps: steps);
    final queue = _Queue(steps: steps);
    final gate = _gate(conversation, queue);

    final closing = gate.close();
    expect(conversation.fences, 1);
    expect(steps.first, 'fence');
    expect(await closing, isTrue);
    expect(steps, ['fence', 'conversation', 'queue']);
  });

  test('unknown conversation close keeps queue untouched and can retry',
      () async {
    final steps = <String>[];
    final conversation = _Conversation(steps: steps, result: false);
    final queue = _Queue(steps: steps);
    final gate = _gate(conversation, queue);

    expect(await gate.close(), isFalse);
    expect(steps, ['fence', 'conversation']);
    conversation.result = true;
    expect(await gate.close(), isTrue);
    expect(conversation.fences, 1);
    expect(steps, ['fence', 'conversation', 'conversation', 'queue']);
  });

  test('unknown queue close keeps the window open and can retry', () async {
    final steps = <String>[];
    final conversation = _Conversation(steps: steps);
    final queue = _Queue(steps: steps, result: false);
    final gate = _gate(conversation, queue);

    expect(await gate.close(), isFalse);
    queue.result = true;
    expect(await gate.close(), isTrue);
    expect(conversation.fences, 1);
    expect(steps, ['fence', 'conversation', 'queue', 'conversation', 'queue']);
  });

  test('shares an in-flight close attempt', () async {
    final steps = <String>[];
    final release = Completer<void>();
    final conversation = _Conversation(steps: steps, gate: release);
    final gate = _gate(conversation, _Queue(steps: steps));

    final first = gate.close();
    expect(gate.close(), same(first));
    release.complete();
    expect(await first, isTrue);
  });
}

DesktopExitGate _gate(_Conversation conversation, _Queue queue) =>
    DesktopExitGate(
      fenceConversation: conversation.fenceNewWork,
      closeConversation: conversation.closeForHostLifecycle,
      closeQueue: queue.closeForHostLifecycle,
    );

class _Conversation {
  _Conversation({required this.steps, this.result = true, this.gate});

  final List<String> steps;
  bool result;
  final Completer<void>? gate;
  int fences = 0;

  void fenceNewWork() {
    fences++;
    steps.add('fence');
  }

  Future<bool> closeForHostLifecycle() async {
    steps.add('conversation');
    await gate?.future;
    return result;
  }
}

class _Queue {
  _Queue({required this.steps, this.result = true});

  final List<String> steps;
  bool result;

  Future<bool> closeForHostLifecycle() async {
    steps.add('queue');
    return result;
  }
}
