import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/task_queue/ollama_text_task_gateway.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_execution.dart';
import 'package:memex/db/app_database.dart';

/// Real-model long-task check against Ollama. Opt-in: runs only with
/// `HIA_OLLAMA_LIVE=1` plus `HIA_TASK_OLLAMA_MODEL` (and `OLLAMA_API_KEY` for
/// ollama.com). Uses an in-memory database and a synthetic goal only.
void main() {
  test('a real Ollama model completes a deterministic long task', () async {
    if (Platform.environment['HIA_OLLAMA_LIVE'] != '1') {
      markTestSkipped('Set HIA_OLLAMA_LIVE=1 to run the real Ollama check');
      return;
    }
    final config = OllamaTextTaskConfig.fromEnvironment();
    if (config == null) fail('HIA_TASK_OLLAMA_MODEL is not set');

    const scope = TaskQueueHostScope(
        profileId: 'live_text_queue',
        scopeType: 'conversation',
        scopeId: 'live_synthetic_conversation');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = TaskRoomService(db: db);
    final gateway = OllamaTextTaskGateway(config: config);
    final execution = WorkbenchTaskQueueExecution(
      service: service,
      runtime: gateway,
      ensureAvailable: gateway.ensureAvailable,
      startTextSession: (manifest) =>
          gateway.startTextTaskSession(contextManifest: manifest),
    );
    addTearDown(execution.closeForHostLifecycle);

    final id = await service.enqueueTaskRoom(
      title: 'live synthetic count',
      goal: 'Output the integers from 1 to 30 in ascending order, one per '
          'line, with no other text.',
      taskType: TaskType.other,
      executor: 'workbench_runtime',
      conversationId: scope.scopeId,
      queueHostScope: scope,
      maxRetries: 0,
      permissions: {
        'profile_id': scope.profileId,
        'scope_type': scope.scopeType,
        'scope_id': scope.scopeId,
      },
    );
    final started = DateTime.now();
    await execution.start(id: id, scope: scope, requestId: 'live-start');
    await execution.waitForAttempt(id);
    final done = (await service.getTaskQueueSnapshot(id))!;
    // ignore: avoid_print
    print('model=${config.model} host=${config.baseUri.host} '
        'status=${done.status.value} '
        'seconds=${DateTime.now().difference(started).inSeconds}');

    expect(done.status, TaskStatus.completed,
        reason: 'failure=${done.failureReason} '
            'interrupted=${done.interruptedReason}');
    final numbers = RegExp(r'\d+')
        .allMatches(done.resultPreview ?? '')
        .map((match) => int.parse(match.group(0)!))
        .toList();
    expect(numbers, List<int>.generate(30, (index) => index + 1));
  }, timeout: const Timeout(Duration(minutes: 12)));
}
