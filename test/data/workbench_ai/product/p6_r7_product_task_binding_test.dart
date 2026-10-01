import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_config.dart';
import 'package:memex/data/workbench_ai/product/p6_r7_product_task_binding.dart';
import 'package:memex/data/workbench_ai/product/workbench_task_product_session.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/p6_r7_product_main.dart'
    show p6R7ProductConversationClosed;
import '../task_queue/workbench_task_queue_execution_test.dart'
    show FakeRuntime;

const _id = '1a2b3c4d-1234-4567-89ab-123456789abc';
const _foreign = '2a2b3c4d-1234-4567-89ab-123456789abc';
const _conversation = 'p6-r7-candidate-synthetic';
const _factory = DesktopWorkbenchTaskQueueAuthorizationFactory();
WorkbenchTaskQueueAuthorization _auth(String text,
        {String conversation = _conversation}) =>
    _factory.build(conversationId: conversation, userText: text);

void main() {
  test(
      'binding rejects wrong scope/profile and permits only exact task after restore',
      () async {
    final binding = P6R7ProductTaskBinding(
        conversationId: _conversation,
        persist: (_) async {},
        readGoal: (_) async => p6R7CandidateGoal,
        register: (_, __) async {});
    expect(binding.accepts(_auth('创建长任务')), isFalse);
    await binding.initialize(_id);
    expect(binding.accepts(_auth('创建长任务')), isFalse);
    expect(binding.accepts(_auth('启动任务 $_foreign')), isFalse);
    expect(binding.accepts(_auth('启动任务 $_id')), isTrue);
    expect(binding.accepts(_auth('查看任务状态')), isTrue);
    expect(binding.accepts(_auth('查看任务状态', conversation: 'other')), isFalse);
    expect(
        binding.accepts(const WorkbenchTaskQueueAuthorization(
            profileId: 'other',
            conversationId: _conversation,
            allowedActions: {WorkbenchTaskQueueAction.status})),
        isFalse);
    expect(binding.accepts(_auth('启动任务 $_id 和 $_foreign')), isFalse);
    expect(binding.accepts(_auth('继续任务')), isFalse);
  });

  test(
      'restore completes exact persistence and witness before Node bind/admission',
      () async {
    final gate = Completer<void>();
    final steps = <String>[];
    final binding = P6R7ProductTaskBinding(
        conversationId: _conversation,
        persist: (id) async {
          steps.add('persist:$id');
          await gate.future;
          steps.add('witness');
        },
        readGoal: (id) async {
          steps.add('read:$id');
          return p6R7CandidateGoal;
        },
        register: (id, goal) async {
          steps.add('register:$id');
        });
    final initialized = binding.initialize(_id);
    expect(binding.accepts(_auth('启动任务 $_id')), isFalse);
    expect(steps, ['persist:$_id']);
    gate.complete();
    await initialized;
    expect(steps, ['persist:$_id', 'witness', 'read:$_id', 'register:$_id']);
    expect(binding.accepts(_auth('启动任务 $_id')), isTrue);
  });

  for (final failAt in ['none', 'persist', 'register']) {
    test(
        'real enqueue result binds once; $failAt failure preserves row and fences next enqueue',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final service = TaskRoomService(db: db);
      var persisted = 0;
      var registered = 0;
      final binding = P6R7ProductTaskBinding(
          conversationId: _conversation,
          persist: (id) async {
            persisted++;
            if (failAt == 'persist') throw StateError('validation');
          },
          readGoal: (id) async => (await service.getTaskRoom(id))!.goal,
          register: (_, __) async {
            registered++;
            if (failAt == 'register') throw StateError('unknown');
          });
      await binding.initialize(null);
      final runtime = FakeRuntime();
      final session = WorkbenchTaskProductSession(
          taskRoomService: service,
          textRuntime: runtime,
          startTextSession: runtime.startTextSession,
          binding: binding,
          afterInvoke: binding.afterInvoke);
      final first = session.taskQueueTool
          .invoke(_enqueue('first'), authorization: _auth('创建长任务'));
      final second = session.taskQueueTool
          .invoke(_enqueue('second'), authorization: _auth('创建长任务'));
      expect((await first).success, failAt == 'none');
      expect((await second).success, isFalse);
      expect(await db.select(db.taskRooms).get(), hasLength(1));
      expect(persisted, 1);
      expect(registered, failAt == 'persist' ? 0 : 1);
      expect(session.isFrozen, failAt != 'none');
      expect(runtime.sessions, isEmpty);
    });
  }

  test('restored invalid fixed goal never registers or admits work', () async {
    var registered = false;
    final binding = P6R7ProductTaskBinding(
        conversationId: _conversation,
        persist: (_) async {},
        readGoal: (_) async => 'other goal',
        register: (_, __) async {
          registered = true;
        });
    await expectLater(binding.initialize(_id), throwsA(isA<Object>()));
    expect(registered, isFalse);
    expect(binding.accepts(_auth('启动任务 $_id')), isFalse);
  });

  test('registration receipt must match exact ID scope and goal digest', () {
    final response = {
      'schema': 'p6_r7_product_task_bound_v1',
      'task_id': _id,
      'scope_hash': 'scope',
      'goal_sha256': sha256.convert(utf8.encode(p6R7CandidateGoal)).toString()
    };
    p6R7ValidateProductTaskRegistration(response,
        taskId: _id, scopeHash: 'scope', goal: p6R7CandidateGoal);
    for (final invalid in [
      {...response, 'scope_hash': 'other'},
      {...response, 'task_id': _foreign},
      {...response, 'goal_sha256': 'wrong'},
      {...response, 'extra': true}
    ]) {
      expect(
          () => p6R7ValidateProductTaskRegistration(invalid,
              taskId: _id, scopeHash: 'scope', goal: p6R7CandidateGoal),
          throwsA(isA<Object>()));
    }
  });

  test(
      'close receipt rejects unknown cross-conversation ACK extra and nonfinite shapes',
      () {
    final receipt = <String, Object?>{
      'status': 'closed',
      'conversation_id': _conversation,
      'session_id': null,
      'turn_ids': <String>[],
      'reason': null,
      'shared_gateway_stopped': false
    };
    expect(p6R7ProductConversationClosed(receipt, _conversation), isTrue);
    for (final invalid in [
      {...receipt, 'status': 'unknown'},
      {...receipt, 'conversation_id': 'other'},
      {...receipt, 'shared_gateway_stopped': true},
      {...receipt, 'reason': 'timeout'},
      {
        ...receipt,
        'turn_ids': [1]
      },
      {...receipt, 'extra': true}
    ]) {
      expect(p6R7ProductConversationClosed(invalid, _conversation), isFalse);
    }
  });
}

Map<String, Object> _enqueue(String request) => {
      'action': 'enqueue',
      'request_id': request,
      'title': p6R7CandidateTitle,
      'goal': p6R7CandidateGoal,
    };
