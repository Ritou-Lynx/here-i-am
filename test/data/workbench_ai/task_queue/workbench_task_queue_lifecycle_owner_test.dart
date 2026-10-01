import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';

class _Controller implements WorkbenchTaskQueueLifecycleController {
  _Controller({this.result = true, this.gate});

  bool result;
  final Completer<void>? gate;
  int closes = 0;

  @override
  Future<bool> closeForHostLifecycle() async {
    closes++;
    await gate?.future;
    return result;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('registry closes every registered controller and exposes an unknown',
      () async {
    final owner = WorkbenchTaskQueueLifecycleOwner();
    final closed = _Controller();
    final unknown = _Controller(result: false);
    owner.register(closed);
    owner.register(unknown);

    expect(await owner.closeForHostLifecycle(), isFalse);
    expect(closed.closes, 1);
    expect(unknown.closes, 1);

    unknown.result = true;
    expect(await owner.closeForHostLifecycle(), isTrue);
    expect(closed.closes, 2);
    expect(unknown.closes, 2);
  });

  test('concurrent close shares the attempt and a later retry uses same controller',
      () async {
    final owner = WorkbenchTaskQueueLifecycleOwner();
    final gate = Completer<void>();
    final controller = _Controller(result: false, gate: gate);
    owner.register(controller);

    final first = owner.closeForHostLifecycle();
    expect(owner.closeForHostLifecycle(), same(first));
    await _flush();
    expect(controller.closes, 1);
    gate.complete();
    expect(await first, isFalse);

    controller.result = true;
    expect(await owner.closeForHostLifecycle(), isTrue);
    expect(controller.closes, 2);
  });

  test('registering after lifecycle fence immediately closes the new controller',
      () async {
    final owner = WorkbenchTaskQueueLifecycleOwner();
    expect(await owner.closeForHostLifecycle(), isTrue);
    final late = _Controller();
    owner.register(late);
    await _flush();
    expect(late.closes, 1);
  });

  test('active drain includes a late unknown controller before reporting',
      () async {
    final owner = WorkbenchTaskQueueLifecycleOwner();
    final gate = Completer<void>();
    owner.register(_Controller(gate: gate));
    final closing = owner.closeForHostLifecycle();
    await _flush();
    final lateUnknown = _Controller(result: false);
    owner.register(lateUnknown);
    gate.complete();
    expect(await closing, isFalse);
    expect(lateUnknown.closes, 1);
  });
}
