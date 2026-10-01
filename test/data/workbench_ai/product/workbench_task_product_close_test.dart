import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_session_resources.dart';
import 'package:memex/data/workbench_ai/product/workbench_task_product_close.dart';

void main() {
  test('fences synchronously and joins owners before resources and witness',
      () async {
    final events = <String>[];
    final pendingConversation = Completer<bool>();
    final pendingInvocation = Completer<void>();
    final close = makeClose(events,
        conversation: () => pendingConversation.future,
        invocations: () => pendingInvocation.future);
    final first = close.close();
    expect(close.acceptsNewWork, isFalse);
    expect(events, ['fence', 'conversation']);
    expect(identical(first, close.close()), isTrue);
    pendingConversation.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['fence', 'conversation', 'invocations']);
    pendingInvocation.complete();
    expect(await first, isTrue);
    expect(events, [
      'fence',
      'conversation',
      'invocations',
      'queue',
      'host',
      'drain',
      'store',
      'client',
      'witness',
    ]);
    expect(close.closed, isTrue);
    expect(await close.close(), isTrue);
    expect(events.where((event) => event == 'witness'), hasLength(1));
  });

  for (final failed in ['conversation', 'queue', 'host']) {
    test('$failed unknown keeps later resources alive and retries same owner',
        () async {
      final events = <String>[];
      var confirmed = false;
      final close = makeClose(events,
          conversation: failed == 'conversation' ? () async => confirmed : null,
          queue: failed == 'queue' ? () async => confirmed : null,
          host: failed == 'host' ? () async => confirmed : null);
      expect(await close.close(), isFalse);
      expect(close.acceptsNewWork, isFalse);
      expect(events, isNot(contains('drain')));
      expect(events, isNot(contains('witness')));
      confirmed = true;
      expect(await close.close(), isTrue);
      expect(events.where((event) => event == 'fence'), hasLength(1));
      expect(events.where((event) => event == failed), hasLength(2));
      if (failed != 'conversation') {
        expect(events.where((event) => event == 'conversation'), hasLength(1));
      }
    });
  }

  test('unfinished queue invocation prevents lifecycle and host close',
      () async {
    final events = <String>[];
    var fail = true;
    final close = makeClose(events, invocations: () async {
      if (fail) throw StateError('join_unknown');
    });
    expect(await close.close(), isFalse);
    expect(events, ['fence', 'conversation', 'invocations']);
    fail = false;
    expect(await close.close(), isTrue);
    expect(events.where((event) => event == 'conversation'), hasLength(1));
  });

  for (final failed in ['drain', 'store', 'client', 'witness']) {
    test('$failed failure stays unknown even if a later close could be a no-op',
        () async {
      final events = <String>[];
      var fail = true;
      final close = makeClose(events,
          resourceFailure: () => fail ? failed : null,
          witness: failed == 'witness' ? () async => !fail : null);
      expect(await close.close(), isFalse);
      fail = false;
      expect(await close.close(), isFalse);
      expect(close.closed, isFalse);
      expect(events.where((event) => event == 'host'), hasLength(1));
      expect(events.where((event) => event == failed), hasLength(1));
      if (failed != 'witness') expect(events, isNot(contains('witness')));
      if (failed == 'drain') {
        expect(events, isNot(contains('store')));
        expect(events, isNot(contains('client')));
      }
    });
  }

  test('fence failure never progresses or grants a new accepting state',
      () async {
    final events = <String>[];
    final close =
        makeClose(events, fence: () => throw StateError('fence_unknown'));
    expect(await close.close(), isFalse);
    expect(await close.close(), isFalse);
    expect(close.acceptsNewWork, isFalse);
    expect(events, ['fence']);
  });

  test('reentrant close shares the pending attempt', () async {
    final events = <String>[];
    late WorkbenchTaskProductClose close;
    Future<bool>? reentrant;
    close = makeClose(events, fence: () {
      reentrant = close.close();
    });
    final first = close.close();
    expect(identical(first, reentrant), isTrue);
    expect(await first, isTrue);
    expect(events.where((event) => event == 'host'), hasLength(1));
  });
}

WorkbenchTaskProductClose makeClose(
  List<String> events, {
  void Function()? fence,
  Future<bool> Function()? conversation,
  Future<void> Function()? invocations,
  Future<bool> Function()? queue,
  Future<bool> Function()? host,
  Future<bool> Function()? witness,
  String? Function()? resourceFailure,
}) {
  void resource(String name) {
    events.add(name);
    if (resourceFailure?.call() == name) throw StateError('${name}_unknown');
  }

  final resources = P6R7CandidateSessionResources(
      drainExecution: () async => resource('drain'),
      closeStore: () async => resource('store'),
      closeClient: () => resource('client'));
  return WorkbenchTaskProductClose(
    fenceNewWork: () {
      events.add('fence');
      fence?.call();
    },
    closeConversation: () {
      events.add('conversation');
      return conversation?.call() ?? Future.value(true);
    },
    joinQueueInvocations: () {
      events.add('invocations');
      return invocations?.call() ?? Future.value();
    },
    closeQueue: () {
      events.add('queue');
      return queue?.call() ?? Future.value(true);
    },
    closeOwnedHost: () {
      events.add('host');
      return host?.call() ?? Future.value(true);
    },
    closeResources: resources.close,
    recordAppClosed: () {
      events.add('witness');
      return witness?.call() ?? Future.value(true);
    },
  );
}
